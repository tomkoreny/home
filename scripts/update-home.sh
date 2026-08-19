#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/update-home.sh [--no-switch] [--no-push] [--skip-flake]

One-shot dependency refresh for this home flake:
  1. requires a clean working tree
  2. pulls origin/main with rebase
  3. updates flake inputs
  4. runs nix flake check
  5. switches the current host configuration
  6. commits and pushes dependency changes

Options:
  --no-switch   Do not run darwin-rebuild/nixos-rebuild switch
  --no-push     Commit locally but do not push
  --skip-flake  Do not run nix flake update
EOF
}

switch_config=true
push_changes=true
update_flake=true

nix_flake_update() {
	local token=""

	if [[ -n "${GITHUB_TOKEN:-}" ]]; then
		token="$GITHUB_TOKEN"
	elif [[ -n "${GH_TOKEN:-}" ]]; then
		token="$GH_TOKEN"
	elif command -v gh >/dev/null 2>&1; then
		token="$(gh auth token 2>/dev/null || true)"
	fi

	if [[ -n "$token" ]]; then
		nix --option access-tokens "github.com=$token" flake update
	else
		echo "warning: no GitHub token found; set GITHUB_TOKEN/GH_TOKEN or run 'gh auth login' to avoid GitHub API rate limits" >&2
		nix flake update
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--no-switch)
		switch_config=false
		;;
	--no-push)
		push_changes=false
		;;
	--skip-flake)
		update_flake=false
		;;
	-h | --help)
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

starting_revision="$(git rev-parse HEAD)"
dependency_files=(flake.lock)

git pull --rebase origin main

if [[ "$update_flake" == true ]]; then
	nix_flake_update
fi

dependencies_changed=false
if ! git diff --quiet -- "${dependency_files[@]}"; then
	dependencies_changed=true
fi

if [[ "$(git rev-parse HEAD)" == "$starting_revision" && "$dependencies_changed" == false ]]; then
	echo "No repository or dependency changes."
	exit 0
fi

# `nix flake check` is a weaker gate than it looks: it only recurses into the
# output schemas nix knows, and it silently omits systems this host cannot
# build. Instantiate each host explicitly as well — evaluating a drvPath needs
# no builder for that system, so a Mac can still vet the NixOS homes.
hosts=(
	'darwinConfigurations.macos.system'
	'homeConfigurations."tom@macos".activationPackage'
	'homeConfigurations."tom@nixos".activationPackage'
	'homeConfigurations."terka@nixos".activationPackage'
)

# nixosConfigurations.nixos is the one host a Mac cannot reach: home-manager's
# hyprland module realises hyprland's x86_64-linux source to build its onChange
# hook, and no configured substituter carries it. The GitHub workflow validates
# that host on every bump, so this only narrows the local gate, never CI's.
if [[ "$(uname -s)" == "Linux" ]]; then
	hosts+=('nixosConfigurations.nixos.config.system.build.toplevel')
fi

nix flake check --show-trace
for attr in "${hosts[@]}"; do
	echo "validating $attr"
	nix eval --raw ".#$attr.drvPath" >/dev/null
done

if [[ "$dependencies_changed" == true ]]; then
	# A Darwin activation reloads this launchd agent and terminates the running
	# script, so persist validated dependency updates before switching.
	git add -- "${dependency_files[@]}"
	git commit -m "chore: update dependencies"

	if [[ "$push_changes" == true ]]; then
		git push origin main
	fi
fi

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
