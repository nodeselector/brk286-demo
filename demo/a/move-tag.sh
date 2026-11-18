#!/usr/bin/env bash
# The live beat: re-point nodeselector/diff-stats tag v1 at the unreviewed commit,
# then start both Demo A workflows and return without waiting for them.
# Same thing as, from a diff-stats checkout:
#   git push --force origin unreviewed:refs/tags/v1
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

before=$(tag_sha "$DIFF_STATS" v1)
if [ "$before" != "$UNREVIEWED" ]; then
  set_tag "$DIFF_STATS" v1 "$UNREVIEWED"
fi
after=$(tag_sha "$DIFF_STATS" v1)

row() { printf '  %-8s %s\n' "$1" "$2"; }
echo
echo "  $DIFF_STATS@v1 moved"
row before "$(name_of "$before")  https://github.com/$DIFF_STATS/commit/$before"
row after "$(name_of "$after")  https://github.com/$DIFF_STATS/commit/$after"
row tag "https://github.com/$DIFF_STATS/tree/v1"
echo
[ "$after" = "$UNREVIEWED" ]

echo "  starting both workflows ..."
start_runs
echo "  runs started"
row locked "https://github.com/$REPO/actions/runs/$LOCKED_ID"
row pinned "https://github.com/$REPO/actions/runs/$PINNED_ID"
echo
