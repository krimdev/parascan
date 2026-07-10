# Architecture

How ParaScan is built, end to end. The source is closed, but nothing here is
hand-waved: every stage is described precisely enough to be challenged.

```
                 ┌─────────────────────────────────────────────┐
 address ──────► │ 1. proxy resolution (EIP-1967 slot via RPC) │
                 │ 2. verified-source fetch                    │
                 │    Sourcify → Etherscan/MonadScan fallback  │
                 │ 3. exact-version solc compilation           │
                 │    → full AST + storage layout              │
 solidity ─────► │                                             │
                 └──────────────────┬──────────────────────────┘
                                    ▼
                 ┌─────────────────────────────────────────────┐
                 │ ENGINE 1 — static contention analysis       │
                 │ access tracing → scope classification →     │
                 │ scoring → hotspots → fix templates          │
                 └──────────────────┬──────────────────────────┘
                                    ▼
                        score · hotspots · fixes
                                    ▲
                 ┌──────────────────┴──────────────────────────┐
                 │ ENGINE 2 — live block measurement           │
                 │ debug_traceBlockByNumber → read/write sets  │
                 │ → dependency DAG → serial depth & speedup   │
                 └─────────────────────────────────────────────┘
```

## Stage 1 — Getting the exact code that runs

**Proxy resolution.** Before fetching anything, ParaScan reads the EIP-1967
implementation slot (and beacon slot) of the target address over RPC. Scanning
a proxy shell would yield a meaningless 100/100; the implementation is what
runs.

**Verified source.** Sources come from Sourcify (Monad's BlockVision-hosted
instance) first, then the Etherscan v2 multichain API (which covers MonadScan)
as a fallback. All source formats are handled: flat files, multi-file JSON,
and full standard-JSON inputs with Foundry remappings. File-to-source-unit
matching is exact-path first — projects routinely contain several files with
the same basename.

**Compilation.** The contract is recompiled with the *exact* compiler version
it was verified with (binaries fetched from binaries.soliditylang.org and
cached), using the original optimizer/evmVersion/remapping settings. The
compiler outputs two things ParaScan needs: the full **AST** of every source
unit and the **storage layout** (which variable lives in which physical slot).

## Engine 1 — static contention analysis

**Access tracing.** For every externally reachable function — following C3
linearization for inheritance, expanding modifier bodies, and propagating
accesses through internal calls to a fixed point — the analyzer walks the AST
and records every state-variable read and write, including compound
assignments, `++/--/delete`, array `push/pop` (which mutate the shared length
slot), and struct/mapping access chains.

**Scope classification.** Each access is classified by *who can collide on it*:

| Scope | Meaning | Contention |
|---|---|---|
| `FIXED` | plain state variable — one slot for everyone | every call collides |
| `FIXED_KEY` | mapping indexed by a constant — one hot slot in disguise | every call collides |
| `PER_PARAM` | mapping keyed by a function parameter | collides on identical keys only |
| `PER_SENDER` | mapping keyed by `msg.sender` | almost never collides |

Mapping keys are classified by walking the key expression: `msg.sender` beats
function parameters beats constants.

**Scoring.** Each state-changing function starts at 100 and loses points per
distinct contended slot (see [METHODOLOGY.md](METHODOLOGY.md) for the exact
penalty table). Admin-gated functions (`onlyOwner` & co) are down-weighted
×0.25; one-shot `initialize` functions behind proxies are excluded entirely —
they never run on the hot path.

**Fixes.** Every hotspot is matched to one of five anti-pattern families
(global counter, accumulator, last-value, array push, constant key), each with
a before/after template instantiated with the contract's real variable and
function names. Optionally, the actually-scanned source is sent to an LLM
which returns a refactor of the developer's own code.

## Engine 2 — live measurement

Monad's public RPC exposes `debug_traceBlockByNumber`. For each transaction of
a block, two traces are taken:

- **prestateTracer** (default): every account/storage slot the transaction
  *accessed* → the read set;
- **prestateTracer + diffMode**: every slot it *changed* → the write set.

Transactions `i < j` conflict when `writeSet(i) ∩ (readSet(j) ∪ writeSet(j))`
is non-empty — the optimistic-execution conflict rule. The resulting
dependency DAG gives, per block:

- the number of conflicting pairs,
- the **serial depth** (longest dependency chain = minimum number of
  sequential execution waves),
- the **achievable speedup** = transactions ÷ depth,
- the most contended contracts and slots, aggregated across blocks.

A background collector runs this sampling every 30s, independent of visitors,
appending each data point to dated JSON in a persistent volume — so the
contention history accumulates continuously and drives a live time-series
chart.

## Naming the slots — Engine 1 × Engine 2

Engine 2 sees raw 32-byte storage slots colliding on-chain. For a verified
contract, ParaScan maps them back to source-level variable names:

- **Plain state variables** — the slot is the declared slot number (direct).
- **Dynamic arrays** — element `i` at `keccak256(baseSlot) + i·elemSlots`.
- **Mappings** — the value for key `k` at `keccak256(pad(k) . pad(baseSlot))`.
  The hash isn't reversible, so keys are **harvested forward**: every 32-byte
  word of the calldata of transactions hitting the contract becomes a candidate
  key (covering address, uint and bytes32 keys alike), plus tx senders and
  small ids. Mapping-to-struct values are resolved to the member name, and
  two-level nested mappings are handled.

Whatever still can't be attributed (e.g. a mapping key set in an older block,
outside the traced window) stays honestly **unresolved** rather than guessed.
The result: *"`s_orderIdCounter` caused these conflicts"*, proven live on a
mainnet orderbook.

## Serving infrastructure

- Node.js service (Express) exposing the scan, live-blocks and AI-fix APIs,
  plus the static frontend (vanilla JS, zero framework).
- Per-IP rate limits on every endpoint; live-block results are cached and the
  cache is served *before* rate limiting, so page refreshes cost nothing.
- Verification statuses and compiler binaries are cached.
- Deployed with Docker Compose behind Caddy (automatic HTTPS), on a dedicated
  Ubuntu server.

## Design decisions worth defending

- **Recompile rather than trust metadata.** Storage layouts are derived from
  an actual compilation with the original settings, not inferred.
- **Static + dynamic, not either.** Static analysis alone over-reports
  (worst case); tracing alone under-explains (no line numbers). Together they
  answer both "where is it guaranteed" and "how much is real".
- **Templates before AI.** Pattern fixes are deterministic, instant and free;
  the LLM is an opt-in layer on top, never a dependency.
