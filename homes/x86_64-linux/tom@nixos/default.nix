{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
  stripHash = lib.removePrefix "#";
  python = pkgs.python3Packages;

  jellyfinApiClient = python.jellyfin-apiclient-python.overridePythonAttrs (_: {
    version = "1.18.0";
    src = inputs.jellyfin-apiclient-python-src;
  });

  mpvJsonIpc = python.python-mpv-jsonipc.overridePythonAttrs (_: {
    version = "1.3.0";
    src = inputs.python-mpv-jsonipc-src;
  });

  jellyfinMpvShim = pkgs.jellyfin-mpv-shim.overridePythonAttrs (old: {
    version = "3.0.0pre14";
    src = inputs.jellyfin-mpv-shim-src;
    dependencies = [
      jellyfinApiClient
      python.mpv
      mpvJsonIpc
      python.requests
      python.pillow
      python.pystray
      python.pypresence
    ];
    postPatch = ''
      # Release archives generate this directory before packaging; the Git tag
      # intentionally omits it, so supply the pinned upstream shader pack.
      cp -r ${inputs.jellyfin-default-shader-pack-src} \
        jellyfin_mpv_shim/default_shader_pack
      chmod -R u+w jellyfin_mpv_shim/default_shader_pack

      # Match upstream dependency names to their nixpkgs Python attributes.
      substituteInPlace pyproject.toml \
        --replace-fail "python-mpv" "mpv" \
        --replace-fail "mpv-jsonipc" "python_mpv_jsonipc"

      # Pillow does not use fontconfig for bare font names in the Nix sandbox.
      # Without absolute paths every requested tile-caption size silently
      # falls back to Pillow's fixed 10 px bitmap font.
      substituteInPlace jellyfin_mpv_shim/mpvtk/pilfont.py \
        --replace-fail '"DejaVuSans.ttf",' \
                       '"${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf",' \
        --replace-fail '"DejaVuSans-Bold.ttf",' \
                       '"${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf",'

      # New profiles should select the system-matched theme by default. The
      # theme itself is installed below through Home Manager.
      substituteInPlace jellyfin_mpv_shim/conf.py \
        --replace-fail 'theme: str = "default"' \
                       'theme: str = "catppuccin-mocha"' \
        --replace-fail 'ui_scale: Optional[float] = None' \
                       'ui_scale: Optional[float] = 1.875' \
        --replace-fail 'ui_text_scale: float = 1.0' \
                       'ui_text_scale: float = 1.1' \
        --replace-fail 'ui_text_min: int = 0' \
                       'ui_text_min: int = 15'
    '';
    preFixup = old.preFixup + ''
      # libmpv loads CUDA/NVDEC dynamically, so expose the active NixOS NVIDIA
      # driver rather than baking a driver-version-specific store path in.
      makeWrapperArgs+=(--prefix LD_LIBRARY_PATH : /run/opengl-driver/lib)
    '';
  });
in
{
  # NOTE: all modules under modules/home/ are auto-imported by Snowfall Lib —
  # no explicit imports needed here, just per-host knobs.

  tomkoreny.waybar.outputs = [
    "HDMI-A-2"
    "DP-2"
    "DP-3"
  ];

  # Always show notifications on the centre Alienware screen.
  tomkoreny.mako.output = "DP-2";
  tomkoreny.komai.enable = true;

  # Preserve the original artwork on the centre display and use the generated
  # portrait outpaints as seamless extensions on the two side displays.
  services.hyprpaper.settings.wallpaper = lib.mkForce [
    {
      monitor = "HDMI-A-2";
      path = "${../../../lib/common/wallpaper-left.png}";
      fit_mode = "cover";
    }
    {
      monitor = "DP-2";
      path = "${common.stylix.wallpaper}";
      fit_mode = "cover";
    }
    {
      monitor = "DP-3";
      path = "${../../../lib/common/wallpaper-right.png}";
      fit_mode = "cover";
    }
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";

  # Captures the host-specific HDR/NVDEC settings declaratively. The cache/
  # readahead tuning that used to live here was reverted: the stutter it
  # chased turned out to be corrupt HEVC bitstreams in specific files, not
  # buffering (see ffmpeg decode-scan, 2026-08-31).
  xdg.configFile."jellyfin-mpv-shim/mpv.conf" = {
    force = true;
    text = ''
      # Native HDR path verified on the Alienware AW3225QF under Hyprland/Wayland.
      vo=gpu-next
      gpu-api=vulkan
      gpu-context=waylandvk
      vulkan-device=NVIDIA GeForce RTX 2070 SUPER
      target-colorspace-hint=yes

      # This host has an NVIDIA RTX 2070 SUPER; keep 4K HEVC decoding on NVDEC.
      hwdec=nvdec
    '';
  };

  # Match the system's OLED Catppuccin Mocha palette while keeping the shared
  # background and accent colours as the single source of truth.
  xdg.configFile."jellyfin-mpv-shim/themes/catppuccin-mocha.json".text =
    builtins.toJSON {
      name = "Catppuccin Mocha (Stylix)";
      palette = {
        WINDOW_BG = stripHash common.stylix.background;
        CARD_BG = "11111b";
        PANEL_BG = "181825";
        PLACEHOLDER_BG = "1e1e2e";
        BUTTON_BG = "313244";
        BUTTON_ACTIVE = "45475a";
        ENTRY_BG = "1e1e2e";
        BORDER = "45475a";
        TEXT_FG = "cdd6f4";
        SUBTLE_FG = "a6adc8";
        ACCENT = stripHash common.stylix.accent;
        ACCENT_HOVER = "51b6ff";
        ACCENT_SOFT = "0b3554";
        ACCENT_FG = "11111b";
        FAV_RED = "f38ba8";
        OK_GREEN = "a6e3a1";
        WARN_AMBER = "f9e2af";
        PROGRESS_TRACK = "313244";
        WATCHED_GREEN = "a6e3a1";
      };
      browse_bg = common.stylix.background;
      hud_accent = stripHash common.stylix.accent;
      # Keep artwork and playback progress edges square and aligned.
      rounded = false;
      glow = false;
      accent_buttons = false;
      arrow_mode = "overlay";
      arrow_bg = "11111b";
      arrow_alpha = 210;
      base_size = 18;
      tile_title_size = 17;
      tile_sub_size = 15;
      window_gradient = [
        [
          0.0
          "11111b"
        ]
        [
          1.0
          (stripHash common.stylix.background)
        ]
      ];
      topbar_gradient = [
        [
          0.0
          "11111b"
        ]
        [
          0.5
          "1e1e2e"
        ]
        [
          1.0
          "11111b"
        ]
      ];
    }
    + "\n";

  # Hyprland starts this unit after its Wayland/systemd environment is ready.
  systemd.user.services.jellyfin-mpv-shim = {
    Unit = {
      Description = "Jellyfin MPV Shim";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${jellyfinMpvShim}/bin/jellyfin-mpv-shim --gui --no-minimized";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  home.packages = [
    pkgs.sshpass
    pkgs.atool
    pkgs.docker
    pkgs.wl-clipboard
    pkgs.cliphist # clipboard history (see Hyprland exec-once + Super+Shift+V)
    # Keep hyprshot on the same upstream package as the running compositor;
    # nixpkgs' independently packaged Hyprland can diverge or fail to build.
    (pkgs.hyprshot.override {
      hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    })
    pkgs.libnotify # notify-send, used by hyprshot to confirm captures
    pkgs.teams-for-linux
    pkgs.slack
    pkgs.git-credential-oauth
    pkgs.gnome-keyring
    pkgs.seahorse
    pkgs.toybox
    pkgs.element-desktop
    jellyfinMpvShim # Browser-enabled Jellyfin desktop/cast client backed by mpv
    pkgs.prismlauncher
    pkgs.remmina
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.whitelist.prefix = [ "/home/tom/projects" ];
  };

  # The state version is required and should stay at the version you
  # originally installed.
  home.stateVersion = "24.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  programs = {
    wofi.enable = true; # required for the default Hyprland config
  };
}
