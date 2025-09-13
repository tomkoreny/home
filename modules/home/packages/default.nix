{
  inputs,
  pkgs,
  ...
}: {
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerdfetch
    #    pkgs.ansible
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.k9s
    pkgs.httpie
    pkgs.nodejs
    pkgs.node-gyp
    #(pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.webstorm ["github-copilot"])
    pkgs.jetbrains-toolbox
    #pkgs.jetbrains.webstorm
    pkgs.ghostty

    pkgs.php
    pkgs.signal-desktop

    pkgs.nodePackages.vercel

    (pkgs.discord.override {
      # withOpenASAR = true; # can do this here too
      withVencord = true;
    })

    pkgs.prismlauncher
    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli
    # pkgs.prusa-slicer

    pkgs.slack
    pkgs.teleport
    pkgs.claude-code
    pkgs.git-crypt
    pkgs.htop
    pkgs.nssTools
  ];
}
