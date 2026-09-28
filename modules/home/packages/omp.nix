# The omp package every user gets; not a module (autoModules only imports
# directories), imported by ./default.nix and ../agents/default.nix.
#
# Upstream's nix/package.nix is used as-is since omp 18.4.1. Two Darwin
# workarounds lived here before that and are worth knowing if a bump breaks:
# the addon's post-link version stamp (upstream now runs
# `stamp-native-version.ts --no-sign` itself), and the Apple Foundation Models
# Swift bridge, whose toolchain probe used to ignore SDKROOT, find the host's
# macOS 27 SDK, and weak-link a FoundationModels.tbd that nixpkgs' ld64 cannot
# parse; the result called NULL at startup on macOS 27. The probe now honours
# SDKROOT, which the nixpkgs stdenv points at apple-sdk 14.4 (no
# FoundationModels), so the bridge is stubbed out and the on-device Apple
# model provider is absent from the Nix build.
{ inputs, pkgs, ... }:
inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp
