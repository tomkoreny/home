# Multi-seat: a second, fully independent seat (seat1) on this desktop.
#
# Hardware split on this host:
#   seat0 (tom):   NVIDIA dGPU (pci-0000:01:00.0) + Corne keyboard + Logitech
#                  receiver — untouched by this module.
#   seat1 (terka): AMD iGPU (pci-0000:11:00.0) — her monitor must be plugged
#                  into a MOTHERBOARD video output (HDMI or DP) — plus the two
#                  USB ports her keyboard/mouse are in today.
#
# A GPU can only belong to one seat (seat assignment is per DRM device, and
# only one process can be DRM master of a card), so the NVIDIA card cannot be
# shared between seats. Terka's *display* runs off the iGPU; her apps can
# still *render* on the NVIDIA card via PRIME offload (`nvidia-run <app>`,
# defined in her home config) because /dev/dri/renderD* nodes are not
# seat-bound.
#
# Login flow for seat1: there is no display manager involved. Autologin is a
# systemd service that opens a real PAM/logind session (pam_systemd, with
# XDG_SEAT injected via pam_env) and execs Hyprland as the seat user.
#
# This is also why seat0 uses greetd instead of SDDM (see
# systems/x86_64-linux/nixos): SDDM starts a greeter on EVERY logind seat
# with CanGraphical=true, and seat1 must be CanGraphical — logind only
# creates a seat at all when it sees a device tagged "master-of-seat"
# (stripping that tag was tried; it just makes CreateSession fail with
# NoSuchSeat). greetd, by contrast, only ever manages seat0's VT.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.multiseat;

  hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

  # pam_env conffile injecting the seat into the PAM environment, which is
  # where pam_systemd looks for it (a plain Environment= on the service does
  # not reach PAM).
  pamEnv = pkgs.writeText "seat1-pam-env" ''
    XDG_SEAT DEFAULT=seat1
  '';

  startSession = pkgs.writeShellScript "hyprland-seat1-session" ''
    # Full NixOS session environment — PATH (incl. the per-user profile, via
    # $USER) and XDG_DATA_DIRS, without which wofi finds no .desktop files and
    # binds can't resolve apps. A display manager's session wrapper would
    # normally source this; nothing does it for a bare systemd session.
    . /etc/set-environment
    export PATH=/etc/profiles/per-user/${cfg.user}/bin:/run/wrappers/bin:$PATH
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland

    # Pin Hyprland to the seat's GPU. AQ_DRM_DEVICES uses ":" as a list
    # separator, so resolve the by-path symlink (which contains ":") to the
    # real /dev/dri/cardN first — card numbering is not stable across boots.
    card="$(readlink -f /dev/dri/by-path/${cfg.gpuPciPath}-card)"
    export AQ_DRM_DEVICES="$card"

    # This seat renders on the AMD iGPU; override the system-wide NVIDIA
    # VA-API/VDPAU defaults from environment.sessionVariables (sourced above).
    export LIBVA_DRIVER_NAME=radeonsi
    export VDPAU_DRIVER=radeonsi

    # Hyprland >= 0.55 wants its launcher (portal/dbus/env setup); launching
    # the bare binary prints a warning on screen.
    exec ${hyprland}/bin/start-hyprland
  '';
in
{
  options.tomkoreny.nixos.multiseat = {
    enable = lib.mkEnableOption "second seat (seat1) with Hyprland autologin";

    user = lib.mkOption {
      type = lib.types.str;
      default = "terka";
      description = "User that owns the seat1 session (created by this module).";
    };

    gpuPciPath = lib.mkOption {
      type = lib.types.str;
      default = "pci-0000:11:00.0";
      description = "udev ID_PATH of the seat1 GPU (the AMD iGPU).";
    };

    gpuAudioPciPath = lib.mkOption {
      type = lib.types.str;
      default = "pci-0000:11:00.1";
      description = "udev ID_PATH of the seat1 GPU's HDMI/DP audio function (monitor speakers).";
    };

    usbPciPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # The physical USB ports Terka's keyboard and mouse occupy today —
        # anything plugged into these ports lands on seat1. Find values with:
        #   udevadm info /dev/input/eventN | grep ID_PATH
        "pci-0000:0f:00.0-usb-0:4.4.3" # Logitech USB keyboard
        "pci-0000:0f:00.0-usb-0:4.4.4" # ZOWIE mouse
      ];
      description = "udev ID_PATH prefixes of USB ports assigned to seat1.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isNormalUser = true;
      description = "Terka";
      # No wheel/docker: plain desktop user. render+video are belt-and-braces
      # for PRIME offload; session device access itself comes from logind.
      extraGroups = [
        "networkmanager"
        "video"
        "render"
      ];
    };

    services.udev.extraRules =
      ''
        # ---- multi-seat: assign seat1 hardware (see modules/nixos/multiseat) ----
        # iGPU. The card keeps its default "master-of-seat" tag: logind only
        # creates seat1 when a master device carries it.
        SUBSYSTEM=="drm", KERNEL=="card*", ENV{ID_PATH}=="${cfg.gpuPciPath}", TAG+="seat", ENV{ID_SEAT}="seat1"
        # iGPU HDMI/DP audio, so the monitor's speakers/jack belong to seat1.
        SUBSYSTEM=="sound", ENV{ID_PATH}=="${cfg.gpuAudioPciPath}", TAG+="seat", ENV{ID_SEAT}="seat1"
      ''
      + lib.concatMapStrings (path: ''
        ENV{ID_PATH}=="${path}*", TAG+="seat", ENV{ID_SEAT}="seat1"
      '') cfg.usbPciPaths;

    # Minimal PAM stack for the autologin session: no authentication (that is
    # what autologin means — same trust model as getty/greetd autologin), but
    # a full session setup so logind registers the session on seat1.
    security.pam.services.hyprland-seat1.text = ''
      auth     required pam_succeed_if.so user = ${cfg.user} quiet_success
      auth     required pam_permit.so
      account  required pam_unix.so
      session  required pam_env.so conffile=${pamEnv} readenv=0
      session  required pam_unix.so
      session  required pam_loginuid.so
      session  required ${config.systemd.package}/lib/security/pam_systemd.so class=user type=wayland desktop=Hyprland
    '';

    systemd.services.hyprland-seat1 = {
      description = "Hyprland session for ${cfg.user} on seat1 (autologin)";
      wantedBy = [ "graphical.target" ];
      after = [
        "systemd-user-sessions.service"
        "systemd-logind.service"
      ];
      # seat1 only exists once udev has tagged its devices; early boot attempts
      # may fail PAM session setup — just keep retrying, and also auto-relogin
      # after logout/crash.
      startLimitIntervalSec = 0;
      serviceConfig = {
        User = cfg.user;
        PAMName = "hyprland-seat1";
        ExecStart = startSession;
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
