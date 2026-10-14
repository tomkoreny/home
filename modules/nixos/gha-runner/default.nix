{
  config,
  lib,
  pkgs,
  ...
}:
# Extra GitHub Actions runner for the TomAndTer org while this desktop is on.
#
# It registers with the `homelab` label, the same name as the ARC runner scale
# set in the homelab cluster (homelab-services: infrastructure/ci/github-runner),
# so `runs-on: homelab` jobs go to whichever runner is free first. When this
# machine is off, the homelab runner takes everything.
#
# It copies the shape of the homelab runner pod rather than running on NixOS
# directly: the workflows expect an Ubuntu runner (setup-python picks builds by
# Ubuntu version, build-essential for node-gyp, /cache), and their test jobs bind
# host ports 5432 and 9000, which the local vet-system dev stack already uses.
# So the runner image runs next to its own Docker-in-Docker daemon in a separate
# network namespace (`--network container:gha-runner-dind`). Jobs see neither
# the host's Docker nor its ports.
#
# The runner is ephemeral: it registers, takes one job and exits, and systemd
# starts a fresh registration. Registration tokens are minted from the same
# GitHub App that ARC uses, so nothing here expires.
#
# Docker data, the workspace and /cache persist in /var/lib/gha-runner, so
# builds reuse layers and checkouts the way the homelab runner does.
let
  cfg = config.tomkoreny.nixos.gha-runner;
  stateDir = "/var/lib/gha-runner";
  docker = lib.getExe' config.virtualisation.docker.package "docker";

  # Same base as homelab-services/services/github-runner/Dockerfile. Bump the
  # two together. The runner updates itself at registration when GitHub needs a
  # newer version, so a stale pin costs a download, not a broken runner.
  runnerDockerfileText = ''
    FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807
    USER root
    RUN apt-get update \
        && apt-get install -y --no-install-recommends build-essential \
        && rm -rf /var/lib/apt/lists/*
    USER runner
  '';
  runnerDockerfile = pkgs.writeTextDir "Dockerfile" runnerDockerfileText;
  # A new tag whenever the Dockerfile changes, so the start script rebuilds.
  runnerImage = "gha-runner-local:${
    builtins.substring 0 12 (builtins.hashString "sha256" runnerDockerfileText)
  }";
  dindImage = "docker:29.9-dind@sha256:0b6d18a4a222e71c88be6034926b4f6cde2fc33c2218643d03ccfddc65995470";

  # Same BuildKit cache caps as the homelab dind. Sizes must be absolute:
  # Docker parses them with units.RAMInBytes and rejects percentages.
  dindDaemonConfig = pkgs.writeText "gha-runner-dind-daemon.json" (
    builtins.toJSON {
      builder.gc = {
        enabled = true;
        defaultReservedSpace = "10GB";
        defaultMaxUsedSpace = "30GB";
        defaultMinFreeSpace = "60GB";
      };
    }
  );

  mintRegistrationToken = pkgs.writeShellApplication {
    name = "gha-mint-registration-token";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      openssl
    ];
    text = ''
      # Prints a runner registration token for org $ORG, authenticating as
      # GitHub App $APP_ID (installation $INSTALLATION_ID) with $APP_KEY_FILE.
      b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

      now=$(date +%s)
      header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
      payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$APP_ID" | b64url)
      signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$APP_KEY_FILE" -binary | b64url)

      installation_token=$(curl -fsS -X POST \
        -H "Authorization: Bearer $header.$payload.$signature" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" | jq -er .token)

      curl -fsS -X POST \
        -H "Authorization: Bearer $installation_token" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$ORG/actions/runners/registration-token" | jq -er .token
    '';
  };

  startRunner = pkgs.writeShellApplication {
    name = "gha-runner-start";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      mintRegistrationToken
    ];
    text = ''
      until docker exec gha-runner-dind docker info >/dev/null 2>&1; do
        sleep 2
      done

      if ! docker image inspect ${runnerImage} >/dev/null 2>&1; then
        # Anonymous pull: the base image is public, and a stale ghcr.io login
        # in a Docker config is rejected instead of ignored.
        mkdir -p "$RUNTIME_DIRECTORY/docker-config"
        DOCKER_CONFIG="$RUNTIME_DIRECTORY/docker-config" docker build -t ${runnerImage} ${runnerDockerfile}
      fi

      # Runner tooling that job containers mount, copied where dind can see it,
      # as the homelab pod's init-dind-externals container does. Only needed
      # again when the image changes.
      if [ "$(cat ${stateDir}/externals/.image 2>/dev/null || true)" != "${runnerImage}" ]; then
        docker run --rm --user 0:0 -v ${stateDir}/externals:/target ${runnerImage} \
          cp -r /home/runner/externals/. /target/
        echo "${runnerImage}" >${stateDir}/externals/.image
      fi

      token_file="$RUNTIME_DIRECTORY/registration-token"
      gha-mint-registration-token >"$token_file"
      # The runner reads it as uid 1001; the directory itself is root-only.
      chmod 0644 "$token_file"

      docker rm -f gha-runner >/dev/null 2>&1 || true
      # /var/run is a symlink to /run in the image, so the token goes under
      # /etc where the socket mount cannot cover it.
      exec docker run --rm --name gha-runner \
        --network container:gha-runner-dind \
        --memory 8g --cpus 12 \
        -v ${stateDir}/run:/var/run \
        -v ${stateDir}/work:/home/runner/_work \
        -v ${stateDir}/cache:/cache \
        -v "$token_file":/etc/gha-registration-token:ro \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -e ORG \
        -e RUNNER_NAME \
        ${runnerImage} \
        bash -c './config.sh --url "https://github.com/$ORG" --token "$(cat /etc/gha-registration-token)" --name "$RUNNER_NAME" --labels homelab --ephemeral --unattended --replace && exec ./run.sh'
    '';
  };
in
{
  options.tomkoreny.nixos.gha-runner = {
    enable = lib.mkEnableOption "an extra TomAndTer GitHub Actions runner with the homelab label";

    name = lib.mkOption {
      type = lib.types.str;
      default = "tom-pc";
      description = "Runner name shown in the org's runner list.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.gha-runner-app-key = {
      sopsFile = ../../../secrets/gha-runner/app-private-key.pem;
      format = "binary";
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "gha-runner.service" ];
    };

    # The runner image runs as uid 1001; it owns its workspace and /cache.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 root root -"
      "d ${stateDir}/docker 0710 root root -"
      "d ${stateDir}/run 0755 root root -"
      "d ${stateDir}/externals 0755 root root -"
      "d ${stateDir}/work 0755 1001 1001 -"
      "d ${stateDir}/cache 0755 1001 1001 -"
    ];

    systemd.services.gha-runner-dind = {
      description = "Docker-in-Docker daemon for the local GitHub Actions runner";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStartPre = "-${docker} rm -f gha-runner-dind";
        # The caps keep a Next.js build from starving the desktop.
        ExecStart = lib.concatStringsSep " " [
          "${docker} run --rm --name gha-runner-dind --privileged"
          "--memory 10g --cpus 12"
          "-v ${stateDir}/docker:/var/lib/docker"
          "-v ${stateDir}/work:/home/runner/_work"
          "-v ${stateDir}/run:/var/run"
          "-v ${stateDir}/externals:/home/runner/externals"
          "-v ${dindDaemonConfig}:/etc/docker/daemon.json:ro"
          "${dindImage}"
          "dockerd --host=unix:///var/run/docker.sock --group=123"
        ];
        Restart = "always";
        RestartSec = "10s";
      };
    };

    systemd.services.gha-runner = {
      description = "Ephemeral GitHub Actions runner for TomAndTer (label homelab)";
      after = [
        "gha-runner-dind.service"
        "network-online.target"
      ];
      requires = [ "gha-runner-dind.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        ORG = "TomAndTer";
        RUNNER_NAME = cfg.name;
        # Not secret: the App and installation the homelab ARC controller uses.
        APP_ID = "5100532";
        INSTALLATION_ID = "165570859";
        APP_KEY_FILE = config.sops.secrets.gha-runner-app-key.path;
      };
      serviceConfig = {
        ExecStart = lib.getExe startRunner;
        RuntimeDirectory = "gha-runner";
        RuntimeDirectoryMode = "0700";
        # An ephemeral runner exits after every job; register a fresh one.
        Restart = "always";
        RestartSec = "15s";
        # A job in progress gets this long to notice the stop and report back.
        TimeoutStopSec = "60s";
      };
    };
  };
}
