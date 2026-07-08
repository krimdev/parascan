# Monad Mainnet Parallelizability Leaderboard

Scores produced by ParaScan v0.2 (static analysis) on verified mainnet
contracts, July 8, 2026. Chain ID 143. Proxies are followed to their
EIP-1967 implementation automatically.

| # | Protocol / Contract | Address | Score | Hot-path weak point |
|---|---|---|---|---|
| 1 | WMON (Wrapped MON) | `0x3bd359...433a` | **98** | none — naturally parallel |
| 2 | Uniswap V3 SwapRouter02 | `0xfe31f7...b900` | **98** | `amountInCached` global cache written on exact-output swaps |
| 3 | Uniswap V3 NonfungiblePositionManager | `0x7197e2...4e53` | **95** | `mint()` **16/100** — `_nextId++` / `_nextPoolId++` serialize every position mint |
| 4 | Uniswap V3 Factory | `0x204fac...0498` | **78** | `createPool()` writes a shared `parameters` struct |
| 5 | aPriori aprMON (LST, via proxy) | `0x0c65A0...0852` | **74** | `deposit()` 59/100 — every stake writes `totalPendingDeposit`; `requestRedeem()` 24/100 — global `nextRequestId++` |

## Reading the numbers

- A contract-level score near 100 can still hide a serialized hot
  function: NonfungiblePositionManager averages 95 because most of its
  functions are clean, but its single most important function, `mint()`,
  scores 16 — on Monad, concurrent liquidity-position mints re-execute
  serially.
- aPriori's `deposit()` finding matters because staking deposits are
  precisely the kind of traffic that spikes in parallel (airdrops,
  incentive programs): a shared `totalPendingDeposit` accumulator turns
  those spikes into a queue.
- These are *static worst-case* results: they show where conflicts are
  structurally guaranteed, not their measured frequency (that is Engine 2,
  on the roadmap).

## Not yet scannable

Some flagship protocols (e.g. nad.fun) verify their contracts on
MonadScan/Etherscan rather than Sourcify; Etherscan-source support is
planned.

## Reproduce

```bash
node bin/parascan.js 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A
node bin/parascan.js 0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900
node bin/parascan.js 0x7197e214c0b767cfb76fb734ab638e2c192f4e53
node bin/parascan.js 0x204faca1764b154221e35c0d20abb3c525710498
node bin/parascan.js 0x0c65A0BC65a5D819235B71F554D210D3F80E0852
```
