# fwupd refreshes its firmware metadata every hour but tells nobody when an
# update exists: its notifier belongs to GNOME and KDE, and this desktop runs
# neither. After each refresh, ask for pending updates and raise a desktop
# notification through systembus-notify, the path smartd uses.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.fwupd-notify;

  notify = pkgs.writeShellApplication {
    name = "fwupd-notify";
    runtimeInputs = [
      config.services.fwupd.package
      pkgs.coreutils
      pkgs.dbus
      pkgs.findutils
      pkgs.jq
    ];
    text = builtins.readFile ./notify.sh;
  };
in
{
  options.tomkoreny.nixos.fwupd-notify.enable =
    lib.mkEnableOption "desktop notifications for pending firmware updates";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.fwupd.enable;
        message = "tomkoreny.nixos.fwupd-notify needs services.fwupd.enable.";
      }
    ];

    services.systembus-notify.enable = true;

    systemd.services.fwupd-notify = {
      description = "Notify about pending firmware updates";
      # Started with every metadata refresh and run once that has finished.
      wantedBy = [ "fwupd-refresh.service" ];
      after = [ "fwupd-refresh.service" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "fwupd-notify";
        ExecStart = lib.getExe notify;
      };
    };
  };
}
