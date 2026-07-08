<div align="center">

# ParaScan `//`

**Is your contract *actually* parallel?**

The parallelism profiler for Solidity contracts on [Monad](https://www.monad.xyz/).

**[→ parascan.dev](https://parascan.dev)** · free · no signup

</div>

---

## The problem

Monad executes independent transactions **in parallel** — validators run on
16+ CPU cores by [spec](https://docs.monad.xyz/monad-arch/hardware-requirements),
and transactions without common dependencies are
[scheduled on separate cores](https://docs.monad.xyz/monad-arch/execution/parallel-execution).
That's where the 10,000 TPS comes from. But when two transactions touch the
same storage slot, they must re-execute **one by one**.

Fifteen years of Ethereum habits produce code that does exactly that:

```solidity
totalTransfers++;                 // every tx writes the same slot
collectedFees += fee;             // every tx writes the same slot
lastTransferBlock = block.number; // every tx writes the same slot
```

Each line is a single toll booth on a 16-lane highway. The code compiles,
works, and nothing warns you — it just quietly runs on one lane.

Ecosystem dev guides already say it plainly: *"profile storage access to
reduce shared-state writes and maximize the gains from parallelism"*
([A Developer's Guide to Monad, QuickNode](https://blog.quicknode.com/monad-developer-guide/)).
The advice existed. The profiler didn't. **Now it does.**

## What ParaScan does

Paste a **mainnet address** or **raw Solidity** at [parascan.dev](https://parascan.dev) and get:

| | |
|---|---|
| 🎯 **Parallelizability score** | 0–100, per contract and per function |
| 🔥 **Hotspots** | the exact variable, its storage slot, who writes/reads it, severity |
| 🛠 **The fix** | before/after refactor using *your* variable names, per detected pattern |
| ✨ **AI fix** | one click: an LLM rewrites your actual code to remove the contention |
| 📡 **Live network monitor** | real contention measured on the latest Monad blocks, hottest contracts right now |

## Real mainnet results

Measured July 2026 on Monad mainnet (chain 143), reproducible on
[parascan.dev](https://parascan.dev):

| Contract | Score | Hot-path weak point |
|---|---|---|
| WMON | **98** | none — naturally parallel |
| Uniswap V3 SwapRouter02 | **98** | `amountInCached` written on exact-output swaps |
| Uniswap V3 PositionManager | **95** | `mint()` **16/100** — `_nextId++` / `_nextPoolId++` serialize every position mint |
| Uniswap V3 Factory | **78** | `createPool()` writes a shared struct |
| aPriori aprMON | **74** | `deposit()` 59 — shared `totalPendingDeposit`; `requestRedeem()` 24 — global `nextRequestId++` |

And from tracing live blocks: the **average achievable parallel speedup on
current mainnet blocks is ~x4** — the rest is lost to storage contention.
Notably, the single most contended contract on the chain has never published
its source code.

## How it's built

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the full technical breakdown and
**[METHODOLOGY.md](METHODOLOGY.md)** for the scoring model, the speedup
measurement and the honest limitations.

The short version — two engines:

1. **Engine 1 — static analysis.** Compiles the verified source with the exact
   original solc version, walks the AST and the storage layout, and classifies
   every storage access of every externally reachable function by *contention
   scope* (shared slot / constant-key / per-param / per-sender). Inheritance,
   internal calls, modifiers and EIP-1967 proxies are resolved.
2. **Engine 2 — live measurement.** Traces recent mainnet blocks
   (`debug_traceBlockByNumber`, prestateTracer), extracts each transaction's
   real read/write sets, builds the dependency graph and computes each block's
   serial depth and achievable speedup.

Engine 1 tells you *where contention is structurally guaranteed*; Engine 2
tells you *how much is actually happening on-chain*.

## FAQ

**Is it free?** Yes. Scanning is free and requires no signup.

**Is the scanner open source?** The core engine is closed source for now; this
repository documents the architecture, methodology and results in detail so
every number can be understood and challenged.

**My contract barely has users — does the score matter?** Parallelism is
about all the transactions in a block, yours and everyone else's. A hotspot
is invisible while your app is small and shows up the day it succeeds — 500
mints in one second running one by one. ParaScan measures rush-hour behavior
before rush hour happens.

**Is a bad score always a bug?** No. Some patterns (like sequential NFT ids)
are product decisions. ParaScan makes the cost visible; the tradeoff is yours.

**→ More: [FAQ.md](FAQ.md)** — Uniswap at 16/100, the ~x4 measurement, what
happens to pasted code, what ParaScan misses, and more.

## Links

- 🌐 **App:** [parascan.dev](https://parascan.dev)
- 📖 Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- 📐 Methodology & limits: [METHODOLOGY.md](METHODOLOGY.md)
- 📚 Monad docs on parallel execution: [docs.monad.xyz](https://docs.monad.xyz/monad-arch/execution/parallel-execution)
