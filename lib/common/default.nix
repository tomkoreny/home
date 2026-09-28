# Shared configuration values used across NixOS and Darwin
# This reduces duplication and provides a single source of truth
#
# Usage in system configs:
#   let common = import ../../../lib/common {}; in { ... }
#
# Then access: common.user.name, common.network.upstreamDns, etc.
{
  lib ? null,
  ...
}:
rec {
  # User identity - used in git config, user definitions, etc.
  user = {
    name = "tom";
    fullName = "Tom Koreny";
    email = "tom@tomkoreny.com";

    # Platform-specific home directory
    homeDir =
      {
        isDarwin ? false,
      }:
      if isDarwin then "/Users/${user.name}" else "/home/${user.name}";
  };

  # Network configuration
  network = {
    # Upstream DNS resolver (Cloudflare) that dnsmasq and Docker forward to
    upstreamDns = "1.1.1.1";
  };

  # OMP voice (dictation, live mode, TTS) on NixOS while the MacBook is
  # attached through herdr. The Mac serves its microphone and speakers with
  # PulseAudio; SSH reverse-forwards that socket to NixOS; the NixOS `omp`
  # wrapper lists it before the local server, so voice follows the Mac while
  # the forward is live and falls back to NixOS audio once it is gone.
  ompVoice = {
    # PULSE_RUNTIME_PATH of the Mac server. PulseAudio creates it 0700 and
    # listens on `native` inside, which keeps the anonymous socket private.
    macRuntimeDir = "${user.homeDir { isDarwin = true; }}/.local/state/omp-voice-pulse";
    # Where NixOS sshd binds the forwarded socket: tom's runtime dir (uid 1000).
    nixosSocket = "/run/user/1000/omp-voice-pulse.sock";
  };

  # Public Yggdrasil peers shared by the Mac and NixOS. Both hosts dial the
  # same nearby nodes, so Mac-to-NixOS traffic crosses one relay close to
  # both instead of a US node (~270 ms round trip before this list). Picked
  # from github.com/yggdrasil-network/public-peers by TCP connect time
  # measured 2026-09-28 (Mac on phone hotspot / NixOS on Starlink):
  #   Warsaw, Skhron      61 / 15 ms
  #   Prague, vpsFree     30 / 53 ms
  #   Vienna, marekjm     42 / 43 ms
  # `?key=` pins the peer's public key where the list publishes one.
  yggdrasil.peers = [
    "tls://waw01.yggdrasil.hosted-by.skhron.eu:8884?key=030602cee88a761c68f5f14e1dad430f25238a703b69dc382321a38f833035b0"
    "tls://37.205.14.171:993?key=0009e16b9e3afe7b13c3612560410434d3dfc70c8a8a0a63e51e0470cb8124f6"
    "tls://109.176.250.101:65534"
  ];

  # Split-tunnel WireGuard link to the internal network.
  #
  # Only the two internal prefixes below are pushed through the tunnel, so the
  # link can stay up permanently without hijacking the default route: general
  # internet traffic keeps using the local uplink.
  #
  # Each host needs its OWN keypair and tunnel address. WireGuard tracks one
  # endpoint per peer, so two machines sharing an identity make the server flip
  # the endpoint back and forth on every handshake and neither stays reachable.
  wireguard = {
    interface = "wg0";
    listenPort = 51820;

    server = {
      publicKey = "r6AaGc3TW7JdpToewFbjhVjfQbXrFaVhKLAmOhpFajk=";
      endpoint = "176.97.247.247:13279";
      # Internal-only prefixes: the tunnel subnet plus the one reachable host.
      allowedIPs = [
        "192.168.22.106/32"
        "10.71.71.0/24"
      ];
    };

    # Tunnel addresses, one per host; the matching public keys are configured
    # server-side as separate peers.
    #   macos: dSrABixgeKzUBYfPtuioOsMO385m+5VUlrWb4h5CU3I=
    #   nixos: MLXa03vU+pZoKgpfiaClWGqSXNh0OJr625D0GPFFaxI=
    addresses = {
      macos = "10.71.71.2/32";
      nixos = "10.71.71.3/32";
    };
  };

  # Docker daemon configuration
  docker = {
    # Insecure registries (internal harbor, etc.)
    insecureRegistries = [ "harbor.acho.loc:443" ];

    # DNS options for containers
    dnsOpts = [ "ndots:0" ];

    # Generate address pools programmatically (requires lib)
    # Usage: common.docker.addressPools lib
    addressPools =
      l:
      l.genList (i: {
        base = "172.${toString (17 + i)}.0.0/16";
        size = 24;
      }) 10;
  };

  # Stylix theme base configuration
  # Usage: common.stylix.base // { fonts.sizes = ...; }
  stylix = {
    # Shared wallpaper (relative to this file)
    wallpaper = ./wallpaper.png;
    # Single source of truth for theme colors; see docs/theming.md.
    background = "#000000";
    accent = "#219fff";
    # Light-mode counterpart of the accent, for the few surfaces that follow the
    # system appearance instead of being dark-only (Catppuccin Latte flavors).
    # Same hue, darkened 30% (`accent` mixed 70% with black): `accent` scores
    # 7.5:1 on the true-black background but only 2.5:1 on Latte's base, while
    # this reaches 4.7:1. See docs/theming.md.
    accentLight = "#176fb3";

    # Core theme settings (shared across all platforms)
    # Takes no `pkgs`: the scheme is a repo-local file, so evaluating a
    # x86_64-linux home from an aarch64-darwin machine no longer has to realise
    # that platform's base16-schemes derivation just to read one YAML file.
    # base16.nix reads the scheme with builtins.readFile, so a store path from
    # `pkgs.base16-schemes` turns theming into cross-system import-from-derivation
    # and breaks `nix flake check` on every nixpkgs bump.
    base = {
      enable = true;
      polarity = "dark";
      base16Scheme = ./catppuccin-mocha.yaml;
      override = {
        base00 = stylix.background; # OLEDpuccin - true black
        base0D = stylix.accent; # Unified blue/accent color
      };
      opacity = {
        applications = 1.0;
        terminal = 1.0;
        desktop = 1.0;
        popups = 1.0;
      };
    };

    # Shared fonts (used everywhere)
    fonts = pkgs: inputs: {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };
      serif = {
        package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.ny-nerd;
        name = "NewYork Nerd Font";
      };
    };

    # Unified font sizes (all platforms)
    fontSizes = {
      applications = 12;
      terminal = 13;
      desktop = 10;
      popups = 10;
    };

    # Cursor theme (NixOS only, Darwin uses system cursor)
    cursor = pkgs: {
      package = pkgs.rose-pine-cursor;
      name = "BreezeX-RosePine-Linux";
      size = 32;
    };
  };

  # Nix binary caches (shared between NixOS and Darwin)
  nix = {
    substituters = [
      "https://cache.nixos.org/"
      "https://hyprland.cachix.org"
      "https://lan-mouse.cachix.org"
    ];
    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "lan-mouse.cachix.org-1:KlE2AEZUgkzNKM7BIzMQo8w9yJYqUpor1CAUNRY6OyM="
    ];
  };
}
