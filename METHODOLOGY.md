# Methodology & limitations

Every number ParaScan shows is computed, not vibes. This page documents how —
and where the model stops.

## The conflict rule

On Monad's optimistic parallel execution, two transactions conflict when one
**writes** a storage slot the other **reads or writes**. Conflicting
transactions re-execute serially, in block order. This is the single rule
everything below derives from.
(Reference: [Monad docs — parallel execution](https://docs.monad.xyz/monad-arch/execution/parallel-execution).)

## Parallelizability score (static, v0.3 — probabilistic)

The score **is** a probability: `score = 100 × P(two concurrent calls do
NOT conflict)`. That is the quantity Monad's scheduler actually pays for —
no abstract point system in between.

For every pair of state-changing functions, each storage variable they both
touch collides with a probability set by how each side derives its key
(read × read never conflicts; every other combination needs at least one
write):

| Key derivation pair | P(same slot) | Intuition |
|---|---|---|
| shared slot × shared slot (plain variable or constant-key mapping) | **1** | same slot by construction |
| parameter × parameter | **κ = 5%** | two calls pass the same key (same pool, same id…) |
| parameter × constant | **κ = 5%** | a parameter happens to equal the hot constant |
| parameter × `msg.sender` | **χ = 2%** | a parameter equals the other caller's address |
| `msg.sender` × `msg.sender` | **ε = 0.5%** | the same account lands twice in one block |

Per-slot probabilities combine as independent events, `1 − Π(1 − p)`, which
gives **saturation** for free: one global counter already makes two calls
conflict for certain — a second one cannot make it worse. (An additive
penalty system, which ParaScan v0.2 used, punishes the same serialization
three times.)

Two scores are derived:

- **Function score** = `100 × (1 − P(conflict with itself))` — can this
  function scale against itself under spike load (mint rush, airdrop)?
  A function that writes any plain shared variable scores **0**: the model's
  literal claim is *two concurrent calls of it conflict with probability 1*.
- **Contract score** = the traffic-weighted mix over all function pairs.
  For deployed contracts the mix is **measured on chain** (v0.4): the
  4-byte selectors of recent transactions to the scanned address are
  counted and each function weighs its real call share. Contracts that are
  mostly called inside router transactions (invisible in top-level
  calldata) escalate to `debug_traceBlockByNumber` with `callTracer`,
  which counts internal calls too; `STATICCALL`s are excluded since view
  traffic writes nothing. Rarely-sampled functions keep a small share
  (Laplace smoothing). Below 10 observed calls the sample is noise, so the
  mix falls back to the uniform assumption — admin-gated functions
  (modifier name matching `only*/admin/auth/...`) weighted ×0.25, one-shot
  initializers excluded — and the report states which mix was used. Under
  the uniform fallback a contract with many clean functions dilutes its
  one serialized hot function: the worst-hot-function figure stays the
  honest headline there.

Scores are **floored**, not rounded: 100 means *provably zero contention*,
never "rounds up to 100". Each report also states the raw conflict
probability and an estimated number of usable parallel lanes (out of 16),
`≈ min(16, 1/P)`.

κ, χ and ε are heuristic defaults, and they are the model's judgment calls;
the *detection* of each access and its scope is not. Calibrating them
against Engine 2's measured mainnet contention is the next milestone —
the goal is to publish the correlation between predicted and observed
contention rather than ask anyone to trust the defaults.

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
