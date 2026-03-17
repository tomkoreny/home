{
  lib,
  pkgs,
  ...
}: {
  programs.nh = {
    enable = true;
    clean.enable = false;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake =
      if pkgs.stdenv.isDarwin
      then "/Users/tom/home"
      else "/home/tom/nixos2";
  };
}
