{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.quickshell-bar;
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  providerLogoSources = {
    anthropic = pkgs.fetchurl {
      url = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.94.0/icons/anthropic.svg";
      hash = "sha256-6DP9+n5xh6hqBbhwklBnVWpQbc1COQia7XPh5YyTZqM=";
    };
    openai = pkgs.fetchurl {
      url = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.94.0/icons/openai.svg";
      hash = "sha256-pZXfa0I5IMZ6f49zwGPkv7ctQVlICXtsrAY6I2a7UYY=";
    };
  };
  providerLogos = pkgs.runCommand "quickshell-provider-logos" { } ''
    mkdir -p "$out"
    substitute ${providerLogoSources.anthropic} "$out/anthropic.svg" \
      --replace-fail currentColor "#ffffff"
    substitute ${providerLogoSources.openai} "$out/openai.svg" \
      --replace-fail currentColor "#ffffff"
  '';
  launcherCustomIcons = builtins.toJSON {
    "betterbird" = ./icons/betterbird.svg;
    "com.mitchellh.ghostty" = ./icons/ghostty.svg;
    "counter-strike 2" = ./icons/counter-strike.svg;
    "datagrip" = ./icons/datagrip.svg;
    "de.feschber.lanmouse" = ./icons/lan-mouse.svg;
    "dev.zed.zed" = ./icons/zed.svg;
    "discord" = ./icons/discord.svg;
    "element-desktop" = ./icons/element.svg;
    "helium-browser" = ./icons/helium.svg;
    "htop" = ./icons/htop.svg;
    "io.github.benjamimgois.goverlay" = ./icons/goverlay.svg;
    "jellyfin-mpv-shim" = ./icons/jellyfin.svg;
    "nvim" = ./icons/neovim.svg;
    "org.gnome.nautilus" = ./icons/files.svg;
    "org.kicad.kicad" = ./icons/kicad.svg;
    "org.openrgb.openrgb" = ./icons/openrgb.svg;
    "org.prismlauncher.prismlauncher" = ./icons/prismlauncher.svg;
    "org.remmina.remmina" = ./icons/remmina.svg;
    "pycharm" = ./icons/pycharm.svg;
    "slack" = ./icons/slack.svg;
    "steam" = ./icons/steam.svg;
    "teams-for-linux" = ./icons/teams.svg;
    "webstorm" = ./icons/webstorm.svg;
  };
  profileIcon = relative: "${config.home.profileDirectory}/share/icons/hicolor/${relative}";
  dataIcon = relative: "${config.xdg.dataHome}/icons/hicolor/${relative}";
  launcherIconOverrides = builtins.toJSON {
    "betterbird" = profileIcon "128x128/apps/betterbird.png";
    "datagrip" = profileIcon "scalable/apps/datagrip.svg";
    "de.feschber.lanmouse" = profileIcon "scalable/apps/de.feschber.LanMouse.svg";
    "dev.zed.zed" = profileIcon "512x512/apps/zed.png";
    "discord" = profileIcon "256x256/apps/discord.png";
    "com.mitchellh.ghostty" = profileIcon "512x512/apps/com.mitchellh.ghostty.png";
    "element-desktop" = profileIcon "512x512/apps/element.png";
    "jellyfin-mpv-shim" = profileIcon "256x256/apps/jellyfin-mpv-shim.png";
    "helium-browser" = dataIcon "256x256/apps/helium.png";
    "kvantummanager" =
      "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/icons/hicolor/scalable/apps/kvantum.svg";
    "nvim" = profileIcon "128x128/apps/nvim.png";
    "org.gnome.nautilus" = profileIcon "scalable/apps/org.gnome.Nautilus.svg";
    "org.gnome.seahorse.application" = profileIcon "scalable/apps/org.gnome.seahorse.Application.svg";
    "org.kicad.bitmap2component" = profileIcon "scalable/apps/bitmap2component.svg";
    "org.kicad.eeschema" = profileIcon "scalable/apps/eeschema.svg";
    "org.kicad.gerbview" = profileIcon "scalable/apps/gerbview.svg";
    "org.kicad.kicad" = profileIcon "128x128/apps/kicad.png";
    "org.kicad.pcbcalculator" = profileIcon "scalable/apps/pcbcalculator.svg";
    "org.kicad.pcbnew" = profileIcon "scalable/apps/pcbnew.svg";
    "org.prismlauncher.prismlauncher" = profileIcon "scalable/apps/org.prismlauncher.PrismLauncher.svg";
    "org.remmina.remmina" = profileIcon "scalable/apps/org.remmina.Remmina.svg";
    "pycharm" = profileIcon "scalable/apps/pycharm.svg";
    "slack" = profileIcon "512x512/apps/slack.png";
    "teams-for-linux" = profileIcon "512x512/apps/teams-for-linux.png";
    "webstorm" = profileIcon "scalable/apps/webstorm.svg";
  };

  themeVars = {
    inherit fontFamily;
    accent = common.stylix.accent;
    accentSurface = "#33219fff";
    border = "#66219fff";
    cardSurface = "#f21e1e2e";
    muted = "#f38ba8";
    surface = "#f2181825";
    text = "#cdd6f4";
    subdued = "#a6adc8";
  };
  shell = pkgs.replaceVars ./shell.qml (
    (builtins.removeAttrs themeVars [ "cardSurface" ])
    // {
      outputs = builtins.toJSON cfg.outputs;
      opaqueSurface = "#181825";
      anthropicLogo = "${providerLogos}/anthropic.svg";
      openaiLogo = "${providerLogos}/openai.svg";
      primaryOutput = cfg.primaryOutput;
      herdr = lib.getExe herdrPackage;
      hyprctl = lib.getExe' config.wayland.windowManager.hyprland.package "hyprctl";
      herdrView = "${config.home.profileDirectory}/bin/herdr-view";
      pavucontrol = lib.getExe pkgs.pavucontrol;
      omp = lib.getExe config.programs.omp.package;
      qs = "${pkgs.quickshell}/bin/qs";
    }
  );
  launcher = pkgs.replaceVars ./Launcher.qml (
    (builtins.removeAttrs themeVars [ "muted" ])
    // {
      uwsm = lib.getExe pkgs.uwsm;
      qalc = lib.getExe pkgs.libqalculate;
      wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
      iconOverrides = launcherIconOverrides;
      customIcons = launcherCustomIcons;
    }
  );
  notificationCard = pkgs.replaceVars ./NotificationCard.qml themeVars;
  notifications = pkgs.replaceVars ./Notifications.qml (
    (builtins.removeAttrs themeVars [
      "cardSurface"
      "muted"
    ])
    // {
      primaryOutput = cfg.primaryOutput;
    }
  );
in
{
  options.tomkoreny.quickshell-bar = {
    enable = lib.mkEnableOption "the Quickshell desktop bar";

    outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Monitor connectors that host Quickshell bars";
    };

    primaryOutput = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Monitor connector that hosts the status cluster";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "The Quickshell bar is currently Linux-only.";
      }
      {
        assertion = cfg.outputs != [ ];
        message = "tomkoreny.quickshell-bar.outputs must contain at least one output.";
      }
      {
        assertion = lib.elem cfg.primaryOutput cfg.outputs;
        message = "tomkoreny.quickshell-bar.primaryOutput must be one of its outputs.";
      }
    ];

    home.packages = [ pkgs.quickshell ];

    xdg.configFile = {
      "quickshell/tom-bar/shell.qml".source = shell;
      "quickshell/tom-bar/Launcher.qml".source = launcher;
      "quickshell/tom-bar/NotificationCard.qml".source = notificationCard;
      "quickshell/tom-bar/Notifications.qml".source = notifications;
    };

    systemd.user.services.quickshell-bar = {
      Unit.Description = "Quickshell desktop bar";
      Service = {
        ExecStart = "${pkgs.quickshell}/bin/qs -c tom-bar";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
