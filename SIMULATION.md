# The saturation simulation — what it shows, and what it doesn't

Live at **[parascan.dev](https://parascan.dev)** (Simulation tab, or
[parascan.dev/sim.html](https://parascan.dev/sim.html) full screen).

The same demand ramp hits two contracts, side by side, on 16 execution
lanes each. The only difference between them is **storage layout**:

| | Left — ⚠ SERIAL | Right — ✓ PARALLEL |
|---|---|---|
| Code | `totalTransfers++;` | `balances[msg.sender]++;` |
| Who touches the slot | every transaction | each sender their own |
| Under load | ~600 TPS, queue explodes | ~10,000 TPS, queue empty |

## The mechanics — mapped to Monad's documented behavior

Monad executes a block's transactions **in parallel, optimistically**,
then re-executes serially any transaction whose inputs were invalidated
by an earlier one ([Monad docs — parallel
execution](https://docs.monad.xyz/monad-arch/execution/parallel-execution)).
The simulation animates exactly that:

1. Every transaction gets **one optimistic pass** on a free lane — both
   sides do, that's the point of optimistic execution.
2. On the serial contract, that pass read a slot another transaction
   wrote: it **flashes red, rolls back, and joins the serial commit
   lane** (the marked lane 0), where conflicting transactions re-execute
   strictly one at a time.
3. On the parallel contract, nothing collides: every lane commits.
4. A transaction that is **alone in flight commits its optimistic pass
   even on the serial contract** — with no concurrency there is no
   conflict. That's why both sides perform identically at the start of
   the ramp and only diverge under load. Contention is a rush-hour
   problem; the simulation doesn't pretend otherwise.

## The scale — what's real and what's shrunk

The animation is slowed down so individual transactions are visible:
each animated transaction stands for **~500 real ones**, and the TPS
counters are displayed at network scale. This is stated on the page
itself.

What is **real** is the ratio. A chain of transactions that write the
same storage slot is a data-dependency chain — it must execute
sequentially, on one lane, no matter how smart the scheduler is (that's
Amdahl's law, not an opinion about Monad). Monad specs validators at
16+ cores and targets ~10,000 TPS; serial-dominated traffic keeps one
lane of sixteen:

**~10,000 TPS becomes ~600.**

## Anticipated objections, answered

**"Where does the 600 TPS figure come from?"**
It's a proportional model — 10,000 ÷ 16 — not an official or measured
number. Monad has never published a serial-workload throughput figure.
The exact floor may differ; the ÷16 ceiling logic doesn't.

**"Re-execution is cheaper than first execution (warm caches)."**
True, and it doesn't change the asymptote: cheap re-execution on one
lane is still one lane. The simulation's roll-back animation shows the
scheduling cost, not the (real, but smaller) recompute cost.

**"Real workloads aren't 100% one contract."**
Today's Monad mainnet says otherwise more than you'd hope: at the time
of writing, a single (unverified) contract receives ~37% of all direct
transactions and tops the conflict ranking of virtually every block —
watch it live in the Live network tab. The simulation shows the two
bounds; reality sits in between: ParaScan's Engine 2 currently measures
an **average achievable speedup of ~×4** on real blocks, against ×16
ideal.

**"Does Monad really have 16 lanes?"**
16 is the spec'd validator core count, used here as the parallelism
proxy. The exact internal scheduling width is Monad's implementation
detail; the shape of the result — serial code forfeits the multiplier,
whatever it is — doesn't depend on it.

**"Is the queue/fee behavior part of the claim?"**
The growing queue is the mempool consequence of demand exceeding
effective throughput. In reality the pressure valve is the fee market:
the chain doesn't stop, it gets expensive and slow — for everyone,
including the contracts that did parallelize. Wasted parallelism is a
shared cost; that's the reason a profiler for it exists.

## Reproduce the real-world numbers

The measured figures quoted above are reproducible against the public
RPC: the ~×4 speedup comes from `debug_traceBlockByNumber` dependency
analysis of live blocks (see [METHODOLOGY.md](METHODOLOGY.md), dynamic
engine), and any contract's parallelizability score can be checked at
[parascan.dev](https://parascan.dev).
