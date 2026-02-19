{ pkgs, ... }: {
  # Keep JetBrains installation declarative via Nix.
  # Manage user settings/plugins via JetBrains Backup and Sync
  # (JetBrains Account) instead of version-pinned XML files in git.
  home.packages = [
    pkgs.jetbrains.datagrip
    pkgs.jetbrains.webstorm
    pkgs.jetbrains.pycharm
  ];
}
