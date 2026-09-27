# Mac half of OMP voice over herdr (see common.ompVoice). OMP running on
# NixOS opens its microphone and speaker streams through PulseAudio; these
# agents give it a PulseAudio server on the Mac, which ~/.ssh/config forwards
# to NixOS while herdr is attached (modules/home/ssh).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
  inherit (common.ompVoice) macRuntimeDir;
  logDir = "${config.home.homeDirectory}/Library/Logs";

  # Serves only the forwarded clients: no default.pa, CoreAudio devices, and
  # the unix socket PulseAudio creates in its 0700 runtime dir. Anonymous auth
  # because the NixOS client carries its own cookie; the directory mode is the
  # access control. Shared memory is off because the peer is another machine:
  # libpulse sees a unix socket, assumes a local server, and otherwise loses
  # most capture blocks to failed shm_open() calls. Suspend-on-idle closes the
  # CoreAudio devices within a second of the last stream, so the microphone is
  # only open while OMP actually records.
  pulseConfig = pkgs.writeText "omp-voice-pulse.pa" ''
    load-module module-coreaudio-detect
    load-module module-native-protocol-unix auth-anonymous=1
    load-module module-suspend-on-idle timeout=1
  '';

  # module-coreaudio-detect makes the first device it enumerates the default
  # (the iPhone Continuity microphone, when it is around) and never follows
  # the macOS default. OMP records from the default source, so mirror the
  # macOS default input and output onto PulseAudio, matching on the CoreAudio
  # device name PulseAudio stores in device.string. The text listing is parsed
  # because `pactl --format=json` rejects non-ASCII device names such as
  # "T📱 Microphone" and would drop exactly those devices.
  followDefaults = pkgs.writeShellApplication {
    name = "omp-voice-pulse-follow";
    runtimeInputs = [
      pkgs.gawk
      pkgs.pulseaudio
      pkgs.switchaudio-osx
    ];
    text = ''
      export PULSE_SERVER=unix:${macRuntimeDir}/native

      follow() {
        local kind=$1 macos_type=$2 wanted name current
        wanted=$(SwitchAudioSource -c -t "$macos_type") || return 0
        name=$(pactl list "''${kind}s" | WANTED="device.string = \"$wanted\"" awk '
          /^[^[:space:]]/ { name = "" }
          { line = $0; sub(/^[[:space:]]+/, "", line) }
          line ~ /^Name: / { name = substr(line, 7) }
          line == "device.class = \"sound\"" { sound[name] = 1 }
          line == ENVIRON["WANTED"] { found[name] = 1 }
          END { for (n in found) if (n in sound) { print n; exit } }') || return 0
        [[ -n "$name" ]] || return 0
        current=$(pactl "get-default-$kind") || return 0
        if [[ "$current" != "$name" ]]; then
          pactl "set-default-$kind" "$name" || true
        fi
      }

      while true; do
        follow source input
        follow sink output
        sleep 2
      done
    '';
  };
in
{
  config = lib.mkIf (pkgs.stdenv.hostPlatform.isDarwin && config.home.username == "tom") {
    launchd.agents = {
      # PulseAudio is the job's own executable: that is the configuration
      # verified to receive real microphone samples from CoreAudio, not the
      # all-zero buffers macOS hands to a process without microphone access.
      omp-voice-pulse = {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe' pkgs.pulseaudio "pulseaudio")
            "--daemonize=no"
            "--exit-idle-time=-1"
            "--disable-shm=yes"
            "--realtime=no"
            "--high-priority=no"
            "-n"
            "-F"
            "${pulseConfig}"
          ];
          EnvironmentVariables.PULSE_RUNTIME_PATH = macRuntimeDir;
          KeepAlive = true;
          RunAtLoad = true;
          ProcessType = "Interactive";
          StandardErrorPath = "${logDir}/omp-voice-pulse.log";
        };
      };

      omp-voice-pulse-follow = {
        enable = true;
        config = {
          ProgramArguments = [ (lib.getExe followDefaults) ];
          KeepAlive = true;
          RunAtLoad = true;
          StandardErrorPath = "${logDir}/omp-voice-pulse-follow.log";
        };
      };
    };
  };
}
