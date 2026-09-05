{
  discord,
  lib,
  librsvg,
}:
let
  discordWithVencord = discord.override {
    withVencord = true;
  };

  trayStates = [
    "tray"
    "tray-unread"
    "tray-connected"
    "tray-speaking"
    "tray-muted"
    "tray-deafened"
  ];

  # The FHS wrapper must launch this payload: its existing stageModules hook
  # links the packaged core into the versioned user-data directory on startup.
  unwrappedDiscord = discordWithVencord.unwrappedDiscord.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ librsvg ];
    postInstall = (old.postInstall or "") + ''
      trayDir="$out/opt/Discord/modules/discord_desktop_core/app/images/systemtray/linux"
      for state in ${lib.escapeShellArgs trayStates}; do
        if [ ! -f "$trayDir/$state.png" ]; then
          echo "Discord's native tray layout changed: missing $trayDir/$state.png" >&2
          exit 1
        fi
        rsvg-convert --width 24 --height 24 \
          --output "$trayDir/$state.png" "${./.}/$state.svg"
      done
    '';
  });
in
discordWithVencord.override {
  inherit unwrappedDiscord;
}
