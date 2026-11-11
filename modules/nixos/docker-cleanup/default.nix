# Docker keeps every image and build layer until told otherwise: 58 GiB of
# images here belonged to no container. Once a week, remove images that no
# container uses and build cache that nothing has used, both past an age limit.
#
# Containers and volumes are never touched. That is why this is not
# `virtualisation.docker.autoPrune`: it runs `docker system prune`, which also
# deletes stopped containers.
{
  config,
  lib,
  ...
}:
let
  cfg = config.tomkoreny.nixos.docker-cleanup;
  docker = lib.getExe' config.virtualisation.docker.package "docker";
in
{
  options.tomkoreny.nixos.docker-cleanup = {
    enable = lib.mkEnableOption "weekly removal of old unused Docker images and build cache";

    olderThan = lib.mkOption {
      type = lib.types.str;
      default = "720h";
      description = ''
        Age limit, as a Go duration. Docker records no last use for an image,
        so an image without a container goes once it was built this long ago.
        Build cache goes once it was last used this long ago.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.docker.enable;
        message = "tomkoreny.nixos.docker-cleanup needs virtualisation.docker.enable.";
      }
    ];

    systemd.services.docker-cleanup = {
      description = "Remove old unused Docker images and build cache";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      startAt = "weekly";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [
          "${docker} image prune --all --force --filter until=${cfg.olderThan}"
          "${docker} builder prune --all --force --filter until=${cfg.olderThan}"
        ];
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    # Run after the next boot when the machine was off at the weekly time.
    systemd.timers.docker-cleanup.timerConfig.Persistent = true;
  };
}
