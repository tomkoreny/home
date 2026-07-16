{
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
in
{
  programs.git = {
    # Build git with the libsecret credential helper compiled in, so the
    # "libsecret" helper below resolves on PATH. Without this, pkgs.git ships
    # only the helper's C source (never built), the helper errors out, and the
    # oauth fallback re-runs the browser flow on every push because it has no
    # working backend to store the token in.
    package = pkgs.git.override { withLibsecret = true; };
    enable = true;
    signing.format = "openpgp";
    settings = {
      user = {
        email = common.user.email;
        name = common.user.fullName;
      };
      credential.helper =
        if pkgs.stdenv.isDarwin then
          "osxkeychain"
        else
          [
            "libsecret"
            "oauth"
          ];
      push = {
        autoSetupRemote = true;
      };
      pull.rebase = true;
    };
  };
}
