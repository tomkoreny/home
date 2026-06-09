#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update-home.sh [--no-switch] [--no-push] [--skip-pi] [--skip-flake]

One-shot dependency refresh for this home flake:
  1. requires a clean working tree
  2. pulls origin/main with rebase
  3. updates flake inputs
  4. updates the pinned pi-coding-agent npm package
  5. runs nix flake check
  6. switches the current host configuration
  7. commits and pushes dependency changes

Options:
  --no-switch   Do not run darwin-rebuild/nixos-rebuild switch
  --no-push     Commit locally but do not push
  --skip-pi     Do not update pi-coding-agent
  --skip-flake  Do not run nix flake update
EOF
}

switch_config=true
push_changes=true
update_pi=true
update_flake=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-switch)
      switch_config=false
      ;;
    --no-push)
      push_changes=false
      ;;
    --skip-pi)
      update_pi=false
      ;;
    --skip-flake)
      update_flake=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "error: working tree is not clean; commit/stash local changes first" >&2
  git status --short >&2
  exit 1
fi

git pull --rebase origin main

if [[ "$update_flake" == true ]]; then
  nix flake update
fi

if [[ "$update_pi" == true ]]; then
  scripts/update-pi-coding-agent.sh
fi

if git diff --quiet -- flake.lock modules/home/packages/default.nix modules/home/packages/pi-coding-agent-lock.json; then
  echo "No dependency changes."
  exit 0
fi

nix flake check --show-trace

if [[ "$switch_config" == true ]]; then
  case "$(uname -s)" in
    Darwin)
      sudo /nix/var/nix/profiles/system/sw/bin/darwin-rebuild switch --flake .#macos
      ;;
    Linux)
      sudo nixos-rebuild switch --flake .#nixos
      ;;
    *)
      echo "error: unsupported platform: $(uname -s)" >&2
      exit 1
      ;;
  esac
fi

git add flake.lock modules/home/packages/default.nix modules/home/packages/pi-coding-agent-lock.json
git commit -m "chore: update dependencies"

if [[ "$push_changes" == true ]]; then
  git push origin main
fi
