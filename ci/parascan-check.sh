#!/usr/bin/env bash
#
# parascan-check.sh — gate CI on contract parallelizability.
#
# Scores each Solidity file against the ParaScan API and fails (exit 1)
# if any contract scores below the threshold. The scanner runs on
# parascan.dev; this script only sends source and reads the score.
#
# usage:   parascan-check.sh <threshold> <file1.sol> [file2.sol ...]
# example: parascan-check.sh 60 flat/*.sol
#
# env:     PARASCAN_API   base URL (default https://parascan.dev)
#
# requires: bash, curl, jq  (all present on GitHub Actions ubuntu runners)

set -euo pipefail

THRESHOLD="${1:?usage: parascan-check.sh <threshold> <file.sol> [...]}"
shift
API="${PARASCAN_API:-https://parascan.dev}/api/scan"

fail=0
printf '%-44s %7s\n' "contract" "score"
printf '%-44s %7s\n' "--------" "-----"

for f in "$@"; do
  [ -f "$f" ] || { printf '%-44s %7s\n' "$(basename "$f")" "MISS"; fail=1; continue; }
  src="$(cat "$f")"
  resp="$(curl -s -X POST "$API" -H 'content-type: application/json' \
    --data "$(jq -n --arg s "$src" '{source:$s}')")" || { printf '%-44s %7s\n' "$(basename "$f")" "NET"; fail=1; continue; }

  score="$(printf '%s' "$resp" | jq -r '.results[0].score // empty')"
  name="$(printf '%s' "$resp" | jq -r '.results[0].contract // empty')"

  if [ -z "$score" ]; then
    err="$(printf '%s' "$resp" | jq -r '.error // "unknown error"' | head -1)"
    printf '%-44s %7s  %s\n' "$(basename "$f")" "ERR" "$err"
    fail=1
    continue
  fi

  printf '%-44s %7s\n' "${name:-$(basename "$f")}" "$score/100"
  if [ "$score" -lt "$THRESHOLD" ]; then fail=1; fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS — all contracts at or above $THRESHOLD/100"
else
  echo "FAIL — one or more contracts below $THRESHOLD/100 (or errored)"
  exit 1
fi
