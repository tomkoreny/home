{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.ssh = {
    enable = true;

    # Suppress deprecation warning about default values
    enableDefaultConfig = false;

    matchBlocks = {
      # Restore useful defaults for all hosts
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
        };
      };

      "proxmox" = {
        hostname = "192.168.1.2";
        user = "root";
      };

      "docker-host" = {
        hostname = "192.168.1.93";
        user = "root";
      };

      "nixos-desktop" = {
        hostname = "192.168.5.201";
        user = "tom";
      };

      "lempls" = {
        hostname = "lempls.com";
        user = "puma";
      };

      "tom-server teplice-ec2" = {
        hostname = "ec2-35-159-178-203.eu-central-1.compute.amazonaws.com";
        user = "ec2-user";
        identityFile = "~/Downloads/tom-mac.pem";
        identitiesOnly = true;
      };

      "server-178" = {
        hostname = "178.22.117.90";
        user = "tom151";
        port = 32479;
        proxyJump = "tom-server";
      };

      "hexpol-camera internal-10-104-128-2" = {
        hostname = "10.104.128.2";
        user = "tom151";
        proxyJump = "server-178";
      };

      "hexpol-camera-8080 internal-10-104-128-2-8080" = {
        hostname = "178.22.117.90";
        user = "tom151";
        port = 32479;
        proxyJump = "tom-server";
        localForwards = [
          {
            bind.address = "127.0.0.1";
            bind.port = 8080;
            host.address = "10.104.128.2";
            host.port = 8080;
          }
        ];
        extraOptions = {
          ExitOnForwardFailure = "yes";
        };
      };

      "gitlab-tom151" = {
        hostname = "gitlab.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519_gitlab_tom151";
        identitiesOnly = true;
        extraOptions = {
          ControlMaster = "no";
          ControlPath = "none";
        };
      };

      "hbc-server" = {
        hostname = "185.156.39.202";
        user = "tech1";
        port = 33894;
      };
    };

    extraConfig = ''
      ControlMaster auto
      ControlPath ~/.ssh/sockets/%C
      ControlPersist 600

      Compression yes
      ServerAliveInterval 60
      ServerAliveCountMax 10

      Include ~/.orbstack/ssh/config
    '';
  };

  home.file.".ssh/sockets/.keep" = {
    text = "";
  };
}
