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
in
{
  # Keep tmux and mux installed as a fallback while Herdr is being evaluated.
  home.packages = [
    herdrPackage
    mux
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

  # Herdr follows the host terminal's light/dark appearance when `auto_switch`
  # is on, and ships both Catppuccin flavors, so its chrome tracks Ghostty
  # instead of staying dark on a Latte background.
  #
  # The config file cannot be a read-only store symlink: Herdr writes it itself
  # (onboarding sets `onboarding`, `herdr config reset-keys` rewrites the whole
  # file). This reconciles only the [theme] keys in place and leaves the rest of
  # the file untouched.
  #
  # `[theme.custom]` is deliberately not used: its overrides apply on top of
  # whichever flavor is active, so the shared accent could only be correct in one
  # of the two modes. Each flavor keeps its own Catppuccin blue.
  home.activation.herdrTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
  # tmux remains available through `mux` during the experiment.
  programs.ghostty = {
    enable = true;
    package = null;
    systemd.enable = false;
    enableBashIntegration = true;
    settings.command = lib.getExe herdrPackage;
  };
}
