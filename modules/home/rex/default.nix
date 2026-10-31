# Rex (superlogical.com/rex): tom's personal Rex server on NixOS. The Mac
# reaches it over Yggdrasil, the iPhone app over Tailscale.
#
# The Yggdrasil listener can't tell callers apart, so it accepts anonymous
# plain HTTP: whoever reaches it gets a shell as tom. It binds only the NixOS
# Yggdrasil address, and modules/nixos/rex lets only the Mac's Yggdrasil
# address through the firewall to it.
#
# The Tailscale listener is Rex's own tailnet node (no tailscaled on NixOS),
# like the Mac server's toms-macbook-pro-rex. Tailscale identifies each
# caller, and only the account that enrolled the node gets in. The tailnet is
# shared with Terka, so leave allowTailnetMembers off.
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
          # https://nixos-rex.<tailnet>.ts.net. The node keeps its identity
          # in Rex's state directory; the first start prints a sign-in link
          # in `rex server status`. Renaming it means enrolling again.
          tailscale = {
            enable = true;
            hostname = "nixos-rex";
          };
        };
      })
      (lib.mkIf isDarwin {
        programs.rex = {
          enable = true;
          # Rex Beta.app ships the CLI and runs the server; this only writes
          # ~/.config/rex/init.lua. Apply a change with `rex config reload`.
          package = null;
          # The label is for the CLI (`rex -S nixos`). The app keeps its own
          # host list in its preferences and does not read init.lua hosts,
          # so it was added there by hand with "Add Remote Host…" and this
          # endpoint.
          config = ''
            rex.host{ label = "nixos", endpoint = "${common.rex.endpoint}" }
          '';
        };
      })
    ]
  );
}
