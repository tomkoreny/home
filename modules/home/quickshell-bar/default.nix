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
  notionTodoAssigneeId = "c3045b6d-8e81-4f7a-a5fe-ebf07f041fef";
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

  launcherClipboard = pkgs.writeShellApplication {
    name = "launcher-clipboard";
    runtimeInputs = [
      pkgs.cliphist
      pkgs.coreutils
      pkgs.imagemagick
      pkgs.jq
      pkgs.wl-clipboard
    ];
    text = ''
      cache_dir="''${XDG_RUNTIME_DIR:?}/quickshell-clipboard-thumbnails"

      valid_id() {
        case "$1" in
          ""|*[!0-9]*) return 1 ;;
        esac
      }

      case "''${1:-}" in
        list)
          rm -rf -- "$cache_dir"
          install -d -m 700 "$cache_dir"
          cliphist list | jq --arg cache "$cache_dir" -Rsc '
            split("\n")
            | map(
                select(length > 0)
                | capture("^(?<id>[0-9]+)\\t(?<preview>.*)$")
                | .image = (.preview | startswith("[[ binary data"))
                | .thumbnail = ($cache + "/" + .id + ".png")
              )
          '
          ;;
        copy)
          id="''${2:-}"
          valid_id "$id"
          cliphist decode "$id" | wl-copy
          ;;
        thumbnail)
          id="''${2:-}"
          valid_id "$id"
          install -d -m 700 "$cache_dir"
          target="$cache_dir/$id.png"
          if [[ ! -f "$target" ]]; then
            temporary="$target.tmp.$$"
            trap 'rm -f -- "$temporary"' EXIT
            cliphist decode "$id" \
              | magick - -auto-orient -thumbnail '192x128>' -strip "png:$temporary"
            mv -- "$temporary" "$target"
            trap - EXIT
          fi
          printf '%s\n' "$target"
          ;;
        *)
          echo "usage: launcher-clipboard list|copy ID|thumbnail ID" >&2
          exit 2
          ;;
      esac
    '';
  };
  timerHelper = pkgs.writeTextFile {
    name = "quickshell-timer";
    executable = true;
    destination = "/bin/quickshell-timer";
    text = builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${pkgs.python3}/bin/python3" ] (
      builtins.readFile ./timer-backend.py
    );
  };

  notionTodoHelper = pkgs.writeTextFile {
    name = "notion-todos";
    executable = true;
    destination = "/bin/notion-todos";
    text =
      builtins.replaceStrings
        [
          "#!/usr/bin/env python3"
          "/run/secrets/notion-todos"
          "@notion-todos-assignee-id@"
        ]
        [
          "#!${pkgs.python3}/bin/python3"
          config.sops.secrets.notion-todos.path
          notionTodoAssigneeId
        ]
        (builtins.readFile ./notion-todos.py);
  };

  launcherAiConfig = pkgs.writeText "launcher-ai-config.yml" ''
    advisor:
      enabled: false
  '';

  launcherAi = pkgs.writeShellApplication {
    name = "launcher-ai";
    text = ''
      state_dir=${lib.escapeShellArg "${config.xdg.stateHome}/quickshell-ai"}
      omp=${lib.escapeShellArg (lib.getExe config.programs.omp.package)}
      uwsm=${lib.escapeShellArg (lib.getExe pkgs.uwsm)}
      ghostty=${lib.escapeShellArg (lib.getExe pkgs.ghostty)}
      env=${lib.escapeShellArg (lib.getExe' pkgs.coreutils "env")}

      mkdir -p -- "$state_dir"
      case "''${1:-}" in
        ask)
          question="''${2:?question is required}"
          exec "$omp" \
            --mode json \
            --thinking low \
            --no-tools \
            --config ${lib.escapeShellArg launcherAiConfig} \
            --no-rules \
            --no-skills \
            --no-extensions \
            --no-title \
            --max-time 45 \
            --session-dir "$state_dir" \
            --cwd ${lib.escapeShellArg config.home.homeDirectory} \
            --allow-home \
            --system-prompt ${lib.escapeShellArg "You are a concise general-purpose assistant. Answer the user's question directly in plain text. Use short paragraphs or bullets when helpful."} \
            -p -- "$question" </dev/null
          ;;
        resume)
          session="''${2:?session id is required}"
          exec "$env" \
            -u HERDR_ENV \
            -u HERDR_SOCKET_PATH \
            -u HERDR_WORKSPACE_ID \
            -u HERDR_TAB_ID \
            -u HERDR_PANE_ID \
            "$uwsm" app -- "$ghostty" -e "$omp" \
              --session-dir "$state_dir" \
              --cwd ${lib.escapeShellArg config.home.homeDirectory} \
              --allow-home \
              --resume "$session"
          ;;
        *)
          echo "usage: launcher-ai ask QUESTION|resume SESSION_ID" >&2
          exit 2
          ;;
      esac
    '';
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
  launcherData = pkgs.replaceVars ./LauncherData.qml {
    camera = "/run/current-system/sw/bin/unifi-cam";
    clipboardHelper = lib.getExe launcherClipboard;
    herdr = lib.getExe herdrPackage;
    herdrView = "${config.home.profileDirectory}/bin/herdr-view";
    launcherAi = lib.getExe launcherAi;
  };
  timerService = pkgs.replaceVars ./TimerService.qml {
    timerHelper = lib.getExe timerHelper;
    notifySend = lib.getExe pkgs.libnotify;
    pwPlay = lib.getExe' pkgs.pipewire "pw-play";
    timerSound = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga";
  };
  timerPopup = pkgs.replaceVars ./TimerPopup.qml (
    (builtins.removeAttrs themeVars [ "cardSurface" ])
    // {
      opaqueSurface = "#181825";
    }
  );
  todoService = pkgs.replaceVars ./TodoService.qml {
    todoHelper = lib.getExe notionTodoHelper;
    xdgOpen = lib.getExe' pkgs.xdg-utils "xdg-open";
  };
  todoPanel = pkgs.replaceVars ./TodoPanel.qml (
    (builtins.removeAttrs themeVars [ "cardSurface" ])
    // {
      primaryOutput = cfg.primaryOutput;
    }
  );
  todoManager = pkgs.replaceVars ./TodoManager.qml (
    themeVars
    // {
      todoHelper = lib.getExe notionTodoHelper;
      xdgOpen = lib.getExe' pkgs.xdg-utils "xdg-open";
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

    sops.secrets.notion-todos = {
      sopsFile = ../../../secrets/notion/todos.json;
      format = "binary";
      mode = "0400";
    };

    home.packages = [
      pkgs.quickshell
      timerHelper
      notionTodoHelper
    ];

    xdg.configFile = {
      "quickshell/tom-bar/shell.qml".source = shell;
      "quickshell/tom-bar/Launcher.qml".source = launcher;
      "quickshell/tom-bar/LauncherData.qml".source = launcherData;
      "quickshell/tom-bar/NotificationCard.qml".source = notificationCard;
      "quickshell/tom-bar/Notifications.qml".source = notifications;
      "quickshell/tom-bar/TimerService.qml".source = timerService;
      "quickshell/tom-bar/TimerPopup.qml".source = timerPopup;
      "quickshell/tom-bar/TodoService.qml".source = todoService;
      "quickshell/tom-bar/TodoPanel.qml".source = todoPanel;
      "quickshell/tom-bar/TodoManager.qml".source = todoManager;
    };

    systemd.user.services.quickshell-bar = {
      Unit = {
        Description = "Quickshell desktop bar";
        Wants = [ "sops-nix.service" ];
        After = [ "sops-nix.service" ];
      };
      Service = {
        ExecStart = "${pkgs.quickshell}/bin/qs -c tom-bar";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };
  };
}
