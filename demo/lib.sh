# shellcheck shell=bash disable=SC2034
# Shared settings for the demo scripts. Source this; don't run it.

REPO=nodeselector/brk286-demo
DIFF_STATS=nodeselector/diff-stats
LABELER=nodeselector/pr-size-labeler

# diff-stats commits: v1 normally points at REVIEWED. a/move-tag.sh points it at
# UNREVIEWED (the tip of the diff-stats `unreviewed` branch).
REVIEWED=e665493068ae1b587936681ea6caf6eb00bf7456
UNREVIEWED=b1f589bba9a2ad388d4046cc87bdd44d3bbdf3c0
LABELER_V1=ae47c61b2ecc8267950c5ac8cf6a55ad7afd23c2

# Demo B: an imposter commit for Steve-Glass/pr-note. It lives only in the fork
# network (nodeselector/pr-note branch imposter-commit), never in upstream history.
PRNOTE=Steve-Glass/pr-note
PRNOTE_FORK=nodeselector/pr-note
PRNOTE_LOCKED=47713a3d521b26f4fa13e43fb64b0687c7603980
IMPOSTER=177435a434f84257b283b9f46dfc2fc36d3abba4

# Demo D: license-check v1 (locked) runs helper.sh fetched at runtime from
# its GitHub Pages site. d/update-helper.sh and reset.sh move the Pages branch between two
# commits; the updated one POSTs a marker to COLLECTOR, which isn't on the allowlist.
LICENSE_CHECK=nodeselector/license-check
LICENSE_CHECK_V1=196d817144d78bb6b0c140815849f73dbb6c457c
PAGES_BRANCH=gh-pages
HELPER_CLEAN=4ec1a39fc45bc24cb2de1e5eee167752934c98ef
HELPER_UPDATED=618c4a4ce8261cd37d934b1c187a3541f0b50261
UPDATED_BRANCH=helper-updated # keeps HELPER_UPDATED reachable
HELPER_URL=https://nodeselector.github.io/license-check/helper.sh
COLLECTOR=evilnodeselector.github.io
RELEASE_WF=release.yml

# The repo's Require lockfile policy (Preview). reset.sh leaves it disabled,
# because an enforced one stops Demo A's SHA-pinned run.
POLICY_NAME="Require lockfile"

LOCKED_WF=ci-locked.yml
PINNED_WF=ci-sha-pinned.yml

# Tag on $REPO at the commit every take starts from. reset.sh force-moves main
# (and this checkout) back to it. After pushing a change to main that should
# stay, move the tag: git push -f origin main:refs/tags/demo-baseline
BASELINE_TAG=demo-baseline

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ -t 1 ]; then
  GREEN=$'\033[1;32m' RED=$'\033[1;31m' DIM=$'\033[2m' OFF=$'\033[0m'
else
  GREEN='' RED='' DIM='' OFF=''
fi

short() { printf '%s' "${1:0:7}"; }

name_of() {
  case "$1" in
    "$REVIEWED") echo "reviewed $(short "$1")" ;;
    "$UNREVIEWED") echo "UNREVIEWED $(short "$1")" ;;
    *) echo "unknown $(short "$1")" ;;
  esac
}

# Commit a lightweight tag points at.
tag_sha() {
  gh api "repos/$1/git/ref/tags/$2" --jq .object.sha
}

# Force a lightweight tag to a commit.
set_tag() {
  gh api -X PATCH "repos/$1/git/refs/tags/$2" -f sha="$3" -F force=true --silent
}

# Point a branch at a commit (force) and ask Pages to rebuild.
set_pages() { # sha
  gh api -X PATCH "repos/$LICENSE_CHECK/git/refs/heads/$PAGES_BRANCH" -f sha="$1" -F force=true --silent || return 1
  gh api -X POST "repos/$LICENSE_CHECK/pages/builds" --silent 2>/dev/null || true
}

# Which helper Pages serves right now: clean, updated or unknown.
served_helper() {
  local body
  body=$(curl -fsS --max-time 10 "$HELPER_URL?nocache=$RANDOM$RANDOM") || { echo unknown; return; }
  if grep -q "$COLLECTOR" <<<"$body"; then echo updated
  elif grep -q 'loaded default license policy' <<<"$body"; then echo clean
  else echo unknown; fi
}

# Actions policies REST API (https://docs.github.com/rest/actions/policies).
policies_api() {
  gh api -H "X-GitHub-Api-Version: 2026-03-10" "$@"
}

# Id of the demo's Require lockfile policy; empty if it doesn't exist.
policy_id() {
  policies_api "repos/$REPO/actions/policies" \
    --jq "[.policies[] | select(.name == \"$POLICY_NAME\") | .id][0] // empty"
}

# Enforcement of the demo policy: active, disabled, evaluate or missing.
policy_enforcement() {
  local id
  id=$(policy_id) || return 1
  [ -n "$id" ] || { echo missing; return; }
  policies_api "repos/$REPO/actions/policies/$id" --jq .enforcement
}

# Set the demo policy's enforcement (active|disabled). The API can't create a
# require_lockfile rule, so the policy itself is made once in the UI.
set_policy() { # enforcement
  local id
  id=$(policy_id) || return 1
  [ -n "$id" ] || { echo "no '$POLICY_NAME' policy on $REPO; create it in Settings -> Actions -> Policies" >&2; return 1; }
  policies_api -X PUT "repos/$REPO/actions/policies/$id" -f enforcement="$1" --silent
}

# Newest workflow_dispatch run id of a workflow (0 if none).
latest_run() {
  gh run list -R "$REPO" -w "$1" -e workflow_dispatch -L 1 \
    --json databaseId --jq '.[0].databaseId // 0'
}

# Wait for a run newer than the given id to show up.
new_run() { # workflow previous-id
  local id _
  for _ in $(seq 12); do
    sleep 5
    id=$(latest_run "$1")
    [ "$id" -gt "$2" ] && { echo "$id"; return; }
  done
  echo "no new run of $1 showed up" >&2
  return 1
}

# Dispatch both Demo A workflows on main; sets LOCKED_ID and PINNED_ID.
start_runs() {
  local locked_prev pinned_prev wf
  locked_prev=$(latest_run "$LOCKED_WF")
  pinned_prev=$(latest_run "$PINNED_WF")
  for wf in "$LOCKED_WF" "$PINNED_WF"; do
    gh workflow run "$wf" -R "$REPO" --ref main >/dev/null
  done
  LOCKED_ID=$(new_run "$LOCKED_WF" "$locked_prev")
  PINNED_ID=$(new_run "$PINNED_WF" "$pinned_prev")
}

# main's actions.lock at demo-baseline: locks/ci.lock, which locks only $LOCKED_WF.
LOCK_PATH=.github/workflows/actions.lock
LOCKS="$ROOT/demo/locks"

main_lock() {
  gh api "repos/$REPO/contents/$LOCK_PATH?ref=main" -H 'Accept: application/vnd.github.raw' 2>/dev/null
}
