# Backup of this Mac with restic to the homelab's MinIO (bucket `macos` on the
# storage container), the counterpart of modules/nixos/desktop-backup. The
# homelab mirrors its buckets to Backblaze B2 every night, and that mirror is
# the off-site copy.
#
# What goes in: /Users, minus what can be downloaded or rebuilt again (the
# exclude list below) and minus iCloud Drive, whose files macOS may keep
# online-only: reading one downloads it, and a backup would download them all.
#
# When: a laptop is not always home, and MinIO is on the home network. The
# controller runs every three hours and takes a snapshot when the last good
# one is older than 20 hours, the Mac is on mains power, and MinIO answers
# without a tunnel in between (the home tunnel rides on whatever uplink there
# is, often a phone's). Otherwise it does nothing and records nothing.
# SketchyBar shows `backup` when a run failed and `no backup` when none has
# succeeded for a week.
#
# Full Disk Access. macOS keeps Mail, Messages, Photos, other apps' data and
# more from every program without it, root included, and grants it to one
# exact program: a path and a code hash. So the snapshot is taken by
# upstream's release binary, pinned here and copied to a fixed path
# (resticPath), run as a launchd job of its own so that it is the program
# macOS judges. It needs the grant once, by hand: System Settings > Privacy &
# Security > Full Disk Access > +, then that file. A new `resticVersion` needs
# it again, which is why bump-pins.py only opens an issue for it. Without the
# grant the snapshot holds everything else, and the run counts as failed.
#
# Restoring, as root:
#   mac-backup-restic snapshots
#   mac-backup-restic restore latest --target /tmp/restore --include /Users/tom/some/path
#
# The repository password and the MinIO credentials are in
# secrets/restic/macos.yaml, encrypted to this Mac's key and to the NixOS
# desktop's, so losing the Mac does not lose the way into its backup.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.backup;
  common = import ../../../lib/common { };
  inherit (common.darwinBackup) log statusFile;

  secretsFile = ../../../secrets/restic/macos.yaml;
  minioHost = "10.10.50.33";
  minioPort = "9000";
  # Plain HTTP on the private storage VLAN; restic encrypts everything before
  # it leaves this machine.
  repository = "s3:http://${minioHost}:${minioPort}/macos";
  password = config.sops.secrets."mac-backup/password".path;
  s3Credentials = config.sops.secrets."mac-backup/s3-credentials".path;
  cacheDir = "/Library/Caches/mac-backup";

  resticVersion = "0.19.1";
  resticRelease = pkgs.fetchurl {
    url = "https://github.com/restic/restic/releases/download/v${resticVersion}/restic_${resticVersion}_darwin_arm64.bz2";
    hash = "sha256-e+ChRMzDd4gPKUIEqicdduS3lVS0KnURUdQlzm66wUM=";
  };
  # Unpacked and nothing else: the bytes, and with them the code hash macOS
  # ties the grant to, only change with resticVersion.
  resticBinary = pkgs.runCommand "restic-${resticVersion}-darwin-arm64" { } ''
    ${pkgs.bzip2}/bin/bunzip2 -c ${resticRelease} > $out
    chmod 755 $out
  '';
  # A store path would move with every nixpkgs bump and take the grant along.
  resticPath = "/usr/local/libexec/mac-backup/restic";
  snapshotLabel = "${config.launchd.labelPrefix}.mac-backup-snapshot";

  # Only what can be downloaded or rebuilt again. Each entry names the
  # regenerable directory itself, never a parent that also holds something a
  # person made.
  excludeFile = pkgs.writeText "mac-backup-exclude" (
    lib.concatLines (
      [
        # iCloud Drive and other cloud folders; Desktop and Documents are in
        # iCloud Drive on this Mac.
        "/Users/*/Library/Mobile Documents"
        "/Users/*/Library/CloudStorage"
        "/Users/*/Desktop"
        "/Users/*/Documents"
        "/Users/*/Library/Caches"
        "/Users/*/Library/Logs"
        # What Xcode builds or downloads again: build products, simulators,
        # device symbols, documentation. Its user data (key bindings,
        # provisioning profiles) and archives are in the same folder and stay.
        "/Users/*/Library/Developer/Xcode/DerivedData"
        "/Users/*/Library/Developer/Xcode/DocumentationCache"
        "/Users/*/Library/Developer/Xcode/* DeviceSupport"
        "/Users/*/Library/Developer/CoreSimulator"
        "/Users/*/Library/Developer/XCTestDevices"
        "/Users/*/Library/Containers/*/Data/Library/Caches"
        "/Users/*/.cache"
        "/Users/*/.Trash"
        "/Users/*/.npm"
        "/Users/*/.bun/install/cache"
        "/Users/*/.cargo/registry"
        "/Users/*/.cargo/git"
        "/Users/*/.rustup"
        "/Users/*/.gradle"
        "/Users/*/.pub-cache"
        "/Users/*/go/pkg"
        "/Users/*/Library/pnpm"
        "/Users/*/.local/share/pnpm"
        "/Users/*/.local/share/uv"
        "/Users/*/.ollama/models"
        # OrbStack's virtual disk and its mount of the machines inside it.
        "/Users/*/Library/Group Containers/HUAQ24HBR6.dev.orbstack"
        "/Users/*/OrbStack"
        # Installed programs and SDKs.
        "/Users/*/Applications"
        "/Users/*/flutter-sdk"
        "/Users/*/Library/Android"
        "/Users/*/Library/Application Support/Autodesk/webdeploy"
        "/Users/*/Library/Application Support/Steam/steamapps/common"
        "/Users/*/Library/Application Support/Steam/steamapps/shadercache"
        "/Users/*/Library/Application Support/Steam/steamapps/downloading"
        # Installers.
        "/Users/*/Downloads/*.dmg"
        "/Users/*/Downloads/*.pkg"
        "/Users/*/Downloads/*.iso"
        "node_modules"
        ".pnpm-store"
        ".next"
        # Browser and Electron caches inside otherwise wanted profiles.
        "/Users/*/Library/Application Support/**/Cache"
        "/Users/*/Library/Application Support/**/Code Cache"
        "/Users/*/Library/Application Support/**/GPUCache"
        "/Users/*/Library/Application Support/**/Service Worker/CacheStorage"
      ]
      ++ cfg.exclude
    )
  );

  # restic for everything but the snapshot: none of it reads the Mac's files,
  # so the nixpkgs build does.
  restic = pkgs.writeShellScriptBin "mac-backup-restic" ''
    export AWS_SHARED_CREDENTIALS_FILE=${s3Credentials}
    exec ${lib.getExe pkgs.restic} --repo ${repository} --password-file ${password} --cache-dir ${cacheDir} "$@"
  '';

  controller = pkgs.writeShellScript "mac-backup" ''
    set -u
    status=${statusFile}
    say() { echo "$(/bin/date '+%F %T') $*"; }

    now=$(/bin/date +%s)
    last_success=$(${lib.getExe pkgs.jq} -r '.lastSuccessAt // 0' "$status" 2>/dev/null || echo 0)
    # Not due, on battery, or not at home: nothing to do and nothing to record.
    [ $((now - last_success)) -ge $((20 * 3600)) ] || exit 0
    /usr/bin/pmset -g batt | /usr/bin/grep -q "AC Power" || exit 0
    interface=$(/sbin/route -n get ${minioHost} 2>/dev/null | /usr/bin/awk '/interface:/ { print $2 }')
    case "$interface" in "" | utun*) exit 0 ;; esac
    /usr/bin/curl -fsS -m 5 -o /dev/null http://${minioHost}:${minioPort}/minio/health/live 2>/dev/null || exit 0

    record() {
      local result=$1 error=$2 finished
      finished=$(/bin/date +%s)
      [ "$result" = success ] && last_success=$finished
      /bin/mkdir -p "$(/usr/bin/dirname "$status")"
      ${lib.getExe pkgs.jq} -n \
        --arg result "$result" \
        --arg error "$error" \
        --argjson finishedAt "$finished" \
        --argjson lastSuccessAt "$last_success" \
        '{result: $result, error: $error, finishedAt: $finishedAt, lastSuccessAt: $lastSuccessAt}' \
        > "$status.tmp"
      /bin/mv "$status.tmp" "$status"
    }
    # The first line restic wrote about a failure since this run began.
    offset=$(/usr/bin/stat -f %z ${log} 2>/dev/null || echo 0)
    first_error() {
      /usr/bin/tail -c "+$((offset + 1))" ${log} | /usr/bin/grep -m1 -i -E '^(fatal|error):' | /usr/bin/cut -c1-200
    }
    fail() {
      local error
      error=$(first_error)
      say "backup failed: $1"
      record failure "''${error:-$1}"
      exit 1
    }

    say "backup started"
    # A run cut short by a reboot leaves its lock in the repository; this
    # removes only locks whose process is gone.
    ${lib.getExe restic} unlock >/dev/null 2>&1

    # The snapshot is the other job, so that macOS judges resticPath itself.
    /bin/launchctl kickstart system/${snapshotLabel} || fail "the snapshot job could not be started"
    /bin/sleep 2
    while /bin/launchctl print system/${snapshotLabel} | /usr/bin/grep -q 'state = running'; do
      /bin/sleep 15
    done
    code=$(/bin/launchctl print system/${snapshotLabel} | /usr/bin/awk '/last exit code/ { print $5; exit }')
    # restic exits 3 when the snapshot was written but some files could not
    # be read, which without Full Disk Access is every run.
    case "$code" in
      0 | 3) ;;
      *) fail "restic backup exited with status $code" ;;
    esac

    ${lib.getExe restic} forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 \
      || fail "restic forget exited with status $?"
    ${lib.getExe restic} check || fail "restic check exited with status $?"

    if [ "$code" = 3 ]; then
      say "backup incomplete: some files could not be read"
      record failure "incomplete: $(first_error) (does ${resticPath} have Full Disk Access?)"
      exit 1
    fi
    say "backup finished"
    record success ""
  '';
