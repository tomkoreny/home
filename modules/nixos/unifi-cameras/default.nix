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
  #   mute=yes             these are yard cameras; nine of them unmuted at once
  #                        is unusable. Muted rather than --no-audio so the
  #                        track is still there and `m` toggles it back on.
  mpvFlags = lib.concatStringsSep " " [
    "--profile=low-latency"
    "--hwdec=auto-safe"
    "--rtsp-transport=tcp"
    "--stream-lavf-o=tls_verify=0"
    "--no-terminal"
    "--force-window=immediate"
    "--mute=yes"
  ];

  camerasScript = pkgs.writeShellScriptBin "unifi-cam" ''
    set -uo pipefail

    SECRET=${lib.escapeShellArg secretPath}
    MPV=${lib.getExe pkgs.mpv}
    WOFI=${lib.getExe pkgs.wofi}
    NOTIFY=${lib.getExe pkgs.libnotify}
    JQ=${lib.getExe pkgs.jq}

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
      # (which contains the stream token). $3, when set, is the grid slot
      # index: it makes the title unique so the placement pass below can find
      # this exact window, and the "CameraGrid" prefix is what the float
      # window rule in main.lua keys on — single playback keeps the plain
      # "Camera: " title and so still tiles normally.
      if [ -n "''${3:-}" ]; then
        exec "$MPV" ${mpvFlags} --title="CameraGrid $3 $1" --force-media-title="$1" "$2"
      fi
      exec "$MPV" ${mpvFlags} --title="Camera: $1" --force-media-title="$1" "$2"
    }

    # Place a grid window by address. mpv's own --geometry is useless here:
    # Wayland clients cannot position themselves, and Hyprland ignored both the
    # size and the position (766x419+-1538+455 came out as 384x210 at
    # -1344,561). Asking the compositor directly is exact.
    place() {
      local addr="$1" w="$2" h="$3" x="$4" y="$5"
      hyprctl dispatch resizewindowpixel "exact $w $h,address:$addr" >/dev/null 2>&1
      hyprctl dispatch movewindowpixel   "exact $x $y,address:$addr" >/dev/null 2>&1
    }

    # Wait for the window carrying a given grid slot to map, and echo its
    # address. mpv has to negotiate the stream before it shows anything, so
    # this can take a couple of seconds per camera.
    await_window() {
      local tag="$1" addr="" tries=0
      while [ $tries -lt 60 ]; do
        addr=$(hyprctl clients -j 2>/dev/null \
          | "$JQ" -r --arg t "$tag" 'first(.[] | select(.title | startswith($t)) | .address) // empty')
        [ -n "$addr" ] && { printf '%s' "$addr"; return 0; }
        sleep 0.25
        tries=$((tries + 1))
      done
      return 1
    }

    # Logical geometry of the focused monitor, minus reserved space (waybar).
    # Falls back to empty, in which case the grid degrades to plain tiling.
    monitor_box() {
      command -v hyprctl >/dev/null 2>&1 || return 1
      hyprctl monitors -j 2>/dev/null | "$JQ" -r '
        ((map(select(.focused)) | .[0]) // .[0]) as $m
        | if $m == null then empty else
            # reserved is [left, top, right, bottom]
            ($m.width  / $m.scale | floor) as $w
          | ($m.height / $m.scale | floor) as $h
          | "\($m.x + $m.reserved[0]) \($m.y + $m.reserved[1]) \($w - $m.reserved[0] - $m.reserved[2]) \($h - $m.reserved[1] - $m.reserved[3])"
          end'
    }

    ALL_LABEL="▦  All cameras"
    if [ "''${1:-}" = "--list" ]; then
      printf '%s\n' "''${names[@]}"
      exit 0
    fi

    choice=""
    if [ "''${1:-}" = "--all" ]; then
      choice="$ALL_LABEL"
      shift
    fi

    # Non-interactive form: `unifi-cam [--slot N] <name>` skips the picker.
    # `--list` exposes names without stream URLs; `--all` launches the grid.
    # --slot tags windows created by the all-cameras fan-out.
    slot=""
    if [ "''${1:-}" = "--slot" ]; then
      slot="''${2:-}"
      shift 2
    fi

    if [ $# -gt 0 ] && [ -z "$choice" ]; then
      want="$*"
      for i in "''${!names[@]}"; do
        if [ "''${names[$i]}" = "$want" ]; then
          play "''${names[$i]}" "''${urls[$i]}" "$slot"
        fi
      done
      "$NOTIFY" -u critical "UniFi cameras" "No camera named: $want"
      exit 1
    fi

    if [ -z "$choice" ]; then
      # No icon prefix: the Protect camera names already carry their own emoji,
      # so a second one just doubles up. The All entry uses ▦ to stand apart.
      choice=$(
        {
          printf '%s\n' "''${names[@]}"
          printf '%s\n' "$ALL_LABEL"
        } | "$WOFI" --dmenu --prompt "Camera" --insensitive
      ) || exit 0
      [ -n "$choice" ] || exit 0
    fi

    if [ "$choice" = "$ALL_LABEL" ]; then
      # One mpv window per camera, explicitly positioned into an even grid.
      # Hyprland's dwindle would otherwise split recursively and give nine
      # wildly uneven panes; there is no grid layout to ask it for. Columns are
      # ceil(sqrt(n)) so the grid stays close to square at any camera count.
      n=''${#names[@]}

      # Start every stream first so they negotiate in parallel, then place
      # them. Placing as each one appears would serialise nine RTSP handshakes.
      for i in "''${!names[@]}"; do
        setsid "$0" --slot "$i" "''${names[$i]}" >/dev/null 2>&1 &
      done

      box=$(monitor_box) || box=""
      # No compositor to ask (or not running under Hyprland): the windows are
      # already up, just leave them wherever they landed.
      [ -n "$box" ] || exit 0
      read -r ox oy ow oh <<<"$box"

      cols=1; while [ $((cols * cols)) -lt "$n" ]; do cols=$((cols + 1)); done
      rows=$(( (n + cols - 1) / cols ))
      tw=$((ow / cols)); th=$((oh / rows))

      for i in "''${!names[@]}"; do
        addr=$(await_window "CameraGrid $i ") || continue
        place "$addr" "$tw" "$th" \
          "$((ox + (i % cols) * tw))" "$((oy + (i / cols) * th))"
      done
      exit 0
    fi

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
    enable = lib.mkEnableOption "UniFi Protect camera picker (launcher/wofi + mpv)";

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
