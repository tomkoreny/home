{
  lib,
  pkgs ? null,
  outputs ? [ ],
  ...
}:
let
  isLinux = if pkgs == null then false else pkgs.stdenv.hostPlatform.isLinux;
  base = {
    height = 30;
    spacing = 4;
    "modules-left" = [
      "hyprland/workspaces"
      "custom/media"
    ];
    "modules-center" = [
      "custom/polytiramisu"
    ];
    "modules-right" = [
      "pulseaudio"
      "network"
      "cpu"
      "memory"
      "tray"
      "clock"
      "custom/power"
    ];
    "keyboard-state" = {
      numlock = true;
      capslock = true;
      format = "{name} {icon}";
      "format-icons" = {
        locked = "";
        unlocked = "";
      };
    };
    "hyprland/workspaces" = {
      format = "<sub>{icon}</sub>{windows}";
      "format-window-separator" = "";
      "window-rewrite-default" = "";
      "window-rewrite" = {
        "title<.*youtube.*>" = "";
        "class<firefox>" = "";
        "class<firefox> title<.*github.*>" = "";
        "class<Helium>" = "";
        "class<Helium> title<.*github.*>" = "";
        "class<helium-browser>" = "";
        "class<helium-browser> title<.*github.*>" = "";
        "class<jetbrains-webstorm>" = "";
        "class<kitty>" = "";
        "class<teams-for-linux>" = "󰊻";
        "class<Beeper>" = "󰭹";
        foot = "";
        code = "󰨞";
      };
    };
    "hyprland/window" = {
      format = "👉 {}";
      rewrite = {
        "(.*) — Mozilla Firefox" = "🌎 $1";
        "(.*) — Helium" = "🌎 $1";
        "Welcome to WebStorm" = "";
        "Beeper (\\[\\d+\\])? \\| (.*)" = "󰭹 ($1) - ($2)";
        "(.*) - fish" = "> [$1]";
      };
      "separate-outputs" = true;
    };
    "custom/polytiramisu" = {
      format = "{} ";
      exec = "bash ~/.config/waybar/scripts/polytiramisu.sh";
    };
    mpd = {
      format = "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
      "format-disconnected" = "Disconnected ";
      "format-stopped" = "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
      "unknown-tag" = "N/A";
      interval = 5;
      "consume-icons" = {
        on = " ";
      };
      "random-icons" = {
        off = "<span color=\"#f53c3c\"></span> ";
        on = " ";
      };
      "repeat-icons" = {
        on = " ";
      };
      "single-icons" = {
        on = "1 ";
      };
      "state-icons" = {
        paused = "";
        playing = "";
      };
      "tooltip-format" = "MPD (connected)";
      "tooltip-format-disconnected" = "MPD (disconnected)";
    };
    idle_inhibitor = {
      format = "{icon}";
      "format-icons" = {
        activated = "";
        deactivated = "";
      };
    };
    tray = {
      spacing = 10;
    };
    clock = {
      "tooltip-format" = ''
        <big>{:%Y %B}</big>
        <tt><small>{calendar}</small></tt>'';
      "format-alt" = "{:%Y-%m-%d}";
    };
    cpu = {
      format = "{usage}% ";
      tooltip = false;
    };
    memory = {
      format = "{}% ";
    };
    temperature = {
      "critical-threshold" = 80;
      format = "{temperatureC}°C {icon}";
      "format-icons" = [
        ""
        ""
        ""
      ];
    };
    backlight = {
      format = "{percent}% {icon}";
      "format-icons" = [
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
      ];
    };
    network = {
      "format-wifi" = "{essid} ({signalStrength}%) ";
      "format-ethernet" = "{ipaddr}/{cidr}";
      "tooltip-format" = "{ifname} via {gwaddr}";
      "format-linked" = "{ifname} (No IP)";
      "format-disconnected" = "Disconnected ⚠";
      "format-alt" = "{ifname}: {ipaddr}/{cidr}";
    };
    pulseaudio = {
      format = "{volume}% {icon} {format_source}";
      "format-bluetooth" = "{volume}% {icon} {format_source}";
      "format-bluetooth-muted" = " {icon} {format_source}";
      "format-muted" = " {format_source}";
      "format-source" = "{volume}% ";
      "format-source-muted" = "";
      "format-icons" = {
        headphone = "";
        "hands-free" = "";
        headset = "";
        phone = "";
        portable = "";
        car = "";
        default = [
          ""
          ""
          ""
        ];
      };
      "on-click" = "pavucontrol";
    };
    "custom/media" = {
      format = "{icon} {text}";
      "return-type" = "json";
      "max-length" = 40;
      "format-icons" = {
        spotify = "";
        default = "🎜";
      };
      escape = true;
      exec = "$HOME/.config/waybar/mediaplayer.py 2> /dev/null";
    };
    "custom/power" = {
      format = "⏻ ";
      tooltip = false;
      menu = "on-click";
      "menu-file" = "$HOME/.config/waybar/power_menu.xml";
      "menu-actions" = {
        shutdown = "shutdown";
        reboot = "reboot";
        suspend = "systemctl suspend";
        hibernate = "systemctl hibernate";
      };
    };
  };
in
{
  config = lib.mkIf isLinux {
    programs.waybar = {
      enable = true;
      settings = map (output: base // { inherit output; }) outputs;
    };

    home.file.".config/waybar/scripts/polytiramisu.sh" = {
      source = ./config/polytiramisu.sh;
    };
    home.file.".config/waybar/power_menu.xml" = {
      source = ./config/power_menu.xml;
    };
  };
}
