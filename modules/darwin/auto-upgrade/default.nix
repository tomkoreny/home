{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.auto-upgrade;
  common = import ../../../lib/common { };
  homeDir = common.user.homeDir { isDarwin = true; };
  inherit (common.darwinAutoUpgrade) log statusFile;
  # darwin-rebuild via the persistent system profile: /run/current-system is
  # volatile on macOS. Must match the sudoers rule below.
  darwinRebuild = "/nix/var/nix/profiles/system/sw/bin/darwin-rebuild";
  # Determinate's own program, installed by its package outside the store.
  # Must match the sudoers rule below.
  determinateNixd = "/usr/local/bin/determinate-nixd";
  # The agent starts the script through the same persistent profile instead of
  # its store path. nix-darwin reloads a user agent whenever its plist changes,
  # and the script's store path changed with every nixpkgs bump, so the switch
  # this agent ran unloaded the agent itself: launchd killed the activation
  # mid-way, the agent stayed unloaded, and the run was never recorded
  # (2026-10-23). With a fixed path the plist only changes when serviceConfig
  # does.
  upgradeCommand = "/nix/var/nix/profiles/system/sw/bin/darwin-auto-upgrade";

  # Pull the configuration CI has already validated, then activate it. Flake
  # inputs are bumped by .github/workflows/update-flake.yml, never here: this
  # machine cannot evaluate the NixOS host, so a lock it bumped locally would be
  # half-validated. Operating on the same checkout nh uses means "what's
  # running" is "what you edit".
  #
  # Each finished run's outcome lands in statusFile in the same shape as the
  # NixOS recorder (systems/x86_64-linux/nixos), and SketchyBar shows a warning
  # when the last run failed or none has finished for a day. Skipped runs
  # (dirty checkout, no network) are not recorded, so a checkout left dirty or
  # a Mac kept offline surfaces through that staleness check instead of
  # flashing as a failure.
  upgradeScript = pkgs.writeShellScriptBin "darwin-auto-upgrade" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.git
        pkgs.curl
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
      ]
    }:${homeDir}/.nix-profile/bin:/etc/profiles/per-user/${common.user.name}/bin:/nix/var/nix/profiles/system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export GIT_TERMINAL_PROMPT=0

    REPO_PATH=${lib.escapeShellArg cfg.repoPath}

    # launchd runs at most one instance of this agent, so no lock is needed;
    # a mkdir lock left by a killed run used to block every later run.
    run_log=""
    trap 'rm -f "$run_log"' EXIT
    if [ ! -d "$REPO_PATH/.git" ]; then
      echo "auto-upgrade: no git checkout at $REPO_PATH" >&2
      exit 1
    fi

    cd "$REPO_PATH"

    # Never touch a dirty checkout — this is the repo the user edits. Exit
    # non-zero so the skip is visible in launchctl instead of silent.
    if [ -n "$(git status --porcelain)" ]; then
      echo "auto-upgrade: $REPO_PATH has local changes; skipping" >&2
      exit 1
    fi

    # launchd fires the slots missed while asleep on the next wake, including
    # the few seconds of a dark wake, before the network is back, and git then
    # failed with "Could not resolve host: github.com" (six runs on
    # 2026-10-23). Retry GitHub every 10 seconds for two minutes, then skip
    # without recording a failure. The deadline, not an attempt count, bounds
    # the wait, because each probe itself can take up to 10 seconds. Only
    # "cannot resolve", "cannot connect" and timeout (curl exits 6, 7, 28)
    # count as offline; any other error goes on to the real pull so it is
    # reported.
    deadline=$((SECONDS + 120))
    while :; do
      net=0
      curl --silent --head --output /dev/null --connect-timeout 5 --max-time 10 \
        https://github.com || net=$?
      case "$net" in
        6 | 7 | 28) ;;
        *) break ;;
      esac
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "auto-upgrade: github.com unreachable (curl exit $net); skipping" >&2
        exit 0
      fi
      sleep 10
    done

    record_status() {
      local state=${lib.escapeShellArg statusFile} status=$1 now last_success error="" result=success
      mkdir -p "$(dirname "$state")"
      now="$(date +%s)"
      last_success="$(jq -r '.lastSuccessAt // 0' "$state" 2>/dev/null || echo 0)"
      if [ "$status" -eq 0 ]; then
        last_success="$now"
      else
        result=failure
        # Nix and git report the root failure first, Homebrew as "Error:";
        # drop store hashes so the line fits the bar.
        error="$(grep -m1 -iE '^[[:space:]]*error:' "$run_log" \
          | sed -E 's/^[[:space:]]*//; s|/nix/store/[a-z0-9]{32}-||g' || true)"
        [ -n "$error" ] || error="auto-upgrade exited with status $status"
      fi
      jq -n \
        --arg result "$result" \
        --arg error "$error" \
        --argjson finishedAt "$now" \
        --argjson lastSuccessAt "$last_success" \
        '{result: $result, error: $error, finishedAt: $finishedAt, lastSuccessAt: $lastSuccessAt}' \
        > "$state.tmp"
      mv "$state.tmp" "$state"
    }

    echo "auto-upgrade: $(date '+%F %T') adopting the configuration on origin/main..."
    run_log="$(mktemp "''${TMPDIR:-/tmp}/auto-upgrade-run.XXXXXX")"
    set +e
    "$REPO_PATH/scripts/update-home.sh" 2>&1 | tee "$run_log"
    status=''${PIPESTATUS[0]}
    # Determinate Nix comes from its installer package and nothing else moves
    # it: it sat at 3.21.0 from May to November 2026, past the security fix in
    # 3.24.1. Its `version` says when a newer release is advised; installing
    # it needs root, which the sudoers rule below allows for this one command.
    # A failed upgrade fails the run, so the bar shows it.
    determinate="$(${determinateNixd} version 2>/dev/null)"
    if [ "$status" -eq 0 ] && [[ "$determinate" == *"new version of Determinate Nix is available"* ]]; then
      echo "auto-upgrade: upgrading Determinate Nix..."
      /usr/bin/sudo -n ${determinateNixd} upgrade 2>&1 | tee -a "$run_log"
      status=''${PIPESTATUS[0]}
      if [ "$status" -ne 0 ]; then
        echo "error: determinate-nixd upgrade exited with status $status" | tee -a "$run_log"
      fi
    fi
    set -e
    record_status "$status"
    exit "$status"
  '';
