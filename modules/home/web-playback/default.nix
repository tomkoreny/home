{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.tomkoreny.web-playback;
  mpv = pkgs.mpv.override {
    scripts = [ pkgs.mpvScripts.mpris ];
  };
  source = pkgs.replaceVars ./playback.py {
    mpv = lib.getExe mpv;
    mpvAspectScript = pkgs.callPackage ../hyprland/mpv-aspect.nix { };
    ytDlp = lib.getExe pkgs.yt-dlp;
    streamlink = lib.getExe pkgs.streamlink;
    wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
    notifySend = lib.getExe pkgs.libnotify;
    chromium = lib.getExe pkgs.chromium;
  };
  launcher = pkgs.writeShellScriptBin "web-playback" ''
    exec ${lib.getExe pkgs.python3} ${source} "$@"
  '';
  nativeHost = {
    name = "com.tomkoreny.web_playback";
    description = "Explicit YouTube and Twitch playback in mpv";
    path = lib.getExe (
      pkgs.writeShellScriptBin "web-playback-native" ''
        exec ${lib.getExe launcher} --native "$@"
      ''
    );
    type = "stdio";
    allowed_origins = [ "chrome-extension://keeppgjpejmhgehmknpjopikndfkajnl/" ];
  };
  clipboardCommand = "${lib.getExe launcher} --clipboard";
  hyprctl = "${inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland}/bin/hyprctl";
in
{
  options.tomkoreny.web-playback.enable = lib.mkEnableOption "explicit YouTube/Twitch handoff to mpv";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "web-playback requires a Linux desktop session";
      }
    ];

    home.packages = [ launcher ];
    xdg.configFile."net.imput.helium/NativeMessagingHosts/${nativeHost.name}.json".text =
      builtins.toJSON nativeHost;

    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      -- Explicit clipboard handoff; ordinary video links stay in the browser.
      hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("${clipboardCommand}"))
    '';
    home.activation.refreshWebPlaybackBinding = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [[ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] \
        && ${hyprctl} version >/dev/null 2>&1; then
        run ${hyprctl} eval ${lib.escapeShellArg ''hl.unbind("SUPER + SHIFT + M")''}
        run ${hyprctl} eval ${lib.escapeShellArg ''hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("${clipboardCommand}"))''}
      fi
    '';
  };
}
