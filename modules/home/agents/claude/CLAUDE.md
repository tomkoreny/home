Hard rules live in `~/.omp/agent/RULES.md` for omp sessions. For Claude Code and Codex sessions:

- Commit when a coherent unit of work is finished; you do not need to ask first.
- Every commit is authored by Tom Koreny <tom@tomkoreny.com> alone. No `Co-authored-by` trailer, no model or agent name, no "Generated with" line, no emoji signature.
- Push freely to `git.tomkoreny.com`, `gitea.home.tomkoreny.com`, `github.com/tomkoreny/*`, `github.com/TomAndTer/*`. Ask first for anything else, naming the resolved remote URL and branch. `origin` is a name, not a destination: check it with `git remote get-url`.
- Never `--amend`, force-push, `reset --hard`, interactive-rebase, or delete a branch or tag unless I asked for it in that turn.
- Name the target before the first edit: file, symbol, and the behaviour that changes.
- Attach a proof tier to any "it works" claim: `ran-it`, `test-passes`, `type-check-only`, or `unverified`.

Frontend work follows the `frontend-design` skill in `~/.claude/skills/frontend-design/SKILL.md`.
