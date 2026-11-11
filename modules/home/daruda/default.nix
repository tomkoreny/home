# Daruda (github.com/daruda-ai/daruda): a native GPUI workspace that runs
# coding agents side by side over the Agent Client Protocol (ACP), one git
# worktree per task, with terminal panes beside the chats. On trial as a GUI
# for OMP.
#
# OMP is not one of Daruda's agent presets, but its catalog accepts custom
# rows: an `[[agents]]` entry in ~/.config/daruda/config.toml with an id, a
# name and the launch command. Daruda rewrites config.toml when settings
# change in the app, so the file cannot be a store symlink. The activation
# step below writes it once, with OMP as the only agent, and never touches an
# existing file.
#
# Over ACP, OMP treats its built-in default approval mode (`yolo`) as
# "always ask" and sends Daruda a permission request before every bash, edit,
# delete and move call. `--auto-approve` (alias `--yolo`) makes the ACP
# session skip those prompts, the same way Daruda's own presets launch
# `claude --dangerously-skip-permissions` and `gemini --yolo`.
#
# Daruda's built-in updater cannot replace a store path. The pin in
# package.nix follows upstream through .github/scripts/bump-pins.py instead.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.daruda;
  daruda = pkgs.callPackage ./package.nix { };

  seedConfig = pkgs.writeText "daruda-config.toml" ''
    [[agents]]
    id = "omp"
    name = "Oh My Pi"
    command = "omp acp --auto-approve"
  '';
in
{
  options.tomkoreny.daruda.enable = lib.mkEnableOption "the Daruda agent workspace";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The Daruda module packages only the x86_64 Linux release.";
      }
    ];

    home.packages = [ daruda ];

    home.activation.darudaSeedConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      darudaConfig=${lib.escapeShellArg "${config.xdg.configHome}/daruda/config.toml"}
      if [[ ! -e "$darudaConfig" ]]; then
        run install -D -m 600 ${seedConfig} "$darudaConfig"
      fi
    '';
  };
}
