# Flectar Mail (github.com/flectar/mail): a mail, calendar and contacts client
# written in Rust with a Slint UI. It draws HTML mail with Blitz, a Rust
# renderer, instead of a browser engine. Alpha software, on trial beside
# Betterbird (modules/home/betterbird), which stays the configured client.
#
# Accounts are added in the app and live in its own database, so none are
# declared here. Passwords and OAuth tokens go to the Secret Service keyring,
# which is gnome-keyring on the NixOS host.
#
# The binary links only libdbus and opens the display libraries at run time,
# so the AppImage's contents are patched in place and its bundled libdbus and
# libsystemd are left out in favour of the system's.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.flectar-mail;
  version = "0.1.0-alpha.7";

  appimageContents = pkgs.appimageTools.extract {
    pname = "flectar-mail";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/flectar/mail/releases/download/v${version}/flectar-mail-${version}-linux-x64.AppImage";
      hash = "sha256-mv8NNbwC5nqT06FEJiSh+wdCs4/abRyCxDzMGl7ySQA=";
    };
  };

  flectar-mail = pkgs.stdenv.mkDerivation {
    pname = "flectar-mail";
    inherit version;
    src = appimageContents;

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    buildInputs = [
      pkgs.dbus
      pkgs.stdenv.cc.cc.lib
    ];

    # Slint and Blitz open these at run time instead of linking them, so they
    # are absent from the binary's NEEDED entries and autoPatchelf cannot find
    # them.
    runtimeDependencies = [
      pkgs.fontconfig
      pkgs.libglvnd
      pkgs.libxkbcommon
      pkgs.vulkan-loader
      pkgs.wayland
    ];

    dontConfigure = true;
    dontBuild = true;

    # Keep bin/ and lib/flectar-mail side by side: the binary looks for PDFium
    # relative to itself.
    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/lib"
      cp usr/bin/flectar-mail "$out/bin/"
      cp -r usr/lib/flectar-mail "$out/lib/"
      cp -r usr/share "$out/"

      runHook postInstall
    '';

    meta = {
      description = "Native mail, calendar and contacts client";
      homepage = "https://flectar.com/mail/";
      license = lib.licenses.agpl3Only;
      mainProgram = "flectar-mail";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  options.tomkoreny.flectar-mail.enable = lib.mkEnableOption "the Flectar Mail client";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The Flectar Mail module packages only the x86_64 Linux release.";
      }
    ];

    home.packages = [ flectar-mail ];
  };
}
