# Rex (superlogical.com/rex): tom's personal Rex server on NixOS, which the
# Mac's Rex app opens as the remote host "nixos" over Yggdrasil.
#
# Rex can tell remote callers apart only through Tailscale, which these hosts
# do not run, so the server accepts anonymous plain HTTP: whoever reaches the
# listener gets a shell as tom. The listener binds only the NixOS Yggdrasil
# address, and modules/nixos/rex lets only the Mac's Yggdrasil address through
# the firewall to it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  config = lib.mkIf (config.home.username == common.user.name) (
    lib.mkMerge [
      (lib.mkIf isLinux {
        # A systemd user service; modules/nixos/rex turns on lingering so it
        # runs from boot and survives logout. Switches never restart it (the
        # module's X-SwitchMethod is keep-old) because a restart ends every
        # session; run `systemctl --user restart rex` to pick up an update.
        # Until Yggdrasil has brought up the address, the bind fails and
        # systemd retries every 5 seconds.
        services.rex = {
          enable = true;
          extraListen = [ common.rex.endpoint ];
          allowAnonymous = true;
        };
      })
      (lib.mkIf isDarwin {
        programs.rex = {
          enable = true;
          # Rex Beta.app ships the CLI and runs the server; this only writes
          # ~/.config/rex/init.lua. Apply a change with `rex config reload`.
          package = null;
          config = ''
            rex.host{ label = "nixos", endpoint = "${common.rex.endpoint}" }
          '';
        };
      })
    ]
  );
}
