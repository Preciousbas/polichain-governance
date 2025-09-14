// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/src/Script.sol";
import {SimpleGovernor} from "../src/SimpleGovernor.sol";
import {GovernanceToken} from "src/MyToken.sol";
import {GovernanceTimelock} from "src/Timelock.sol";

contract GovernanceDeployment is Script {
    //////////////////////////////////////////////////
    // STATE VARIABLES
    //////////////////////////////////////////////////

    SimpleGovernor public governor;
    GovernanceToken public token;
    GovernanceTimelock public timelock;

    string public constant TOKEN_NAME = "Polichain Token";
    string public constant TOKEN_SYMBOL = "PCT";

    uint256 public constant MIN_DEPLOYMENT_DELAY = 1 hours; // Minimum delay before operations
    uint256 public constant OWNERSHIP_TRANSFER_DELAY = 24 hours; // 24h delay for ownership transfer

    address public deployer;
    address public treasury;
    address public multisig;

    bool public deploymentComplete;
    uint256 public deploymentTimestamp;

    ////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////

    event DeploymentStarted(address indexed deployer, uint256 timestamp);
    event TokenDeployed(address indexed token, address indexed initialOwner);
    event GovernorDeployed(address indexed governor, address indexed token, address indexed treasury);
    event TimelockDeployed(address indexed timelock, uint256 minDelay);
    event OwnershipTransferred(address indexed token, address indexed newOwner);
    event DeploymentCompleted(address indexed token, address indexed governor, uint256 timestamp);
    event SecurityCheckPassed(string check);

    ////////////////////////////////////////////////////
    // MODIFIERS
    ////////////////////////////////////////////////////

    modifier onlyAfterDelay() {
        require(block.timestamp >= deploymentTimestamp + MIN_DEPLOYMENT_DELAY, "Deployment delay not met");
        _;
    }

    modifier deploymentNotComplete() {
        require(!deploymentComplete, "Deployment already completed");
        _;
    }

    ////////////////////////////////////////////////////
    // MAIN DEPLOYMENT FUNCTION
    ////////////////////////////////////////////////////

    function run() external {
        _initializeDeployment();

        _performPreDeploymentChecks();

        _deployContracts();

        _verifyDeployment();

        _integrateGovernorAndTimelock();

        _configureSecuritySettings();

        _transferOwnership();

        _completeDeployment();
    }

    //////////////////////////////////////////////////////
    // DEPLOYMENT INITIALIZATION
    /////////////////////////////////////////////////////

    function _initializeDeployment() internal {
        deploymentTimestamp = block.timestamp;

        deployer = vm.envOr("DEPLOYER", msg.sender);
        bool deployTreasury = vm.envOr("DEPLOY_TREASURY", false);
        if (deployTreasury) {
            uint256 treasuryPk = vm.envOr("TREASURY_PRIVATE_KEY", uint256(1));
            require(treasuryPk > 0 && treasuryPk < type(uint256).max, "Invalid TREASURY_PRIVATE_KEY");
            treasury = vm.addr(treasuryPk);
            console.log("Deployed new Treasury at:", treasury);
        } else {
            treasury = vm.envOr("TREASURY", address(0));
        }
        multisig = vm.envOr("MULTISIG", address(0));

        console.log("Deployment timestamp:", deploymentTimestamp);
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        console.log("Deployer address:", deployer);
        console.log("Treasury address:", treasury);
        console.log("Multisig address:", multisig);

        emit DeploymentStarted(deployer, deploymentTimestamp);
    }

    //////////////////////////////////////////////////////////
    // PRE-DEPLOYMENT SECURITY CHECKS
    //////////////////////////////////////////////////////////

    function _performPreDeploymentChecks() internal view {
        require(deployer != address(0), "Invalid deployer");
        require(treasury != address(0), "Invalid treasury");
        //require(deployer.balance > 0.1 ether, "Low deployer balance");
    }

    //////////////////////////////////////////////////////////
    // CONTRACT DEPLOYMENT
    //////////////////////////////////////////////////////////

    function _deployContracts() internal deploymentNotComplete {
        console.log("=== CONTRACT DEPLOYMENT ===");

        vm.startBroadcast(deployer);

        console.log("Deploying GovernanceToken...");
        token = new GovernanceToken{salt: _getSalt("TOKEN")}(TOKEN_NAME, TOKEN_SYMBOL, deployer);

        console.log("GovernanceToken deployed at:", address(token));
        emit TokenDeployed(address(token), deployer);

        require(address(token) != address(0), "Token deployment failed");
        require(token.owner() == deployer, "Token owner mismatch");
        require(token.totalSupply() == 1_000_000 * 10 ** 18, "Token supply mismatch");
        console.log("Token deployment verified");

        console.log("Deploying Timelock ....");
        address[] memory proposers = new address[](1);
        proposers[0] = address(governor);

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        uint256 nonce = 2;

        timelock =
            new GovernanceTimelock{salt: _getSalt("TIMELOCK")}(_getDeploymentDelay(), proposers, executors, deployer);
        emit TimelockDeployed(address(timelock), MIN_DEPLOYMENT_DELAY);

        console.log("Deploying SimpleGovernor...");
        governor = new SimpleGovernor{salt: _getSalt("GOVERNOR")}(address(token), treasury, deployer);

        console.log("SimpleGovernor deployed at:", address(governor));
        emit GovernorDeployed(address(governor), address(token), treasury);

        require(address(governor) != address(0), "Governor deployment failed");
        require(address(governor.governanceToken()) == address(token), "Governor token mismatch");
        require(governor.treasury() == treasury, "Governor treasury mismatch");
        console.log("Governor deployment verified");

        vm.stopBroadcast();

        console.log("  All contracts deployed successfully ...");
    }

    function _integrateGovernorAndTimelock() internal {
        vm.startBroadcast(deployer);
        console.log(governor.owner());
        console.log(deployer);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        if (multisig != address(0)) timelock.grantRole(timelock.CANCELLER_ROLE(), multisig);
        governor.transferOwnership(address(timelock));

        vm.stopBroadcast();

        console.log("Governor ownership transferred to Timelock");
    }

    function _getDeploymentDelay() internal view returns (uint256) {
        if (block.chainid == 1) {
            return 2 days;
        }
        return MIN_DEPLOYMENT_DELAY;
    }

    //////////////////////////////////////////////////////////
    // POST-DEPLOYMENT VERIFICATION
    //////////////////////////////////////////////////////////

    function _verifyDeployment() internal view {
        console.log("=== POST-DEPLOYMENT VERIFICATION ===");

        require(address(token) != address(0), "Token failed");
        require(treasury != address(0), "Invalid treasury");
        require(address(governor) != address(0), "Governor failed");
        require(address(timelock) != address(0), "Timelock failed");

        console.log("  All deployment verifications passed ...");
    }

    function _isContract(address aContract) internal view returns (bool) {
        return aContract.code.length > 0;
    }

    function _requireEOA(address aContract, string memory tag) internal view {
        require(aContract != address(0), string.concat(tag, ": zero address"));
        require(!_isContract(aContract), string.concat(tag, ": must be EOA (no code)"));
    }

    function _requireContract(address aContract, string memory tag) internal view {
        require(aContract != address(0), string.concat(tag, ": zero address"));
        require(_isContract(aContract), string.concat(tag, ": must be a contract"));
    }

    /////////////////////////////////////////////////////
    // SECURITY CONFIGURATION
    /////////////////////////////////////////////////////

    function _configureSecuritySettings() internal {
        console.log("Proposal threshold:", governor.PROPOSAL_THRESHOLD() / 1e18);
        console.log("Voting duration:", governor.VOTING_DURATION() / 1 days);
        console.log("Quorum %:", governor.QUORUM_PERCENTAGE());

        _performSecurityAudit();
    }

    function _performSecurityAudit() internal {
        assert(token.owner() == deployer);

        assert(address(token) != address(0));
        assert(address(governor) != address(0));
        assert(treasury != address(0));

        assert(token.totalSupply() <= token.MAX_SUPPLY());

        console.log("  Automated security audit passed");
        emit SecurityCheckPassed("Automated security audit");
    }
    //////////////////////////////////////////////////////////
    // OWNERSHIP TRANSFER
    //////////////////////////////////////////////////////////

    function _transferOwnership() internal {
        vm.startBroadcast(deployer);

        token.transferOwnership(address(governor));
        require(token.owner() == address(governor), "Token ownership transfer failed");
        emit OwnershipTransferred(address(token), address(governor));

        vm.stopBroadcast();
    }

    //////////////////////////////////////////////////
    // DEPLOYMENT COMPLETION
    //////////////////////////////////////////////////

    function _completeDeployment() internal deploymentNotComplete {
        deploymentComplete = true;
        emit DeploymentCompleted(address(token), address(governor), block.timestamp);

        console.log("GOVERNANCE PROTOCOL DEPLOYMENT COMPLETED SUCCESSFULLY!");
        console.log("GovernanceToken:", address(token));
        console.log("SimpleGovernor:", address(governor));
        console.log("GovernanceTimelock:", address(timelock));
        console.log("Treasury:", treasury);
    }

    //////////////////////////////////////////////////////////
    // UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////

    function _getSalt(string memory identifier) internal view returns (bytes32) {
        bool forceRedeploy = vm.envOr("FORCE_REDEPLOY", false);
        uint256 nonce = forceRedeploy ? block.timestamp : 0;
        return keccak256(abi.encodePacked(identifier, block.chainid, deployer, nonce));
    }

    //////////////////////////////////////////////////////////
    // EMERGENCY FUNCTIONS (FOR TESTING)
    //////////////////////////////////////////////////////////

    function emergencyReset() external {
        require(msg.sender == deployer, "Only deployer");
        require(block.chainid != 1, "Cannot reset on mainnet");
        deploymentComplete = false;
        console.log("Emergency reset performed");
    }

    ////////////////////////////////////////////////////
    // VIEW FUNCTIONS
    ////////////////////////////////////////////////////
    function getDeploymentInfo()
        external
        view
        returns (
            address tokenAddress,
            address governorAddress,
            address treasuryAddress,
            bool isComplete,
            uint256 timestamp
        )
    {
        return (address(token), address(governor), treasury, deploymentComplete, deploymentTimestamp);
    }

    function getSalt(string memory identifier) external view returns (bytes32) {
        return keccak256(abi.encodePacked(identifier, block.chainid, deployer));
    }

    function isContract(address aContract) external view returns (bool) {
        return aContract.code.length > 0;
    }

    function requireEOA(address aContract, string memory tag) external view returns (bool) {
        require(aContract != address(0), string.concat(tag, ": zero address"));
        require(aContract.code.length == 0, string.concat(tag, ": must be EOA (no code)"));
        return true;
    }

    function requireContract(address aContract, string memory tag) external view returns (bool) {
        require(aContract != address(0), string.concat(tag, ": zero address"));
        require(aContract.code.length > 0, string.concat(tag, ": must be a contract"));
        return true;
    }
}
