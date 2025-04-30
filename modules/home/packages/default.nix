{inputs, pkgs, ...}: {
  home.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerdfetch
    pkgs.ansible
    pkgs.openfortivpn
    pkgs.kubectl
    pkgs.httpie
    pkgs.nodejs
    pkgs.node-gyp
    # (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.webstorm ["github-copilot"])
    pkgs.jetbrains.webstorm
    pkgs.beeper
    pkgs.ghostty

    pkgs.nodePackages.vercel

    (pkgs.discord.override {
      # withOpenASAR = true; # can do this here too
      withVencord = true;
    })

    pkgs.thunderbird
    pkgs.hypridle
    pkgs.git-credential-oauth
    pkgs.gnome-keyring
    pkgs.seahorse
    pkgs.toybox
    pkgs.typescript
    pkgs.typescript-language-server
    pkgs.prismlauncher
    pkgs.qmk

    pkgs.typescript
    pkgs.typescript-language-server

    pkgs.eas-cli
  ];
}
