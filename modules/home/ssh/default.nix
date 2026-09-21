{
  config,
  lib,
  ...
}:

let
  # Single source of truth for SSH hosts. Blocks use upstream ssh_config
  # directive names; the attribute name becomes the `Host` pattern.
  # ~/.omp/agent/ssh.json is derived from this set below.
  sshSettings = {
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

    # mDNS name published by the NixOS host's avahi; its DHCP address has
    # changed before, so no hardcoded IP.
    "nixos-desktop" = {
      HostName = "nixos.local";
      User = "tom";
    };

    # Global IPv6 address of the same host, reachable from outside the home
    # network without a VPN. Herdr's saved "nixos" machine targets this alias.
    # The host-key alias keeps one known_hosts identity across both paths.
    "nixos-v6" = {
      HostName = "2a0d:3344:78f0:9f07:c8b8:5c45:e58e:b26e";
      User = "tom";
      AddressFamily = "inet6";
      HostKeyAlias = "nixos.local";
    };

    # Attach directly to the persistent NixOS tmux session.
    "nixos-session" = {
      HostName = "nixos.local";
      User = "tom";
      RequestTTY = "force";
      RemoteCommand = "mux main";
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

  # Blocks OMP's ssh:// registry should not expose: the pattern block, git
  # transport, the forced-RemoteCommand tmux session, and the port-forward
  # profile (none of them serve plain shell/file access).
  ompExcludedHosts = [
    "*"
    "gitlab-tom151"
    "nixos-session"
    "hexpol-camera-8080 internal-10-104-128-2-8080"
  ];

  # OMP host registry entries: name + description only. Connection details
  # stay in ssh_config — `host` points back at the alias, so OpenSSH still
  # resolves user, port, keys, and jump chains from the blocks above.
  ompSshHosts = lib.mapAttrs' (
    pattern: block:
    let
      alias = lib.head (lib.splitString " " pattern);
    in
    lib.nameValuePair alias {
      host = alias;
      description =
        "${block.User}@${block.HostName}"
        + lib.optionalString (block ? Port) ":${toString block.Port}"
        + lib.optionalString (block ? ProxyJump) " via ${block.ProxyJump}";
    }
  ) (builtins.removeAttrs sshSettings ompExcludedHosts);
in
{
  programs.ssh = {
    enable = true;

    # Suppress deprecation warning about default values
    enableDefaultConfig = false;

    settings = sshSettings;

    extraConfig = ''
      Include ~/.orbstack/ssh/config
    '';
  };

  home.file.".ssh/sockets/.keep" = {
    text = "";
  };

  # OMP ssh:// host registry, derived from sshSettings. Read-only store
  # symlink: `omp ssh add --scope user` cannot write it — add hosts here.
  home.file.".omp/agent/ssh.json" = lib.mkIf (config.home.username == "tom") {
    text = builtins.toJSON { hosts = ompSshHosts; };
  };
}
