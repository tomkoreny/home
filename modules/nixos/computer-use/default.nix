# Host-desktop input and accessibility for OMP's `computer` Eval prelude.
#
# OMP sends Wayland input only through libei, either from `LIBEI_SOCKET` or
# from the RemoteDesktop portal's ConnectToEIS. xdg-desktop-portal-hyprland
# implements neither, so Hyprland routes RemoteDesktop to hypr-kdeconnect-fix,
# a small portal backend that accepts libei clients and replays their events
# through the wlr virtual-pointer and virtual-keyboard protocols.
#
# That backend shows no consent dialog. It only accepts callers whose
# /proc/<pid>/exe is on an allowlist, and HKCF_DESKFLOW_EXECUTABLE adds the
# exact OMP binary from this flake. Upstream applies the executable check only
# when the portal reports an empty app id. Here it applies to every caller,
# because OMP inherits the app id of whatever terminal unit started herdr.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.computer-use;

  # Same derivation Home Manager installs (useGlobalPkgs), so the allowlisted
  # path is the binary that actually runs.
  omp = import ../../home/packages/omp.nix { inherit inputs pkgs; };

  remoteDesktopPortal = pkgs.stdenv.mkDerivation {
    pname = "hypr-kdeconnect-fix";
    version = "0.1.0-unstable-2026-10-05";

    src = pkgs.fetchFromGitHub {
      owner = "gfhdhytghd";
      repo = "hypr-kdeconnect-fix";
      rev = "5fc959475177197f0aa953fcc42a3742e6648671";
      hash = "sha256-vhb+UMDJXvw8PAIzH1bsLk4JmXzRIPiFTRQxZX3wPZM=";
    };

    postPatch = ''
      substituteInPlace src/security_policy.hpp \
        --replace-fail \
          'return normalized.isEmpty() || normalized == QStringLiteral("surface-transient");' \
          'return true;'
    '';

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
      pkgs.wayland-scanner
    ];
    buildInputs = [
      pkgs.libei
      pkgs.libxkbcommon
      pkgs.qt6.qtbase
      pkgs.wayland
    ];
    # A D-Bus daemon with no Qt GUI; there is no plugin path to wrap.
    dontWrapQtApps = true;

    cmakeFlags = [
      "-DBUILD_TESTING=OFF"
      "-DHKCF_DESKFLOW_EXECUTABLE=${omp}/bin/.omp-wrapped"
    ];

    # NixOS links user units from lib/systemd/user; the D-Bus activation file
    # names this unit, so it has to be found there.
    postInstall = ''
      mkdir -p "$out/lib/systemd"
      mv "$out/share/systemd/user" "$out/lib/systemd/user"
    '';

    meta.mainProgram = "hypr-kdeconnect-portal";
  };
in
{
  options.tomkoreny.nixos.computer-use.enable =
    lib.mkEnableOption "input and accessibility backends for OMP's computer prelude";

  config = lib.mkIf cfg.enable {
    xdg.portal = {
      extraPortals = [ remoteDesktopPortal ];
      # Replaces Hyprland's packaged hyprland-portals.conf, so its default
      # routing is restated here.
      config.hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
        "org.freedesktop.impl.portal.RemoteDesktop" = [ "hypr-kdeconnect" ];
      };
    };
    # The packaged unit's mount-namespace hardening (ProtectSystem, ProtectHome,
    # PrivateTmp) makes readlink(/proc/<caller>/exe) fail, so the executable
    # allowlist above rejects every caller. Keep the other restrictions.
    systemd.user.services.hypr-kdeconnect-portal.serviceConfig = {
      ProtectSystem = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      PrivateTmp = lib.mkForce false;
    };
    # AT-SPI lets the prelude list windows and read and press their controls.
    # Enabling it also drops NixOS's NO_AT_BRIDGE=1 default, which only takes
    # effect for applications started in a new login session.
    services.gnome.at-spi2-core.enable = true;
    # The bus launcher reports org.a11y.Status.IsEnabled from this key, and
    # GTK, Qt and Chromium only register their windows with AT-SPI while it is
    # true. Without it the prelude sees no windows at all.
    programs.dconf = {
      enable = true;
      profiles.user.databases = [
        { settings."org/gnome/desktop/interface".toolkit-accessibility = true; }
      ];
    };
  };
}
