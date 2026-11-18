#!/usr/bin/env bash
# Run both workflows on main, wait for them, and say which diff-stats commit each ran.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

echo "$DIFF_STATS@v1 currently -> $(name_of "$(tag_sha "$DIFF_STATS" v1)")"

report() { # workflow run-id
  local log ran locked unreviewed
  gh run watch "$2" -R "$REPO" -i 15 --exit-status >/dev/null 2>&1 || true
  log=$(gh run view "$2" -R "$REPO" --log 2>/dev/null || true)
  if [ -z "$log" ]; then
    sleep 5
    log=$(gh run view "$2" -R "$REPO" --log 2>/dev/null || true)
  fi
  ran=$(grep -o "Download action repository '$DIFF_STATS@v1' (SHA:[0-9a-f]*)" <<<"$log" |
    head -1 | sed 's/.*SHA://; s/)//') || ran=''
  locked=no; grep -q "Using locked action versions" <<<"$log" && locked=yes
  unreviewed=no; grep -q "UNREVIEWED diff-stats commit ran" <<<"$log" && unreviewed=yes
  printf '%-26s lockfile used: %-3s  diff-stats ran: %-20s banner: %s\n' \
    "$1" "$locked" "$(name_of "${ran:-?}")" "$unreviewed"
  echo "  https://github.com/$REPO/actions/runs/$2"
}

start_runs
echo "waiting for runs $LOCKED_ID and $PINNED_ID ..."
report "$LOCKED_WF" "$LOCKED_ID"
report "$PINNED_WF" "$PINNED_ID"
