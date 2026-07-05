{
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
in
{
  programs.git = {
    package = pkgs.git;
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
