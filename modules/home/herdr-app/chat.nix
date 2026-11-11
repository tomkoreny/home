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
  version = "0-unstable-2026-11-10";

  # A Herdr mod is unsandboxed code with the user's access, and this one is a
  # young single-author project. The commit below was read before pinning (it
  # runs python3, hc, sh, env and rm, and opens no network connection), and
  # bump-pins.py does not move it: read the diff, then change rev and hash.
  src = fetchFromGitHub {
    owner = "azaeldrm";
    repo = "herdr-chat";
    rev = "81ab4f44c83ce6c2d311b71a090d077883a5c583";
    hash = "sha256-AVfRl17vrYNGfOfGBHUcgv9Zd2IWUFF6v/3ONYUD2ac=";
  };

  # Upstream's way to add an agent: an adapter in harnesses/ and a reader in
  # readers/, each registered in its list. --replace-fail stops the build when
  # upstream reshapes either list.
  postPatch = ''
    cp ${./omp-adapter/omp.js} mods/herdr-chat/harnesses/omp.js
    cp ${./omp-adapter/omp.py} mods/herdr-chat/readers/omp.py
    substituteInPlace mods/herdr-chat/harnesses/index.js \
      --replace-fail 'import opencode from "./opencode.js";' 'import opencode from "./opencode.js"; import omp from "./omp.js";' \
      --replace-fail '[claudeCode, codex, pi, opencode]' '[claudeCode, codex, pi, opencode, omp]'
    substituteInPlace mods/herdr-chat/readers/manifest.json \
      --replace-fail '"opencode.py", "main.py"' '"opencode.py", "omp.py", "main.py"'
  '';

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
  # something the mod imports fails here, in CI, instead of in the chat view.
  # The app needs a font to start, and the sandbox has none. It writes its
  # type files beside a mod it loads, so it gets a copy.
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
    description = "Herdr layout and mod that show a coding agent's terminal as a chat, with an OMP adapter";
    homepage = "https://github.com/azaeldrm/herdr-chat";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
