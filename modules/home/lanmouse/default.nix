{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  importCargoLockFromStaticCrates =
    pkgs.callPackage (pkgs.path + "/pkgs/build-support/rust/import-cargo-lock.nix")
      {
        fetchurl =
          args:
          pkgs.fetchurl (
            args
            // {
              url =
                lib.replaceStrings [ "https://crates.io/api/v1/crates" ] [ "https://static.crates.io/crates" ]
                  args.url;
            }
          );
      };
in
{
  imports = [ inputs.lan-mouse.homeManagerModules.default ];

  programs.lan-mouse = {
    enable = true;
    # Set these explicitly rather than evaluating the upstream module's
    # deprecated stdenv.isLinux/isDarwin defaults.
    systemd = pkgs.stdenv.hostPlatform.isLinux;
    launchd = pkgs.stdenv.hostPlatform.isDarwin;
    # crates.io's API download endpoint returns HTTP 403 from this network;
    # its static CDN serves the same checksummed registry artifacts.
    package = inputs.lan-mouse.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (_: {
      cargoDeps = importCargoLockFromStaticCrates {
        lockFile = "${inputs.lan-mouse}/Cargo.lock";
      };
    });
    # Optional configuration in nix syntax, see config.toml for available options
    # settings = { };
  };
}
