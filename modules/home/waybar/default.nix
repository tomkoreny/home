{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.waybar;
  base = {
    height = 30;
    spacing = 4;
    "modules-left" = [
      "hyprland/workspaces"
    ];
    "modules-center" = [
      "hyprland/window"
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
    "hyprland/workspaces" = {
      format = "<sub>{icon}</sub>{windows}";
      "format-window-separator" = "";
      "window-rewrite-default" = "";
      "window-rewrite" = {
        "title<.*youtube.*>" = "";
        "class<firefox>" = "";
        "class<firefox> title<.*github.*>" = "";
        "class<Helium>" = "";
        "class<Helium> title<.*github.*>" = "";
        "class<helium-browser>" = "";
        "class<helium-browser> title<.*github.*>" = "";
        "class<jetbrains-webstorm>" = "";
        "class<kitty>" = "";
        "class<teams-for-linux>" = "󰊻";
        "class<Beeper>" = "󰭹";
        foot = "";
        code = "󰨞";
      };
    };
    "hyprland/window" = {
      format = "👉 {}";
      rewrite = {
        "(.*) — Mozilla Firefox" = "🌎 $1";
        "(.*) — Helium" = "🌎 $1";
        "Welcome to WebStorm" = "";
        "Beeper (\\[\\d+\\])? \\| (.*)" = "󰭹 ($1) - ($2)";
        "(.*) - fish" = "> [$1]";
      };
      "separate-outputs" = true;
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
      format = "{usage}% ";
      tooltip = false;
    };
    memory = {
      format = "{}% ";
    };
    network = {
      "format-wifi" = "{essid} ({signalStrength}%) ";
      "format-ethernet" = "{ipaddr}/{cidr}";
      "tooltip-format" = "{ifname} via {gwaddr}";
      "format-linked" = "{ifname} (No IP)";
      "format-disconnected" = "Disconnected ⚠";
      "format-alt" = "{ifname}: {ipaddr}/{cidr}";
    };
    pulseaudio = {
      format = "{volume}% {icon} {format_source}";
      "format-bluetooth" = "{volume}% {icon} {format_source}";
      "format-bluetooth-muted" = " {icon} {format_source}";
      "format-muted" = " {format_source}";
      "format-source" = "{volume}% ";
      "format-source-muted" = "";
      "format-icons" = {
        headphone = "";
        "hands-free" = "";
        headset = "";
        phone = "";
        portable = "";
        car = "";
        default = [
          ""
          ""
          ""
        ];
      };
      "on-click" = lib.getExe pkgs.pavucontrol;
    };
    "custom/power" = {
      format = "⏻ ";
      tooltip = false;
      menu = "on-click";
      "menu-file" = "$HOME/.config/waybar/power_menu.xml";
      "menu-actions" = {
        shutdown = "systemctl poweroff";
        reboot = "systemctl reboot";
        suspend = "systemctl suspend";
        hibernate = "systemctl hibernate";
      };
    };
  };
in
{
  options.tomkoreny.waybar = {
    outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Monitor connectors to show a bar on (one bar per output); empty disables waybar";
    };
  };

  config = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && cfg.outputs != [ ]) {
    programs.waybar = {
      enable = true;
      settings = map (output: base // { inherit output; }) cfg.outputs;
    };

    home.file.".config/waybar/power_menu.xml" = {
      source = ./config/power_menu.xml;
    };
  };
}
