# Host side of modules/home/rex: keeps tom's Rex server running without a
# login session and lets the Mac's Rex app reach its Yggdrasil listener.
{
  config,
  lib,
  ...
}:
let
  cfg = config.tomkoreny.nixos.rex;
  common = import ../../../lib/common { };
in
{
  options.tomkoreny.nixos.rex.enable =
    lib.mkEnableOption "the Mac's access to tom's Rex server over Yggdrasil";

  config = lib.mkIf cfg.enable {
    # The server is a systemd user service. Lingering starts tom's user
    # manager at boot and keeps it running after logout, so Rex sessions
    # survive both.
    users.users.${common.user.name}.linger = true;

    # The listener hands a shell as tom to anyone who connects, and both hosts
    # peer with public Yggdrasil nodes, so the whole Yggdrasil network can
    # route to it. Admit only the Mac's address, and only from Yggdrasil's
    # device: checkReversePath is "loose" here, so a forged Mac address
    # arriving on the LAN would otherwise pass. Yggdrasil's IfName is "auto",
    # and as the only tun user it gets tun0. If that ever changes, the rule
    # stops matching and the Mac is refused rather than anyone let in.
    networking.firewall.extraCommands = ''
      ip6tables -A nixos-fw -i tun0 -p tcp -s ${common.yggdrasil.addresses.macos} -d ${common.yggdrasil.addresses.nixos} --dport ${toString common.rex.port} -j nixos-fw-accept
    '';
  };
}
