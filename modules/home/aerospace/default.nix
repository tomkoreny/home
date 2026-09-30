{
  config,
  lib,
  pkgs,
  ...
}:
# AeroSpace tiling on macOS, bound to mirror the Hyprland keys in
# modules/home/hyprland. Super becomes Caps Lock: Karabiner-Elements (cask in
# systems/aarch64-darwin/macos) turns a held Caps Lock into Ctrl+Alt+Cmd, which
# leaves Shift free for the "move" variants exactly like Super+Shift on Linux.
let
  cfg = config.tomkoreny.aerospace;
  aerospace = pkgs.aerospace;
  tomlFormat = pkgs.formats.toml { };
  mod = "ctrl-alt-cmd";
  bin = "${config.home.profileDirectory}/bin";
  withBar = config.tomkoreny.sketchybar.enable;
  # Workspace strip refresh for the SketchyBar module; moves do not change the
  # focused workspace, so exec-on-workspace-change alone misses them.
  notifyBar = lib.optional withBar "exec-and-forget sketchybar --trigger aerospace_workspace_change";

  workspaces = map toString (lib.range 1 10);
  # Keys 1..9 and 0 select workspaces 1..10, like the Hyprland loop.
  workspaceKey = name: if name == "10" then "0" else name;

  # Ghostty 1.2 on macOS has neither `+new-window` nor an AppleScript
  # dictionary. Opening a folder with the running app opens a new window
  # there; a Cmd-N keystroke would need Accessibility and Automation grants
  # for AeroSpace on top.
  newTerminal = pkgs.writeShellScript "aerospace-new-terminal" ''
    if /usr/bin/pgrep -xq ghostty; then
      exec /usr/bin/open -a Ghostty "$HOME"
    fi
    exec /usr/bin/open -a Ghostty
  '';

  karabinerConfig = {
    global.show_in_menu_bar = false;
    profiles = [
      {
        name = "Default";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        complex_modifications.rules = [
          {
            description = "Caps Lock held acts as Ctrl+Alt+Cmd (AeroSpace modifier)";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "caps_lock";
                  modifiers.optional = [ "any" ];
                };
                to = [
                  {
                    key_code = "left_control";
                    modifiers = [
                      "left_option"
                      "left_command"
                    ];
                  }
                ];
              }
            ];
          }
        ];
      }
    ];
  };
