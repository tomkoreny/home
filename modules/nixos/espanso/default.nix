{ lib, ... }:
let
  common = import ../../../lib/common { };
in
{
  # A dedicated group rather than the global input group or CAP_DAC_OVERRIDE:
  # only Tom's account gains raw access to the event devices.
  users.groups.seat0-input = { };
  users.users.${common.user.name}.extraGroups = [ "seat0-input" ];
  boot.kernelModules = [ "uinput" ];

  # An unset ID_SEAT means seat0, the only seat on this host.
  services.udev.extraRules = lib.mkAfter ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_SEAT}=="", GROUP="seat0-input", MODE="0660"
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_SEAT}=="seat0", GROUP="seat0-input", MODE="0660"
    SUBSYSTEM=="misc", KERNEL=="uinput", GROUP="seat0-input", MODE="0660"
  '';
}
