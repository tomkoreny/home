{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  aiTools = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system};

  # Fonts and applications that need a screen are left out of a profile
  # without a graphical session. Tagged in place so the list keeps its order.
  desktopOnly = lib.optional config.tomkoreny.desktop.enable;
in
{
  programs.omp = {
    enable = true;
    package = lib.mkDefault (import ./omp.nix { inherit inputs lib pkgs; });
  };

  home.packages = lib.flatten [
    (desktopOnly pkgs.nerd-fonts.jetbrains-mono)
    pkgs.nerdfetch
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.kubeseal
    pkgs.k9s
    pkgs.nodejs_22
    pkgs.node-gyp
    (desktopOnly (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty))
    pkgs.glab

    pkgs.php

    (desktopOnly (
      if pkgs.stdenv.hostPlatform.isLinux then
        pkgs.callPackage ./discord-tray-icons { }
      else
        pkgs.discord.override { withVencord = true; }
    ))

    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli

    inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    aiTools.codex
    # `pi` was hand-packaged here with buildNpmPackage + a vendored 142 KB
    # package-lock.json, which meant it only moved when someone remembered to
    # run scripts/update-pi-coding-agent.sh — it had drifted 7 weeks behind.
    # nixpkgs ships the same upstream (github.com/earendil-works/pi) with a
    # nix-update updateScript, so it now rides the daily flake.lock CI instead,
    # comes from the binary cache, and gets the Darwin fixes we didn't have.
    # Keep it as a fallback while OMP is being evaluated.
    pkgs.pi-coding-agent
    pkgs.git-crypt
    pkgs.gh
    pkgs.htop
    pkgs.nssTools
    pkgs.lazyssh
    pkgs.usql

    # CLI tools formerly installed via Homebrew on macOS
    pkgs.pandoc
    pkgs.imagemagick
    pkgs.git-lfs
    pkgs.socat
    pkgs.uv
    pkgs.hugo
    pkgs.mkcert
    pkgs.cloudflared
    pkgs.argocd

    (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      # Clipboard image provider used by img-clip.nvim/PiPasteImage.
      pkgs.pngpaste
    ])
    (lib.optionals (config.tomkoreny.desktop.enable && !pkgs.stdenv.hostPlatform.isDarwin) [
      # Native desktop shell for Hermes Agent on the Linux workstation.
      aiTools.hermes-desktop
      pkgs.kicad
      pkgs.zed-editor
    ])
  ];
}
