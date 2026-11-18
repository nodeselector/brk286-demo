#!/usr/bin/env bash
# Demo D: make GitHub Pages serve the updated helper.sh, in place. No new
# license-check release, no lockfile change. reset.sh puts the clean one back.
set -euo pipefail
source "$(dirname "$0")/../lib.sh"

set_pages "$HELPER_UPDATED" || { echo "${RED}couldn't move $PAGES_BRANCH${OFF}" >&2; exit 1; }
echo "$LICENSE_CHECK $PAGES_BRANCH -> updated $(short "$HELPER_UPDATED"); waiting for Pages to serve it ..."
for _ in $(seq 60); do
  if [ "$(served_helper)" = updated ]; then
    echo "${GREEN}$HELPER_URL now serves the updated helper${OFF}"
    exit 0
  fi
  sleep 5
done
echo "${RED}Pages still isn't serving the updated helper after 5 minutes${OFF}" >&2
exit 1
