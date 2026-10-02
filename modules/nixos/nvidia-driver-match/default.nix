{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.nvidia-driver-match;
  installed = config.hardware.nvidia.package.version;
in
{
  options.tomkoreny.nixos.nvidia-driver-match = {
    enable = lib.mkEnableOption "keeping GPU libraries on the loaded NVIDIA module's version until reboot";
  };

  # A switch that bumps the NVIDIA driver repoints /run/opengl-driver at the new
  # userspace libraries, but the running kernel keeps the old module until
  # reboot. NVIDIA's libraries refuse a module of a different version, so every
  # app started afterwards silently falls back to CPU rendering. While the
  # versions differ, point the driver links back at the booted system's set,
  # which matches the loaded module. After a reboot the versions agree and this
  # does nothing.
  config = lib.mkIf cfg.enable {
    systemd.services.nvidia-driver-match = {
      description = "Match GPU userspace libraries to the loaded NVIDIA module";
      wantedBy = [ "multi-user.target" ];
      # tmpfiles re-setup reruns on switches that change any tmpfiles rule and
      # re-creates the links to the new drivers; PartOf reruns this after it.
      after = [ "systemd-tmpfiles-resetup.service" ];
      partOf = [ "systemd-tmpfiles-resetup.service" ];
      restartTriggers = [ installed ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.coreutils
        pkgs.gnugrep
        config.systemd.package
      ];
      script = ''
        loaded=$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' /proc/driver/nvidia/version | head -n 1 || true)
        if [ -z "$loaded" ] || [ "$loaded" = "${installed}" ]; then
          echo "NVIDIA module ''${loaded:-not loaded} matches installed ${installed}; nothing to do"
          exit 0
        fi
        booted=/run/booted-system/etc/tmpfiles.d/graphics-driver.conf
        if [ ! -e "$booted" ]; then
          echo "loaded NVIDIA module $loaded differs from ${installed}, but $booted is missing" >&2
          exit 1
        fi
        systemd-tmpfiles --create "$booted"
        if [ ! -e "/run/opengl-driver/lib/libnvidia-glcore.so.$loaded" ]; then
          echo "booted system's drivers do not provide $loaded either; apps will render on CPU until reboot" >&2
          exit 1
        fi
        echo "loaded NVIDIA module $loaded differs from installed ${installed}; using the booted system's drivers until reboot"
      '';
    };
  };
}
