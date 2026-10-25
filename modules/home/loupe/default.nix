{
  pkgs,
  lib,
  ...
}:
let
  # Image types Loupe registers in org.gnome.Loupe.desktop. Without explicit
  # defaults, xdg-open handed images to whichever app happened to claim them
  # (ONLYOFFICE).
  imageTypes = [
    "image/png"
    "image/apng"
    "image/jpeg"
    "image/webp"
    "image/gif"
    "image/svg+xml"
    "image/svg+xml-compressed"
    "image/avif"
    "image/heic"
    "image/jxl"
    "image/tiff"
    "image/bmp"
    "image/vnd.microsoft.icon"
  ];
in
{
  # Loupe (GNOME Image Viewer): GTK4/libadwaita, so it follows the Stylix GTK
  # theme and matches Nautilus.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.loupe
  ];

  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications = lib.genAttrs imageTypes (_: [ "org.gnome.Loupe.desktop" ]);
  };
}
