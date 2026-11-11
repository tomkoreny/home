#!/usr/bin/env bash
# Push the commit the "Commit and push" step just made.
#
# A run takes most of an hour, and a push to the branch in that time turns
# this one into a non-fast-forward. That is not a failure: the lock this run
# validated belongs to the old head, and the next hourly run starts from the
# new one. Any other push error still fails the job.
set -euo pipefail

if git push; then
  exit 0
fi

git fetch --quiet origin "$GITHUB_REF_NAME"
if [ "$(git rev-parse FETCH_HEAD)" != "$GITHUB_SHA" ]; then
  echo "::notice::$GITHUB_REF_NAME moved during this run; leaving the update to the next run"
  exit 0
fi
exit 1
