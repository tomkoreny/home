# White-on-transparent provider logos for the AI usage widget, shared by the
# Quickshell (SVG) and SketchyBar (rasterised) bars.
pkgs: {
  anthropic = pkgs.fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.94.0/icons/anthropic.svg";
    hash = "sha256-6DP9+n5xh6hqBbhwklBnVWpQbc1COQia7XPh5YyTZqM=";
  };
  openai = pkgs.fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.94.0/icons/openai.svg";
    hash = "sha256-pZXfa0I5IMZ6f49zwGPkv7ctQVlICXtsrAY6I2a7UYY=";
  };
}
