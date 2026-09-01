{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.quickshell-osd;
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;

  shell = pkgs.replaceVars ./shell.qml {
    inherit fontFamily;
    systemctl = "${pkgs.systemd}/bin/systemctl";
    output = cfg.output;
    accent = common.stylix.accent;
    accentSurface = "#33219fff";
    border = "#66219fff";
    muted = "#f38ba8";
    mutedSurface = "#33f38ba8";
    surface = "#f2181825";
    text = "#cdd6f4";
    track = "#45475a";
  };

  controller = pkgs.writeShellApplication {
    name = "desktop-osd";
    runtimeInputs = [
      pkgs.ddcutil
      pkgs.quickshell
      pkgs.util-linux
      pkgs.wireplumber
    ];
    text = ''
      serial=${lib.escapeShellArg cfg.monitorSerial}

      show_volume() {
        local status value muted
        status="$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" || return 0
        value="''${status#Volume: }"
        value="''${value%% *}"
        muted=false
        [[ "$status" == *"[MUTED]"* ]] && muted=true
        qs -c tom-osd ipc call osd showVolume "$value" "$muted" >/dev/null 2>&1 || true
      }

      read_brightness() {
        local line
        line="$(ddcutil --sn "$serial" getvcp 10 --brief 2>/dev/null)" || return 1
        read -r _ _ _ brightness_current brightness_maximum <<< "$line"
        [[ "$brightness_current" =~ ^[0-9]+$ && "$brightness_maximum" =~ ^[0-9]+$ ]] || return 1
        (( brightness_maximum > 0 ))
      }

      show_brightness() {
        read_brightness || return 0
        qs -c tom-osd ipc call osd showBrightness "$((brightness_current * 100 / brightness_maximum))" >/dev/null 2>&1 || true
      }

      adjust_brightness() {
        local operator="$1"
        local lock="''${XDG_RUNTIME_DIR:-/tmp}/tom-osd-brightness.lock"
        local expected
        exec 9>"$lock"
        flock -n 9 || return 1

        read_brightness || return 1
        if [[ "$operator" == + ]]; then
          expected=$((brightness_current + 10))
          (( expected > brightness_maximum )) && expected=$brightness_maximum
        else
          expected=$((brightness_current - 10))
          (( expected < 0 )) && expected=0
        fi

        ddcutil --sn "$serial" setvcp 10 "$expected" --noverify >/dev/null 2>&1 || return 1
        read_brightness || return 1
        if (( brightness_current != expected )); then
          ddcutil --sn "$serial" setvcp 10 "$expected" --noverify >/dev/null 2>&1 || return 1
          read_brightness || return 1
        fi

        qs -c tom-osd ipc call osd showBrightness "$((brightness_current * 100 / brightness_maximum))" >/dev/null 2>&1 || true
        (( brightness_current == expected ))
      }

      case "''${1:-}" in
        volume-up)
          wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
          show_volume
          ;;
        volume-down)
          wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
          show_volume
          ;;
        volume-mute)
          wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
          show_volume
          ;;
        brightness-up)
          adjust_brightness +
          ;;
        brightness-down)
          adjust_brightness -
          ;;
        session)
          qs -c tom-osd ipc call session reveal >/dev/null
          ;;
        *)
          echo "usage: desktop-osd {volume-up|volume-down|volume-mute|brightness-up|brightness-down|session}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.tomkoreny.quickshell-osd = {
    enable = lib.mkEnableOption "Quickshell desktop overlays";

    output = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Wayland output connector that hosts the OSD";
    };

    monitorSerial = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Serial number of the monitor that receives DDC brightness changes";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "The Quickshell OSD is currently Linux-only.";
      }
      {
        assertion = cfg.output != "";
        message = "tomkoreny.quickshell-osd.output must identify the target output.";
      }
      {
        assertion = cfg.monitorSerial != "";
        message = "tomkoreny.quickshell-osd.monitorSerial must identify the target monitor.";
      }
    ];

    home.packages = [
      pkgs.quickshell
      pkgs.ddcutil
      controller
    ];

    xdg.configFile."quickshell/tom-osd/shell.qml".source = shell;

    systemd.user.services.quickshell-osd = {
      Unit.Description = "Quickshell desktop OSD";
      Service = {
        ExecStart = "${pkgs.quickshell}/bin/qs -c tom-osd";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
