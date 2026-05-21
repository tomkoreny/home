{
  pkgs,
  ...
}:
let
  common = import ../../../lib/common { };
  betterbird-unwrapped = pkgs.callPackage ./package.nix { };
  betterbird =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.wrapThunderbird betterbird-unwrapped {
        applicationName = "betterbird";
        pname = "betterbird";
        icon = "betterbird";
        wmClass = "Betterbird";
      }
    else
      betterbird-unwrapped;

  microsoft365Oauth2Settings = id: {
    "mail.server.server_${id}.authMethod" = 10;
    "mail.smtpserver.smtp_${id}.authMethod" = 10;
  };

  replyAboveQuoteSettings = id: {
    "mail.identity.id_${id}.reply_on_top" = 1;
  };
in
{
  # Betterbird uses Thunderbird's profile/account directory layout. Home
  # Manager's Thunderbird module is still the right declarative generator.
  programs.thunderbird = {
    enable = true;
    package = betterbird;

    profiles.default = {
      isDefault = true;
      accountsOrder = [
        "tom"
        "it2go"
        "plaut"
        "pumaslab"
      ];
    };
  };

  # The Thunderbird module owns this file; replace any imperative copy.
  home.file.".thunderbird/profiles.ini".force = true;

  accounts.email.accounts = {
    tom = {
      primary = true;
      flavor = "gmail.com";
      address = common.user.email;
      realName = common.user.fullName;

      # Google Workspace uses OAuth2 here, so no password is stored in this repo.
      thunderbird = {
        enable = true;
        perIdentitySettings = replyAboveQuoteSettings;
      };
    };

    it2go = {
      flavor = "outlook.office365.com";
      address = "tomas.koreny@it2go.cz";
      realName = common.user.fullName;

      thunderbird = {
        enable = true;
        settings = microsoft365Oauth2Settings;
        perIdentitySettings = replyAboveQuoteSettings;
      };
    };

    plaut = {
      flavor = "outlook.office365.com";
      address = "koreny@plaut.sk";
      realName = common.user.fullName;

      thunderbird = {
        enable = true;
        settings = microsoft365Oauth2Settings;
        perIdentitySettings = replyAboveQuoteSettings;
      };
    };

    pumaslab = {
      flavor = "gmail.com";
      address = "pumaslab@gmail.com";
      realName = common.user.fullName;

      thunderbird = {
        enable = true;
        perIdentitySettings = replyAboveQuoteSettings;
      };
    };
  };
}
