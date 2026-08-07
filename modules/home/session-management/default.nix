{
  lib,
  pkgs,
  ...
}:
let
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
  home.packages = [ mux ];

  programs.tmux = {
    enable = true;
    sensibleOnTop = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 10;
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];

    extraConfig = ''
      # Keep window numbering compact and preserve true-colour applications.
      set -g renumber-windows on
      set -g set-clipboard on
      set -g extended-keys on
      set -as terminal-features ',xterm-ghostty:RGB'
    '';
  };

  # Ghostty is only the renderer; tmux owns windows and process lifetime.
  # The package itself is installed by modules/home/packages.
  programs.ghostty = {
    enable = true;
    package = null;
    systemd.enable = false;
    enableBashIntegration = true;
    settings.command = lib.getExe mux;
  };
}
