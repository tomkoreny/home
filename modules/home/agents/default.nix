# Coding-agent policy for OMP, Claude Code, and Codex.
#
# Three kinds of file live here:
#   agent/RULES.md          sticky rules, re-attached near the current turn so
#                           they keep their hold in a long conversation
#   agent/rules/*.md        TTSR rules: a regex match on the model's own output
#                           stream aborts the turn and regenerates it, so the
#                           violating sentence or edit never lands. Test one
#                           without a model call: `omp ttsr test --source text '<snippet>'`
#   agent/skills/*/SKILL.md workflow protocols the agent pulls in on demand,
#                           also reachable interactively as /skill:<name>
#
# OMP writes session state, SQLite databases, and its credential vault. Herdr
# manages its own lifecycle extension; custom extensions are declared beside it
# below rather than modifying Herdr's generated file.
#
# Every module under modules/home/ is shared with terka@nixos via
# home-manager.sharedModules, so this one is scoped to tom.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
  ompPackage = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  ompWithHindsight = pkgs.writeShellScriptBin "omp" ''
    set -eu
    token_file=${lib.escapeShellArg config.sops.secrets.hindsight-api-token.path}
    if [[ ! -r "$token_file" ]]; then
      echo "omp: Hindsight API token is unavailable at $token_file" >&2
      exit 1
    fi
    export HINDSIGHT_API_TOKEN
    HINDSIGHT_API_TOKEN="$(${pkgs.coreutils}/bin/cat "$token_file")"
    ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      export PUPPETEER_EXECUTABLE_PATH=${lib.getExe pkgs.chromium}
    ''}
    exec ${lib.getExe ompPackage} "$@"
  '';
  ompRelayExtension = pkgs.runCommand "omp-browser-relay-extension" { } ''
    export HOME="$TMPDIR"
    ${lib.getExe ompPackage} browser-relay install --dir "$out"
  '';
  bitwardenRelayCrx = pkgs.fetchurl {
    url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=152.0.0.0&acceptformat=crx3&x=id%3Dnngceckbapebfimnlniiiahkandclblb%26uc";
    hash = "sha256-0aWULZwjTQM4LamSeZMgVQZMquejLMmxV5QMhjFl1Z8=";
  };
  bitwardenRelayExtension =
    pkgs.runCommand "bitwarden-browser-extension-2026.8.0"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.unzip
        ];
      }
      ''
        mkdir -p "$out"
        dd if='${bitwardenRelayCrx}' of="$TMPDIR/bitwarden.zip" bs=1 skip=1322 status=none
        unzip -q "$TMPDIR/bitwarden.zip" -d "$out"
        jq --arg key 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmqKbvreshyXRuN2gikeR1idqR6KL0Di89JZcMyD4bjJRZVmQO7aznSGSALIHzSAUGYocUYBNDOP5QAhImxXyQ1qG8+goXs93v9GzrNJETdVuCEhqBggC4/DFabryJZDiKvZ2Jl0DM7MsWdoybZPwrj70V3aJ/nVNOMkf868scNTMliwitCqqjT5baTANsG0DkZWQExD4lSXzSZHH9MEO8q0iZ7RRlNuGRBAkZgNV8FwZRsPKm/rwQ9dy3VpgLcmLp5GiMt+kAEncqKAkuRYnhVXXBsKqIyYTMjHSLkLnpfFySyOPLBdS617i/PGNiP/MT6Xy6z//v5NozUgaAZ4gJQIDAQAB' \
          '.key = $key' "$out/manifest.json" > "$out/manifest.json.tmp"
        mv "$out/manifest.json.tmp" "$out/manifest.json"
      '';
  ompRelayBrowser = pkgs.writeShellScriptBin "omp-relay-browser" ''
    set -eu
    profile_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/omp-relay-chromium"
    ${pkgs.coreutils}/bin/mkdir -p "$profile_dir"
    if [[ $# -eq 0 ]]; then
      set -- http://127.0.0.1:9224/
    fi
    printf 'omp-relay-browser: launching dedicated Chromium\n' >&2
    exec ${lib.getExe pkgs.chromium} \
      --user-data-dir="$profile_dir" \
      --disable-extensions-except=${ompRelayExtension},${bitwardenRelayExtension} \
      --load-extension=${ompRelayExtension},${bitwardenRelayExtension} \
      --no-first-run \
      --no-default-browser-check \
      --class=omp-relay-browser \
      "$@"
  '';
  accentLight = common.stylix.accentLight;

  # OMP picks a theme slot from the terminal background, so the light slot needs
  # a real Catppuccin Latte theme rather than OMP's generic built-in `light`.
  # Custom themes live in ~/.omp/agent/themes/<name>.json and every colour token
  # is required; `""` means "terminal default", which keeps text in step with
  # whatever Ghostty's active theme uses.
  #
  # Text-bearing roles use Latte hues darkened until they clear 4:1 on Latte's
  # base (#eff1f5), the same rule that produces the shared light accent. Pure
  # Latte values stay where they only need to be distinguishable: borders,
  # background tints and comments.
  latte = {
    base = "#eff1f5";
    mantle = "#e6e9ef";
    crust = "#dce0e8";
    surface0 = "#ccd0da";
    surface1 = "#bcc0cc";
    surface2 = "#acb0be";
    overlay1 = "#8c8fa1";
    overlay2 = "#7c7f93";
    subtext0 = "#6c6f85";
    red = "#d20f39";
    mauve = "#8839ef";
    # Darkened for readability on `base`; upstream Latte sits at 2.3-3.0:1.
    greenInk = "#338022";
    yellowInk = "#9c6314";
    peachInk = "#be4b08";
    tealInk = "#147c82";
    sapphireInk = "#1a7f91";
    pinkInk = "#a4538e";
    # Green and red at 14% and 12% over `base`, for the tool result frames.
    successBg = "#d7e6d9";
    errorBg = "#ecd6de";
  };

  ompLatteTheme = {
    name = "catppuccin-latte-stylix";
    colors = {
      accent = accentLight;
      border = latte.surface1;
      borderAccent = accentLight;
      borderMuted = latte.surface0;
      success = latte.greenInk;
      error = latte.red;
      warning = latte.yellowInk;
      muted = latte.subtext0;
      dim = latte.overlay1;
      text = "";
      thinkingText = latte.subtext0;

      selectedBg = latte.surface0;
      userMessageBg = latte.mantle;
      userMessageText = "";
      customMessageBg = latte.crust;
      customMessageText = "";
      customMessageLabel = accentLight;
      toolPendingBg = latte.mantle;
      toolSuccessBg = latte.successBg;
      toolErrorBg = latte.errorBg;
      toolTitle = "";
      toolOutput = latte.subtext0;

      mdHeading = accentLight;
      mdLink = accentLight;
      mdLinkUrl = latte.subtext0;
      mdCode = latte.mauve;
      mdCodeBlock = "";
      mdCodeBlockBorder = latte.surface1;
      mdQuote = latte.subtext0;
      mdQuoteBorder = latte.surface1;
      mdHr = latte.surface1;
      mdListBullet = accentLight;

      toolDiffAdded = latte.greenInk;
      toolDiffRemoved = latte.red;
      toolDiffContext = latte.subtext0;

      syntaxComment = latte.overlay2;
      syntaxKeyword = latte.mauve;
      syntaxFunction = accentLight;
      syntaxVariable = "";
      syntaxString = latte.greenInk;
      syntaxNumber = latte.peachInk;
      syntaxType = latte.yellowInk;
      syntaxOperator = latte.tealInk;
      syntaxPunctuation = latte.subtext0;

      thinkingOff = latte.overlay1;
      thinkingMinimal = latte.overlay2;
      thinkingLow = accentLight;
      thinkingMedium = latte.tealInk;
      thinkingHigh = latte.mauve;
      thinkingXhigh = latte.red;
      thinkingMax = latte.pinkInk;
      bashMode = latte.tealInk;
      pythonMode = latte.mauve;

      statusLineBg = latte.mantle;
      statusLineSep = latte.surface2;
      statusLineModel = latte.mauve;
      statusLinePath = accentLight;
      statusLineGitClean = latte.greenInk;
      statusLineGitDirty = latte.yellowInk;
      statusLineContext = latte.tealInk;
      statusLineSpend = latte.sapphireInk;
      statusLineStaged = latte.greenInk;
      statusLineDirty = latte.peachInk;
      statusLineUntracked = latte.red;
      statusLineOutput = "";
      statusLineCost = latte.peachInk;
      statusLineSubagents = latte.mauve;
    };
    export = {
      pageBg = latte.base;
      cardBg = latte.mantle;
      infoBg = latte.crust;
    };
  };
in
{
  config = lib.mkIf (config.home.username == "tom") {
    sops = {
      defaultSopsFile = ../../../secrets/omp-hindsight.yaml;
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      secrets.hindsight-api-token = {
        key = "hindsight-api-token";
        mode = "0400";
      };
    };

    # Keep the bearer token out of the Nix store and config.yml. The wrapper
    # reads the sops-nix runtime secret immediately before starting OMP.
    programs.omp.package = ompWithHindsight;
    home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      ompRelayBrowser
    ];

    # Written to ~/.omp/agent/config.yml as a read-only store symlink: OMP's
    # own /settings edits apply for the session but revert on the next rebuild,
    # so change settings here rather than in the TUI.
    programs.omp.settings = {
      providers.webSearchOrder = [ ];
      completion.notify = "on";
      browser = {
        headless = false;
      };

      modelRoles = {
        default = "openai-codex/gpt-5.6-sol";
        # Second model reviewing every primary turn; it can inject a note or
        # interrupt with a blocker. Runs on the same ChatGPT OAuth account as
        # the primary, so both draw from one rate limit.
        advisor = "openai-codex/gpt-5.6-sol:medium";
      };
      advisor.enabled = true;

      symbolPreset = "nerd";
      # Editor + status line layout; default `box` draws a rounded frame
      # around the input. Other values: claude, pi.
      composer.shape = "borderless";

      # Shared remote memory for Linux and macOS. Tagged scoping isolates
      # unrelated repositories by default; this repo's .omp/config.yml selects
      # a dedicated bank because its checkout basename differs between hosts.
      memory.backend = "hindsight";
      hindsight = {
        apiUrl = "https://hindsight.home.tomkoreny.com";
        scoping = "per-project-tagged";
      };
      theme = {
        dark = "titanium";
        # Generated below. The name carries the `-stylix` suffix because
        # built-in theme names win over custom files of the same name.
        light = ompLatteTheme.name;
      };
      # OMP re-runs the setup wizard (theme picker included) whenever this is
      # older than the onboarding version the running build writes; every
      # rebuild reverts the file to this value, so if the wizard reappears
      # after an OMP upgrade, bump it to what the new build wrote to
      # ~/.omp/agent/config.yml.
      setupVersion = 2;
    };

    # Files are listed one by one rather than as directory symlinks: an
    # existing imperative directory is not covered by
    # home-manager.backupFileExtension, while an individual file is, so the
    # first switch renames the current copies to *.hm-bak instead of failing.
    home.file = {

      ".omp/agent/AGENTS.md".source = ./agent/AGENTS.md;
      ".omp/agent/RULES.md".source = ./agent/RULES.md;
      ".omp/agent/models.yml".source = ./agent/models.yml;
      # Advisor-only guidance: appended to the reviewer's prompt, never to the
      # primary agent's.
      ".omp/agent/WATCHDOG.md".source = ./agent/WATCHDOG.md;

      ".omp/agent/rules/slop-guard.md".source = ./agent/rules/slop-guard.md;
      ".omp/agent/rules/no-stub-delivery.md".source = ./agent/rules/no-stub-delivery.md;
      # Git policy: commit freely as Tom alone, resolve a remote before pushing
      # to it, and never rewrite history unasked.
      ".omp/agent/rules/no-agent-attribution.md".source = ./agent/rules/no-agent-attribution.md;
      ".omp/agent/rules/push-needs-permission.md".source = ./agent/rules/push-needs-permission.md;
      ".omp/agent/rules/no-history-rewrite.md".source = ./agent/rules/no-history-rewrite.md;

      ".omp/agent/skills/diagnose/SKILL.md".source = ./agent/skills/diagnose/SKILL.md;
      ".omp/agent/skills/verify-claim/SKILL.md".source = ./agent/skills/verify-claim/SKILL.md;
      ".omp/agent/skills/grill/SKILL.md".source = ./agent/skills/grill/SKILL.md;

      # Light-slot theme; see the comment above the definition.
      ".omp/agent/themes/${ompLatteTheme.name}.json".text = builtins.toJSON ompLatteTheme;

      # OMP shadows both of these with its own native files above; they carry
      # the same rules for sessions run through Claude Code and Codex directly.
      ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ./codex/AGENTS.md;
    };
  };
}
