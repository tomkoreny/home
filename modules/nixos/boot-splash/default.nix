{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.nixos.boot-splash;
  common = import ../../../lib/common { };

  # The homepage brand kit's underprint colour (homepage public/brand/BRAND.md).
  signalOrange = "#FF5A1F";
  # Catppuccin Mocha mantle: the top bar's surface, barely lifted off black.
  trackColor = "#181825";

  # The script picks the largest width that fits the smallest display, so the
  # mark is never resampled at boot and keeps its hard edges.
  markWidths = [
    160
    200
    240
    280
    320
    360
    420
    480
    560
  ];

  script = pkgs.replaceVars ./tk.script {
    markWidths = lib.concatMapStringsSep ", " toString markWidths;
    # Mark width as a share of the smallest display's height.
    markScale = "0.24";
  };

  theme =
    pkgs.runCommand "plymouth-theme-tk"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
      }
      ''
        dir=$out/share/plymouth/themes/tk
        mkdir -p "$dir"

        render_mark() {
          sed 's/@fill@/'"$2"'/' ${./tk-mark.svg} | rsvg-convert --width "$3" --output "$dir/$1-$3.png"
        }
        for width in ${toString markWidths}; do
          render_mark face '${common.stylix.accent}' "$width"
          render_mark under '${signalOrange}' "$width"
        done

        # Solid swatches the script scales into the progress hairline.
        swatch() {
          echo '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="'"$2"'"/></svg>' \
            | rsvg-convert --output "$dir/$1.png"
        }
        swatch accent '${common.stylix.accent}'
        swatch orange '${signalOrange}'
        swatch track '${trackColor}'

        cp ${script} "$dir/tk.script"
        cat > "$dir/tk.plymouth" <<EOF
        [Plymouth Theme]
        Name=TK
        Description=TK mark on true black with a boot progress hairline
        ModuleName=script

        [script]
        ImageDir=$dir
        ScriptFile=$dir/tk.script
        EOF
      '';
in
{
  options.tomkoreny.nixos.boot-splash = {
    enable = lib.mkEnableOption "the quiet TK boot splash";
  };

  config = lib.mkIf cfg.enable {
    # Stylix would otherwise install and select its own Plymouth theme.
    stylix.targets.plymouth.enable = false;

    boot = {
      plymouth = {
        enable = true;
        theme = "tk";
        themePackages = [ theme ];
        # DeviceScale=1: draw in device pixels on every display. The script
        # sizes the mark itself, and Plymouth's HiDPI guess would upscale it
        # on the 4K panel.
        # UseSimpledrm=1: start on the firmware framebuffer and move to the
        # GPU driver once it loads. Loading NVIDIA in the initrd instead would
        # also start the splash early, but it registers NVIDIA's connectors
        # before amdgpu's, which renames DP-2/HDMI-A-2/DP-3 that the desktop
        # config refers to.
        extraConfig = ''
          DeviceScale=1
          UseSimpledrm=1
        '';
      };

      # Kernel messages stay in the journal instead of the console. Level 0
      # also hides KERN_EMERG lines such as the Zen 5 "RDSEED32 is broken"
      # notice; panics and oopses still raise the level before printing. With
      # nothing printed, fbcon also defers its takeover and never draws text.
      consoleLogLevel = 0;
      initrd.verbose = false;

      kernelParams = [
        "quiet"
        # Only failed units reach the console; progress lines never do.
        "rd.systemd.show_status=error"
        "systemd.show_status=error"
        "rd.udev.log_level=3"
        "udev.log_level=3"
      ];
    };

    # While attached, Plymouth makes systemd print every status line (it shows
    # them in its details view). It lifts that override only as it exits, and
    # PID 1 logs "Finished Terminate Plymouth Boot Screen" to the bare console
    # before it handles that signal. Lift the override before quitting so the
    # status setting above applies to those last lines too.
    systemd.services.plymouth-quit.serviceConfig.ExecStartPre =
      "${pkgs.util-linux}/bin/kill --signal RTMIN+21 1";
  };
}
