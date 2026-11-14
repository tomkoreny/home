{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeFontsConf,
  dejavu_fonts,
  herdr-app,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-chat";
  version = "0-unstable-2026-11-14";

  # Tom's fork of azaeldrm/herdr-chat, a young single-author project: upstream
  # plus OMP (its chat, its slash commands with their choices, a status line
  # with the model and thinking level, and a card with its to-do list and
  # running subagents), on the fork's `omp` branch. A Herdr mod is
  # unsandboxed code with the user's access; upstream was read
  # before forking (it runs python3, hc, sh, env and rm, and opens no network
  # connection; the fork adds `omp --mode rpc --no-session`). bump-pins.py does
  # not move it: merge upstream into the branch after reading its diff, then
  # change rev and hash.
  src = fetchFromGitHub {
    owner = "tomkoreny";
    repo = "herdr-chat";
    rev = "d5d9a962cdc4a9a7f32f13c713a3d42f8fb9c596";
    hash = "sha256-LA6sktHShVGpGtBfPZAIerJj75lbbYzcm3oHPVzRVng=";
  };

  dontConfigure = true;
  dontBuild = true;
  # The files are copied into the app's home as they are; no store paths in them.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/mods" "$out/layouts"
    cp -r mods/herdr-chat "$out/mods/herdr-chat"
    cp layouts/herdr-chat.json "$out/layouts/herdr-chat.json"

    runHook postInstall
  '';

  # The app loads the mod once, without a window. A Herdr release that drops
  # something the mod imports fails here instead of in the chat view: in CI for
  # the Linux build, on the Mac when it builds its own. On Linux the app needs
  # a font to start, and the sandbox has none. It writes its type files beside
  # a mod it loads, so it gets a copy.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ herdr-app ];
  installCheckPhase = ''
    runHook preInstallCheck

    cp -r "$out/mods/herdr-chat" "$TMPDIR/herdr-chat"
    HOME="$TMPDIR" FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }} \
      herdr-app check "$TMPDIR/herdr-chat"

    runHook postInstallCheck
  '';

  meta = {
    description = "Herdr layout and mod that show a coding agent's terminal as a chat, with OMP support";
    homepage = "https://github.com/tomkoreny/herdr-chat";
    license = lib.licenses.mit;
    inherit (herdr-app.meta) platforms;
  };
}
