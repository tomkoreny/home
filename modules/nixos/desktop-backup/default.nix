# Nightly restic backup of this desktop to the homelab's MinIO (bucket `desktop`
# on the storage container). The homelab mirrors its buckets to Backblaze B2
# every night (homelab-services: clusters/proxmox-lab/proxmox/offsite-sync),
# and that mirror is the off-site copy.
#
# What goes in: every home directory, the Secure Boot keys, every named Docker
# volume, and dumps of the databases in running containers (dump-databases.sh).
#
# Restoring, as root:
#   restic-desktop snapshots
#   restic-desktop restore latest --target /tmp/restore --include /home/tom/some/path
#
# The repository password and the MinIO credentials are in
# secrets/restic/desktop.yaml. The password is the only way into the
# repository, so it also has to exist somewhere that is not this machine.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.desktop-backup;

  secretsFile = ../../../secrets/restic/desktop.yaml;
  stateDir = "/var/lib/desktop-backup";
  dumpDir = "${stateDir}/dumps";
  # In the unit's RuntimeDirectory, so it is gone once the run is over.
  dumpFailures = "/run/restic-backups-desktop/dump-failures";

  dumpDatabases = pkgs.writeShellApplication {
    name = "desktop-backup-dump-databases";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ./dump-databases.sh;
  };

  # Anonymous volumes are named by a 64-digit hash. Nothing refers to them by
  # name, so they are scratch space by construction.
  anonymousVolume = lib.concatStrings (lib.genList (_: "[0-9a-f]") 64);