in
{
  options.tomkoreny.aerospace = {
    enable = lib.mkEnableOption "AeroSpace tiling with a Caps Lock modifier on macOS";
    parkedMonitors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "WaveShsare" ];
      description = ''
        Monitor name patterns (AeroSpace monitor-pattern regexes) that only
        exist to host a BetterDisplay stream of a virtual screen. They keep the
        parking workspace P so numbered workspaces, and the windows moved to
        them, never land on a display nobody can see.
      '';
    };
    workspaceMonitors = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        "6" = [
          "WSMirror"
          "built-in"
        ];
      };
      description = ''
        Workspace to monitor-pattern assignments (first matching pattern wins),
        like Hyprland's fixed workspace columns. Unlisted workspaces follow
        AeroSpace's default and live on the main monitor.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "tomkoreny.aerospace is macOS-only.";
      }
    ];

    xdg.configFile."karabiner/karabiner.json".text = builtins.toJSON karabinerConfig;

    # AeroSpace tiles and closes windows from the keyboard, so Ghostty's
    # titlebar (and its traffic lights) is dead chrome. Windows can still be
    # dragged with Option+click on the frame. Applies to windows opened after
    # Ghostty reloads its config.
    programs.ghostty.settings.macos-titlebar-style = "hidden";

    # Not Home Manager's programs.aerospace: it always writes
    # after-login-command, which AeroSpace flags as deprecated since 0.19.
    home.packages = [ aerospace ];

    launchd.agents.aerospace = {
      enable = true;
      config = {
        Program = "${aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/aerospace.log";
      };
    };

    xdg.configFile."aerospace/aerospace.toml" = {
      onChange = ''
        if ${lib.getExe aerospace} list-modes --current >/dev/null 2>&1; then
          ${lib.getExe aerospace} reload-config
        fi
      '';
      source = tomlFormat.generate "aerospace.toml" {
        # launchd starts AeroSpace; its own login item would start a second copy.
        start-at-login = false;
        config-version = 2;
        # Closest to Hyprland's dwindle-style default.
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";
        on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

        # Every workspace gets a home so a reload or monitor change never
        # parks a numbered workspace on a display that is only a stream target.
        workspace-to-monitor-force-assignment =
          cfg.workspaceMonitors // lib.optionalAttrs (cfg.parkedMonitors != [ ]) { P = cfg.parkedMonitors; };

        # AeroSpace has no smart gaps (gaps cannot depend on the window
        # count), so outer gaps are 0 and a lone window fills the area below
        # the bar edge to edge, like Hyprland's single-window rule. Several
        # windows keep a 4pt gap between them (Hyprland gaps_in 2 per side).
        # The top gap counts from the usable area, which on the notched
        # built-in display starts 32pt down (measured) under a 38pt bar. The
        # SketchyBar module shows the bar on the main display only, so other
        # displays get no top gap.
        gaps = {
          inner.horizontal = 4;
          inner.vertical = 4;
          outer = {
            left = 0;
            right = 0;
            bottom = 0;
            top = [
              { monitor."built-in" = 6; }
              0
            ];
          };
        };

        # launchd starts AeroSpace with a bare PATH; bindings call Nix tools.
        exec.env-vars.PATH = "${bin}:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";

        exec-on-workspace-change = lib.optionals withBar [
          "/bin/bash"
          "-c"
          "sketchybar --trigger aerospace_workspace_change"
        ];
        on-focus-changed = notifyBar;

        mode.main.binding = {
          "${mod}-q" = "exec-and-forget ${newTerminal}";
          "${mod}-c" = [ "close" ] ++ notifyBar;
          "${mod}-e" = "exec-and-forget open ~";
          # Chromium hands --new-window to the running instance.
          "${mod}-b" = "exec-and-forget /Applications/Helium.app/Contents/MacOS/Helium --new-window";
          "${mod}-v" = [ "layout floating tiling" ] ++ notifyBar;
          "${mod}-j" = "layout tiles horizontal vertical";
          "${mod}-f" = "fullscreen";
          "${mod}-l" = "exec-and-forget pmset displaysleepnow";

          # Left/right cross to the neighbouring monitor at the edge, like
          # Hyprland's movefocus/movewindow. Up/down stay inside the workspace
          # so a parked monitor sitting below is never a target. `move` refuses
          # floating windows, so those fall back to move-node-to-monitor.
          "${mod}-left" = "focus --boundaries all-monitors-outer-frame left";
          "${mod}-right" = "focus --boundaries all-monitors-outer-frame right";
          "${mod}-up" = "focus up";
          "${mod}-down" = "focus down";
          "${mod}-shift-left" = [
            "move --boundaries all-monitors-outer-frame left || move-node-to-monitor --focus-follows-window left"
          ]
          ++ notifyBar;
          "${mod}-shift-right" = [
            "move --boundaries all-monitors-outer-frame right || move-node-to-monitor --focus-follows-window right"
          ]
          ++ notifyBar;
          "${mod}-shift-up" = "move up";
          "${mod}-shift-down" = "move down";

          # Hyprland's special "magic" workspace becomes workspace S.
          "${mod}-s" = "workspace S";
          "${mod}-shift-s" = [ "move-node-to-workspace S" ] ++ notifyBar;
        }
        // lib.optionalAttrs withBar {
          # Bar popups standing in for the Quickshell launcher/manager binds.
          "${mod}-h" = "exec-and-forget sketchybar-widgets herdr click";
          "${mod}-t" = "exec-and-forget sketchybar-widgets todos click";
          "${mod}-shift-t" = "exec-and-forget sketchybar-widgets todos new";
        }
        // lib.optionalAttrs (withBar && config.tomkoreny.bar-backends.workTasks.enable) {
          "${mod}-w" = "exec-and-forget sketchybar-widgets work click";
        }
        // lib.listToAttrs (
          lib.concatMap (name: [
            (lib.nameValuePair "${mod}-${workspaceKey name}" "workspace ${name}")
            (lib.nameValuePair "${mod}-shift-${workspaceKey name}" (
              [ "move-node-to-workspace ${name}" ] ++ notifyBar
            ))
          ]) workspaces
        );
      };
    };
  };
}
