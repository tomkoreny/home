# Wofi picker that opens UniFi Protect camera streams in mpv.
#
# Why this exists: UniFi Protect's "Enhanced" recording profile is H.265/HEVC,
# and Helium (an ungoogled-chromium fork) ships no HEVC decoder — the binary has
# no PlatformHEVCDecoderSupport feature and no H265Decoder symbols, so no flag
# can enable it. Rather than downgrade every camera to H.264, play the streams
# outside the browser: mpv + NVDEC handles HEVC natively (vainfo advertises
# VAProfileHEVCMain through Main444_12 on this host).
#
# The camera list is sops-encrypted because each Protect RTSPS URL embeds a
# per-camera stream token — possession of the URL is possession of the stream.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.unifi-cameras;

  common = import ../../../lib/common { };

  secretName = "unifi-cameras";
  secretPath = "/run/secrets/${secretName}";

  # mpv tuned for a live camera feed rather than a media file:
  #   profile=low-latency  drop the demuxer/output buffering that adds seconds
  #   rtsp-transport=tcp   Protect's RTSPS is TLS over TCP; the UDP default
  #                        silently stalls behind NAT/firewalls
  #   tls_verify=0         the NVR presents a self-signed cert
  #   hwdec=auto-safe      NVDEC for HEVC, falling back rather than erroring
  mpvFlags = lib.concatStringsSep " " [
    "--profile=low-latency"
    "--hwdec=auto-safe"
    "--rtsp-transport=tcp"
    "--stream-lavf-o=tls_verify=0"
    "--no-terminal"
    "--force-window=immediate"
  ];

  camerasScript = pkgs.writeShellScriptBin "unifi-cam" ''
    set -uo pipefail

    SECRET=${lib.escapeShellArg secretPath}
    MPV=${lib.getExe pkgs.mpv}
    WOFI=${lib.getExe pkgs.wofi}
    NOTIFY=${lib.getExe pkgs.libnotify}

    if [ ! -r "$SECRET" ]; then
      "$NOTIFY" -u critical "UniFi cameras" \
        "No camera list at $SECRET. Populate secrets/unifi/cameras.conf with sops."
      exit 1
    fi

    # Format: one camera per line, "Display Name<TAB>rtsps://…".
    # Blank lines and #-comments are ignored so the decrypted file can be
    # annotated. Read into arrays rather than re-reading the secret per lookup.
    names=()
    urls=()
    while IFS=$'\t' read -r name url; do
      case "$name" in
        ""|"#"*) continue ;;
      esac
      [ -n "''${url:-}" ] || continue
      names+=("$name")
      urls+=("$url")
    done < "$SECRET"

    if [ ''${#names[@]} -eq 0 ]; then
      "$NOTIFY" -u critical "UniFi cameras" "Camera list is empty."
      exit 1
    fi

    play() {
      # Title the window after the camera so Hyprland window rules and the
      # waybar window module show something meaningful instead of the URL
      # (which contains the stream token).
      exec "$MPV" ${mpvFlags} --title="Camera: $1" --force-media-title="$1" "$2"
    }

    # Non-interactive form: `unifi-cam <name>` skips the picker. Used by the
    # "All cameras" fan-out below and handy for ad-hoc binds.
    if [ $# -gt 0 ]; then
      want="$*"
      for i in "''${!names[@]}"; do
        if [ "''${names[$i]}" = "$want" ]; then
          play "''${names[$i]}" "''${urls[$i]}"
        fi
      done
      "$NOTIFY" -u critical "UniFi cameras" "No camera named: $want"
      exit 1
    fi

    ALL_LABEL="▦  All cameras"
    choice=$(
      {
        printf '%s\n' "''${names[@]}" | ${pkgs.gnused}/bin/sed 's/^/🎥 /'
        printf '%s\n' "$ALL_LABEL"
      } | "$WOFI" --dmenu --prompt "Camera" --insensitive
    ) || exit 0
    [ -n "$choice" ] || exit 0

    if [ "$choice" = "$ALL_LABEL" ]; then
      # One mpv window per camera; Hyprland tiles them into a grid for us, so
      # there is no need for a mosaic filter or a second video tool.
      for i in "''${!names[@]}"; do
        setsid "$0" "''${names[$i]}" >/dev/null 2>&1 &
      done
      exit 0
    fi

    choice="''${choice#🎥 }"
    for i in "''${!names[@]}"; do
      if [ "''${names[$i]}" = "$choice" ]; then
        play "''${names[$i]}" "''${urls[$i]}"
      fi
    done
    exit 1
  '';
in
{
  options.tomkoreny.nixos.unifi-cameras = {
    enable = lib.mkEnableOption "UniFi Protect camera picker (wofi + mpv)";

    user = lib.mkOption {
      type = lib.types.str;
      default = common.user.name;
      description = "User that owns the decrypted camera list";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.mpv
      camerasScript
    ];

    # Whole-file secret: the list is a flat name/URL table, so there is nothing
    # to gain from per-key extraction, and binary format keeps `sops` editing
    # of the plaintext trivial.
    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/unifi/cameras.conf;
      format = "binary";
      owner = cfg.user;
      group = "users";
      mode = "0400";
      path = secretPath;
    };
  };
}
