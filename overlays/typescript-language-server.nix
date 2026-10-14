# typescript-language-server 6.0.2 moved to fetchPnpmDeps, whose output
# differs per platform. nixpkgs pins one hash for every platform: first a
# stale one, then (NixOS/nixpkgs@ac7b1aa) the x86_64-linux one. Neither
# matches aarch64-darwin, so the macOS build failed with a hash mismatch and
# blocked every darwin-rebuild. Measured 2026-10-14 against nixpkgs 7fd4004:
#   x86_64-linux    sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=
#   aarch64-darwin  sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU=
#
# Scoped to 6.0.2 on aarch64-darwin, so the next upstream version bump drops
# the override instead of pinning a stale hash onto new sources.
final: prev: {
  typescript-language-server =
    if
      prev.stdenv.hostPlatform.system == "aarch64-darwin"
      && prev.typescript-language-server.version == "6.0.2"
    then
      prev.typescript-language-server.overrideAttrs (old: {
        pnpmDeps = old.pnpmDeps.overrideAttrs {
          outputHash = "sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU=";
        };
      })
    else
      prev.typescript-language-server;
}
