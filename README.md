# VIPR Stablecoin (VSC) System

A decentralized, algorithmic stablecoin system built on Ethereum that maintains a 1:1 peg with the US dollar. VSC is backed by exogenous collateral (WETH and WBTC) and designed to remain overcollateralized at all times.

## Overview

The VIPR Stablecoin system consists of two main contracts:

1. **ViprStableCoin (VSC)**: The ERC20 token itself, with mint and burn functions controlled by the owner.
2. **VSCEngine**: The core contract that manages collateral, minting, burning, redemption, and liquidation processes.

This system is inspired by MakerDAO's DSS system and Cryfin:
- No governance
- No fees
- Only WETH and WBTC as collateral
- Always overcollateralized (minimum of 200%)

## Key Features

- **Collateral Management**: Deposit and withdraw WETH and WBTC as collateral
- **Minting & Burning**: Create and destroy VSC tokens based on collateral
- **Liquidation System**: Undercollateralized positions can be liquidated with a bonus to liquidators
- **Health Factor Monitoring**: System tracks each user's collateralization ratio
- **Price Oracle Integration**: Uses Chainlink price feeds for real-time collateral valuation

## Deployment

The contracts have been deployed on the Sepolia testnet. Below are the contract addresses for reference:

- **Vipr Stablecoin (VSC) Contract**: [View on Etherscan](https://sepolia.etherscan.io/address/0x8beb8fe513ff3f15571c0E8cAa36B4d1cbe5e29d)
- **VSC Engine Contract**: [View on Etherscan](https://sepolia.etherscan.io/address/0x346E008Df62609E40C46bbF549Ec4848348157eb)

You can interact with these contracts on Sepolia using your Ethereum wallet or through a script.


## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - Ethereum development toolkit
- A `.env` file with required environment variables

## Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/Vinayapr23/ViprStableCoin.git
cd ViprStableCoin
make install
```

## Usage

This project uses a Makefile to simplify common operations:

### Build and Test

```bash
# Build the project
make build

# Run all tests
make test

# Generate code coverage report
make coverage
```

### Usage

```bash
# Start a local Anvil node
make anvil

# Deploy to local Anvil instance
make deploy

# Deploy to Sepolia testnet
make deploy ARGS="--network sepolia"
```

### Development Tools

```bash
# Format code
make format

# Create a gas snapshot
make snapshot
```

## Contract Architecture

### ViprStableCoin

The VSC token implements ERC20 with additional features:

- Extends ERC20Burnable and Ownable from OpenZeppelin
- Initial supply: 1,000,000 VSC (minted to deployer)
- Controlled minting and burning functions (only by owner)

### VSCEngine

The core engine that manages the protocol's functionality:

- Deposit collateral (WETH/WBTC)
- Mint VSC against collateral
- Burn VSC to reduce debt
- Redeem collateral when positions are healthy
- Liquidate undercollateralized positions

#### Key Parameters

- **LIQUIDATION_THRESHOLD**: 50 (representing 50%, requiring 200% collateralization)
- **LIQUIDATION_BONUS**: 10 (representing 10% bonus for liquidators)
- **MIN_HEALTH_FACTOR**: 1e18 (representing a health factor of 1)
- **PRECISION** and **ADDITIONAL_FEED_PRECISION**: Constants for math operations


## Development Status

The project is currently in development with ongoing work on:

- Comprehensive test coverage
- Integration tests with Chainlink price feeds
- User interface for interacting with the protocol
- Additional collateral types

## Environment Setup

Create a `.env` file with the following variables:

```
SEPOLIA_RPC_URL=your_sepolia_rpc_url
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Makefile Commands

```bash
make help  # Show all available commands
```

## Author

Vinaya Prasad R
