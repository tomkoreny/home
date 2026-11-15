{
  lib,
  pkgs,
  config,
  ...
}:
let
  # `conf` and `ksecret` act on Tom's flake checkout. Its per-platform path
  # is defined once, as programs.nh.flake in modules/home/nh.
  isTom = config.home.username == "tom";
  flakeCheckout = config.programs.nh.flake;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  npmPrefix = "${config.home.homeDirectory}/.local/share/npm";
in
{
  home.sessionVariables.PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
  # Where `npm install -g` puts packages. The node in the Nix profile has the
  # read-only store for its prefix, so global installs need one of their own.
  home.sessionVariables.NPM_CONFIG_PREFIX = npmPrefix;
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/pnpm"
    "${config.home.homeDirectory}/.local/share/pnpm/bin"
    "${npmPrefix}/bin"
  ];
  # A login shell that is not interactive leaves ~/.bashrc at its first line,
  # so the Mac's PATH is put in order here for those, and again at the end of
  # ~/.bashrc for interactive shells, after everything there that prepends.
  programs.bash.profileExtra = lib.mkIf isDarwin ''
    . ${./path-order.sh}
    standard_path
  '';

  home.shellAliases = {
    v = "nvim";
    vi = "nvim";
    conf = lib.mkIf isTom "nvim ${flakeCheckout}";
    dcu = "docker compose up -d";
    dcd = "docker compose down";
    dc = "docker compose";
    dev = "npm run dev";
    start = "npm run start";
  };
  xdg.configFile."nix/nix.conf".text = ''
    !include ${config.home.homeDirectory}/.config/nix/access-tokens.conf
  '';
  home.packages = [
    (pkgs.writeShellScriptBin "sw" ''
      set -euo pipefail

      case "$(uname -s)" in
        Darwin)
          exec ${lib.getExe pkgs.nh} darwin switch --diff never "$@"
          ;;
        *)
          exec ${lib.getExe pkgs.nh} os switch --diff never "$@"
          ;;
      esac
    '')
    (pkgs.writeShellScriptBin "nix-github-token-refresh" ''
      set -euo pipefail

      token_file="$HOME/.config/nix/access-tokens.conf"
      token=""

      if [ -n "''${GITHUB_TOKEN:-}" ]; then
        token="$GITHUB_TOKEN"
      elif [ -n "''${GH_TOKEN:-}" ]; then
        token="$GH_TOKEN"
      elif command -v gh >/dev/null 2>&1; then
        token="$(gh auth token 2>/dev/null || true)"
      fi

      if [ -z "$token" ]; then
        echo "error: set GITHUB_TOKEN/GH_TOKEN or run: gh auth login" >&2
        exit 1
      fi

      mkdir -p "$(dirname "$token_file")"
      (umask 077 && printf 'access-tokens = github.com=%s\n' "$token" > "$token_file")
      echo "wrote $token_file"
    '')
  ];
  programs.bash.enable = true;
  programs.bash.initExtra = lib.mkAfter ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"
    case ":$PATH:" in
      *":$PNPM_HOME/bin:"*) ;;
      *) export PATH="$PNPM_HOME/bin:$PATH" ;;
    esac
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac
    case ":$PATH:" in
      *":$NPM_CONFIG_PREFIX/bin:"*) ;;
      *) export PATH="$NPM_CONFIG_PREFIX/bin:$PATH" ;;
    esac
    ${lib.optionalString isDarwin ''
      # One order for PATH, whichever way this shell was started: Nix
      # profiles, own tools, Homebrew, system. See path-order.sh.
      . ${./path-order.sh}
      standard_path
    ''}

    # Rex puts its `rex` CLI first on PATH when it opens a terminal, but
    # nix-darwin and NixOS reset PATH to a fixed list in every interactive
    # shell. Put it back in front so `rex` matches the running server. Rex's
    # docs advise against home.sessionPath: outside Rex the variable is empty.
    if [ -n "''${REX_BIN_DIR:-}" ]; then
      export PATH="$REX_BIN_DIR:$PATH"
    fi

    ${lib.optionalString isTom ''
      ksecret() {
        if [ -z "$1" ]; then
          echo "usage: ksecret <cluster>" >&2
          return 1
        fi

        local secrets_dir="${flakeCheckout}/secrets/kubeconfig"
        local secret_file="$secrets_dir/$1.json"

        if [ ! -f "$secret_file" ]; then
          echo "secret file not found: $secret_file" >&2
          return 1
        fi

        SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
          ${pkgs.sops}/bin/sops "$secret_file"
      }
    ''}
  '';
  programs.starship.enable = true;
}
