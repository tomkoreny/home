{
  lib,
  pkgs,
  config,
  ...
}:
{
  home.sessionVariables.PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/pnpm"
    "${config.home.homeDirectory}/.local/share/pnpm/bin"
  ];

  home.shellAliases = {
    v = "nvim";
    vi = "nvim";
    conf = "nvim ~/nixos2";
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
          exec ${lib.getExe pkgs.nh} darwin switch --diff never "$@"
          ;;
        *)
          # Not nh here: nh wraps its elevated calls as `sudo env ... <cmd>`,
          # which cannot be matched by the restricted NOPASSWD sudoers rule
          # (see systems/x86_64-linux/nixos/default.nix). nixos-rebuild is
          # allowlisted and needs no env wrapper.
          exec sudo /run/current-system/sw/bin/nixos-rebuild switch \
            --flake /home/tom/nixos2#nixos "$@"
          ;;
      esac
    '')
  ];
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
