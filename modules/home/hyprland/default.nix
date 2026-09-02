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
}:
let
  hyprlandPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  desktopBarService =
    if config.tomkoreny.quickshell-bar.enable then "quickshell-bar.service" else "waybar.service";
  hyprlandConfig = builtins.replaceStrings [ "@desktopBarService@" ] [ desktopBarService ] (
    builtins.readFile ./config/hyprland/main.lua
  );
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;
  oledIdle = pkgs.writeShellApplication {
    name = "oled-idle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ddcutil
      pkgs.util-linux
    ];
    text = ''
      state="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is unset}/tom-oled-idle-brightness"
      exec 9>"''${XDG_RUNTIME_DIR}/tom-oled-idle.lock"
      flock 9
      serials=(6D12YZ3 W6Z205100322 W6Z210400266)

      call_idle() {
        ${pkgs.quickshell}/bin/qs -c tom-idle ipc call idle "$1" >/dev/null
      }
      set_dpms() {
        local dispatch
        printf -v dispatch 'hl.dsp.dpms({ action = "%s" })' "$1"
        "${hyprlandPackage}/bin/hyprctl" dispatch "$dispatch"
      }


      capture_brightness() {
        [[ -e "$state" ]] && return 0
        tmp="$state.tmp.$$"
        : >"$tmp"
        for serial in "''${serials[@]}"; do
          if line="$(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief --sn "$serial" 2>/dev/null)"; then
            read -r label code kind current _maximum <<<"$line"
            if [[ "$label" == VCP && "$code" == 10 && "$kind" == C && "$current" =~ ^[0-9]+$ ]]; then
              printf '%s %s\n' "$serial" "$current" >>"$tmp"
            fi
          fi
        done
        if [[ -s "$tmp" ]]; then
          mv "$tmp" "$state"
        else
          rm -f "$tmp"
          return 1
        fi
      }

      set_saved_brightness() {
        local fixed_value="''${1:-}"
        local failed=0
        local pids=()
        local serial saved value

        [[ -r "$state" ]] || return 0
        while read -r serial saved; do
          value="''${fixed_value:-$saved}"
          ${pkgs.ddcutil}/bin/ddcutil setvcp 10 "$value" --sn "$serial" >/dev/null 2>&1 &
          pids+=("$!")
        done <"$state"
        for pid in "''${pids[@]}"; do
          wait "$pid" || failed=1
        done
        return "$failed"
      }

      restore_brightness() {
        [[ -r "$state" ]] || return 0
        if set_saved_brightness; then
          rm -f "$state"
        else
          return 1
        fi
      }

      case "''${1:-}" in
        dim)
          call_idle dim || true
          capture_brightness
          set_saved_brightness 20
          ;;
        blank)
          call_idle blank
          ;;
        wake)
          call_idle wake || true
          restore_brightness
          ;;
        dpms-off)
          call_idle blank || true
          set_dpms off
          ;;
        dpms-on)
          set_dpms on
          call_idle wake || true
          restore_brightness
          ;;
        *)
          echo "usage: oled-idle {dim|blank|wake|dpms-off|dpms-on}" >&2
          exit 2
          ;;
      esac
    '';
  };
  idleShell = pkgs.replaceVars ./idle.qml {
    inherit fontFamily;
    oledIdle = lib.getExe oledIdle;
  };
in
{
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    wayland.windowManager.hyprland = {
      enable = true; # enable Hyprland
      systemd.enableXdgAutostart = true; # enable HyprlandAutostart
      configType = "lua";
      extraConfig = hyprlandConfig;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      systemd.enable = false;
    };

    # Hyprpaper, Hypridle, and the OLED saver are managed by user services.
    # UWSM activates graphical-session.target; the compositor callback starts
    # only units which are intentionally tied to this Hyprland session.
    home.packages = [
      pkgs.hyprpaper
      pkgs.hypridle
      pkgs.quickshell
      oledIdle

      # Programs referenced by binds in main.lua
      pkgs.nautilus # Super+E file manager
      pkgs.playerctl # media keys
      pkgs.brightnessctl # brightness keys

      # Proofread the current selection and rewrite it with Czech diacritics.
      # Reads the highlighted text (Wayland primary selection), sends it through
      # the already-authenticated `claude` CLI, then types the corrected text
      # back over the selection. Bound to Super+D in main.lua.
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

    xdg.configFile."quickshell/tom-idle/shell.qml".source = idleShell;

    systemd.user.services.quickshell-idle = {
      Unit.Description = "Quickshell OLED idle surface";
      Service = {
        ExecStart = "${pkgs.quickshell}/bin/qs -c tom-idle";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    services.hyprpaper.enable = true;
    services.hypridle.enable = true;
    services.hypridle.settings = {
      general = {
        after_sleep_cmd = "${oledIdle}/bin/oled-idle dpms-on";
        ignore_dbus_inhibit = false;
        # This remains a visual OLED saver rather than an authenticated lock.
        lock_cmd = "${oledIdle}/bin/oled-idle blank";
      };

      listener = [
        {
          timeout = 120;
          on-timeout = "${oledIdle}/bin/oled-idle dim";
          on-resume = "${oledIdle}/bin/oled-idle wake";
        }
        {
          timeout = 300;
          on-timeout = "${oledIdle}/bin/oled-idle blank";
          on-resume = "${oledIdle}/bin/oled-idle wake";
        }
        {
          timeout = 600;
          on-timeout = "${oledIdle}/bin/oled-idle dpms-off";
        }
      ];
    };
  };
}
