# Methodology & limitations

Every number ParaScan shows is computed, not vibes. This page documents how —
and where the model stops.

## The conflict rule

On Monad's optimistic parallel execution, two transactions conflict when one
**writes** a storage slot the other **reads or writes**. Conflicting
transactions re-execute serially, in block order. This is the single rule
everything below derives from.
(Reference: [Monad docs — parallel execution](https://docs.monad.xyz/monad-arch/execution/parallel-execution).)

## Parallelizability score (static)

Each state-changing, externally callable function starts at **100** and loses
points per **distinct** contended slot it touches:

| Access | Penalty | Severity |
|---|---|---|
| write to a `FIXED` slot (plain state variable) | −25 | HIGH |
| write to a `FIXED_KEY` slot (constant-key mapping entry) | −15 | HIGH |
| read of a `FIXED` slot that is written on the hot path | −8 | MEDIUM |
| write to a `PER_PARAM` slot (parameter-keyed mapping) | −4 | LOW |
| write to a `PER_SENDER` slot (msg.sender-keyed mapping) | −1 | info |

Contract score = weighted mean over those functions, with admin-gated
functions (modifier name matching `only*/admin/auth/...`) weighted ×0.25 and
one-shot initializers excluded.

The penalty weights are judgment calls (they encode "a shared write is
roughly six times worse than a parameter-keyed write"); the *detection* of
each access and its scope is not.

## Measured speedup (dynamic)

For a block of `n` transactions with real read/write sets from
`debug_traceBlockByNumber`:

- Build the dependency DAG with the conflict rule above, respecting block
  order.
- **Serial depth** = length of the longest dependency chain = the minimum
  number of sequential execution waves even with unlimited cores.
- **Achievable speedup** = `n / depth`.

A block with no conflicts has depth 1 (speedup = n). A block where each
transaction depends on the previous one has depth n (speedup = 1 — Ethereum
behavior).

## Honest limitations

**Static engine**
- Reports *structurally guaranteed* contention, not measured frequency.
- Storage accesses made in inline assembly (`sstore`/`sload` in Yul) are not
  traced — possible false negatives on assembly-heavy code.
- Cross-contract external calls are not followed.
- Runtime key collisions on parameter-keyed mappings (everyone trading the
  same hot pool) are classified low-risk but can contend in practice.
- Struct members sharing a packed slot are treated at variable granularity.

**Dynamic engine**
- The speedup is a **structural upper bound**: it assumes uniform transaction
  cost and enough cores. A wave containing one slow transaction takes longer
  in reality.
- Only contract-storage conflicts are counted; native MON balance conflicts
  (two txs paying the same address) are not, so the real figure is slightly
  *worse* than reported.
- It models Monad's scheduler from its documented conflict rule; the actual
  scheduler may have additional optimizations not visible from outside.

**Both**
- Unverified contracts cannot be analyzed at source level — by any tool.
- A low score is not automatically a bug: some contended patterns are
  deliberate product decisions. The score makes the cost visible; the
  tradeoff belongs to the developer.
