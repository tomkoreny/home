{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    # Tom's per-platform checkout of this flake, and the single definition of
    # it: the shell module's `conf` and `ksecret` read it back. Other users
    # cannot rebuild, so they get no default flake.
    flake = lib.mkIf (config.home.username == "tom") (
      if pkgs.stdenv.hostPlatform.isDarwin
      then "/Users/tom/home"
      else "/home/tom/nixos2"
    );
  };
}
