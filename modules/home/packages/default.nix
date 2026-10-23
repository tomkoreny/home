{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  aiTools = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system};

  # hermes-agent 0.22.4 pins prompt-toolkit==3.0.52 and markdown==3.10.2.
  # llm-agents.nix builds it against its own nixpkgs (f20cd90), which still
  # carries those versions; this flake makes it follow nixos-unstable 02c087f,
  # which has 3.0.53 and 3.10.3, so pythonRuntimeDepsCheck failed and took
  # every nixos-upgrade down with it (2026-10-23). Scoped to 0.22.4, so the
  # next hermes bump drops the override.
  hermes-desktop =
    if aiTools.hermes-agent.version == "0.22.4" then
      aiTools.hermes-desktop.override {
        hermes-agent = aiTools.hermes-agent.overridePythonAttrs (old: {
          # Spelled as in hermes' pyproject: the hook does not fold `_` to `-`.
          pythonRelaxDeps = old.pythonRelaxDeps ++ [
            "markdown"
            "prompt_toolkit"
          ];
        });
      }
    else
      aiTools.hermes-desktop;
in
{
  programs.omp = {
    enable = true;
    package = lib.mkDefault (import ./omp.nix { inherit inputs lib pkgs; });
  };

  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerdfetch
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.kubeseal
    pkgs.k9s
    pkgs.nodejs_22
    pkgs.node-gyp
    (if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty)
    pkgs.glab

    pkgs.php

    (
      if pkgs.stdenv.hostPlatform.isLinux then
        pkgs.callPackage ./discord-tray-icons { }
      else
        pkgs.discord.override { withVencord = true; }
    )

    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli

    inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    pkgs.codex
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
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    # Clipboard image provider used by img-clip.nvim/PiPasteImage.
    pkgs.pngpaste
  ]
  ++ lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) [
    # Native desktop shell for Hermes Agent on the Linux workstation.
    hermes-desktop
    pkgs.kicad
    pkgs.zed-editor
  ];
}
