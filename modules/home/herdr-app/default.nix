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
#   commands in the / menu, a status line with the model and thinking level,
#   and a card with its to-do list and running subagents above the reply box.
#   Its OMP extension, linked into ~/.omp/agent/extensions, keeps what the
#   agent is doing right now beside the session's log, which the chat shows
#   under its working spark; OMP loads it when a session starts.
# - OMP's entry in programs.json, so OMP is in the app's + menu with its own
#   mark (omp-icon.svg, tinted like the app's other agents). Upstream's table of
#   agents does not list it (herdrdev/herdr-app#730).
# - omp-resume.py, a user service (a launchd agent on macOS). After a reboot
#   herdr-core brings each terminal back as a plain shell; the service types
#   `omp --resume` with the session that ran there. Its docstring has the rules.
#
# The rest of the system's look: themes/stylix.json and stylix-light.json are
# the Ghostty themes Stylix and modules/home/stylix define (the terminal colours
# 1:1, the shared accent for the app's panels), and settings.json shows them
# with the system's light or dark mode, with Ghostty's font in the terminals.
#
# The app treats its home, ~/.config/herdr-app, as files it and the user edit.
# A mod linked in from outside the home folder loads but cannot read its own
# files (0.1.15), so herdr-chat cannot be a store symlink: activation copies
# it in whenever the pinned source changes. Edit a clone (the app's Duplicate
# mod), not that copy. Activation also copies the themes and the icon, and
# merges the keys above into settings.json and programs.json, leaving the
# app's and the user's other keys alone. shared.json (which layout is shown)
# is written once and never touched again.
#
# Neither program updates itself from the store: the app reports "a build from
# source" and herdr-core "managed by nix". Their pins follow upstream through
# .github/scripts/bump-pins.py. Usage telemetry is off in settings.json; the
# Linux wrapper says so a second time, which the signed macOS bundle cannot.
#
# On macOS both programs are upstream's signed bundles, unchanged. Herdr.app is
# linked into ~/Applications/Home Manager Apps like the other Nix-built apps;
# what terminal programs may use (microphone, folders) is granted to Herdr
# Core, by its signature, so the grants survive version bumps.
#
# The Mac and the NixOS desktop show each other's spaces: each has the other
# as a machine (Settings > Machines), over the ssh aliases in
# modules/home/ssh. herdr-core keeps a machine in its state, so each was
# added once by hand:
#
#   Mac:    hc machine add nixos-ygg --name nixos
#   NixOS:  hc machine add macos-ygg --name macos
#
# A machine starts the other one's herdr-core whenever it finds none running:
# within a second of a stop, and after a reboot as soon as ssh answers
# (measured, 0.1.21). That is Herdr's own behaviour, kept on purpose: either
# machine is reachable from the other at any time. Two things follow from it.
# A core started that way brings back its kept terminals, and omp-resume.py
# their OMP sessions, before anyone opened Herdr there. And on the Mac such a
# core runs outside the desktop login, where the login keychain refuses and
# no ssh agent is set (measured); `hc --skill` names `hc server restart`, run
# from a terminal on the Mac's desktop, as what moves it into the desktop
# login.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.herdr-app;
  herdrCore = pkgs.callPackage ./core.nix { };
  herdrApp = pkgs.callPackage ./package.nix { };

  seedShared = pkgs.writeText "herdr-app-shared.json" (builtins.toJSON { layout = "herdr-chat"; });
  # Which herdr-chat build the copy in the app's home came from. A file, not a
  # here-string: GNU install refuses to copy from /dev/stdin on macOS.
  chatSource = pkgs.writeText "herdr-chat-source" "${cfg.chatPackage}\n";

  common = import ../../../lib/common { };
  ghostty = config.programs.ghostty;
  hexOf =
    value: "#" + lib.removePrefix "#" (if builtins.isList value then builtins.head value else value);
  # A Ghostty theme as the app's theme file: the terminal colours as they are,
  # and the accent the app's panels and buttons use.
  appTheme =
    name: accent:
    let
      theme = ghostty.themes.${name};
      slot = entry: lib.toInt (builtins.head (lib.splitString "=" entry));
    in
    {
      background = hexOf theme.background;
      foreground = hexOf theme.foreground;
      selection = hexOf theme.selection-background;
      cursor = hexOf theme.cursor-color;
      ansi = map (entry: hexOf (lib.last (lib.splitString "=" entry))) (
        lib.sort (a: b: slot a < slot b) theme.palette
      );
      colors.accent = accent;
    };
  appThemes = {
    stylix = appTheme "stylix" common.stylix.accent;
    stylix-light = appTheme "stylix-light" common.stylix.accentLight;
  };
  ghosttyFont =
    let
      family = ghostty.settings.font-family;
    in
    if builtins.isList family then builtins.head family else family;

  # Keys this module owns in the app's own files, merged in on every activation.
  ownedSettings = {
    theme = {
      light = "stylix-light";
      dark = "stylix";
    };
    font = ghosttyFont;
    telemetry = false;
  };
  ownedPrograms.programs.omp = {
    name = "omp";
    icon = "my-icons/omp.svg";
    tint = true;
    run = [ "omp" ];
    match = [ "oh-my-pi" ];
  };
  # The app's Hermes item opens the homelab Hermes (hermesHomelab), on both
  # machines' menus; it is installed where it can reach the cluster.
  ownedPrograms.programs.hermes = {
    name = "Hermes (homelab)";
    run = [ "hermes-homelab" ];
    match = [ "hermes-homelab" ];
  };

  # The homelab Hermes (homelab-services, apps/services/hermes-agent) in a
  # terminal: its TUI, run in the pod as the `hermes` user, so it shares the
  # gateway, sessions and memory with Telegram and Matrix. Hermes' TUI attaches
  # only to a gateway on its own machine (a loopback WebSocket with a one-time
  # ticket), so it runs there and kubectl carries the terminal. The script stays
  # in front of kubectl rather than exec-ing it, so Herdr names the terminal by
  # this script and shows it as Hermes. Linux only: the desktop reaches the
  # cluster's API (10.11.0.10) and the Mac away from home does not, so the Mac
  # opens Hermes in a NixOS space.
  hermesHomelab = pkgs.writeShellScriptBin "hermes-homelab" ''
    set -euo pipefail
    kubeconfig="''${HERMES_HOMELAB_KUBECONFIG:-$HOME/WebstormProjects/homelab-services/.ai/generated/proxmox-lab/kubeconfig}"
    ${lib.getExe pkgs.kubectl} --kubeconfig "$kubeconfig" -n hermes-agent \
      exec -it deploy/hermes-agent -c hermes-agent -- \
      /command/s6-setuidgid hermes env HERMES_HOME=/opt/data HOME=/opt/data LANG=C.UTF-8 \
      TERM="''${TERM:-xterm-256color}" COLORTERM="''${COLORTERM:-truecolor}" \
      sh -c 'cd /opt/data && exec /opt/hermes/.venv/bin/hermes --tui "$@"' hermes "$@"
  '';
  mergeJson = pkgs.writeShellScript "herdr-app-merge-json" ''
    # Merges the JSON in $2 into the JSON file $1 (created when missing), keeping
    # every other key. A file jq can't read is left alone, with a warning.
    set -uo pipefail
    current=$(cat "$1" 2>/dev/null || echo '{}')
    if merged=$(${lib.getExe pkgs.jq} --argjson owned "$2" '. * $owned' <<< "$current"); then
      printf '%s\n' "$merged" > "$1.tmp" && mv "$1.tmp" "$1"
    else
      echo "herdr-app: $1 is not JSON; left as it is" >&2
    fi
  '';
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
    assertions = lib.mapAttrsToList (name: theme: {
      assertion = builtins.length theme.ansi == 16;
      message = "The Herdr app theme ${name} needs Ghostty's 16 palette colours; it has ${toString (builtins.length theme.ansi)}.";
    }) appThemes;

    home.packages = [
      herdrApp
      herdrCore
      # herdr-chat reads session logs with `python3`: here, and for a space on
      # another machine there, through that machine's herdr-core. So it has to
      # be on the PATH of both, which the login PATH otherwise lacks on NixOS
      # and fills with Xcode's Python 3.9 on macOS.
      pkgs.python3
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux hermesHomelab;

    home.file.".omp/agent/extensions/herdr-chat-live.ts".source =
      "${cfg.chatPackage}/omp/herdr-chat-live.ts";

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
        run install -D -m 644 ${chatSource} "$herdrChatStamp"
      fi
      if [[ ! -e "$herdrAppHome/shared.json" ]]; then
        run install -m 644 ${seedShared} "$herdrAppHome/shared.json"
      fi
      ${lib.concatStrings (
        lib.mapAttrsToList (name: theme: ''
          run install -D -m 644 ${pkgs.writeText "herdr-app-${name}.json" (builtins.toJSON theme)} "$herdrAppHome/themes/${name}.json"
        '') appThemes
      )}
      run install -D -m 644 ${./omp-icon.svg} "$herdrAppHome/my-icons/omp.svg"
      run ${mergeJson} "$herdrAppHome/settings.json" ${lib.escapeShellArg (builtins.toJSON ownedSettings)}
      run ${mergeJson} "$herdrAppHome/programs.json" ${lib.escapeShellArg (builtins.toJSON ownedPrograms)}
    '';

    systemd.user.services.herdr-omp-resume = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit.Description = "Reopen OMP sessions in Herdr app terminals after herdr-core loses them";
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./omp-resume.py} ${lib.getExe herdrCore}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.herdr-omp-resume = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.python3}/bin/python3"
          "${./omp-resume.py}"
          (lib.getExe herdrCore)
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-omp-resume.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-omp-resume.log";
      };
    };
  };
}
