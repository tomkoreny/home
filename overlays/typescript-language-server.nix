# typescript-language-server 6.0.2 moved to fetchPnpmDeps, whose output
# differs per platform. nixpkgs pins one hash for every platform, and at
# nixpkgs 7fd4004 that hash (sha256-MUSxDM…) matches neither platform built
# here, so both nixos-rebuild and darwin-rebuild failed with a hash mismatch.
# Measured 2026-10-14 against nixpkgs 7fd4004.
#
# Scoped to 6.0.2, so the next upstream version bump drops the override
# instead of pinning a stale hash onto new sources.
let
  pnpmDepsHashes = {
    x86_64-linux = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
    aarch64-darwin = "sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU=";
  };
in
final: prev:
let
  hash = pnpmDepsHashes.${prev.stdenv.hostPlatform.system} or null;
in
{
  typescript-language-server =
    if hash != null && prev.typescript-language-server.version == "6.0.2" then
      prev.typescript-language-server.overrideAttrs (old: {
        pnpmDeps = old.pnpmDeps.overrideAttrs {
          outputHash = hash;
        };
      })
    else
      prev.typescript-language-server;
}
