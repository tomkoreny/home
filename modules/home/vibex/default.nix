# Vibex (github.com/vibex-ai/vibex): a native GPUI workbench that hosts coding
# agents over the Agent Client Protocol (ACP). On trial as a GUI for OMP.
#
# OMP is not in Vibex's agent catalog, and 0.1.0 cannot start a session with
# it. A custom ACP agent (Config Center → Agents → Add custom ACP Agent,
# command `omp`, argument `acp`) registers, signs in and lists OMP's models,
# but the new-session picker offers only the ids on Vibex's built-in
# USER_VISIBLE_AGENT_IDS list (crates/core/src/agent_config.rs), and a custom
# agent may not reuse a built-in id. Vibex keeps agents in its own database
# under ~/.vibex, so the entry is not declared here.
#
# The release .deb is patched in place instead of running the AppImage through
# appimageTools: that wrapper starts the app inside a bubblewrap namespace,
# every agent Vibex spawns would inherit it, and setuid programs such as sudo
# do not work there.
#
# Vibex's built-in updater cannot replace a store path. The pin below follows
# upstream through .github/scripts/bump-pins.py instead.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.vibex;
  version = "0.1.0";

  vibex = pkgs.stdenv.mkDerivation {
    pname = "vibex";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/vibex-ai/vibex/releases/download/v${version}/vibex-${version}-linux-x86_64-deb.deb";
      hash = "sha256-ieZNz/CiCdL17ysP10Q098deXE3VtnsTt1y5kjSMfXU=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.dpkg
    ];

    buildInputs = [
      pkgs.dbus
      pkgs.glib
      pkgs.gtk3
      pkgs.libxcb
      pkgs.libxkbcommon
      pkgs.stdenv.cc.cc.lib
    ];

    # GPUI opens these at runtime instead of linking them, so they are absent
    # from the binaries' NEEDED entries and autoPatchelf cannot find them.
    runtimeDependencies = [
      pkgs.fontconfig
      pkgs.libglvnd
      pkgs.vulkan-loader
      pkgs.wayland
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;

    # Keep upstream's usr/ layout: vibex-tui resolves the `vibex` beside it,
    # and the desktop finds PDFium under lib/vibex-desktop.
    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r usr/bin usr/lib usr/share "$out/"

      runHook postInstall
    '';

    meta = {
      description = "Native workbench for ACP coding agents";
      homepage = "https://github.com/vibex-ai/vibex";
      license = lib.licenses.agpl3Plus;
      mainProgram = "vibex-desktop";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  options.tomkoreny.vibex.enable = lib.mkEnableOption "the Vibex agent workbench";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The Vibex module packages only the x86_64 Linux release.";
      }
    ];

    home.packages = [ vibex ];
  };
}
