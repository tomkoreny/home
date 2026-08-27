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
# Deliberately NOT managed here, because OMP or its integrations write them:
# ~/.omp/agent/sessions, the sqlite databases, the credential vault, and
# extensions/ (herdr reinstalls its own file on every activation).
#
# Every module under modules/home/ is shared with terka@nixos via
# home-manager.sharedModules, so this one is scoped to tom.
{
  config,
  lib,
  ...
}:
let
  common = import ../../../lib/common { };
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
    # Written to ~/.omp/agent/config.yml as a read-only store symlink: OMP's
    # own /settings edits apply for the session but revert on the next rebuild,
    # so change settings here rather than in the TUI.
    programs.omp.settings = {
      providers.webSearchOrder = [ ];

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

      # Shared-memory bridge: read/write the homelab Honcho instance the
      # hermes-agent uses (workspace `hermes`, agent peer `omp`), over the
      # VPN-only ingress honcho.home.tomkoreny.com. See the file header and
      # homelab-services apps/services/honcho/README.md.
      ".omp/agent/tools/honcho.ts".source = ./agent/tools/honcho.ts;

      # Light-slot theme; see the comment above the definition.
      ".omp/agent/themes/${ompLatteTheme.name}.json".text = builtins.toJSON ompLatteTheme;

      # OMP shadows both of these with its own native files above; they carry
      # the same rules for sessions run through Claude Code and Codex directly.
      ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ./codex/AGENTS.md;
    };
  };
}
