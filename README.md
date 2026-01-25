# ShadowSwap

Privacy-first execution for Uniswap v4: **encrypted swap intents**, **trader-first MEV protection**, and **off-chain matching** coordinated by an AVS-style service manager.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue.svg)](https://soliditylang.org/)

## What problem are we solving?

On public DEXs, large traders routinely lose money because:

- **MEV attacks** (especially sandwiching) worsen execution.
- **Information leakage** (size/direction/limits visible pre-trade) lets searchers position against you.

ShadowSwap’s goal is to make “trading on a public AMM” feel closer to “trading with a private execution desk”:
intent is private, matching is coordinated, and value that would go to MEV searchers is redirected back to **traders**, **LPs**, and the **protocol**.

## ShadowSwap in one sentence

**ShadowSwap is a Uniswap v4 hook that accepts encrypted intents, queues them for private matching, and applies a trader-first MEV allocation model (trader made whole first, remainder split to LPs + protocol).**

## Why traders use ShadowSwap

- **Private intent**: order size/direction/slippage bounds are encrypted (Fhenix FHE types).
- **MEV protection**: trader-first rebates aim to neutralize measurable MEV loss versus a fair price reference.
- **Better execution for size**: off-chain matching can net opposing flow before hitting the AMM.

## Why LPs + the protocol win

- **LP alignment**: LPs receive a share of the remaining “captured value” after traders are protected.
- **Protocol revenue**: a protocol share is reserved from the remainder to fund operations.

## Architecture (high level)

```
User / Frontend
  |  encrypt intent (Fhenix)
  v
Uniswap v4 PoolManager
  |  calls hooks
  v
ShadowSwapHook (on-chain)
  - stores encrypted orders
  - emits events + calls service manager
  - records trader-first allocation accounting
  v
Service Manager (AVS-style coordinator)
  - watches events
  - finds matches off-chain
  - calls executeMatch() on-chain
```

## Economics: Trader-first MEV allocation

ShadowSwap uses a **Trader-first** policy:

1. Estimate the trader’s shortfall vs a **fair price** (oracle/TWAP-style reference).
2. Allocate to the trader first (up to the captured value).
3. Split what remains:
   - **80% to LP rewards**
   - **20% to protocol treasury**

Important: the current implementation records **accounting** and emits events; **token settlement/claims are not implemented yet** (see “Status & limitations”).

## Uniswap v4 hook notes (flash accounting)

Uniswap v4 uses **flash accounting**: if a hook returns a non-zero delta, that delta must be properly **settled/taken** within the same unlocked flow.

ShadowSwap currently does **not** return a swap delta from `beforeSwap`; it returns `BeforeSwapDeltaLibrary.ZERO_DELTA` and only overrides the dynamic LP fee.

## Code pointers

- **Main hook**: `src/ShadowSwapHook.sol`
  - Encrypted order intake in `_beforeSwap`
  - Trader-first accounting in `_captureMEV`
  - Oracle-based loss estimate in `_estimateTraderLoss`
  - Matching callback restricted to service manager in `executeMatch`

- **MEV library (math utilities / reference)**: `src/libraries/MEVRedistribution.sol`

## Oracle interface (for Trader-first loss estimation)

`ShadowSwapHook` expects an oracle that supports:

- `getPriceX18(bytes32 poolId) -> uint256`

Where the return value is `token1PerToken0` scaled by `1e18` for that pool’s `poolId`.
For `oneForZero` swaps, the hook inverts that price internally.

Configure via:

- `setPriceOracle(address)`
- `setProtocolTreasury(address)`

## Status & limitations (important)

This repo is an MVP / prototype and intentionally leaves some parts as “accounting-first”:

- **Captured value is a placeholder estimate** derived from swap deltas (needs a production-grade definition tied to measurable MEV savings).
- **Rebates / LP rewards / protocol fees are accounted for**, but not actually paid out on-chain yet (no claim/settle flow).
- **FHE boolean checks use a heuristic** in `FHEUtils` (explicitly marked as not production-safe).
- The AVS/service manager integration is a simplified coordinator stub.

## Development

### Prerequisites

- Foundry
- Node.js (optional for `frontend/`)

### Build & test

```bash
forge build
forge test --summary
```

### Deploy (Foundry script)

```bash
forge script script/Deploy.s.sol:DeployShadowSwap --sig "deployLocal()" --broadcast
```

## Roadmap (suggested next steps)

- Replace placeholder “captured value” with a defensible MEV-savings metric (oracle/TWAP + route simulation).
- Implement **actual settlement**:
  - trader rebate claiming
  - LP reward distribution mechanism
  - protocol fee withdrawal
- Harden oracle design (TWAP windowing, manipulation resistance).
- Security review + audits (especially around hooks + settlement flows).

## License

MIT. See `LICENSE`.