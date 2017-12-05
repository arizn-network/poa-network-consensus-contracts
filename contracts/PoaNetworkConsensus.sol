pragma solidity ^0.4.18;

import "./interfaces/IPoaNetworkConsensus.sol";
import "./interfaces/IProxyStorage.sol";


contract PoaNetworkConsensus is IPoaNetworkConsensus {
    /// Issue this log event to signal a desired change in validator set.
    /// This will not lead to a change in active validator set until 
    /// finalizeChange is called.
    ///
    /// Only the last log event of any block can take effect.
    /// If a signal is issued while another is being finalized it may never
    /// take effect.
    /// 
    /// parentHash here should be the parent block hash, or the
    /// signal will not be recognized.
    event InitiateChange(bytes32 indexed parentHash, address[] newSet);
    event ChangeFinalized(address[] newSet);
    event ChangeReference(string nameOfContract, address newAddress);
    event MoCInitializedProxyStorage(address proxyStorage);
    struct ValidatorState {
        // Is this a validator.
        bool isValidator;
        // Index in the currentValidators.
        uint256 index;
    }

    bool public finalized = false;
    bool public isMasterOfCeremonyInitialized = false;
    address public masterOfCeremony;
    address public systemAddress = 0xfffffffffffffffffffffffffffffffffffffffe;
    address[] public currentValidators;
    address[] public pendingList;
    uint256 public currentValidatorsLength;
    mapping(address => ValidatorState) public validatorsState;
    IProxyStorage public proxyStorage;

    modifier onlySystemAndNotFinalized() {
        require(msg.sender == systemAddress && !finalized);
        _;
    }

    modifier onlyVotingContract() {
        require(msg.sender == getVotingToChangeKeys());
        _;
    }

    modifier onlyKeysManager() {
        require(msg.sender == getKeysManager());
        _;
    }
    
    modifier isNewValidator(address _someone) {
        require(!validatorsState[_someone].isValidator);
        _;
    }

    modifier isNotNewValidator(address _someone) {
        require(validatorsState[_someone].isValidator);
        _;
    }

    function PoaNetworkConsensus(address _masterOfCeremony) public {
        // TODO: When you deploy this contract, make sure you hardcode items below
        // Make sure you have those addresses defined in spec.json
        require(_masterOfCeremony != address(0));
        masterOfCeremony = _masterOfCeremony;
        currentValidators = [masterOfCeremony];
        for (uint256 i = 0; i < currentValidators.length; i++) {
            validatorsState[currentValidators[i]] = ValidatorState({
                isValidator: true,
                index: i
            });
        }
        currentValidatorsLength = currentValidators.length;
        pendingList = currentValidators;
    }

    /// Get current validator set (last enacted or initial if no changes ever made)
    function getValidators() public view returns(address[]) {
        return currentValidators;
    }

    function getPendingList() public view returns(address[]) {
        return pendingList;
    }

    /// Called when an initiated change reaches finality and is activated. 
    /// Only valid when msg.sender == SUPER_USER (EIP96, 2**160 - 2)
    ///
    /// Also called when the contract is first enabled for consensus. In this case,
    /// the "change" finalized is the activation of the initial set.
    function finalizeChange() public onlySystemAndNotFinalized {
        finalized = true;
        currentValidators = pendingList;
        currentValidatorsLength = currentValidators.length;
        ChangeFinalized(getValidators());
    }

    function addValidator(address _validator) public onlyKeysManager isNewValidator(_validator) {
        require(_validator != address(0));
        validatorsState[_validator] = ValidatorState({
            isValidator: true,
            index: pendingList.length
        });
        pendingList.push(_validator);
        finalized = false;
        InitiateChange(block.blockhash(block.number - 1), pendingList);
    }

    function removeValidator(address _validator) public onlyKeysManager isNotNewValidator(_validator) {
        uint256 removedIndex = validatorsState[_validator].index;
        // Can not remove the last validator.
        uint256 lastIndex = pendingList.length - 1;
        address lastValidator = pendingList[lastIndex];
        // Override the removed validator with the last one.
        pendingList[removedIndex] = lastValidator;
        // Update the index of the last validator.
        validatorsState[lastValidator].index = removedIndex;
        delete pendingList[lastIndex];
        require(pendingList.length > 0);
        pendingList.length--;
        validatorsState[_validator].index = 0;
        validatorsState[_validator].isValidator = false;
        finalized = false;
        InitiateChange(block.blockhash(block.number - 1), pendingList);
    }

    function setProxyStorage(address _newAddress) public {
        // Address of Master of Ceremony;
        require(msg.sender == masterOfCeremony);
        require(!isMasterOfCeremonyInitialized);
        require(_newAddress != address(0));
        proxyStorage = IProxyStorage(_newAddress);
        isMasterOfCeremonyInitialized = true;
        MoCInitializedProxyStorage(proxyStorage);
    }

    function isValidator(address _someone) public view returns(bool) {
        return validatorsState[_someone].isValidator;
    }

    function getKeysManager() public view returns(address) {
        return proxyStorage.getKeysManager();
    }

    function getVotingToChangeKeys() public view returns(address) {
        return proxyStorage.getVotingToChangeKeys();
    }

}