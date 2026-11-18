#!/usr/bin/env bash
# Demo D: dispatch release.yml (same locked job on the firewall runner
# and a plain runner), then print each job's log and a per-host verdict from
# the firewall's decision log. The updated helper POSTs silently, so the
# verdict is the proof: the firewall runner logs the collector as BLOCKED.
set -uo pipefail
source "$(dirname "$0")/../lib.sh"

echo "Pages serves the $(served_helper) helper: $HELPER_URL"
before=$(latest_run "$RELEASE_WF")
gh workflow run "$RELEASE_WF" -R "$REPO" --ref main >/dev/null || exit 1
id=$(new_run "$RELEASE_WF" "$before") || exit 1
echo "Watch it live: https://github.com/$REPO/actions/runs/$id"
gh run watch "$id" -R "$REPO" -i 15 --exit-status >/dev/null 2>&1

ok=0
while IFS=$'\t' read -r job name conclusion; do
  log=$(gh run view -R "$REPO" --job "$job" --log 2>/dev/null) || log=''
  echo
  echo "${name}: $conclusion"
  grep -o 'Using locked action versions.*' <<<"$log" | head -1 | sed 's/^/  /'
  grep -oE "license-check policy helper.*|license-check: .*" <<<"$log" |
    sort -u | sed 's/^/  /'
  echo "  https://github.com/$REPO/actions/runs/$id/job/$job"
  [ "$conclusion" = success ] && ok=$((ok + 1))
done < <(gh run view "$id" -R "$REPO" --json jobs --jq '.jobs[] | [.databaseId, .name, .conclusion] | @tsv')

dir=$(mktemp -d)
echo
if gh run download "$id" -R "$REPO" -p 'firewall-decisions-*' -D "$dir" >/dev/null 2>&1; then
  # One line per host: BLOCKED if any decision blocked it. Hosts the runner
  # itself talks to (Actions service, results storage) collapse into one line.
  # Blocks with no process (pid 0) are left out: the runner image's own DNS
  # and NTP traffic, seen with the clean helper too. DNS decisions never carry
  # a pid, so the collector is kept by name.
  verdict=$(find "$dir" -name '*.json' -exec cat {} + | jq -rs --arg collector "$COLLECTOR" '
    [.[].decision[] | select(.msg | test("ALLOWED|BLOCKED"))
     | select((.blocked and .pid == 0 and ((.domains // "") | rtrimstr(".")) != $collector) | not)
     | {host: ((.domains // "") | rtrimstr(".")), blocked, runner: ((.cmd // "") | test("actions-runner|REDACTED"))}]
    | group_by(.host)
    | map({host: .[0].host, blocked: any(.blocked), runner: all(.runner)})
    | (map(select(.blocked | not) | select(.runner | not)) | .[] | "ALLOWED\t\(.host)"),
      (map(select(.blocked | not) | select(.runner)) | length | select(. > 0) | "ALLOWED\t\(.) GitHub runner service hosts"),
      (map(select(.blocked)) | .[] | "BLOCKED\t\(.host)")')
  echo "Firewall runner:"
  while IFS=$'\t' read -r v host; do
    if [ "$v" = BLOCKED ]; then printf '  %sBLOCKED%s  %s\n' "$RED" "$OFF" "$host"
    else printf '  %sALLOWED%s  %s\n' "$GREEN" "$OFF" "$host"; fi
  done <<<"$verdict"
else
  echo "Firewall runner: no firewall-decisions artifact on run $id"
fi
echo
echo "https://github.com/$REPO/actions/runs/$id"
[ "$ok" = 2 ] || exit 1
