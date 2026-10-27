# BlueFerry brings a paired iPhone's messages, app notifications, contacts and
# (opt-in) calls to the desktop over Bluetooth, without a Mac relay. Upstream
# ships Arch, Debian and Fedora packages; this module installs what those do.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.blueferry;
  bluez = config.hardware.bluetooth.package;
  package = pkgs.callPackage ./package.nix { inherit bluez; };
in
{
  options.tomkoreny.nixos.blueferry = {
    enable = lib.mkEnableOption "BlueFerry, the iPhone-to-desktop Bluetooth bridge";
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth.enable = true;

    # BlueFerry keeps ANCS (app notifications) on LE and MAP/PBAP (messages,
    # contacts) on BR/EDR through BlueZ's experimental per-bearer API, so
    # bluetoothd needs -E. BlueFerry looks for -E in bluetoothd's argv, which is
    # why main.conf's Experimental=true would not do. -E also loads BlueZ 5.87's
    # own HFP hands-free plugin, which takes the iPhone's call channel before
    # oFono can; -P hfp leaves it out, as upstream's Arch drop-in does. This
    # replaces the stock ExecStart, so hardware.bluetooth.disabledPlugins has no
    # effect while the module is on.
    systemd.services.bluetooth.serviceConfig.ExecStart = lib.mkForce [
      ""
      "${bluez}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf -E -P hfp"
    ];

    # The user daemon repairs the adapter's volatile Class of Device (without
    # it the iPhone hides the Messages and Contacts toggles) by starting this
    # one fixed system unit. Same rule as upstream's 49-blueferry-cod.rules.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id !== "org.freedesktop.systemd1.manage-units" ||
            action.lookup("verb") !== "start" ||
            !subject.active || !subject.local) {
          return polkit.Result.NOT_HANDLED;
        }
        var unit = action.lookup("unit");
        if (unit && /^blueferry-btmgmt-set-class@[0-9]+\.service$/.test(unit)) {
          return polkit.Result.YES;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';

    environment.systemPackages = [ package ];
    services.dbus.packages = [ package ];
    systemd.packages = [ package ];

    # Upstream enables the backend for every user; the unit only starts once
    # pairing has written ~/.config/blueferry/local.env.
    systemd.user.services.blueferry.wantedBy = [ "default.target" ];
  };
}
