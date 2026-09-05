{ lib, ... }:
let
  common = import ../../../lib/common { };
in
{
  # Mirror multiseat's seat1-input group instead of granting the global input
  # group or CAP_DAC_OVERRIDE, either of which would expose Terka's keyboard.
  users.groups.seat0-input = { };
  users.users.${common.user.name}.extraGroups = [ "seat0-input" ];
  boot.kernelModules = [ "uinput" ];

  # Run after multiseat's ID_SEAT assignments in the same 99-local.rules file.
  # An unset ID_SEAT means seat0. Other seats retain their existing permissions.
  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_SEAT}=="", GROUP="seat0-input", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_SEAT}=="seat0", GROUP="seat0-input", MODE="0660"
    SUBSYSTEM=="misc", KERNEL=="uinput", GROUP="seat0-input", MODE="0660"
  '';
}
