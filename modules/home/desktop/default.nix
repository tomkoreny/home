{ lib, ... }:
{
  options.tomkoreny.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether this user has a graphical session. Modules that only make sense
      with one (the compositor, GUI applications and their settings) read
      this; turn it off for an account that is used over SSH only.
    '';
  };
}
