# ParaScan in CI

Gate your pull requests on contract **parallelizability**: fail the build when
a contract would serialize its transactions on Monad.

The scanner runs on [parascan.dev](https://parascan.dev) — the CI script only
sends your Solidity and reads back the score, so there's nothing to install
and no engine to run locally.

## Quick start (GitHub Actions + Foundry)

Drop this in `.github/workflows/parascan.yml`:

```yaml
name: ParaScan
on: [pull_request]

jobs:
  parallelizability:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: foundry-rs/foundry-toolchain@v1

      # ParaScan scores self-contained sources, so flatten first
      - name: Flatten contracts
        run: |
          mkdir -p .parascan-flat
          for c in $(find src -name '*.sol'); do
            forge flatten "$c" > ".parascan-flat/$(basename "$c")" 2>/dev/null || true
          done

      - name: Check parallelizability (fail under 60/100)
        run: |
          curl -sSL https://raw.githubusercontent.com/krimdev/parascan/master/ci/parascan-check.sh -o parascan-check.sh
          chmod +x parascan-check.sh
          ./parascan-check.sh 60 .parascan-flat/*.sol
```

Output on a failing PR:

```
contract                                       score
--------                                       -----
GoodToken                                     94/100
BadToken                                      55/100

FAIL — one or more contracts below 60/100 (or errored)
```

## The script directly

```bash
# usage: parascan-check.sh <threshold> <file.sol> [file2.sol ...]
PARASCAN_API=https://parascan.dev ./parascan-check.sh 60 flat/*.sol
```

Exits `0` if every contract is at or above the threshold, `1` otherwise —
so any CI system (GitLab, CircleCI, a git hook) can use it. Requires
`bash`, `curl` and `jq` (all present on GitHub Actions ubuntu runners).

## Notes

- **Flatten** because the hosted scanner analyzes one self-contained file at a
  time. `forge flatten` (Foundry) or `hardhat flatten` both work.
- **Pick a threshold that fits you.** 60 is a sensible default; raise it for
  hot-path DeFi contracts, lower it if you have admin-heavy contracts that
  rarely run under load. The score already down-weights admin functions and
  ignores one-shot initializers.
- Interfaces, libraries and contracts with no state-changing external
  functions score 100 (nothing to serialize).
- A low score isn't automatically a bug — see the
  [FAQ](../FAQ.md). Use the threshold to catch regressions, and
  [parascan.dev](https://parascan.dev) to understand and fix them.
