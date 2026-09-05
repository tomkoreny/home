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

  jellyfinMpris = pkgs.mpvScripts.mpris.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # Shim owns its queue outside mpv, whose playlist contains one file.
      # Forward MPRIS skips to Shim's existing media-key handlers instead.
      substituteInPlace mpris.c \
        --replace-fail '{"playlist_next", NULL}' '{"keypress", "NEXT", NULL}' \
        --replace-fail '{"playlist_prev", NULL}' '{"keypress", "PREV", NULL}' \
        --replace-fail 'if (ud->playlist_count == 1)
              return FALSE;' 'if (ud->playlist_count == 1)
              return TRUE;'
    '';
  });

  mpvForJellyfinShim = pkgs.mpv.override {
    scripts = [ jellyfinMpris ];
  };

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

      # MPRIS requires the C plugin in a standalone mpv process; it cannot
      # register from Shim's embedded libmpv backend. Use the external backend
      # for new profiles so global media controls can see playback.
      substituteInPlace jellyfin_mpv_shim/conf.py \
        --replace-fail 'mpv_ext: bool = sys.platform.startswith("darwin")' \
                       'mpv_ext: bool = True' \
        --replace-fail 'mpv_ext_path: Optional[str] = None' \
                       'mpv_ext_path: Optional[str] = "${mpvForJellyfinShim}/bin/mpv"' \
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

  tomkoreny.quickshell-bar = {
    enable = true;
    outputs = [
      "HDMI-A-2"
      "DP-2"
      "DP-3"
    ];
    primaryOutput = "DP-2";
  };

  tomkoreny.komai.enable = true;
  tomkoreny.web-playback.enable = true;
  tomkoreny.quickshell-osd = {
    enable = true;
    output = "DP-2";
    monitorSerial = "6D12YZ3";
  };

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

  # Use Evolution's persisted sidebar order instead of alphabetical sorting.
  dconf.settings."org/gnome/evolution/mail"."sort-accounts-alpha" = false;

  # Seed Evolution's writable sort-order state once. Evolution rewrites this
  # file itself, so it must not be a Home Manager store symlink.
  home.activation.seedEvolutionMailSortOrder = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/evolution/mail"
    sort_order="$config_dir/sortorder.ini"

    if [ -L "$sort_order" ]; then
      link_target="$(${pkgs.coreutils}/bin/readlink "$sort_order")"
      case "$link_target" in
        /nix/store/*)
          ${pkgs.coreutils}/bin/rm "$sort_order"
          ;;
        *)
          echo "Skipping Evolution sort order: unexpected symlink to $link_target" >&2
          ;;
      esac
    fi

    if [ ! -L "$sort_order" ]; then
      if [ ! -e "$sort_order" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
        tmp_file="$(${pkgs.coreutils}/bin/mktemp "$sort_order.XXXXXX")"
        ${pkgs.coreutils}/bin/printf '%s\n' \
          '[Accounts]' \
          'SortOrder=vfolder;3c393ab1b02fc414b3f89b49a89fbbb1e535e416;52c0459ec57947bf9ca217648a517342c34c1c9b;97c93e0cb16ef48dda53d240eb3e094ac78aff08;832122f4a66e8a6eb9ab37e5a51a158065574d90;local;rss;' \
          > "$tmp_file"
        ${pkgs.coreutils}/bin/chmod 600 "$tmp_file"
        ${pkgs.coreutils}/bin/mv "$tmp_file" "$sort_order"
      fi

      if [ -f "$sort_order" ] && [ ! -L "$sort_order" ]; then
        ${pkgs.coreutils}/bin/chmod 600 "$sort_order"
      else
        echo "Cannot manage Evolution sort order: $sort_order is not a regular file" >&2
        exit 1
      fi
    fi
  '';

  # Captures the host-specific HDR/NVDEC settings declaratively. The cache/
  # readahead tuning that used to live here was reverted: the stutter it
  # chased turned out to be corrupt HEVC bitstreams in specific files, not
  # buffering (see ffmpeg decode-scan, 2026-08-31).
  xdg.configFile."jellyfin-mpv-shim/mpv.conf" = {
    force = true;
    text = ''
      # Give Shim a distinct MPRIS bus name; standalone mpv remains separate.
      audio-client-name=JellyfinMPVShim

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

  # Existing profiles persist these settings in conf.json, so changing the
  # package defaults alone would leave them on the embedded backend. Update
  # only those keys atomically without taking ownership of the app-managed file.
  home.activation.enableJellyfinMpvMpris = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_file="$HOME/.config/jellyfin-mpv-shim/conf.json"
    mpv_path="${mpvForJellyfinShim}/bin/mpv"
    if [ -f "$config_file" ] && {
      [ "$(${pkgs.jq}/bin/jq -r '.mpv_ext // false' "$config_file")" != true ] ||
      [ "$(${pkgs.jq}/bin/jq -r '.mpv_ext_path // ""' "$config_file")" != "$mpv_path" ]
    }; then
      tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.XXXXXX")"
      if ${pkgs.jq}/bin/jq --arg mpv_path "$mpv_path" \
        '.mpv_ext = true | .mpv_ext_path = $mpv_path' \
        "$config_file" > "$tmp_file"; then
        ${pkgs.coreutils}/bin/chmod --reference="$config_file" "$tmp_file"
        ${pkgs.coreutils}/bin/mv "$tmp_file" "$config_file"
      else
        ${pkgs.coreutils}/bin/rm -f "$tmp_file"
        exit 1
      fi
    fi
  '';

  # Hyprland starts this unit after its Wayland/systemd environment is ready.
  systemd.user.services.jellyfin-mpv-shim = {
    Unit = {
      Description = "Jellyfin MPV Shim";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${jellyfinMpvShim}/bin/jellyfin-mpv-shim --gui --minimized";
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
    pkgs.onlyoffice-desktopeditors
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
    wofi.enable = true; # Retained for the standalone Herdr pane fallback.
  };
}
