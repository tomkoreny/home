{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,
  # Additional metadata is provided by Snowfall Lib.
  namespace, # The namespace used for your flake, defaulting to "internal" if not set.
  # All other arguments come from the system system.
  config,
  ...
}:
let
  dagLib =
    if config ? lib && config.lib ? dag then
      config.lib.dag
    else if lib ? hm then
      lib.hm.dag
    else
      throw "home shell module: unable to locate DAG helpers (expected config.lib.dag or lib.hm.dag).";
in
{
  home.sessionVariables.PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/pnpm"
    "${config.home.homeDirectory}/.local/share/pnpm/bin"
  ];

  home.shellAliases = {
    v = "nvim";
    #    ssh = "kitten ssh";
    vi = "nvim";
    conf = "nvim ~/nixos2";
    sw = if pkgs.stdenv.isDarwin then "nh darwin switch" else "nh os switch";
    dcu = "docker compose up -d";
    dcd = "docker compose down";
    dc = "docker compose";
    dev = "npm run dev";
    start = "npm run start";
  };
  home.packages = [
    (pkgs.writeShellScriptBin "sw" ''
      set -euo pipefail

      case "$(uname -s)" in
        Darwin)
          target="darwin"
          ;;
        *)
          target="os"
          ;;
      esac

      exec ${lib.getExe pkgs.nh} "$target" switch "$@"
    '')
  ];
  home.activation.ensurePiCodingAgent = lib.mkIf pkgs.stdenv.isLinux (
    dagLib.entryAfter [ "writeBoundary" ] ''
      set -eu

      export HOME=${lib.escapeShellArg config.home.homeDirectory}
      export PNPM_HOME="$HOME/.local/share/pnpm"
      export PATH="$PNPM_HOME:$PNPM_HOME/bin:${
        lib.makeBinPath [
          pkgs.nodejs_22
          pkgs.pnpm
        ]
      }:$PATH"

      mkdir -p "$PNPM_HOME" "$PNPM_HOME/bin"

      if [ ! -x "$PNPM_HOME/pi" ] && [ ! -x "$PNPM_HOME/bin/pi" ]; then
        ${lib.getExe pkgs.pnpm} add -g @mariozechner/pi-coding-agent@latest
      fi
    ''
  );
  programs.bash.enable = true;
  programs.bash.initExtra = lib.mkAfter ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    case ":$PATH:" in
      *":$PNPM_HOME/bin:"*) ;;
      *) export PATH="$PNPM_HOME/bin:$PATH" ;;
    esac
    case ":$PATH:" in
      *":$PNPM_HOME:"*) ;;
      *) export PATH="$PNPM_HOME:$PATH" ;;
    esac

    ksecret() {
      if [ -z "$1" ]; then
        echo "usage: ksecret <cluster>" >&2
        return 1
      fi

      local secrets_dir="$HOME/nixos2/secrets/kubeconfig"
      local secret_file="$secrets_dir/$1.json"

      if [ ! -f "$secret_file" ]; then
        echo "secret file not found: $secret_file" >&2
        return 1
      fi

      SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
        ${pkgs.sops}/bin/sops "$secret_file"
    }
  '';
  programs.starship.enable = true;
}
