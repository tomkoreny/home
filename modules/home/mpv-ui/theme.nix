{
  pkgs,
  lib,
  inputs,
}:
let
  common = import ../../../lib/common { };
  fontFamily = (common.stylix.fonts pkgs inputs).sansSerif.name;
  color = lib.removePrefix "#";
  controls = lib.concatStringsSep "," [
    "play-pause"
    "gap"
    "<seekable>command:replay_10:seek -10?Back 10 seconds"
    "<seekable>command:forward_10:seek 10?Forward 10 seconds"
    "space"
    "<has_sub>subtitles"
    "<has_many_audio>audio"
    "<has_chapter>chapters"
    "<seekable>speed"
    "gap"
    "menu"
    "fullscreen"
  ];
  uoscText = ''
    # No permanent OLED chrome, including in windowed playback.
    progress=never
    top_bar=never
    window_border_size=0
    autohide=yes
    timeline_style=line
    timeline_size=32
    timeline_line_width=2
    timeline_heatmap=no
    controls_size=28
    controls_margin=8
    controls_spacing=4
    controls_persistency=
    timeline_persistency=
    volume_persistency=
    volume_size=32
    menu_item_height=32
    menu_min_width=260
    menu_padding=6
    border_radius=6
    scale=1
    scale_fullscreen=1
    font_scale=1
    color=foreground=${color common.stylix.accent},foreground_text=000000,background=${color common.stylix.background},background_text=cdd6f4,curtain=${color common.stylix.background},success=a6e3a1,error=f38ba8,match=${color common.stylix.accent}
    opacity=controls=0.92,timeline=0.92,menu=1,submenu=0.8,curtain=0.45
    animation_duration=120
    proximity_in=32
    proximity_out=96
    destination_time=playtime-remaining
    pause_indicator=flash
    disable_elements=idle_indicator,audio_indicator
    autoload=no
  '';
in
{
  mpvConfig = pkgs.writeText "mpv-ui.conf" ''
    osc=no
    script=${./stream.lua}
    osd-bar=no
    border=no
    osd-font=${fontFamily}
    osd-color="#cdd6f4"
    osd-border-color="#000000"
    cursor-autohide=1500
  '';
  uoscConfig = pkgs.writeText "uosc.conf" (
    uoscText
    + ''
      controls=${controls}
    ''
  );
  jellyfinUoscConfig = pkgs.writeText "uosc-jellyfin.conf" (
    uoscText
    + ''
      # Shim owns the queue: do not navigate mpv's one-file playlist.
      controls=command:skip_previous:keypress PREV?Previous item,${
        builtins.replaceStrings [ ",menu," ] [ ",command:menu:script-message tom-jellyfin-menu?Menu," ]
          controls
      },command:skip_next:keypress NEXT?Next item,command:settings:keypress c?Jellyfin settings
    ''
  );
  inputConfig = pkgs.writeText "mpv-ui-input.conf" ''
    MBTN_RIGHT script-binding uosc/menu
    MENU script-binding uosc/menu
    TAB script-binding uosc/toggle-ui
  '';
}