in
{
  options.tomkoreny.darwin.auto-upgrade = {
    enable = lib.mkEnableOption "periodic pull of the CI-validated configuration and system/Home Manager rebuild";

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/home";
      description = "Git checkout to pull and rebuild (the same one nh uses)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Let the (non-root) launchd agent activate the rebuilt system and upgrade
    # Determinate Nix without a password. The first is root-equivalent, not a
    # narrow grant: darwin-rebuild activates whatever configuration it is
    # pointed at as root, so anyone running as this user can run arbitrary
    # code as root. The second allows only that one subcommand.
    environment.etc."sudoers.d/darwin-rebuild".text = ''
      ${common.user.name} ALL=(ALL) NOPASSWD: ${darwinRebuild}
      ${common.user.name} ALL=(ALL) NOPASSWD: ${determinateNixd} upgrade
    '';

    environment.systemPackages = [ upgradeScript ];

    # Every run appends its whole pull, check and switch output, and nothing
    # trimmed the file: 235 MB by November 2026. launchd opens it anew for
    # each run, so newsyslog can rotate it between runs.
    system.newsyslog = {
      enable = true;
      files.auto-upgrade = [
        {
          logfilename = log;
          owner = common.user.name;
          group = "staff";
          mode = "644";
          count = 3;
          # In kilobytes.
          size = "10240";
          flags = [ "Z" ];
        }
      ];
    };

    launchd.user.agents.auto-upgrade = {
      command = upgradeCommand;
      serviceConfig = {
        # Every 30 minutes, on the hour and half hour. Not StartInterval: on
        # macOS 27 launchd parks StartInterval agents at "pended nondemand
        # spawn = interval" and never starts them (this agent went five days
        # without a run), while calendar-scheduled agents fire normally.
        StartCalendarInterval = [
          { Minute = 0; }
          { Minute = 30; }
        ];
        RunAtLoad = false;
        StandardOutPath = log;
        StandardErrorPath = log;
      };
    };
  };
}
