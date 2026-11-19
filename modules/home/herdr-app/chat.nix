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
  version = "0-unstable-2026-11-19";

  # Tom's fork of azaeldrm/herdr-chat, a young single-author project: upstream
  # plus OMP (its chat, its slash commands with their choices, a status line
  # with the model and thinking level, a card with its to-do list and running
  # subagents, what it is doing right now, and its ask form shown whole and
  # answered from the card, from the OMP extension in omp/), and pictures
  # in agents' replies, copied from the agent's machine; on the fork's
  # `omp` branch; it needs Herdr 0.1.16's mod API. A
  # Herdr mod is unsandboxed code with the user's access; upstream was read
  # before forking (it runs python3, hc, sh, env and rm, and opens no network
  # connection; the fork adds `omp --mode rpc --no-session`). Upstream's
  # repository is gone (404 since November 2026), so the fork is the only
  # source. bump-pins.py does not move it: read the diff, then change rev and
  # hash.
  src = fetchFromGitHub {
    owner = "tomkoreny";
    repo = "herdr-chat";
    rev = "629fe444b21c919fc36d6834f3614c45c50810f2";
    hash = "sha256-MhqOmCnq3IL9SZO62p9sFFCC6DIVs7fJE9bwz8X+xVQ=";
  };

  dontConfigure = true;
  dontBuild = true;
  # The files are copied into the app's home as they are; no store paths in them.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/mods" "$out/layouts" "$out/omp"
    cp -r mods/herdr-chat "$out/mods/herdr-chat"
    cp layouts/herdr-chat.json "$out/layouts/herdr-chat.json"
    cp omp/herdr-chat-live.ts "$out/omp/herdr-chat-live.ts"

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
