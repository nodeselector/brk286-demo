#!/usr/bin/env bash
# Put the demo back at its starting state, then print GREEN or RED.
# Safe to run any number of times.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

# One brace group, so bash has read the whole script before step 3 resets the
# checkout this file lives in.
{
# Every check below reads the GitHub API; with no quota they'd all report bogus problems.
if left=$(gh api rate_limit --jq '"\(.resources.core.remaining) \(.resources.core.reset|todate)"'); then
  if [ "${left%% *}" -lt 100 ]; then
    echo "${RED}RED${OFF}"
    echo "  - GitHub API quota is used up (${left%% *} left) until ${left#* }; nothing was checked"
    exit 1
  fi
fi

problems=()
fixed=()

# 1. Tags the demo moves (or someone moved by hand) go back to the reviewed commits.
check_tag() { # repo tag want
  local got
  if ! got=$(tag_sha "$1" "$2"); then
    problems+=("$1@$2: tag not found")
    return
  fi
  if [ "$got" != "$3" ]; then
    if set_tag "$1" "$2" "$3"; then
      fixed+=("$1@$2: $(short "$got") -> $(short "$3")")
    else
      problems+=("$1@$2 is $(short "$got"), want $(short "$3"); couldn't move it back")
    fi
  fi
}
check_tag "$DIFF_STATS" v1 "$REVIEWED"
check_tag "$LABELER" v1 "$LABELER_V1"
check_tag "$LICENSE_CHECK" v1 "$LICENSE_CHECK_V1"

got=$(gh api "repos/$DIFF_STATS/branches/unreviewed" --jq .commit.sha 2>/dev/null) || got=missing
[ "$got" = "$UNREVIEWED" ] ||
  problems+=("$DIFF_STATS branch unreviewed is $got, want $(short "$UNREVIEWED")")

# 2. main goes back to the start commit (tag demo-baseline), force. That undoes
# the `gh actions-lock` commits pushed during a take. It refuses
# when main changed anything outside .github/ since the tag, such as a script
# fix that should have moved the tag.
git_ok=false
if start=$(tag_sha "$REPO" "$BASELINE_TAG") &&
  git -C "$ROOT" fetch -q origin main "+refs/tags/$BASELINE_TAG:refs/tags/$BASELINE_TAG"; then
  git_ok=true
  head=$(git -C "$ROOT" rev-parse origin/main)
  if [ "$head" != "$start" ]; then
    other=$(git -C "$ROOT" diff --name-only "$start" "$head" -- . ':!.github')
    if [ -n "$other" ]; then
      problems+=("main changed ${other//$'\n'/ } since $BASELINE_TAG; left main alone. If that should stay: git push -f origin main:refs/tags/$BASELINE_TAG")
    elif gh api -X PATCH "repos/$REPO/git/refs/heads/main" -f sha="$start" -F force=true --silent &&
      git -C "$ROOT" fetch -q origin main; then
      fixed+=("main $(short "$head") -> $BASELINE_TAG $(short "$start") (force)")
    else
      problems+=("couldn't force main back to $BASELINE_TAG $(short "$start")")
    fi
  fi
else
  problems+=("can't read tag $BASELINE_TAG on $REPO or fetch it into $ROOT")
fi

# 2a. This checkout is a clean main at origin/main (before the checks below,
# which read locks/ from it). Nothing is lost: tracked
# changes go to the stash, local commits to a reset-backup/<time> branch.
# Untracked files stay.
if $git_ok; then
  g() { git -C "$ROOT" "$@"; }
  stamp=$(date +%Y%m%d-%H%M%S)
  if [ -n "$(g status --porcelain --untracked-files=no)" ]; then
    g stash push -q -m "reset.sh $stamp" && fixed+=("local changes -> git stash (reset.sh $stamp)")
  fi
  branch=$(g branch --show-current)
  if [ -n "$(g status --porcelain --untracked-files=no)" ]; then
    problems+=("couldn't stash the changes in $ROOT; left it alone")
  elif [ "$branch" != main ]; then
    if err=$(g switch -q main 2>&1); then
      fixed+=("checkout ${branch:-detached HEAD} -> main")
    else
      problems+=("couldn't switch $ROOT to main: $err")
    fi
  fi
  if [ "$(g branch --show-current)" = main ] && [ -z "$(g status --porcelain --untracked-files=no)" ] &&
    [ "$(g rev-parse HEAD)" != "$(g rev-parse origin/main)" ]; then
    if g merge-base --is-ancestor HEAD origin/main; then
      g merge -q --ff-only origin/main
    elif g branch "reset-backup/$stamp" HEAD; then
      g reset -q --hard origin/main &&
        fixed+=("local main commits -> branch reset-backup/$stamp; main = origin/main")
    fi
  fi
  [ "$(g branch --show-current)" = main ] && [ "$(g rev-parse HEAD)" = "$(g rev-parse origin/main)" ] &&
    [ -z "$(g status --porcelain --untracked-files=no)" ] ||
    problems+=("$ROOT isn't a clean main at origin/main")
fi

remote_file() {
  gh api "repos/$REPO/contents/$1?ref=main" -H 'Accept: application/vnd.github.raw' 2>/dev/null
}
# main's actions.lock locks $LOCKED_WF only; Demo B relocks it live during the talk.
if lock=$(main_lock); then
  [ "$lock" = "$(cat "$LOCKS/ci.lock")" ] ||
    problems+=("main actions.lock isn't locks/ci.lock")
  grep -q "^    '.github/workflows/$LOCKED_WF':" <<<"$lock" ||
    problems+=("main actions.lock doesn't list $LOCKED_WF")
  ! grep -q "^    '.github/workflows/$PINNED_WF':" <<<"$lock" ||
    problems+=("main actions.lock lists $PINNED_WF; the comparison workflow must stay unlocked")
  grep -A2 "^    '$DIFF_STATS@v1':" <<<"$lock" | grep -q "commit: 'sha1-$REVIEWED'" ||
    problems+=("main actions.lock doesn't record $DIFF_STATS@v1 at $(short "$REVIEWED")")
else
  problems+=("can't read actions.lock on $REPO main")
fi
grep -A2 "^    'steve-glass/pr-note@v3':" <<<"$lock" | grep -q "commit: 'sha1-$PRNOTE_LOCKED'" ||
  problems+=("main actions.lock doesn't record steve-glass/pr-note@v3 at $(short "$PRNOTE_LOCKED")")
check_uses() { # workflow action ref
  local body
  if body=$(remote_file ".github/workflows/$1"); then
    grep -q "uses: $2@$3" <<<"$body" ||
      problems+=("main $1 doesn't use $2@$(short "$3")")
  else
    problems+=("$1 missing on $REPO main")
  fi
}
check_uses "$PINNED_WF" "$LABELER" "$LABELER_V1"
check_uses "$LOCKED_WF" "$LABELER" v1
check_uses "$LOCKED_WF" "$PRNOTE" v3
grep -A2 "^    '$LABELER@v1':" <<<"$lock" | grep -q "commit: 'sha1-$LABELER_V1'" ||
  problems+=("main actions.lock doesn't record $LABELER@v1 at $(short "$LABELER_V1")")

# 2b. Demo B: the imposter commit stays on its fork branch.
got=$(gh api "repos/$PRNOTE_FORK/branches/imposter-commit" --jq .commit.sha 2>/dev/null) || got=missing
[ "$got" = "$IMPOSTER" ] ||
  problems+=("$PRNOTE_FORK branch imposter-commit is $got, want $(short "$IMPOSTER")")

# 2c. Demo D: Pages serves the clean helper again; the updated one stays parked.
got=$(gh api "repos/$LICENSE_CHECK/branches/$UPDATED_BRANCH" --jq .commit.sha 2>/dev/null) || got=missing
[ "$got" = "$HELPER_UPDATED" ] ||
  problems+=("$LICENSE_CHECK branch $UPDATED_BRANCH is $got, want $(short "$HELPER_UPDATED")")
got=$(gh api "repos/$LICENSE_CHECK/branches/$PAGES_BRANCH" --jq .commit.sha 2>/dev/null) || got=missing
if [ "$got" != "$HELPER_CLEAN" ]; then
  if set_pages "$HELPER_CLEAN"; then
    fixed+=("$LICENSE_CHECK $PAGES_BRANCH: $(short "$got") -> clean $(short "$HELPER_CLEAN")")
  else
    problems+=("$LICENSE_CHECK $PAGES_BRANCH is $(short "$got"), want clean $(short "$HELPER_CLEAN")")
  fi
fi
served=$(served_helper)
for _ in $(seq 36); do # a Pages rebuild usually takes under a minute
  [ "$served" = clean ] && break
  sleep 5
  served=$(served_helper)
done
[ "$served" = clean ] ||
  problems+=("Pages serves the $served helper; it rebuilds in about a minute, then rerun reset.sh")
if body=$(remote_file .github/egress-firewall.yaml); then
  grep -qx '  - nodeselector.github.io' <<<"$body" ||
    problems+=("main egress-firewall.yaml doesn't allow nodeselector.github.io")
  ! grep -qF -e '*' -e "$COLLECTOR" <<<"$body" ||
    problems+=("main egress-firewall.yaml allows the collector or a wildcard; it must not")
else
  problems+=("can't read egress-firewall.yaml on $REPO main")
fi

# 2d. No Actions policy is enforced: an enforced Require lockfile policy would
# fail Demo A's SHA-only run. Silent unless something had to change.
if enforced=$(policies_api "repos/$REPO/actions/policies" --jq \
  '.policies[] | select(.enforcement != "disabled") | .name'); then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$name" = "$POLICY_NAME" ] && set_policy disabled && [ "$(policy_enforcement)" = disabled ]; then
      fixed+=("$POLICY_NAME policy -> off")
    else
      problems+=("Actions policy '$name' is enforced on $REPO")
    fi
  done <<<"$enforced"
else
  problems+=("can't read Actions policies on $REPO")
fi

# 4. Nothing from an earlier run still going.
for wf in "$LOCKED_WF" "$PINNED_WF" "$RELEASE_WF"; do
  n=$(gh run list -R "$REPO" -w "$wf" --json status \
    --jq '[.[] | select(.status != "completed")] | length' 2>/dev/null) || n=0
  [ "$n" = 0 ] || problems+=("$wf has $n run(s) still in progress")
done

row() { printf '  %-18s %s\n' "$1" "$2"; }

echo
for f in "${fixed[@]+"${fixed[@]}"}"; do echo "  ${DIM}reset  $f${OFF}"; done
row "${DIFF_STATS#*/}@v1" "$(name_of "$(tag_sha "$DIFF_STATS" v1 2>/dev/null)")"
row "helper.sh" "$served"
echo
if [ ${#problems[@]} -eq 0 ]; then
  echo "${GREEN}GREEN${OFF}  ready"
  echo
  echo "  Demo B commit page: https://github.com/$PRNOTE/commit/$IMPOSTER"
else
  echo "${RED}RED${OFF}"
  for p in "${problems[@]}"; do echo "  - $p"; done
  exit 1
fi
exit
}
