# Litigation Finance Tokenisation Platform

Smart contract implementation for tokenising litigation claims on Ethereum. Developed as part of the IFTE0007 Decentralised Finance and Blockchain coursework at UCL.

## Overview

The platform enables fractional investment in litigation cases through a hybrid token architecture of four smart contracts:

- **MockUSDC** (ERC-20) — Test stablecoin simulating USDC for Sepolia testnet
- **CaseNFT** (ERC-721) — Non-transferable token serving as an on-chain registry of case metadata
- **LitigationVault** (ERC-4626) — Tokenised vault issuing LIT tokens to passive investors who deposit USDC into a diversified pool of cases
- **CaseManager** — Central orchestrator that creates cases, manages funding rounds, resolves outcomes, and distributes payouts

## Deployed Contracts (Sepolia Testnet)

| Contract | Address |
|----------|---------|
| MockUSDC | `0x6f5eAe3817eb8bAFb40ED5ee72D98ccaEa8Ffc21` |
| CaseNFT | `0x538545aF48008d9DC136B834A36888CaD091Cd03` |
| LitigationVault | `0x2CfdB6AcED44E789ffc5F854f809be07980Bc27D` |
| CaseManager | `0x1C252Da9ff79400A4105d7f9802D0F4cC756Af62` |

## Token Architecture

```
Passive Investor → deposit USDC → LitigationVault → receive LIT tokens
Direct Investor  → fundDirect USDC → CaseManager → receive CASE-XXX tokens
```

**LIT tokens** represent a share in a diversified portfolio of cases. Value appreciates automatically when cases are won.

**CASE-XXX tokens** represent a direct investment in a specific case. One ERC-20 token is deployed per case.

**Case NFTs** store on-chain metadata: jurisdiction, case type, claim amount, funding requirement, and procedural stage.

## Workflow

1. **Create case** — Owner calls `createCase()` on CaseManager
2. **Fund case** — Via vault (`fundFromVault()`) or directly (`fundDirect()`)
3. **Close funding** — Owner calls `closeFunding()`
4. **Resolve case** — Owner calls `resolveCase(caseId, won, payoutAmount)`
5. **Distribute payout** — Vault receives its share via `receivePayout()`; direct investors claim via `claimDirectPayout()`

## Tech Stack

- Solidity ^0.8.20
- OpenZeppelin Contracts 5.x
- Ethereum Sepolia Testnet
- Remix IDE
