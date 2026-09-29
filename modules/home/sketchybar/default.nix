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
    border = "0x66219fff";
    cardSurface = "0xf21e1e2e";
    muted = "0xfff38ba8";
    subdued = "0xffa6adc8";
    surface = "0xf2181825";
    text = "0xffcdd6f4";
  };

  # SketchyBar renders bitmap images only; rasterise the provider SVGs at 2x
  # for the Retina bar (scaled back down with image.scale in sketchybarrc).
  providerLogos =
    pkgs.runCommand "sketchybar-provider-logos" { nativeBuildInputs = [ pkgs.resvg ]; }
      ''
        mkdir -p "$out"
        substitute ${providerLogoSources.anthropic} anthropic.svg --replace-fail currentColor "#ffffff"
        substitute ${providerLogoSources.openai} openai.svg --replace-fail currentColor "#ffffff"
        resvg -w 36 -h 36 anthropic.svg "$out/anthropic.png"
        resvg -w 36 -h 36 openai.svg "$out/openai.png"
      '';

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
          "@openaiLogo@"
          "@anthropicLogo@"
          "@accent@"
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
          "${providerLogos}/openai.png"
          "${providerLogos}/anthropic.png"
          theme.accent
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
      font = "${fontFamily}:Semibold:12.0";
      inherit (theme)
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

    targets.darwin.defaults.NSGlobalDomain._HIHideMenuBar = true;
    # macOS reads _HIHideMenuBar only at login or when System Settings posts
    # this notification, so without it the native bar keeps drawing over
    # SketchyBar until the next login. Posting it applies the change live.
    home.activation.applyMenuBarHiding = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
      run /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("AppleInterfaceMenuBarHidingChangedNotification", $(), $(), true)'
    '';
  };
}
