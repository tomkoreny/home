# Microsoft AutoUpdate (MAU), the program through which Teams for Mac updates
# itself (learn.microsoft.com/microsoftteams/teams-client-update). Homebrew's
# microsoft-teams cask installs Teams with the MAU in its installer switched
# off, and brew does not upgrade Teams either (the cask is auto_updates, and
# an upgrade needs sudo), so without MAU nothing updates Teams. That was this
# Mac until 2026-11-15: MAU's app was gone, the last update its preferences
# record is from February 2025, and Teams only moved when it was reinstalled.
#
# MAU's package needs root to install, which the unattended `brew bundle` does
# not have, so the microsoft-auto-update cask cannot be declared. Activation
# installs the package instead, whenever the app is missing, and fails when it
# cannot, which the auto-upgrade warning on the bar then shows. MAU updates
# itself from then on: the version here is only where a Mac without it starts.
#
# After an install the session that is logged in at the time does not get
# MAU's agent: on macOS 27.0.1 launchd turned it down ("Unable to verify
# trusted spawn") when the installer loaded it, when MAU was opened and when
# it was bootstrapped by hand. Whether a later login starts it has not been
# seen yet; Teams > Help > Check for Updates opening MAU is the sign that it
# has.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.darwin.microsoft-autoupdate;
  version = "4.85.26091737";
  # Signed by Microsoft Corporation (UBF8T346G9) and notarized; the same file
  # and hash as Homebrew's microsoft-auto-update cask.
  package = pkgs.fetchurl {
    name = "microsoft-autoupdate-${version}.pkg";
    url = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_AutoUpdate_${version}_Updater.pkg";
    hash = "sha256-1kerqVOJg/DGzYktLDRCtxrhyFc85Ty/Yus+qDHp0WU=";
  };
  app = "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app";
in
{
  options.tomkoreny.darwin.microsoft-autoupdate.enable =
    lib.mkEnableOption "keeping Microsoft AutoUpdate installed, which updates Teams";

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      if [ ! -d "${app}" ]; then
        echo "installing Microsoft AutoUpdate ${version}" >&2
        if ! /usr/sbin/installer -pkg ${package} -target / >&2; then
          echo "error: Microsoft AutoUpdate could not be installed; nothing updates Teams" >&2
          exit 1
        fi
      fi
    '';
  };
}
