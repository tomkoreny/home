{
  inputs,
  lib,
  pkgs,
  ...
}:
let
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
    #    pkgs.ansible
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.kubeseal
    pkgs.k9s
    #pkgs.httpie
    pkgs.nodejs_22
    pkgs.node-gyp
    #(pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.webstorm ["github-copilot"])
    #pkgs.jetbrains.webstorm
    (if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty)
    pkgs.glab

    pkgs.php
    # pkgs.signal-desktop

    (pkgs.discord.override {
      # withOpenASAR = true; # can do this here too
      withVencord = true;
    })

    # pkgs.prismlauncher
    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli
    # pkgs.prusa-slicer

    #pkgs.slack
    #pkgs.teleport
    pkgs.claude-code
    pkgs.codex
    pi-coding-agent
    pkgs.git-crypt
    pkgs.htop
    pkgs.tmux
    pkgs.nssTools
    pkgs.lazyssh
    # pkgs.claude-code-acp  # TODO: needs overlay
    # pkgs.codex-acp  # TODO: needs overlay
    pkgs.usql
  ]
  ++ lib.optionals (!pkgs.stdenv.isDarwin) [
    pkgs.zed-editor
  ];
}
