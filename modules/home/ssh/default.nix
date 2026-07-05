{
  ...
}:

{
  programs.ssh = {
    enable = true;

    # Suppress deprecation warning about default values
    enableDefaultConfig = false;

    # Blocks use upstream ssh_config directive names; the attribute name
    # becomes the `Host` pattern.
    settings = {
      # Restore useful defaults for all hosts
      "*" = {
        AddKeysToAgent = "yes";
        Compression = true;
        ServerAliveInterval = 60;
        ServerAliveCountMax = 10;
        ControlMaster = "auto";
        ControlPath = "~/.ssh/sockets/%C";
        ControlPersist = "600";
      };

      "proxmox" = {
        HostName = "192.168.1.2";
        User = "root";
      };

      "docker-host" = {
        HostName = "192.168.1.93";
        User = "root";
      };

      "nixos-desktop" = {
        HostName = "192.168.5.201";
        User = "tom";
      };

      "lempls" = {
        HostName = "lempls.com";
        User = "puma";
      };

      # NOTE: the key must live at ~/.ssh/tom-mac.pem (mode 600) on the Mac —
      # it used to sit in ~/Downloads, which sync/cleanup tools can eat.
      "tom-server teplice-ec2" = {
        HostName = "ec2-35-159-178-203.eu-central-1.compute.amazonaws.com";
        User = "ec2-user";
        IdentityFile = "~/.ssh/tom-mac.pem";
        IdentitiesOnly = true;
      };

      "server-178" = {
        HostName = "178.22.117.90";
        User = "tom151";
        Port = 32479;
        ProxyJump = "tom-server";
      };

      "hexpol-camera internal-10-104-128-2" = {
        HostName = "10.104.128.2";
        User = "tom151";
        ProxyJump = "server-178";
      };

      "hexpol-camera-8080 internal-10-104-128-2-8080" = {
        HostName = "178.22.117.90";
        User = "tom151";
        Port = 32479;
        ProxyJump = "tom-server";
        LocalForward = [
          {
            bind = {
              address = "127.0.0.1";
              port = 8080;
            };
            host = {
              address = "10.104.128.2";
              port = 8080;
            };
          }
        ];
        ExitOnForwardFailure = true;
      };

      "gitlab-tom151" = {
        HostName = "gitlab.com";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_gitlab_tom151";
        IdentitiesOnly = true;
        ControlMaster = "no";
        ControlPath = "none";
      };

      "hbc-server" = {
        HostName = "185.156.39.202";
        User = "tech1";
        Port = 33894;
      };
    };

    extraConfig = ''
      Include ~/.orbstack/ssh/config
    '';
  };

  home.file.".ssh/sockets/.keep" = {
    text = "";
  };
}
