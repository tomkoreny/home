#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: scripts/update-home.sh [--no-switch]

Adopt the configuration currently on origin/main for this host:
  1. requires a clean working tree
  2. pulls origin/main with rebase
  3. validates every host this machine can evaluate
  4. switches the current host configuration

Flake inputs are owned by .github/workflows/update-flake.yml, which bumps
flake.lock only after instantiating every host. This script never runs
`nix flake update` and never pushes, so a machine can only ever adopt a lock
that already passed that gate. A Mac cannot evaluate the NixOS host at all
(see below), which is why local bumping was retired.

Options:
  --no-switch   Do not run darwin-rebuild/nixos-rebuild switch
EOF
}

switch_config=true

# Kept verbatim so the apply phase below can be handed the same invocation.
original_args=("$@")

while [[ $# -gt 0 ]]; do
	case "$1" in
	--no-switch)
		switch_config=false
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
	echo "error: working tree is not clean; refusing to touch it" >&2
	exit 1
fi

# The pull below can replace this very file. Bash keeps reading from the open
# file descriptor, which still points at the old inode, so the remainder of the
# run would come from the previous version of the script — including code that
# no longer exists in it. Do the pull in one phase, then hand over to the file
# on disk with exec. UPDATE_HOME_PHASE is internal; it is not a documented flag
# because nothing outside this script should set it.
if [[ "${UPDATE_HOME_PHASE:-pull}" == "pull" ]]; then
	starting_revision="$(git rev-parse HEAD)"

	git pull --rebase origin main

	if [[ "$(git rev-parse HEAD)" == "$starting_revision" ]]; then
		echo "Already on the latest validated configuration."
		exit 0
	fi

	UPDATE_HOME_PHASE=apply exec "$0" ${original_args[@]+"${original_args[@]}"}
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
# that host on every bump, so it is covered, just not from here.
if [[ "$(uname -s)" == "Linux" ]]; then
	hosts+=('nixosConfigurations.nixos.config.system.build.toplevel')
fi

nix flake check --show-trace
for attr in "${hosts[@]}"; do
	echo "validating $attr"
	nix eval --raw ".#$attr.drvPath" >/dev/null
done

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
