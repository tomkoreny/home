{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
in
{
  config = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && config.home.username == common.user.name) {
    services.espanso = {
      enable = true;
      x11Support = false;
      waylandSupport = true;
      configs.default = {
        # QMK handles the layout in firmware; Hyprland and Espanso see US keycodes.
        keyboard_layout.layout = "us";
        show_notifications = false;
      };
      matches.base.matches = [
        {
          triggers = [
            ";email"
            ";@"
          ];
          replace = common.user.email;
        }
        {
          trigger = ";name";
          replace = common.user.fullName;
        }
        {
          trigger = ";web";
          replace = "https://tomkoreny.com";
        }
        {
          trigger = ";date";
          replace = "{{today}}";
          vars = [
            {
              name = "today";
              type = "date";
              params.format = "%Y-%m-%d";
            }
          ];
        }
      ];
    };

    systemd.user.services.espanso = {
      Unit = {
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        # Run unprivileged: NixOS grants access only to seat0 devices.
        ExecStart = lib.mkForce "${lib.getExe pkgs.espanso-wayland} daemon";
        NoNewPrivileges = true;
      };
      Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
    };
  };
}
