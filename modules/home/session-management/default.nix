{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  continuumPlugin = pkgs.tmuxPlugins.continuum;
  mux = pkgs.writeShellApplication {
    name = "mux";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      session="''${1:-main}"

      case "$session" in
        list|ls)
          exec tmux list-sessions
          ;;
      esac

      if [[ ! "$session" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "usage: mux [SESSION|list]" >&2
        echo "session names may contain letters, numbers, dots, dashes, and underscores" >&2
        exit 2
      fi

      if [[ -n "''${TMUX:-}" ]]; then
        if ! tmux has-session -t "=$session" 2>/dev/null; then
          tmux new-session -d -s "$session"
        fi
        exec tmux switch-client -t "=$session"
      fi

      exec tmux new-session -A -s "$session"
    '';
  };
  # Herdr focus is session-global: every full client attached to a session
  # renders the same workspace, so a second Ghostty window running plain
  # `herdr` only mirrors the first (confirmed for 0.8.2; the changelog calls
  # per-client independent navigation "not yet" supported). Direct terminal
  # attach is the only way to view one server-owned pane of the same session
  # independently; this opens a new Ghostty window doing exactly that. With
  # no argument it offers a wofi picker over every pane in the session.
  #
  # The HERDR_* variables are unset inside the new window so the attach runs
  # as a fresh client instead of inheriting this pane's nested-launch guard.
  herdrView = pkgs.writeShellApplication {
    name = "herdr-view";
    runtimeInputs = [ pkgs.jq ] ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.util-linux;
    text = ''
      herdr=${lib.getExe herdrPackage}

      panes() {
        "$herdr" api snapshot | jq -r '
          .result.snapshot as $s
          | ($s.workspaces | map({key: .workspace_id, value: .label}) | from_entries) as $ws
          | $s.panes[]
          | [.pane_id, ($ws[.workspace_id] // .workspace_id), .agent // "-", .terminal_title_stripped // ""]
          | @tsv'
      }

      if [[ $# -eq 0 && -n "''${WAYLAND_DISPLAY:-}" ]] && command -v wofi >/dev/null 2>&1; then
        choice=$(panes | wofi --dmenu --prompt "herdr pane" || true)
        [[ -n "$choice" ]] || exit 0
        set -- "''${choice%%''$'\t'*}"
      fi

      if [[ $# -eq 0 || "$1" == list ]]; then
        echo "usage: herdr-view [--takeover] PANE_ID|TERMINAL_ID" >&2
        echo >&2
        echo "panes in the default session:" >&2
        panes >&2
        exit 2
      fi

      extra=()
      if [[ "$1" == --takeover ]]; then
        extra+=(--takeover)
        shift
      fi
      target="''${1:?usage: herdr-view [--takeover] PANE_ID|TERMINAL_ID}"

      # `agent attach` resolves pane targets like w2:p1; `terminal attach`
      # takes raw term_* ids. The agent *type* (e.g. "omp") is not a target.
      subcommand=(agent attach)
      if [[ "$target" == term_* ]]; then
        subcommand=(terminal attach)
      fi

      window=(
        ghostty -e
        env -u HERDR_ENV -u HERDR_SOCKET_PATH
        -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_PANE_ID
        "$herdr" "''${subcommand[@]}" "$target" "''${extra[@]}"
      )

      if command -v uwsm >/dev/null 2>&1 && [[ -n "''${WAYLAND_DISPLAY:-}" ]]; then
        window=(uwsm app -- "''${window[@]}")
      fi
      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        # setsid (pinned util-linux) detaches the window from this pane so the
        # launcher returns immediately and a closed pane never takes the viewer
        # down with it. `uwsm app` alone stays foreground until the window closes.
        exec setsid --fork "''${window[@]}" >/dev/null 2>&1
      ''}
      exec "''${window[@]}"
    '';
  };
in
{
  # Keep tmux and mux installed as a fallback while Herdr is being evaluated.
  home.packages = [
    herdrPackage
    mux
    herdrView
  ];

  # OMP has no reliable screen fallback in Herdr; its lifecycle extension is
  # authoritative for working/idle state and must track the Herdr package.
  # The OMP agent directory is populated by Home Manager's linkGeneration
  # phase. On a fresh host it does not exist at writeBoundary yet, and Herdr
  # deliberately refuses to create an unknown agent directory.
  home.activation.herdrOmpIntegration = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [[ -d "$HOME/.omp/agent" ]]; then
      run ${lib.getExe herdrPackage} integration install omp
    fi
  '';

  # Herdr follows the host terminal's light/dark appearance and sends agent
  # completion notifications through the system notification service.
  #
  # The config file cannot be a read-only store symlink: Herdr writes it itself
  # (onboarding sets `onboarding`, and `herdr config reset-keys` rewrites the
  # whole file). Reconcile only repo-owned keys in place and leave everything
  # else untouched. `[theme.custom]` remains unused because its overrides apply
  # across both light and dark flavors.
  home.activation.herdrConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 ${./herdr-theme.py} \
      "''${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"
  '';

  programs.tmux = {
    enable = true;
    sensibleOnTop = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 10;
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    shell = "/etc/profiles/per-user/tom/bin/bash";
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuumPlugin;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];

    extraConfig = ''
      # Clear stale namespace wrappers retained by long-running tmux servers.
      set -g default-command ""

      # Keep window numbering compact and preserve true-colour applications.
      set -g renumber-windows on
      set -g set-clipboard on
      set -g extended-keys on
      set -as terminal-features ',xterm-ghostty:RGB'

      # Use process-aware tmux names, then pass the active one through to
      # Ghostty's native window title. Idle shells show their working directory;
      # full-screen applications may provide a more useful pane title.
      set -wg allow-rename off
      set -wg allow-set-title on
      set -wg automatic-rename on
      set -wg automatic-rename-format '#{?pane_in_mode,[tmux],#{?#{==:#{pane_current_command},bash},#{b:pane_current_path},#{?#{==:#{s/ *$//:pane_title},},#{pane_current_command},#{s/ *$//:pane_title}}}}#{?pane_dead,[dead],}'
      set -g set-titles on
      set -g set-titles-string '#{?#{==:#S,main},,#S · }#W'

      # A quiet, palette-driven status line: session at the left, windows in the
      # centre, and only useful context at the right. ANSI palette slots come
      # from Stylix, so this follows the Ghostty theme without hard-coded colors.
      set -g status-position bottom
      set -g status-interval 5
      set -g status-justify absolute-centre
      set -g status-style 'bg=default,fg=colour7'
      set -g status-left-length 30
      set -g status-left '#[fg=colour4,bold] 󰆍 #S #[fg=colour8,nobold]│'
      set -g status-right-length 80
      set -g status-right '#(${continuumPlugin}/share/tmux-plugins/continuum/scripts/continuum_save.sh)#[fg=colour0,bg=colour3,bold]#{?client_prefix, PREFIX ,}#[fg=colour8,bg=default,nobold]#{?window_zoomed_flag,󰊓  ,}󰉋 #{b:pane_current_path}  #[fg=colour4]󰥔 #[fg=colour7]%H:%M '
      set -wg window-status-separator ""
      set -wg window-status-format '#[fg=colour8] #I #[fg=colour7]#W#[fg=colour3]#{?window_bell_flag, 󰂞,}#[fg=colour4]#{?window_activity_flag, •,} '
      set -wg window-status-current-format '#[fg=colour4,bg=default]#[fg=colour0,bg=colour4,bold] #I #W#{?window_zoomed_flag, 󰊓,} #[fg=colour4,bg=default,nobold]'
    '';
  };

  # Herdr owns workspaces and process lifetime; Ghostty is only the renderer.
  # tmux remains available through `mux` during the experiment. Extra windows
  # onto the same session go through `herdr-view` (see above); plain windows
  # mirror by design.
  programs.ghostty = {
    enable = true;
    package = null;
    systemd.enable = false;
    enableBashIntegration = true;
    settings.command = lib.getExe herdrPackage;
  };
}