in
{
  options.tomkoreny.nixos.desktop-backup = {
    enable = lib.mkEnableOption "the nightly restic backup of this desktop to the homelab";

    disposableVolumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "myproject_vendor" ];
      description = ''
        Named Docker volumes that are deliberately not backed up. Every other
        named volume is included, so a new compose project is covered without
        being listed anywhere.
      '';
    };

    keep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/home/tom/.cache/some-project" ];
      description = ''
        Entries directly inside an excluded cache directory that are backed up
        after all, for data that lives where caches normally do.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."desktop-backup/password" = {
      sopsFile = secretsFile;
      key = "password";
    };
    sops.secrets."desktop-backup/s3-env" = {
      sopsFile = secretsFile;
      key = "s3_env";
    };

    services.restic.backups.desktop = {
      # Plain HTTP on the private storage VLAN; restic encrypts everything
      # before it leaves this machine.
      repository = "s3:http://10.10.50.33:9000/desktop";
      initialize = true;
      passwordFile = config.sops.secrets."desktop-backup/password".path;
      environmentFile = config.sops.secrets."desktop-backup/s3-env".path;

      paths = [
        "/home"
        "/etc/secureboot"
        "/var/lib/docker/volumes"
        dumpDir
      ];

      # Only what can be downloaded or rebuilt again. Each entry names the
      # regenerable subdirectory itself, never a parent that also holds
      # something a person made: saves, generated images, volume data.
      exclude = [
        # Child by child, so that `keep` can bring one of them back.
        "/home/*/.cache/*"
        "/home/*/.npm"
        "/home/*/.bun/install/cache"
        "/home/*/.cargo/registry"
        "/home/*/.cargo/git"
        "/home/*/.rustup"
        "/home/*/.local/share/Trash"
        "/home/*/.local/share/pnpm/store"
        # IDE installations; settings live in ~/.config/JetBrains.
        "/home/*/.local/share/JetBrains/Toolbox/apps"
        # Steam: installed games, shader caches, workshop downloads and the
        # client's own runtimes. Saves and settings (userdata, config and the
        # Proton prefixes in steamapps/compatdata) stay in.
        "/home/*/.local/share/Steam/steamapps/common"
        "/home/*/.local/share/Steam/steamapps/shadercache"
        "/home/*/.local/share/Steam/steamapps/workshop"
        "/home/*/.local/share/Steam/steamapps/downloading"
        "/home/*/.local/share/Steam/steamapps/temp"
        "/home/*/.local/share/Steam/ubuntu12_32"
        "/home/*/.local/share/Steam/ubuntu12_64"
        "/home/*/.local/share/Steam/steamrt32"
        "/home/*/.local/share/Steam/steamrt64"
        "/home/*/.local/share/Steam/package"
        "/home/*/.local/share/Steam/appcache"
        "/home/*/.local/share/Steam/config/htmlcache"
        # Rootless Docker: image layers and build cache. Its volumes stay in.
        "/home/*/.local/share/docker/overlay2"
        "/home/*/.local/share/docker/image"
        "/home/*/.local/share/docker/buildkit"
        "/home/*/.local/share/docker/volumes/${anonymousVolume}"
        # Stable Diffusion: Python environments, cloned dependencies and base
        # checkpoints. Outputs, settings and locally trained models stay in.
        "/home/*/stable-diffusion-webui*/venv"
        "/home/*/stable-diffusion-webui*/repositories"
        "/home/*/stable-diffusion-webui*/models/Stable-diffusion"
        "node_modules"
        ".pnpm-store"
        ".next"
        # Browser and Electron caches inside otherwise wanted profiles.
        "/home/*/.config/**/Cache"
        "/home/*/.config/**/Code Cache"
        "/home/*/.config/**/GPUCache"
        "/home/*/.config/**/Service Worker/CacheStorage"
        "/var/lib/docker/volumes/${anonymousVolume}"
      ]
      ++ map (volume: "/var/lib/docker/volumes/${volume}") cfg.disposableVolumes
      # A negation has to follow the pattern it undoes.
      ++ map (path: "!${path}") cfg.keep;

      extraBackupArgs = [
        "--one-file-system"
        "--exclude-caches"
      ];

      # The dump script handles its own failures; `||` covers it crashing
      # outright. Either way the snapshot is still written.
      backupPrepareCommand = ''
        DUMP_DIR=${dumpDir} FAILURES=${dumpFailures} ${lib.getExe dumpDatabases} \
          || echo "the dump step itself" >> ${dumpFailures}
      '';

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
      runCheck = true;

      # After the homelab's own 01:00 backups have started, well before its
      # 05:00 mirror to B2. Persistent: a night the desktop was off is made up
      # at the next boot.
      timerConfig = {
        OnCalendar = "01:30";
        Persistent = true;
      };
    };

    systemd.services.restic-backups-desktop = {
      serviceConfig = {
        StateDirectory = "desktop-backup";
        # A catch-up run after a missed night happens while the desktop is in use.
        Nice = 10;
        IOSchedulingClass = "idle";

        # Runs after the snapshot, prune and check: a dump that failed must
        # not hide behind an otherwise successful run.
        ExecStart = lib.mkAfter [
          (pkgs.writeShellScript "desktop-backup-dump-result" ''
            if [ -s ${dumpFailures} ]; then
              echo "error: database dump failed for: $(${lib.getExe' pkgs.coreutils "paste"} -sd, ${dumpFailures})" >&2
              exit 1
            fi
          '')
        ];
      };

      # Same shape as /var/lib/nixos-upgrade-status/status.json, and read by
      # the Quickshell bar the same way, so a failing or missing backup is
      # visible instead of silently leaving the last snapshot to age.
      postStop = lib.mkAfter ''
        state=${stateDir}/status.json
        now=$(date +%s)
        last_success=$(${lib.getExe pkgs.jq} -r '.lastSuccessAt // 0' "$state" 2>/dev/null || echo 0)
        result=$SERVICE_RESULT
        error=""
        # Stopping a run by hand ends it with SERVICE_RESULT=success too.
        if [ "$result" = success ] && { [ "''${EXIT_CODE:-}" != exited ] || [ "''${EXIT_STATUS:-}" != 0 ]; }; then
          result=interrupted
        fi
        if [ "$result" = success ]; then
          last_success=$now
        else
          error=$(journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID="$INVOCATION_ID" \
            | grep -m1 -i -E '^(fatal|error):' | cut -c1-200 || true)
          [ -n "$error" ] || error="desktop backup ended with $SERVICE_RESULT (''${EXIT_CODE:-} ''${EXIT_STATUS:-})"
        fi
        ${lib.getExe pkgs.jq} -n \
          --arg result "$result" \
          --arg error "$error" \
          --argjson finishedAt "$now" \
          --argjson lastSuccessAt "$last_success" \
          '{result: $result, error: $error, finishedAt: $finishedAt, lastSuccessAt: $lastSuccessAt}' \
          > "$state.tmp"
        mv "$state.tmp" "$state"
      '';
    };
  };
}
