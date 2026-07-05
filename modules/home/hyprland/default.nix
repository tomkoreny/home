{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,
  # Additional metadata is provided by Snowfall Lib.
  namespace, # The namespace used for your flake, defaulting to "internal" if not set.
  # All other arguments come from the module system.
  config,
  ...
}: {
  config = lib.mkIf pkgs.stdenv.isLinux {
    wayland.windowManager.hyprland = {
      enable = true; # enable Hyprland
      systemd.enableXdgAutostart = true; # enable HyprlandAutostart
      configType = "hyprlang";
      extraConfig = builtins.readFile ./config/hyprland/main.conf;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      systemd.enable = false;
    };

    # `services.hyprpaper.enable` writes hyprpaper's config/systemd unit, but the
    # Hyprland config starts it with `exec-once = uwsm app -- hyprpaper`. Make the
    # binary available in PATH so that autostart command can actually launch it.
    home.packages = [
      pkgs.hyprpaper

      # Programs referenced by binds in main.conf
      pkgs.nautilus # Super+E file manager
      pkgs.playerctl # media keys
      pkgs.brightnessctl # brightness keys

      # Proofread the current selection and rewrite it with Czech diacritics.
      # Reads the highlighted text (Wayland primary selection), sends it through
      # the already-authenticated `claude` CLI, then types the corrected text
      # back over the selection. Bound to Super+D in main.conf.
      (pkgs.writeShellScriptBin "diacritics-fix" ''
        set -uo pipefail

        sel="$(${pkgs.wl-clipboard}/bin/wl-paste --primary --no-newline 2>/dev/null || true)"
        if [ -z "$sel" ]; then
          ${pkgs.libnotify}/bin/notify-send "Diacritics" "No text selected."
          exit 0
        fi

        ${pkgs.libnotify}/bin/notify-send -t 1500 "Diacritics" "Proofreading…"

        prompt='Add correct Czech diacritics to the following text and fix obvious typos and spelling. Output ONLY the corrected text, with no commentary, explanations, or surrounding quotes. Preserve line breaks, punctuation and capitalization.'
        fixed="$(printf '%s' "$sel" | claude -p "$prompt" 2>/dev/null || true)"
        fixed="''${fixed%$'\n'}"

        if [ -z "$fixed" ]; then
          ${pkgs.libnotify}/bin/notify-send "Diacritics" "No result — is the claude CLI logged in?"
          exit 1
        fi

        ${pkgs.wtype}/bin/wtype -- "$fixed"
      '')
    ];

    services.hyprpaper.enable = true;
    services.hypridle.enable = true;
    services.hypridle.settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
        # Intentional: no real screen lock. This is a desktop in a physically
        # secure space, so "locking" just turns the displays off rather than
        # running hyprlock. hyprlock is deliberately not installed.
        lock_cmd = "hyprctl dispatch dpms off";
      };

      listener = [
        {
          # Intentionally aggressive (60s): these are OLED panels, so we blank
          # them quickly when idle to minimise burn-in. Pairs with the
          # mouse_move_enables_dpms = false misc setting in main.conf.
          timeout = 60;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
