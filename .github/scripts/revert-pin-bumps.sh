#!/usr/bin/env bash
# Undo this run's pin bumps after they broke a check, keep the lock update, and
# report the reverted bumps in one reused issue. Usage: revert-pin-bumps.sh REASON
# Exits 1 when there were no pin bumps to blame, so the caller's failure stands.
set -euo pipefail

reason="$1"
if [ ! -s "$BUMP_SUMMARY" ]; then
  exit 1
fi
echo "::warning::pinned version bumps $reason; retrying without them"
bumps="$(cat "$BUMP_SUMMARY")"
git diff --name-only | grep -vx flake.lock | xargs git checkout HEAD --
# flake.nix tag pins are back at their old values; re-lock just those inputs.
nix flake lock
: > "$BUMP_SUMMARY"

title="Pinned version bumps fail CI"
body="$(printf 'These bumps were reverted because the configuration %s with them:\n\n%s\n\nRun: %s\n' "$reason" "$bumps" "$RUN_URL")"
existing="$(gh issue list --state open --json number,title \
  --jq "map(select(.title == \"$title\")) | .[0].number // empty")"
if [ -n "$existing" ]; then
  gh issue comment "$existing" --body "$body"
else
  gh issue create --title "$title" --body "$body"
fi
