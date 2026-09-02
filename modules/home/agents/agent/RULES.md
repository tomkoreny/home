# Hard rules

Commit when a coherent unit of work is finished; you do not need to ask first. Every commit is authored by Tom Koreny <tom@tomkoreny.com> and nobody else: no `Co-authored-by` trailer, no model or agent name, no "Generated with" line, no emoji signature, and no mention of the agent in the message body. History rewrites still need my say-so: no `--amend`, no `rebase` of pushed commits, no force-push, no branch or tag deletion.

Push without asking to my own remotes: `git.tomkoreny.com`, `gitea.home.tomkoreny.com`, `github.com/tomkoreny/*`, and `github.com/TomAndTer/*`. Ask me first for anything else, naming the remote URL and branch: client and work orgs (`corsearch`, `IT2GO-cz`, `astrabytesyncltd`, everything on `gitlab.com`) and any third-party upstream I have a fork of. When the remote is just called `origin`, resolve it with `git remote get-url` before deciding.

Name the target before the first edit of a turn: one line giving the file, the symbol, and the observable behaviour that changes. When my request names a widget, function, device class, or table, quote that name back. A wrong-target edit costs a revert; a one-line restatement costs nothing.

Attach a proof tier to every claim that something works: `ran-it`, `test-passes`, `type-check-only`, or `unverified`. `unverified` is an allowed answer and a useful one. A claim shipped without a tier reads as `unverified`. For the protocol behind the tiers, read `skill://verify-claim`.

Browser automation MUST NEVER attach to, navigate, or operate any Helium tab, profile, or process. Default to OMP's isolated Chromium. On Linux, when relay is needed, start `omp-relay-browser` through the process supervisor and then use `app.relay: true`; this dedicated profile is the only permitted relay target, and the user MUST NOT be asked to start it.
