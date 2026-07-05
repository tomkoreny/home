{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Pinned, reproducible install of the `pi` coding agent. Bump with
  # scripts/update-pi-coding-agent.sh (updates version + both hashes + lockfile).
  pi-coding-agent = pkgs.buildNpmPackage rec {
    pname = "pi-coding-agent";
    version = "0.79.0";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
      hash = "sha512-pZoXk65vFR3dAzzmPNWEX61aHnT6+BaVhTyFDQAs1DyumaMeWpvzRV9ZrGxqlbVLwhrq+0LnXbaqDAFkhe2+MQ==";
    };

    postPatch = ''
      cp ${./pi-coding-agent-lock.json} package-lock.json
      rm -f npm-shrinkwrap.json
    '';

    npmDepsHash = "sha256-4qFbQr2y6m7IKZ7gyMSphVqwr25eq5NWOtujaX/KxBQ=";
    dontNpmBuild = true;

    meta = {
      description = "Minimal terminal coding harness";
      homepage = "https://pi.dev/";
      license = lib.licenses.mit;
      mainProgram = "pi";
    };
  };
in
{
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
    (if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty)
    pkgs.glab

    pkgs.php

    (pkgs.discord.override {
      withVencord = true;
    })

    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli

    inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    pkgs.codex
    pi-coding-agent
    pkgs.git-crypt
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
  ++ lib.optionals (!pkgs.stdenv.isDarwin) [
    pkgs.kicad
    pkgs.zed-editor
  ];
}