in
{
  options.tomkoreny.darwin.backup = {
    enable = lib.mkEnableOption "the restic backup of this Mac to the homelab";

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/Users/tom/scratch" ];
      description = ''
        Further paths on this host that are not worth a backup, in restic's
        exclude syntax.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."mac-backup/password" = {
      sopsFile = secretsFile;
      key = "password";
    };
    sops.secrets."mac-backup/s3-credentials" = {
      sopsFile = secretsFile;
      key = "s3_credentials";
    };

    environment.systemPackages = [ restic ];

    # Executable by root alone, so that a program with Full Disk Access is not
    # there for everything else on the Mac to run; readable by all, because
    # System Settings has to read the file to add it.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      if ! /usr/bin/cmp -s ${resticBinary} ${resticPath}; then
        echo "installing restic ${resticVersion} at ${resticPath}; it needs Full Disk Access granted again" >&2
        /bin/mkdir -p "$(/usr/bin/dirname ${resticPath})"
        /usr/bin/install -m 0744 -o root -g wheel ${resticBinary} ${resticPath}
      fi
    '';

    # Started by the controller below, never on its own.
    launchd.daemons.mac-backup-snapshot.serviceConfig = {
      ProgramArguments = [
        resticPath
        "backup"
        "--repo"
        repository
        "--password-file"
        password
        "--cache-dir"
        cacheDir
        "--host"
        config.networking.hostName
        "--one-file-system"
        "--exclude-caches"
        "--exclude-file"
        "${excludeFile}"
        "/Users"
      ];
      EnvironmentVariables.AWS_SHARED_CREDENTIALS_FILE = s3Credentials;
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = log;
      StandardErrorPath = log;
    };

    launchd.daemons.mac-backup = {
      command = "${controller}";
      serviceConfig = {
        # Calendar slots, because macOS 27 parks StartInterval jobs (see
        # modules/darwin/auto-upgrade). A slot missed asleep runs at wake.
        StartCalendarInterval =
          map
            (hour: {
              Hour = hour;
              Minute = 20;
            })
            [
              0
              3
              6
              9
              12
              15
              18
              21
            ];
        RunAtLoad = false;
        StandardOutPath = log;
        StandardErrorPath = log;
      };
    };

    # Both jobs start anew for every run, so newsyslog can rotate between runs.
    system.newsyslog = {
      enable = true;
      files.mac-backup = [
        {
          logfilename = log;
          mode = "644";
          count = 3;
          # In kilobytes.
          size = "10240";
          flags = [ "Z" ];
        }
      ];
    };
  };
}
