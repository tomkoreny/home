{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.waybar;

  # Hyprland's Lua configuration API changed socket dispatches from the old
  # `workspace 2` syntax to dispatcher objects. Waybar 0.15 still emits the
  # old command when a workspace button is clicked, so teach its numeric
  # workspace handler the equivalent Lua dispatcher syntax.
  waybar = pkgs.waybar.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/modules/hyprland/workspace.cpp \
        --replace-fail \
          'm_ipc.getSocket1Reply("dispatch workspace " + std::to_string(id()));' \
          'm_ipc.getSocket1Reply("dispatch hl.dsp.focus({ workspace = " + std::to_string(id()) + " })");'
    '';
  });

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
      "sort-by" = "number";
      "move-to-monitor" = false;
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
      package = waybar;
      settings = map (output: base // { inherit output; }) cfg.outputs;
      # Run the bar as a supervised user service instead of a bare
      # `exec-once`. Waybar 0.15.0's pulseaudio module recurses forever inside
      # AudioBackend::connectContext when the PulseAudio socket disappears
      # (pa_context_connect -> autospawn fails -> state callback -> reconnect
      # -> ...), ballooning to tens of GB before it aborts. A `sw` restarts
      # pipewire-pulse, so every rebuild silently killed the bar for good.
      systemd.enable = true;
    };

    # The unit is started from Hyprland's exec-once, not by
    # graphical-session.target: this session runs Hyprland with
    # `systemd.enable = false`, so that target never activates and the
    # generated `WantedBy` is inert.
    systemd.user.services.waybar = {
      # No start rate limiting: if pipewire-pulse is mid-restart the bar may
      # crash several times in a row, and the default burst limit would give up
      # exactly when we most need it to keep trying.
      Unit.StartLimitIntervalSec = 0;
      Service = {
        Restart = lib.mkForce "always";
        RestartSec = 3;
      };
    };

    home.file.".config/waybar/power_menu.xml" = {
      source = ./config/power_menu.xml;
    };
  };
}
