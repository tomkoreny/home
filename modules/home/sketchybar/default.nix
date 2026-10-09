{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# macOS port of the Quickshell bar's status island. SketchyBar draws the bar,
# widgets.py feeds it from the shared bar backends (Notion todos, work tasks,
# timers) plus herdr and omp, and the native menu bar is set to auto-hide so
# the two do not overlap; it still slides in when the mouse touches the top
# edge, so app menus and Control Center stay reachable.
let
  cfg = config.tomkoreny.sketchybar;
  backends = config.tomkoreny.bar-backends;
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  providerLogoSources = import ../bar-backends/provider-logos.nix pkgs;

  # SketchyBar takes ARGB hex; these are the Quickshell theme values.
  theme = {
    accent = "0xff219fff";
    accentSurface = "0x33219fff";
    border = "0x66219fff";
    cardSurface = "0xf21e1e2e";
    muted = "0xfff38ba8";
    subdued = "0xffa6adc8";
    surface = "0xf2181825";
    text = "0xffcdd6f4";
  };

  # SketchyBar renders bitmap images only and cannot tint them, so rasterise
  # each provider SVG once per status colour, at 2x for the Retina bar (scaled
  # back down with image.scale in sketchybarrc). Files are named after the omp
  # provider id, <provider>-<tone>.png, as widgets.py expects.
  logoTones = [
    "accent"
    "muted"
    "subdued"
    "text"
  ];
  providerLogos =
    pkgs.runCommand "sketchybar-provider-logos" { nativeBuildInputs = [ pkgs.resvg ]; }
      (
        ''
          mkdir -p "$out"
        ''
        + lib.concatMapStrings (
          tone:
          let
            # 0xAARRGGBB -> #RRGGBB
            hex = "#" + builtins.substring 4 6 theme.${tone};
          in
          ''
            substitute ${providerLogoSources.anthropic} anthropic.svg --replace-fail currentColor "${hex}"
            substitute ${providerLogoSources.openai} openai.svg --replace-fail currentColor "${hex}"
            resvg -w 28 -h 28 anthropic.svg "$out/anthropic-${tone}.png"
            resvg -w 28 -h 28 openai.svg "$out/openai-codex-${tone}.png"
          ''
        ) logoTones
      );

  plugin = pkgs.writeTextFile {
    name = "sketchybar-widgets";
    executable = true;
    destination = "/bin/sketchybar-widgets";
    text =
      builtins.replaceStrings
        [
          "#!/usr/bin/env python3"
          "@sketchybar@"
          "@notion@"
          "@work@"
          "@workLabel@"
          "@timer@"
          "@herdr@"
          "@herdrView@"
          "@omp@"
          "@logoDir@"
          "@aerospace@"
          "@upgradeStatus@"
          "@upgradeLog@"
          "@accent@"
          "@accentSurface@"
          "@surface@"
          "@muted@"
          "@subdued@"
          "@text@"
        ]
        [
          "#!${pkgs.python3}/bin/python3"
          (lib.getExe cfg.package)
          (lib.getExe backends.helpers.notion)
          (lib.optionalString backends.workTasks.enable "${backends.helpers.work}/bin/work-tasks")
          backends.workTasks.label
          (lib.getExe backends.helpers.timer)
          (lib.getExe herdrPackage)
          "${config.home.profileDirectory}/bin/herdr-view"
          (lib.getExe config.programs.omp.package)
          "${providerLogos}"
          (lib.optionalString config.tomkoreny.aerospace.enable (lib.getExe pkgs.aerospace))
          common.darwinAutoUpgrade.statusFile
          common.darwinAutoUpgrade.log
          theme.accent
          theme.accentSurface
          theme.surface
          theme.muted
          theme.subdued
          theme.text
        ]
        (builtins.readFile ./widgets.py);
  };

  sketchybarrc = pkgs.replaceVarsWith {
    src = ./sketchybarrc;
    isExecutable = true;
    replacements = {
      bash = lib.getExe pkgs.bash;
      sketchybar = lib.getExe cfg.package;
      plugin = lib.getExe plugin;
      # The SF Pro Display Nerd Font family lists only Regular and Bold faces
      # (`fc-list`); Semibold rendered thin in the bar, Bold reads clearly.
      font = "${fontFamily}:Bold:12.0";
      smallFont = "${fontFamily}:Bold:9.0";
      inherit (theme)
        accent
        accentSurface
        border
        cardSurface
        surface
        text
        ;
    };
  };
in
{
  options.tomkoreny.sketchybar = {
    enable = lib.mkEnableOption "the SketchyBar status island on macOS";
    package = lib.mkPackageOption pkgs "sketchybar" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "tomkoreny.sketchybar is macOS-only.";
      }
    ];

    tomkoreny.bar-backends.enable = true;

    home.packages = [
      cfg.package
      plugin
    ];

    xdg.configFile."sketchybar/sketchybarrc" = {
      source = sketchybarrc;
      executable = true;
    };

    launchd.agents.sketchybar = {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe cfg.package)
          "--config"
          "${sketchybarrc}"
        ];
        # The plugin spawns herdr-view (Ghostty from Homebrew) and `open`;
        # launchd agents do not inherit the login shell PATH.
        EnvironmentVariables.PATH = lib.concatStringsSep ":" [
          "${config.home.profileDirectory}/bin"
          "/run/current-system/sw/bin"
          "/opt/homebrew/bin"
          "/usr/bin"
          "/bin"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sketchybar.log";
      };
    };

    targets.darwin.defaults.NSGlobalDomain = {
      _HIHideMenuBar = true;
      # System Settings > Menu Bar > "Show menu bar background". Without it the
      # revealed menu bar is transparent and its text draws over SketchyBar.
      SLSMenuBarUseBlurredAppearance = true;
    };
    # macOS reads both defaults only at login or when System Settings applies
    # them, so without this the native bar keeps drawing over SketchyBar until
    # the next login. The notification re-reads the hiding setting, and
    # SkyLight's SLSSetMenuBarUseBlurredAppearance applies the background.
    home.activation.applyMenuBarHiding = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("AppleInterfaceMenuBarHidingChangedNotification", $(), $(), true)'
      run /usr/bin/osascript -l JavaScript -e 'ObjC.bindFunction("dlopen", ["void*", ["char*", "int"]]); $.dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", 1); ObjC.bindFunction("SLSSetMenuBarUseBlurredAppearance", ["int", ["bool"]]); $.SLSSetMenuBarUseBlurredAppearance(true)' >/dev/null
    '';
  };
}
