// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title GovernanceTimelock
 * @notice Timelock controller for governance proposals with configurable delays
 * @dev Extends OpenZeppelin TimelockController with additional security features
 */
contract GovernanceTimelock is TimelockController {
    uint256 public constant TESTNET_DELAY = 1 hours;
    uint256 public constant MAINNET_DELAY = 48 hours;
    uint256 public constant MAX_ALLOWED_DELAY = 30 days;
    uint256 public constant EMERGENCY_DELAY = 6 hours; // For critical fixes

    mapping(bytes32 => string) public proposalDescriptions;
    mapping(bytes32 => uint256) public proposalTypes;

    event ProposalQueued(
        bytes32 indexed id, uint256 indexed proposalType, string description, uint256 delay, uint256 executionTime
    );
    event ProposalExecuted(bytes32 indexed id, uint256 indexed proposalType, string description);
    // event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event DelayChangeRequested(uint256 newDelay, bytes32 salt, address proposer);
    event DelayChangeExecuted(uint256 newDelay, bytes32 salt, address executor);

    /**
     * @notice Constructor for GovernanceTimelock
     * @param minDelay Minimum delay for operations
     * @param proposers List of addresses that can propose
     * @param executors List of addresses that can execute (use address(0) for public execution)
     * @param admin Address that can manage roles (should be renounced after setup)
     */
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {
        if (block.chainid == 1) {
            require(minDelay >= MAINNET_DELAY, "Mainnet delay too short");
        } else {
            require(minDelay >= TESTNET_DELAY, "Testnet delay too short");
        }

        require(minDelay <= MAX_ALLOWED_DELAY, "Delay exceeds maximum");
        _grantRole(PROPOSER_ROLE, address(this));
    }

    /**
     * @notice Schedule a proposal with metadata
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Call data
     * @param predecessor Previous proposal dependency (usually bytes32(0))
     * @param salt Unique salt for proposal
     * @param delay Execution delay
     * @param description Human-readable description
     * @param proposalType Type of proposal for categorization
     */
    function scheduleWithMetadata(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay,
        string memory description,
        uint256 proposalType
    ) external onlyRole(PROPOSER_ROLE) {
        schedule(target, value, data, predecessor, salt, delay);

        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        proposalDescriptions[id] = description;
        proposalTypes[id] = proposalType;

        emit ProposalQueued(id, proposalType, description, delay, block.timestamp + delay);
    }

    /**
     * @notice Schedule a batch of operations with metadata
     */
    function scheduleBatchWithMetadata(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay,
        string memory description,
        uint256 proposalType
    ) external onlyRole(PROPOSER_ROLE) {
        scheduleBatch(targets, values, payloads, predecessor, salt, delay);

        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        proposalDescriptions[id] = description;
        proposalTypes[id] = proposalType;

        emit ProposalQueued(id, proposalType, description, delay, block.timestamp + delay);
    }

    /**
     * @notice Execute a proposal and emit metadata events
     */
    function executeWithMetadata(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        external
        payable
    {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        string memory description = proposalDescriptions[id];
        uint256 proposalType = proposalTypes[id];

        execute(target, value, data, predecessor, salt);

        emit ProposalExecuted(id, proposalType, description);

        delete proposalDescriptions[id];
        delete proposalTypes[id];
    }

    /**
     * @notice Execute a batch proposal and emit metadata events
     */
    function executeBatchWithMetadata(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external payable {
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        string memory description = proposalDescriptions[id];
        uint256 proposalType = proposalTypes[id];

        executeBatch(targets, values, payloads, predecessor, salt);

        emit ProposalExecuted(id, proposalType, description);

        delete proposalDescriptions[id];
        delete proposalTypes[id];
    }

    /**
     * @notice Schedule a timed operation that will call updateDelay(newDelay) on the timelock itself.
     * @dev Caller must have PROPOSER_ROLE. The operation will be executable after getMinDelay().
     */
    function requestUpdateDelay(uint256 newDelay, bytes32 salt) external onlyRole(PROPOSER_ROLE) {
        if (block.chainid == 1) {
            require(newDelay >= MAINNET_DELAY, "Mainnet delay too short");
        } else {
            require(newDelay >= TESTNET_DELAY, "Testnet delay too short");
        }
        require(newDelay <= MAX_ALLOWED_DELAY, "Delay exceeds maximum");

        bytes memory data = abi.encodeWithSelector(this.updateDelay.selector, newDelay);
        this.schedule(address(this), 0, data, bytes32(0), salt, getMinDelay());

        emit DelayChangeRequested(newDelay, salt, msg.sender);
    }

    /**
     * @notice Execute the previously scheduled delay change.
     * @dev Caller must have EXECUTOR_ROLE (or be address(0) executor if you allowed public execution).
     */
    function executeUpdateDelay(uint256 newDelay, bytes32 salt) external onlyRole(EXECUTOR_ROLE) {
        bytes memory data = abi.encodeWithSelector(this.updateDelay.selector, newDelay);
        this.execute(address(this), 0, data, bytes32(0), salt);

        emit DelayChangeExecuted(newDelay, salt, msg.sender);
    }

    /**
     * @notice Get proposal metadata
     * @param id Proposal ID
     * @return description Human-readable description
     * @return proposalType Type of proposal
     * @return isReady Whether proposal is ready for execution
     */
    function getProposalMetadata(bytes32 id)
        external
        view
        returns (string memory description, uint256 proposalType, bool isReady)
    {
        description = proposalDescriptions[id];
        proposalType = proposalTypes[id];
        isReady = isOperationReady(id);
    }

    /**
     * @notice Check if timelock is properly configured
     * @return isConfigured Whether timelock has proper role setup
     */
    function isProperlyConfigured(address expectedGovernor, address expectedMultisig) external view returns (bool) {
        bool proposerOk = hasRole(PROPOSER_ROLE, expectedGovernor);
        bool cancellerOk = expectedMultisig == address(0) ? true : hasRole(CANCELLER_ROLE, expectedMultisig);
        return proposerOk && cancellerOk;
    }

    /**
     * @notice Get network-appropriate delay
     * @return delay Recommended delay for current network
     */
    function getNetworkDelay() external view returns (uint256 delay) {
        if (block.chainid == 1) {
            return MAINNET_DELAY;
        } else {
            return TESTNET_DELAY;
        }
    }

    /**
     * @notice Emergency function to cancel a proposal (only admin)
     * @param id Proposal ID to cancel
     */
    function emergencyCancel(bytes32 id) external onlyRole(CANCELLER_ROLE) {
        require(isOperation(id), "Operation does not exist");
        require(!isOperationDone(id), "Operation already executed");

        cancel(id);

        delete proposalDescriptions[id];
        delete proposalTypes[id];
    }

    receive() external payable override {}
    fallback() external payable {}
}
