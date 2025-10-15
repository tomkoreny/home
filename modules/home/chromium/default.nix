{pkgs, ...}: {
  programs.chromium = {
    enable = true;
    package = pkgs.google-chrome;
    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-features=UseOzonePlatform,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL" # Video decode
      "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder" # Video encode
      # "--enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE" # Vulkan - makes window transparent
      "--enable-accelerated-video-decode"
      "--enable-gpu-rasterization"
      "--ignore-gpu-blocklist"
      # Network stability improvements
      # "--disable-quic"  # Disable QUIC protocol which can cause connection issues
      # "--disable-background-timer-throttling"  # Prevent connection timeouts
      # "--aggressive-cache-discard"  # Clear problematic cache entries
      # "--disable-features=NetworkService"  # Use legacy network stack if issues persist
    ];
  };
}
