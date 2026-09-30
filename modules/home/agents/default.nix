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
  ompPackage = import ../packages/omp.nix { inherit inputs lib pkgs; };
  ompWithHindsight = pkgs.writeShellScriptBin "omp" ''
    set -eu
    token_file=${lib.escapeShellArg config.sops.secrets.hindsight-api-token.path}
    if [[ ! -r "$token_file" ]]; then
      echo "omp: Hindsight API token is unavailable at $token_file" >&2
      exit 1
    fi
    export HINDSIGHT_API_TOKEN
    HINDSIGHT_API_TOKEN="$(${pkgs.coreutils}/bin/cat "$token_file")"
    # OMP refuses to emit images inside herdr because it cannot tell whether
    # the attached client renders Kitty graphics. Herdr does (its
    # `terminal.kitty_graphics` defaults to true) and Ghostty is the outer
    # terminal on both hosts, so opt in explicitly.
    if [[ -n "''${HERDR_PANE_ID:-}" ]]; then
      export PI_FORCE_IMAGE_PROTOCOL="''${PI_FORCE_IMAGE_PROTOCOL:-kitty}"
    fi
    ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      # A herdr server first started over SSH hands every pane an SSH-login
      # environment without WAYLAND_DISPLAY, so headed Chromium and the
      # `computer` prelude cannot reach the desktop. Borrow the live Hyprland
      # session's variables from the systemd user manager, which UWSM fills.
      if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
        while IFS='=' read -r name value; do
          case "$name" in
            WAYLAND_DISPLAY | DISPLAY | HYPRLAND_INSTANCE_SIGNATURE | XDG_CURRENT_DESKTOP)
              export "$name=$value"
              ;;
          esac
        done < <(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null || true)
        if [[ -n "''${WAYLAND_DISPLAY:-}" ]]; then
          export XDG_SESSION_TYPE=wayland
        fi
      fi
      export PUPPETEER_EXECUTABLE_PATH=${lib.getExe pkgs.chromium}
      # OMP voice follows a Mac attached through herdr (common.ompVoice).
      # libpulse tries the list in order on every new stream, so each
      # recording or TTS reply picks the Mac while its forwarded socket
      # accepts connections and NixOS audio once it refuses. Child processes
      # OMP starts inherit the same routing.
      export PULSE_SERVER="''${PULSE_SERVER:-unix:${common.ompVoice.nixosSocket} unix:''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/pulse/native}"
    ''}
    exec ${lib.getExe ompPackage} "$@"
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

    # Copied to ~/.omp/agent/config.yml as a writable file on every switch:
    # OMP's own /settings edits persist until the next rebuild overwrites
    # them, so change settings here rather than in the TUI.
    programs.omp.settings = {
      providers.webSearchOrder = [ ];
      # Off: OMP runs inside Herdr panes, and since OMP 18.1.12 this toast is
      # routed through `herdr notification show`, which duplicates Herdr's own
      # agent-state "omp finished" toast (the one the Quickshell bar reconciles
      # and dismisses per pane). Ask/error notifications are not gated by this.
      completion.notify = "off";
      # OMP's default sleep prevention takes a logind `idle` block lock while
      # an agent works. On Linux, logind's IdleAction is `ignore`, so the lock
      # prevents no suspend; hypridle reads it as user activity and skips the
      # OLED dim, clock saver and DPMS-off stages for the whole agent run.
      # macOS keeps the default, where the lock is a real `caffeinate -i`.
      power = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        sleepPrevention = "off";
      };
      # Agents default to hidden, project-shared Chromium so nothing opens on
      # screen. Relay into Helium (`app.relay: true`) is reserved for tasks that
      # need the user's logged-in session; see agent/RULES.md.
      browser.headless = true;
      # Opt-in tools. `generate_image` runs on the `image` model role;
      # `computer` is the host-desktop Eval prelude (screenshots, input,
      # AT-SPI); `github` wraps the `gh` CLI, which must be on PATH.
      generate_image.enabled = true;
      computer.enabled = true;
      github.enabled = true;

      modelRoles = {
        default = "anthropic/claude-opus-5-5:xhigh";
        slow = "anthropic/claude-opus-5-5:xhigh";
        plan = "anthropic/claude-opus-5-5:xhigh";
        # Vibe-mode worker tiers: `fast` spawns run @smol, `good` spawns run @task.
        smol = "openai-codex/gpt-6.1-sol:high";
        task = "anthropic/claude-opus-5-5:xhigh";
        # Second model reviewing every primary turn; it can inject a note or
        # interrupt with a blocker.
        advisor = "openai-codex/gpt-6.1-sol:xhigh";
        # Routine helpers use Sol; model-kind roles do not take thinking suffixes.
        commit = "openai-codex/gpt-6.1-sol:high";
        tiny = "openai-codex/gpt-6.1-sol:high";
        memory = "openai-codex/gpt-6.1-sol:high";
        vision = "openai-codex/gpt-6.1-sol:xhigh";
        judge = "openai-codex/gpt-6.1-sol";
      };
      # Provider quota is finite and unpredictable per plan. Model-keyed fallback
      # chains (keys containing "/") follow the model wherever it is active,
      # including inside vibe/task subagents, so a 429 or a depleted usage
      # reserve on one provider moves the turn to the other and reverts when the
      # cooldown ends. The chains are deliberately circular.
      retry = {
        usageAwareFallback = true;
        usageReservePct = 10;
        usageReservePolicy = "auto";
        fallbackChains = {
          "anthropic/claude-opus-5-5" = [ "openai-codex/gpt-6.1-sol:high" ];
          "openai-codex/gpt-6.1-sol" = [ "anthropic/claude-opus-5-5:xhigh" ];
        };
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
      # The eval tool otherwise looks for `python`/`python3` on PATH, which
      # nothing on these hosts provides, so `language: "py"` cells failed with
      # "Python backend is unavailable". The bundled runner needs 3.10+ and no
      # extra packages.
      python.interpreter = lib.getExe pkgs.python3;
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
      # Replaces OMP's built-in `default` personality block, which asks for
      # fragments and arrow shorthand; this one asks for whole plain sentences.
      ".omp/agent/PERSONALITY.md".source = ./agent/PERSONALITY.md;

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
      # Hidden from the model; `/skill:bro` restates the last reply plainly.
      ".omp/agent/skills/bro/SKILL.md".source = ./agent/skills/bro/SKILL.md;
      # Anthropic's frontend-design skill, vendored with its upstream license.
      ".omp/agent/skills/frontend-design/SKILL.md".source = ./agent/skills/frontend-design/SKILL.md;
      ".omp/agent/skills/frontend-design/LICENSE.txt".source = ./agent/skills/frontend-design/LICENSE.txt;

      # Light-slot theme; see the comment above the definition.
      ".omp/agent/themes/${ompLatteTheme.name}.json".text = builtins.toJSON ompLatteTheme;

      # OMP shadows both of these with its own native files above; they carry
      # the same rules for sessions run through Claude Code and Codex directly.
      ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ./codex/AGENTS.md;
    };
  };
}
