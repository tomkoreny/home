{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.tomkoreny.desktop.enable {
  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications = {
      "message/rfc822" = [ "org.gnome.Evolution.desktop" ];
      "x-scheme-handler/mailto" = [ "org.gnome.Evolution.desktop" ];
      "text/calendar" = [ "org.gnome.Evolution.desktop" ];
      "x-scheme-handler/calendar" = [ "org.gnome.Evolution.desktop" ];
      "x-scheme-handler/webcal" = [ "org.gnome.Evolution.desktop" ];
      "x-scheme-handler/webcals" = [ "org.gnome.Evolution.desktop" ];
    };
  };
}
