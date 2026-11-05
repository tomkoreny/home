#!/usr/bin/env bash
# Undo this run's pin bumps after they broke a check, keep the lock update and
# the rolling-download refreshes, and report the reverted bumps in one reused
# issue. Usage: revert-pin-bumps.sh REASON
# Exits 1 when there were no pin bumps to blame, so the caller's failure stands.
set -euo pipefail

reason="$1"
if [ ! -s "$BUMP_SUMMARY" ]; then
  exit 1
fi
echo "::warning::pinned version bumps $reason; retrying without them"
bumps="$(cat "$BUMP_SUMMARY")"
git diff --name-only | grep -vx flake.lock | xargs git checkout HEAD --
# That also restored rolling-download hashes sharing a file with a pin, and pins
# whose old release upstream has since deleted; the retry would fail on either,
# so re-apply them. They move to $ROLLING_SUMMARY, out of the blame below.
python3 .github/scripts/bump-pins.py --after-revert
# flake.nix tag pins are back at their old values; re-lock just those inputs.
nix flake lock
: > "$BUMP_SUMMARY"
reverted="$(grep -vxFf "$ROLLING_SUMMARY" <<<"$bumps" || true)"
if [ -z "$reverted" ]; then
  # Every bump had to be re-applied, so a retry would check the same configuration.
  echo "::warning::no pinned version bump could be reverted; the failure stands"
  exit 1
fi

title="Pinned version bumps fail CI"
body="$(printf 'These bumps were reverted because the configuration %s with them:\n\n%s\n\nRun: %s\n' "$reason" "$reverted" "$RUN_URL")"
existing="$(gh issue list --state open --json number,title \
  --jq "map(select(.title == \"$title\")) | .[0].number // empty")"
if [ -n "$existing" ]; then
  gh issue comment "$existing" --body "$body"
else
  gh issue create --title "$title" --body "$body"
fi
