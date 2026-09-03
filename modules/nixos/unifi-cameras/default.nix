# Launcher backend that discovers UniFi Protect cameras and opens streams in mpv.
#
# Why this exists: UniFi Protect's "Enhanced" recording profile is H.265/HEVC,
# and Helium (an ungoogled-chromium fork) ships no HEVC decoder — the binary has
# no PlatformHEVCDecoderSupport feature and no H265Decoder symbols, so no flag
# can enable it. Rather than downgrade every camera to H.264, play the streams
# outside the browser: mpv + NVDEC handles HEVC natively (vainfo advertises
# VAProfileHEVCMain through Main444_12 on this host).
#
# Camera inventory and RTSPS URLs come from Protect's local Integration API.
# Its console URL and API key are sops-encrypted; stream tokens stay ephemeral.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.unifi-cameras;

  common = import ../../../lib/common { };

  secretName = "unifi-protect-api-key";
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
    API_BASE=""
    API_KEY=""
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/unifi-cameras"
    CACHE="$CACHE_DIR/connected.json"
    CURL=${lib.getExe pkgs.curl}
    JQ=${lib.getExe pkgs.jq}
    MPV=${lib.getExe pkgs.mpv}
    NOTIFY=${lib.getExe pkgs.libnotify}

    notify_error() {
      "$NOTIFY" -u critical "UniFi cameras" "$1"
    }

    load_config() {
      if [ ! -r "$SECRET" ] || [ ! -s "$SECRET" ]; then
        notify_error "No Protect API configuration at $SECRET."
        return 1
      fi
      if ! API_BASE=$(
        "$JQ" -er '.url | select(type == "string" and length > 0) | rtrimstr("/")' "$SECRET"
      ) || ! API_KEY=$(
        "$JQ" -er '.apiKey | select(type == "string" and length > 0)' "$SECRET"
      ); then
        notify_error "The Protect API configuration is invalid."
        return 1
      fi
    }

    api() {
      local method="$1" path="$2"
      shift 2
      "$CURL" \
        --silent \
        --show-error \
        --fail-with-body \
        --insecure \
        --connect-timeout 2 \
        --max-time 10 \
        --request "$method" \
        --header @<(printf 'X-API-KEY: %s\n' "$API_KEY") \
        "$@" \
        "$API_BASE$path"
    }

    refresh_inventory() {
      local temporary
      load_config || return 1
      install -d -m 700 "$CACHE_DIR"
      temporary=$(mktemp "$CACHE_DIR/connected.json.XXXXXX")

      if api GET "/v1/cameras" \
        | "$JQ" -ce '
            [
              .[]
              | select(
                  .state == "CONNECTED"
                  and (.name | type == "string")
                  and (.name | length > 0)
                )
              | { id, name }
            ]
            | sort_by(.name)
          ' >"$temporary"
      then
        chmod 600 "$temporary"
        mv -f "$temporary" "$CACHE"
        return 0
      fi

      rm -f "$temporary"
      if [ -r "$CACHE" ] && "$JQ" -e 'type == "array"' "$CACHE" >/dev/null 2>&1; then
        printf 'Protect inventory refresh failed; using cached cameras.\n' >&2
        return 0
      fi

      notify_error "Could not read cameras from Protect."
      return 1
    }

    ensure_inventory() {
      if [ -r "$CACHE" ] && "$JQ" -e 'type == "array"' "$CACHE" >/dev/null 2>&1; then
        return 0
      fi
      refresh_inventory
    }

    camera_name() {
      "$JQ" -r --arg id "$1" \
        'first(.[] | select(.id == $id) | .name) // empty' "$CACHE"
    }

    stream_url() {
      local id="$1" response url
      case "$id" in
        ""|*[!a-zA-Z0-9_-]*)
          notify_error "Protect returned an invalid camera ID."
          return 1
          ;;
      esac

      if ! response=$(api GET "/v1/cameras/$id/rtsps-stream"); then
        notify_error "Could not read the camera stream from Protect."
        return 1
      fi
      url=$(printf '%s' "$response" | "$JQ" -r '.high // empty') || return 1
      if [ -n "$url" ]; then
        printf '%s' "$url"
        return 0
      fi

      if ! response=$(api POST "/v1/cameras/$id/rtsps-stream" \
        --json '{"qualities":["high"]}')
      then
        notify_error "Could not enable the camera's high-quality stream."
        return 1
      fi
      url=$(printf '%s' "$response" | "$JQ" -er '.high') || {
        notify_error "Protect did not return a high-quality stream."
        return 1
      }
      printf '%s' "$url"
    }

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

    play_camera() {
      local id="$1" name url
      load_config || return 1
      ensure_inventory || return 1
      name=$(camera_name "$id")
      if [ -z "$name" ]; then
        notify_error "The selected camera is no longer connected."
        return 1
      fi
      url=$(stream_url "$id") || return 1
      play "$name" "$url"
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

    launch_all() {
      local box="" n cols rows tw th addr name url
      local -a ids names urls
      refresh_inventory || return 1
      mapfile -t ids < <("$JQ" -r '.[].id' "$CACHE")
      if [ "''${#ids[@]}" -eq 0 ]; then
        notify_error "No connected cameras."
        return 1
      fi

      # Protect rate-limits simultaneous Integration API calls. Resolve streams
      # sequentially with a short gap, then let mpv negotiate them in parallel.
      for id in "''${ids[@]}"; do
        name=$(camera_name "$id")
        url=$(stream_url "$id") || continue
        names+=("$name")
        urls+=("$url")
        sleep 0.3
      done
      n=''${#urls[@]}
      if [ "$n" -eq 0 ]; then
        notify_error "No camera streams are available."
        return 1
      fi

      for i in "''${!urls[@]}"; do
        (play "''${names[$i]}" "''${urls[$i]}" "$i") >/dev/null 2>&1 &
      done

      box=$(monitor_box) || box=""
      # No compositor to ask (or not running under Hyprland): the windows are
      # already up, just leave them wherever they landed.
      [ -n "$box" ] || return 0
      read -r ox oy ow oh <<<"$box"

      cols=1; while [ $((cols * cols)) -lt "$n" ]; do cols=$((cols + 1)); done
      rows=$(( (n + cols - 1) / cols ))
      tw=$((ow / cols)); th=$((oh / rows))

      for i in "''${!urls[@]}"; do
        addr=$(await_window "CameraGrid $i ") || continue
        place "$addr" "$tw" "$th" \
          "$((ox + (i % cols) * tw))" "$((oy + (i / cols) * th))"
      done
      return 0
    }

    case "''${1:-}" in
      --list)
        refresh_inventory || exit 1
        "$JQ" -c . "$CACHE"
        ;;
      --all)
        launch_all
        ;;
      "")
        printf 'usage: unifi-cam --list|--all|CAMERA_ID\n' >&2
        exit 2
        ;;
      *)
        [ $# -eq 1 ] || {
          printf 'usage: unifi-cam CAMERA_ID\n' >&2
          exit 2
        }
        play_camera "$1"
        ;;
    esac
  '';
in
{
  options.tomkoreny.nixos.unifi-cameras = {
    enable = lib.mkEnableOption "UniFi Protect camera launcher backend";

    user = lib.mkOption {
      type = lib.types.str;
      default = common.user.name;
      description = "User allowed to read the decrypted Protect API configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.mpv
      camerasScript
    ];

    # Connection URL and API key. The script passes the key to curl through a
    # header file descriptor, never a command-line argument or process listing.
    sops.secrets.${secretName} = {
      sopsFile = ../../../secrets/unifi/protect-api-key;
      format = "binary";
      owner = cfg.user;
      group = "users";
      mode = "0400";
      path = secretPath;
    };
  };
}
