# The hyprland input tracks main, which since v0.56 reports workspaces as
# {address, type, name} without a numeric "id" in hyprctl JSON and socket2
# selectors. Quickshell 0.3.1 keys its Hyprland workspace model on "id", so
# every workspace parsed as 0 and collapsed into one entry, blanking the bar's
# workspace strip. Upstream Quickshell has no fix yet; drop this once it does.
#
# Applied to both the NixOS package set and the standalone Home Manager
# evaluation so `pkgs.quickshell` is the same binary in every consumer.
final: prev: {
  quickshell = prev.quickshell.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./quickshell-hyprland-workspace-address.patch ];
  });
}
