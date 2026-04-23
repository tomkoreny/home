{
  lib,
  stdenv,
  fetchurl,
  config,
  writeText,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  gtk3,
  undmg,
}:
let
  version = "140.10.0esr-bb21";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://www.betterbird.eu/downloads/LinuxArchive/betterbird-${version}.en-US.linux-x86_64.tar.xz";
      hash = "sha256-Uh55xWn/cjoIutX2xdM/jUWw9c2As8P4fefK5KQtbQo=";
    };

    aarch64-darwin = fetchurl {
      url = "https://www.betterbird.eu/downloads/MacDiskImage/betterbird-${version}.en-US.mac-arm64.dmg";
      hash = "sha256-KOLJ+VoUUrVWKyxbbc9vuTxaDYJc3AM+b0WiITWQm9A=";
    };
  };

  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported Betterbird system: ${stdenv.hostPlatform.system}");

  policies = {
    DisableAppUpdate = true;
  }
  // (config.betterbird.policies or { });

  policiesJson = writeText "betterbird-policies.json" (builtins.toJSON { inherit policies; });
in
stdenv.mkDerivation (
  {
    pname = "betterbird";
    inherit version src;

    nativeBuildInputs =
      lib.optionals stdenv.hostPlatform.isLinux [
        wrapGAppsHook3
        autoPatchelfHook
        patchelfUnstable
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [
        undmg
      ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      alsa-lib
      gtk3
    ];

    postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
      echo 'pref("app.update.auto", "false");' >> defaults/pref/channel-prefs.js
    '';

    preInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
      gappsWrapperArgs+=(
        --argv0 "$out/bin/.betterbird-wrapped"
        --set-default MOZ_ENABLE_WAYLAND 1
      )
    '';

    installPhase =
      if stdenv.hostPlatform.isDarwin then
        ''
          runHook preInstall

          mkdir -p "$out/Applications"
          mv Betterbird*.app "$out/Applications/Betterbird.app"

          runHook postInstall
        ''
      else
        ''
          runHook preInstall

          install_dir="$out/lib/betterbird-${version}"
          mkdir -p "$install_dir" "$out/bin"
          cp -r . "$install_dir"
          ln -s "$install_dir/betterbird" "$out/bin/betterbird"

          mkdir -p "$install_dir/distribution"
          ln -s ${policiesJson} "$install_dir/distribution/policies.json"

          runHook postInstall
        '';

    passthru = {
      applicationName = "Betterbird";
      binaryName = "betterbird";
      gssSupport = true;
      inherit gtk3;
    };

    meta = {
      description = "Betterbird, a soft fork of Mozilla Thunderbird";
      homepage = "https://www.betterbird.eu/";
      mainProgram = "betterbird";
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      license = lib.licenses.mpl20;
      platforms = builtins.attrNames sources;
    };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    patchelfFlags = [ "--no-clobber-old-sections" ];
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    sourceRoot = ".";
    dontFixup = true;
  }
)
