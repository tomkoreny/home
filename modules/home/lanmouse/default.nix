{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.lan-mouse.homeManagerModules.default ];

  programs.lan-mouse = {
    enable = true;
    # Set these explicitly rather than evaluating the upstream module's
    # deprecated stdenv.isLinux/isDarwin defaults.
    systemd = pkgs.stdenv.hostPlatform.isLinux;
    launchd = pkgs.stdenv.hostPlatform.isDarwin;
    # package = inputs.lan-mouse.packages.${pkgs.stdenv.hostPlatform.system}.default
    # Optional configuration in nix syntax, see config.toml for available options
    # settings = { };
  };
}
