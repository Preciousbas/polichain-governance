// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {GovernanceToken} from "src/MyToken.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract SimpleGovernor is Ownable {
    enum ProposalStatus {
        Active,
        Passed,
        Failed,
        Executed
    }

    enum ProposalType {
        General,
        MintTokens,
        TransferETH,
        UpdateQuorum
    }

    struct ProposalAction {
        ProposalType proposalType;
        address target;
        uint256 amount;
        bytes data;
    }

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 snapshotBlock;
        ProposalStatus status;
        ProposalAction action;
        bool executed;
    }

    ERC20Votes public immutable governanceToken;

    uint256 public constant VOTING_DURATION = 3 days;
    uint256 public constant PROPOSAL_THRESHOLD = 1000 * 10 ** 18; // 1000 tokens to propose
    uint256 public constant QUORUM_PERCENTAGE = 4; // 4% of total supply needed for quorum
    uint256 public proposalCount;
    uint256 public quorumPercentage = QUORUM_PERCENTAGE;

    address public treasury;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => ProposalAction) public proposalActions;

    event ProposalCreated(
        uint256 indexed proposalId, address indexed proposer, string description, uint256 snapshotBlock
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);

    modifier onlyTokenHolders() {
        require(governanceToken.balanceOf(msg.sender) > 0, "Must hold governance tokens");
        _;
    }

    constructor(address _governanceToken, address _treasury, address _initialOwner) Ownable(_initialOwner) {
        require(_governanceToken != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        governanceToken = ERC20Votes(_governanceToken);
        treasury = _treasury;
    }

    /**
     * @notice Create a new proposal
     * @param description Description of the proposal
     * @return proposalId The ID of the created proposal
     */
    function createProposal(string memory description) external onlyTokenHolders returns (uint256) {
        require(bytes(description).length > 0, "Description cannot be empty");

        uint256 proposerVotes = governanceToken.getVotes(msg.sender);
        require(proposerVotes >= PROPOSAL_THRESHOLD, "Insufficient tokens to propose");

        uint256 proposalId = ++proposalCount;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_DURATION;
        uint256 snapshotBlock = block.number - 1; // Use previous block for snapshot

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: startTime,
            endTime: endTime,
            snapshotBlock: snapshotBlock,
            status: ProposalStatus.Active,
            action: ProposalAction({proposalType: ProposalType.General, target: address(0), amount: 0, data: ""}),
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, snapshotBlock);
        return proposalId;
    }

    /**
     * @notice Create a proposal to mint tokens to treasury
     * @param description Description of the proposal
     * @param amount Amount of tokens to mint
     */
    function createMintProposal(string memory description, uint256 amount)
        external
        onlyTokenHolders
        returns (uint256)
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(amount > 0, "Amount must be greater than 0");

        uint256 proposerVotes = governanceToken.getVotes(msg.sender);
        require(proposerVotes >= PROPOSAL_THRESHOLD, "Insufficient tokens to propose");

        uint256 proposalId = ++proposalCount;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_DURATION;
        uint256 snapshotBlock = block.number - 1;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: startTime,
            endTime: endTime,
            snapshotBlock: snapshotBlock,
            status: ProposalStatus.Active,
            action: ProposalAction({proposalType: ProposalType.MintTokens, target: treasury, amount: amount, data: ""}),
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, snapshotBlock);
        return proposalId;
    }

    /**
     * @notice Create a proposal to transfer ETH from treasury
     * @param description Description of the proposal
     * @param to Address to transfer ETH to
     * @param amount Amount of ETH to transfer (in wei)
     */
    function createTransferProposal(string memory description, address to, uint256 amount)
        external
        onlyTokenHolders
        returns (uint256)
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        uint256 proposerVotes = governanceToken.getVotes(msg.sender);
        require(proposerVotes >= PROPOSAL_THRESHOLD, "Insufficient tokens to propose");

        uint256 proposalId = ++proposalCount;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_DURATION;
        uint256 snapshotBlock = block.number - 1;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: startTime,
            endTime: endTime,
            snapshotBlock: snapshotBlock,
            status: ProposalStatus.Active,
            action: ProposalAction({proposalType: ProposalType.TransferETH, target: to, amount: amount, data: ""}),
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, snapshotBlock);
        return proposalId;
    }

    /**
     * @notice Create a proposal to update quorum percentage
     * @param description Description of the proposal
     * @param newQuorumPercentage New quorum percentage (1-100)
     */
    function createQuorumUpdateProposal(string memory description, uint256 newQuorumPercentage)
        external
        onlyTokenHolders
        returns (uint256)
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(newQuorumPercentage > 0 && newQuorumPercentage <= 100, "Invalid quorum percentage");

        uint256 proposerVotes = governanceToken.getVotes(msg.sender);
        require(proposerVotes >= PROPOSAL_THRESHOLD, "Insufficient tokens to propose");

        uint256 proposalId = ++proposalCount;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_DURATION;
        uint256 snapshotBlock = block.number - 1;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: startTime,
            endTime: endTime,
            snapshotBlock: snapshotBlock,
            status: ProposalStatus.Active,
            action: ProposalAction({
                proposalType: ProposalType.UpdateQuorum,
                target: address(this),
                amount: newQuorumPercentage,
                data: ""
            }),
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, snapshotBlock);
        return proposalId;
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId ID of the proposal to vote on
     * @param support True for support, false for against
     */
    function vote(uint256 proposalId, bool support) external {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp <= proposal.endTime, "Voting period ended");

        uint256 weight = governanceToken.getPastVotes(msg.sender, proposal.snapshotBlock);
        require(weight > 0, "No voting power at snapshot");

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Finalize a proposal after voting period ends
     * @param proposalId ID of the proposal to finalize
     */
    function finalizeProposal(uint256 proposalId) external {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp > proposal.endTime, "Voting period not ended");

        _finalizeProposal(proposalId);
    }

    /**
     * @notice Internal function to finalize proposal
     * @param proposalId ID of the proposal to finalize
     */
    function _finalizeProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];

        // Check quorum - total votes must be >= 4% of total supply at snapshot
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        uint256 requiredQuorum = (governanceToken.getPastTotalSupply(proposal.snapshotBlock) * quorumPercentage) / 100;

        if (totalVotes < requiredQuorum) {
            proposal.status = ProposalStatus.Failed;
            emit ProposalFinalized(proposalId, ProposalStatus.Failed);
            return;
        }

        // Determine result based on votes
        if (proposal.forVotes > proposal.againstVotes) {
            proposal.status = ProposalStatus.Passed;
        } else {
            proposal.status = ProposalStatus.Failed;
        }

        emit ProposalFinalized(proposalId, proposal.status);
    }

    /**
     * @notice Execute a passed proposal (only owner)
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) external onlyOwner {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        Proposal storage proposal = proposals[proposalId];

        // Auto-finalize if voting has ended and still Active
        if (proposal.status == ProposalStatus.Active && block.timestamp > proposal.endTime) {
            _finalizeProposal(proposalId);
        }

        require(!proposal.executed, "Already executed");
        require(proposal.status == ProposalStatus.Passed, "Proposal not passed");

        proposal.executed = true;
        proposal.status = ProposalStatus.Executed;

        _executeProposalAction(proposal.action);

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Internal function to execute proposal actions
     * @param action The action to execute
     */
    function _executeProposalAction(ProposalAction memory action) internal {
        if (action.proposalType == ProposalType.General) {
            // No specific execution logic
            // Just for governance signaling/voting
            return;
        } else if (action.proposalType == ProposalType.MintTokens) {
            // Mint tokens to treasury
            GovernanceToken(address(governanceToken)).mint(treasury, action.amount);
        } else if (action.proposalType == ProposalType.TransferETH) {
            // Transfer ETH from contract to target
            require(address(this).balance >= action.amount, "Insufficient contract balance");
            (bool success,) = action.target.call{value: action.amount}("");
            require(success, "ETH transfer failed");
        } else if (action.proposalType == ProposalType.UpdateQuorum) {
            // Update quorum percentage
            quorumPercentage = action.amount;
        }
    }

    /**
     * @notice Get proposal by ID
     * @param proposalId ID of the proposal
     * @return Proposal data
     */
    function getProposalById(uint256 proposalId) external view returns (Proposal memory) {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");
        return proposals[proposalId];
    }

    /**
     * @notice Get all proposals
     * @return Array of all proposals
     */
    function getAllProposals() external view returns (Proposal[] memory) {
        Proposal[] memory allProposals = new Proposal[](proposalCount);
        for (uint256 i = 1; i <= proposalCount; i++) {
            allProposals[i - 1] = proposals[i];
        }
        return allProposals;
    }

    /**
     * @notice Get active proposals
     * @return Array of active proposals
     */
    function getActiveProposals() external view returns (Proposal[] memory) {
        uint256 activeCount = 0;

        // Count active proposals
        for (uint256 i = 1; i <= proposalCount; i++) {
            if (proposals[i].status == ProposalStatus.Active && block.timestamp <= proposals[i].endTime) {
                activeCount++;
            }
        }

        // Create array of active proposals
        Proposal[] memory activeProposals = new Proposal[](activeCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= proposalCount; i++) {
            if (proposals[i].status == ProposalStatus.Active && block.timestamp <= proposals[i].endTime) {
                activeProposals[index] = proposals[i];
                index++;
            }
        }

        return activeProposals;
    }

    /**
     * @notice Check if an address can vote on a proposal
     * @param proposalId ID of the proposal
     * @param voter Address to check
     * @return ableToVote Whether the address can vote
     * @return votingPower Voting power of the address
     */
    function canVote(uint256 proposalId, address voter) external view returns (bool ableToVote, uint256 votingPower) {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");

        Proposal storage proposal = proposals[proposalId];

        if (
            hasVoted[proposalId][voter] || proposal.status != ProposalStatus.Active
                || block.timestamp > proposal.endTime
        ) {
            return (false, 0);
        }

        votingPower = governanceToken.getPastVotes(voter, proposal.snapshotBlock);
        ableToVote = votingPower > 0;
    }

    /**
     * @notice Get quorum requirements for a proposal
     * @param proposalId ID of the proposal
     * @return required Required votes for quorum
     * @return current Current total votes
     * @return met Whether quorum is met
     */
    function getQuorumInfo(uint256 proposalId) external view returns (uint256 required, uint256 current, bool met) {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal ID");

        Proposal storage proposal = proposals[proposalId];
        required = (governanceToken.getPastTotalSupply(proposal.snapshotBlock) * quorumPercentage) / 100;
        current = proposal.forVotes + proposal.againstVotes;
        met = current >= required;
    }

    /**
     * @notice Get actions for a proposal
     * @param proposalId ID of the proposal
     * @return required Required votes for quorum
     * @return current Current total votes
     * @return met Whether quorum is met
     */
    function getProposalAction(uint256 proposalId)
        external
        view
        returns (ProposalType, address, uint256, bytes memory)
    {
        Proposal storage p = proposals[proposalId];
        return (p.action.proposalType, p.action.target, p.action.amount, p.action.data);
    }

    receive() external payable {}
}
