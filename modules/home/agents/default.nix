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
      theme = {
        dark = "titanium";
        light = "light";
      };
      # Suppresses the onboarding wizard; do not drop this when editing above.
      setupVersion = 1;
    };

    # Files are listed one by one rather than as directory symlinks: an
    # existing imperative directory is not covered by
    # home-manager.backupFileExtension, while an individual file is, so the
    # first switch renames the current copies to *.hm-bak instead of failing.
    home.file = {
      ".omp/agent/AGENTS.md".source = ./agent/AGENTS.md;
      ".omp/agent/RULES.md".source = ./agent/RULES.md;
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

      # OMP shadows both of these with its own native files above; they carry
      # the same rules for sessions run through Claude Code and Codex directly.
      ".claude/CLAUDE.md".source = ./claude/CLAUDE.md;
      ".codex/AGENTS.md".source = ./codex/AGENTS.md;
    };
  };
}
