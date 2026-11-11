# The Herdr app (github.com/herdrdev/herdr-app): the native desktop app of the
# Herdr project, set up here as a graphical front end for OMP.
#
# It is a separate program from the Herdr TUI in modules/home/session-management.
# Its terminals run in herdr-core (`hc`), a different server, so nothing that
# runs in one shows up in the other.
#
# OMP runs in it as its ordinary TUI in a terminal, and reports its own status
# to the sidebar. Three pieces make that graphical and durable:
#
# - herdr-chat (chat.nix), a layout and mod that swaps an agent's terminal for
#   a chat view read from the agent's session log, with a Chat | Terminal
#   toggle. It comes from Tom's fork, which adds OMP: its chat, its slash
#   commands in the / menu, and a status line with the model and thinking level.
# - A seeded programs.json entry, so OMP is in the app's + menu. Upstream's
#   table of agents does not list it (herdrdev/herdr-app#730).
# - omp-resume.py, a user service. After a reboot herdr-core brings each
#   terminal back as a plain shell; the service types `omp --resume` with the
#   session that ran there. Its docstring has the rules.
#
# The app treats its home, ~/.config/herdr-app, as files it and the user edit.
# A mod linked in from outside the home folder loads but cannot read its own
# files (0.1.15), so herdr-chat cannot be a store symlink: activation copies
# it in whenever the pinned source changes. Edit a clone (the app's Duplicate
# mod), not that copy. shared.json (which layout is shown) and programs.json
# are written once and never touched again.
#
# Neither program updates itself from the store: the app reports "a build from
# source" and herdr-core "managed by nix". Their pins follow upstream through
# .github/scripts/bump-pins.py. The wrapper turns the app's usage telemetry off.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.herdr-app;
  herdrCore = pkgs.callPackage ./core.nix { };
  # herdr-chat reads session logs with python3, which the login PATH lacks.
  herdrApp = pkgs.callPackage ./package.nix { extraPath = [ pkgs.python3 ]; };

  seedShared = pkgs.writeText "herdr-app-shared.json" (builtins.toJSON { layout = "herdr-chat"; });
  seedPrograms = pkgs.writeText "herdr-app-programs.json" (
    builtins.toJSON {
      programs.omp = {
        name = "omp";
        # The app's own generic agent mark; an entry without one shows none.
        icon = "icons/agent.svg";
        tint = true;
        run = [ "omp" ];
        match = [ "oh-my-pi" ];
      };
    }
  );
in
{
  options.tomkoreny.herdr-app = {
    enable = lib.mkEnableOption "the Herdr desktop app with a chat view for OMP";

    chatPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./chat.nix { herdr-app = herdrApp; };
      defaultText = lib.literalExpression "pkgs.callPackage ./chat.nix { }";
      description = "The herdr-chat layout and mod copied into the app's home. Building it loads the mod in the packaged app.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The Herdr app module packages only the x86_64 Linux releases.";
      }
    ];

    home.packages = [
      herdrApp
      herdrCore
    ];

    home.activation.herdrAppHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      herdrAppHome=${lib.escapeShellArg "${config.xdg.configHome}/herdr-app"}
      herdrChatStamp=${lib.escapeShellArg "${config.xdg.stateHome}/herdr-app/chat-source"}
      if [[ ! -d "$herdrAppHome/mods/herdr-chat" || ! -f "$herdrAppHome/layouts/herdr-chat.json" \
        || "$(cat "$herdrChatStamp" 2>/dev/null)" != ${cfg.chatPackage} ]]; then
        run mkdir -p "$herdrAppHome/mods" "$herdrAppHome/layouts"
        run rm -rf "$herdrAppHome/mods/herdr-chat"
        run cp -r ${cfg.chatPackage}/mods/herdr-chat "$herdrAppHome/mods/herdr-chat"
        run chmod -R u+w "$herdrAppHome/mods/herdr-chat"
        run install -m 644 ${cfg.chatPackage}/layouts/herdr-chat.json "$herdrAppHome/layouts/herdr-chat.json"
        run install -D -m 644 /dev/stdin "$herdrChatStamp" <<< ${cfg.chatPackage}
      fi
      if [[ ! -e "$herdrAppHome/shared.json" ]]; then
        run install -m 644 ${seedShared} "$herdrAppHome/shared.json"
      fi
      if [[ ! -e "$herdrAppHome/programs.json" ]]; then
        run install -m 644 ${seedPrograms} "$herdrAppHome/programs.json"
      fi
    '';

    systemd.user.services.herdr-omp-resume = {
      Unit.Description = "Reopen OMP sessions in Herdr app terminals after herdr-core loses them";
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./omp-resume.py} ${lib.getExe herdrCore}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
