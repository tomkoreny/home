{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.tomkoreny.mpv-ui;
  ui = pkgs.callPackage ./theme.nix { inherit inputs; };
in
{
  options.tomkoreny.mpv-ui.enable = lib.mkEnableOption "the shared OLED-friendly mpv controller";

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.mpv.override { scripts = [ pkgs.mpvScripts.uosc ]; })
    ];
    xdg.configFile = {
      "mpv/mpv.conf".source = ui.mpvConfig;
      "mpv/script-opts/uosc.conf".source = ui.uoscConfig;
      "mpv/input.conf".source = ui.inputConfig;
    };
  };
}
