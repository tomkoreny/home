#!/usr/bin/env bash
# Instantiate every host so a lock or pin that breaks evaluation is never pushed.
#
# `nix flake check` alone is a weaker gate than it looks. It understands a
# fixed set of output schemas: nixosConfigurations is deep-checked, but
# darwinConfigurations and homeConfigurations are only visited, and on the
# pinned nix 2.31.3 a `throw` inside either still exits 0. That asymmetry is
# exactly why this job caught a removed services.i2pd option in the NixOS
# config while an nvf assertion in the home configs sailed past.
#
# So instantiate every host explicitly rather than trusting the schema list.
# `nix eval` of a drvPath instantiates without building, which is what lets an
# ubuntu runner vet the two darwin hosts. --all-systems keeps the check itself
# from skipping aarch64-darwin outputs such as formatter.
set -euo pipefail

nix flake check --all-systems path:.
for attr in \
  'nixosConfigurations.nixos.config.system.build.toplevel' \
  'darwinConfigurations.macos.system' \
  'homeConfigurations."tom@macos".activationPackage' \
  'homeConfigurations."tom@nixos".activationPackage' \
  'homeConfigurations."terka@nixos".activationPackage'; do
  echo "instantiating $attr"
  nix eval --raw "path:.#$attr.drvPath" > /dev/null
done
