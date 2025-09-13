{pkgs, ...}: {
  programs.chromium = {
    enable = true;
    package = pkgs.google-chrome;
    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-features=UseOzonePlatform,VaapiVideoDecodeLinuxGL"
      "--enable-accelerated-video-decode"
      "--enable-gpu-rasterization"
      "--ignore-gpu-blocklist"
    ];
  };
}
