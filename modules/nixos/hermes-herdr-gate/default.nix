# Lets the Hermes agent (homelab cluster) drive this host's herdr agents over
# SSH, so Tom can list, prompt and answer his OMP agents from Matrix.
#
# The key is pinned to a forced command (gate.py): no shell, no forwarding,
# only an allowlist of herdr subcommands, each call logged to
# ~/.local/state/herdr-hermes-gate/log.jsonl. Like the Authentik RAC key, it
# is accepted only from the Talos node addresses that cluster pods leave from.
# Prompting an OMP agent still means that agent can run anything as Tom; the
# gate limits what Hermes can do directly, not what OMP does.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.hermes-herdr-gate;
  common = import ../../../lib/common { };

  # Same herdr the Home Manager session-management module installs.
  herdr = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  gate = pkgs.writers.writePython3Bin "herdr-hermes-gate" {
    flakeIgnore = [ "E501" ];
  } (builtins.replaceStrings [ "@herdr@" ] [ herdr ] (builtins.readFile ./gate.py));
in
{
  options.tomkoreny.nixos.hermes-herdr-gate = {
    enable = lib.mkEnableOption "Hermes access to herdr through an SSH forced command";

    user = lib.mkOption {
      type = lib.types.str;
      default = common.user.name;
      description = "Account whose herdr server Hermes drives.";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbRxH2iE1f/bYZWu8EBMDOlafnX3cznjY02GMYNega8 hermes-herdr@proxmox-lab";
      description = "Hermes' key; the private half is ~/.ssh/id_ed25519_herdr_hermes in the Hermes sandbox home.";
    };

    fromAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.11.0.10"
        "10.11.0.11"
      ];
      description = "Source addresses the key is accepted from (Talos nodes).";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user}.openssh.authorizedKeys.keys = [
      ''from="${lib.concatStringsSep "," cfg.fromAddresses}",restrict,command="${gate}/bin/herdr-hermes-gate" ${cfg.publicKey}''
    ];
  };
}
