# FAQ

The questions we expect — answered straight.

### My contract barely has users. Does the score matter?

Not today — and that's exactly the trap. Parallelism is about all the
transactions in a block, yours *and everyone else's*. One mint alone in a
block conflicts with nothing and runs instantly. The defect only expresses
when many people call the same function in the same block: an NFT drop, an
airdrop claim, an incentive spike. A shared-slot hotspot is invisible while
your app is small and shows up **the day it succeeds** — 500 mints in one
second executing one by one instead of together. ParaScan measures rush-hour
behavior before rush hour happens.

### Does Monad split my single transaction across cores?

No — nobody does. A transaction is atomic and executes sequentially on Monad
like everywhere else. What runs in parallel is *different transactions of the
same block* (from different users). That's why contention between
transactions, not the speed of one transaction, is what ParaScan analyzes.

### You gave Uniswap's mint() 16/100. Are you saying Uniswap is broken?

No. `mint()` works perfectly — it increments two global counters
(`_nextId++`, `_nextPoolId++`) because sequential NFT ids were a fine design
on Ethereum, where everything runs serially anyway. On a parallel EVM the
same code means concurrent mints re-execute one by one. It's not a bug and
Uniswap's engineers aren't careless: **parallelizability wasn't a criterion
when that code was written.** That's the entire point of the tool.

### A low score = I must fix it?

Not necessarily. Some contended patterns are deliberate product decisions
(pretty sequential token ids, a global TVL counter someone reads on-chain).
ParaScan makes the *cost* visible — how much parallelism a choice throws away
— and the tradeoff stays yours.

### How is the score computed?

Static analysis of the verified source: every storage read/write of every
externally reachable function is traced (inheritance, internal calls,
modifiers, proxies included) and classified by who can collide on it. Each
function starts at 100 and loses points per contended slot. The exact penalty
table, the weighting, and every known limitation are in
[METHODOLOGY.md](METHODOLOGY.md).

### Where does the "~x4 average speedup" figure come from?

From tracing real mainnet blocks via `debug_traceBlockByNumber` on the public
Monad RPC: each transaction's actual read/write sets, the dependency graph
they form, and the block's longest dependency chain. Transactions ÷ chain
length = the block's achievable speedup. It's a structural upper bound
(uniform tx cost assumed) and it only counts contract-storage conflicts —
details and caveats in [METHODOLOGY.md](METHODOLOGY.md). Anyone can reproduce
it: the RPC is public.

### Isn't Monad's scheduler smart enough to make conflicts cheap?

Monad's optimistic execution is excellent engineering, and re-execution is
cheaper than naive serial execution (state is warm). But no scheduler can run
two writes to the same slot at the same time — that's a logical dependency,
not an implementation detail. The scheduler decides *how gracefully* you pay
for contention; your storage layout decides *whether* you pay.

### Blocks aren't full today. Why care now?

Because storage layout is nearly free to fix at design time and expensive to
fix after deployment (migrations, integrators, audits). The chains' history
is consistent: load arrives in spikes, and the contracts that melt are the
ones that were never measured. Also: our block traces already show measurable
contention today, concentrated in a handful of contracts.

### Why is the scanner closed source? Why should I trust the numbers?

The engine is closed; the *science* is not. The architecture
([ARCHITECTURE.md](ARCHITECTURE.md)), the full scoring model and limitations
([METHODOLOGY.md](METHODOLOGY.md)) are public, and every mainnet claim is
reproducible: scores by pasting the same address at
[parascan.dev](https://parascan.dev), speedups by tracing the same public RPC.
Challenge any number — that's what the docs are for.

### What happens to the code I paste? Is it stored?

Scans run server-side and results are kept in memory for 15 minutes (so the
AI-fix button can reuse the exact analyzed source), then dropped. Nothing is
written to a database. One exception, clearly opt-in: if you click **AI fix**,
the scanned source is sent to a third-party LLM API to generate the refactor.
If your code is secret, don't click that button — the pattern-template fixes
are computed locally and shown regardless. (Also: if your contract is
verified on-chain, its source is already public by definition.)

### Are the suggested fixes safe to copy-paste?

The pattern fixes (before/after templates) show the *shape* of the solution
with your real variable names — adapting surrounding logic, views and tests
is on you. The AI fix rewrites your actual code and is usually right, but it
is LLM output: **review it like a pull request, not like a patch from your
auditor.** Anything that changes storage layout on an already-deployed
upgradeable contract deserves extra care.

### Which contracts can be scanned?

Anything with verified source: Sourcify or MonadScan/Etherscan. Proxies
(EIP-1967, beacon) are followed to their implementation automatically.
Unverified bytecode can't be analyzed at source level — by any tool. Notably,
the most contention-heavy contract on Monad today is unverified.

### What does ParaScan miss?

Honest list: storage accesses done in inline assembly (Yul `sstore`/`sload`),
conflicts through external cross-contract calls, runtime key collisions on
parameter-keyed mappings (everyone hitting the same hot pool), and packed
struct members are treated at variable granularity. All documented in
[METHODOLOGY.md](METHODOLOGY.md), all on the roadmap.

### How is this different from Slither or a gas profiler?

Slither answers "is my contract **safe**?". Gas tools answer "is it
**cheap**?". ParaScan answers a question that didn't exist before parallel
EVMs: "is it **parallel**?". Different failure mode, different analysis,
different fix patterns.

### Will this work for other parallel EVMs?

The conflict rule (write/write and read/write on the same slot) is common to
optimistic-parallel designs, so the analysis largely transfers. ParaScan
targets Monad first: chain 143, its verification stack, its RPC, its docs.
