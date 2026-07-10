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
| 🎯 **Parallelizability score** | the probability (×100) that two concurrent calls don't conflict — per contract and per function, with an estimate of usable parallel lanes out of 16 |
| 🔥 **Hotspots** | the exact variable, its storage slot, who writes/reads it, severity |
| 🛠 **The fix** | before/after refactor using *your* variable names, per detected pattern |
| ✨ **AI fix** | one click: an LLM rewrites your actual code to remove the contention |
| 🔧 **Fix simulator** | edit the contract and re-score in place to prove the gain — *55 → 94* |
| 📡 **Live network monitor** | contention sampled from mainnet every 30s, a real-time chart, the hottest contracts right now |
| 🏷 **Named live contention** | for a verified contract, the storage slots actually colliding on-chain mapped back to their **variable names** (`s_orderIdCounter`, `balances[0x…]`, `positions[id].amount`) |
| 🏆 **Contention leaderboard** | the worst contention offenders on Monad over the last 24h, accumulated continuously — historical data no one else has |
| ⚙️ **CI gate** | fail a pull request when a contract scores below your threshold — [ci/](ci/) |

## Real mainnet results

Measured July 2026 on Monad mainnet (chain 143) with the v0.3 probabilistic
scoring, reproducible on [parascan.dev](https://parascan.dev). A function at
**0** is the model's literal claim: *two concurrent calls of it conflict
with probability 1* — under load it runs on one lane out of sixteen.

| Contract | Score | Worst hot function | Weak point |
|---|---|---|---|
| Uniswap V3 SwapRouter02 | **99** | swap callback **0** | `amountInCached` written on exact-output swaps |
| WMON | **98** | `transfer` 94 | none — naturally parallel |
| Uniswap V3 PositionManager | **98** | `mint()` **0** | `_nextId++` / `_nextPoolId++` serialize every position mint |
| aPriori aprMON | **86** | `deposit()` **0** | shared `totalPendingDeposit` accumulator; `requestRedeem()` also 0 (`nextRequestId++`) |
| Uniswap V3 Factory | **53** | `createPool()` **0** | shared `parameters` struct written on every pool creation |

(The contract column mixes all functions under a uniform traffic
assumption, so many clean functions can dilute one serialized hot function
— PositionManager averages 98 while `mint()` is 0. The worst-hot-function
column is the honest headline; traffic-weighted scores are on the roadmap.)

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
   serial depth and achievable speedup. A background collector samples the
   chain every 30s so the contention history accumulates continuously.

Engine 1 tells you *where contention is structurally guaranteed*; Engine 2
tells you *how much is actually happening on-chain*. **Fused**, they name it:
the raw slots Engine 2 sees colliding on mainnet are mapped back — through
the storage layout, keccak-derived mapping/array slots and keys harvested
from transaction calldata — to the exact variable in your source. When a
verified contract is contended, ParaScan can say *"`s_orderIdCounter` caused
these conflicts"* instead of *"slot 0x…"*.

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

**→ More: [FAQ.md](FAQ.md)** — Uniswap's `mint()` at 0/100, the ~x4
measurement, what happens to pasted code, what ParaScan misses, and more.

## Links

- 🌐 **App:** [parascan.dev](https://parascan.dev)
- ⚙️ CI gate: [ci/](ci/)
- 📖 Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- 📐 Methodology & limits: [METHODOLOGY.md](METHODOLOGY.md)
- 📚 Monad docs on parallel execution: [docs.monad.xyz](https://docs.monad.xyz/monad-arch/execution/parallel-execution)
