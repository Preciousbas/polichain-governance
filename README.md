# Polichain – Decentralized Governance Protocol
## Overview

Polichain is a lightweight, on-chain governance protocol designed to empower communities with transparent, decentralized decision-making. Token holders can propose, vote, and execute governance actions directly on-chain. The system includes a timelock for secure execution and a treasury for controlled management of funds.

This project was built as part of the Tatum Hackathon and demonstrates the use of Tatum’s RPC infrastructure.

## Features

- Governance Token (PCT): ERC20-compatible token used for voting power.

- Governor Contract: Allows token holders to create proposals and vote.

- Timelock Controller: Enforces execution delays for additional security.

- Treasury: Manages protocol funds, receiving minted tokens and transfers.

* Token-Weighted Voting: Voting power is proportional to token holdings.

- Fully On-Chain Transparency: All proposals, votes, and executions are stored on-chain.

## Architecture

- GovernanceToken.sol – ERC20 voting token with delegation.

- SimpleGovernor.sol – Governance logic for proposals and voting.

- GovernanceTimelock.sol – Enforces a time delay before proposal execution.

- Deployment Scripts – Automated deployment with Forge.

## Tatum Integration

Tatum RPC: Used as the primary provider for interacting with Sepolia testnet.

## Deployment

- Network: Ethereum Sepolia Testnet

- Deployer: Forge

- Token Symbol: PCT (Polichain Token)

### Key Contracts/Addresses:

- Governance Token: 0x875eEa8bB1baE34EDCC821A8561bF722C946C549

Governor: 0xA600AAbCA11a0dC0c99ED7426d47f716Ad934925

## Running Locally
### Prerequisites

- Foundry
 for compiling and deploying contracts

- Node.js & npm for the frontend

- Sepolia RPC URL from [Tatum](https://tatum.io)
