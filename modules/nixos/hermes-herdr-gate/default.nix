# Lets the Hermes agent (homelab cluster) drive this host's herdr agents over
# SSH, so Tom can list, prompt and answer his OMP agents from Matrix; and, with
# `car.enable`, the car's display (car-display on the car's Raspberry Pi) list
# them, show their recent output and send them a reply.
#
# Each key is pinned to a forced command: no shell, no forwarding, each call
# logged. Hermes' gate (gate.py) allows an allowlist of herdr subcommands and
# logs to ~/.local/state/herdr-hermes-gate/log.jsonl. Like the Authentik RAC
# key, Hermes' key is accepted only from the Talos node addresses that cluster
# pods leave from. The car's gate (car_gate.py) allows exactly `agent list`,
# `agent read` and `agent prompt`, no keystrokes, and logs to
# ~/.local/state/herdr-car-gate/log.jsonl; its key is accepted only from the
# Pi's Yggdrasil address, which Yggdrasil binds to the Pi's own key. Prompting
# an OMP agent still means that agent can run anything as Tom; the gates limit
# what Hermes and the car can do directly, not what OMP does.
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

  carGate = pkgs.writers.writePython3Bin "herdr-car-gate" {
    flakeIgnore = [ "E501" ];
  } (builtins.replaceStrings [ "@herdr@" ] [ herdr ] (builtins.readFile ./car_gate.py));
in
{
  options.tomkoreny.nixos.hermes-herdr-gate = {
    enable = lib.mkEnableOption "Hermes access to herdr through an SSH forced command";

    user = lib.mkOption {
      type = lib.types.str;
      default = common.user.name;
      description = "Account whose herdr server Hermes and the car drive.";
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

    # No defaults: enabling the car without its real key and address fails
    # evaluation instead of authorizing a placeholder. The car is part of the
    # gate: switching `enable` off withdraws its key too.
    car = {
      enable = lib.mkEnableOption "the car display's access to herdr (list, read, prompt) through an SSH forced command";

      publicKey = lib.mkOption {
        type = lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+=*( [^\n]*)?";
        example = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA… car-display@pi";
        description = "The car's key, one line: the Pi's /var/lib/car-display/agents.key.pub (car-display's README, Agents).";
      };

      fromAddresses = lib.mkOption {
        type = lib.types.nonEmptyListOf (lib.types.strMatching "[0-9A-Fa-f:./]+");
        example = [ "200:1234:5678:9abc:def0:1234:5678:9abc" ];
        description = "Source addresses the car's key is accepted from: the Pi's Yggdrasil address (`sudo yggdrasilctl getself` on the Pi).";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      users.users.${cfg.user}.openssh.authorizedKeys.keys = [
        ''from="${lib.concatStringsSep "," cfg.fromAddresses}",restrict,command="${gate}/bin/herdr-hermes-gate" ${cfg.publicKey}''
      ];
    })
    (lib.mkIf (cfg.enable && cfg.car.enable) {
      users.users.${cfg.user}.openssh.authorizedKeys.keys = [
        ''from="${lib.concatStringsSep "," cfg.car.fromAddresses}",restrict,command="${carGate}/bin/herdr-car-gate" ${cfg.car.publicKey}''
      ];
    })
  ];
}
