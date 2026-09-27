{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tomkoreny.moshi-hook;
  package = pkgs.callPackage ./package.nix { };
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # moshi-hook bridges agent hooks (OMP, Claude Code, Codex, ...) to the Moshi
  # phone app: push notifications, approvals, Chat View, and Herdr session
  # context. Pairing (`moshi-hook pair --token ...`) and hook installation
  # (`moshi-hook install`) write per-user state and stay manual, because the
  # pairing token is shown once by the phone.
  options.tomkoreny.moshi-hook.enable = lib.mkEnableOption "the moshi-hook daemon for the Moshi mobile terminal";

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    # Replaces `moshi-hook service install`, which would write an unmanaged
    # unit pointing at a mutable binary path.
    systemd.user.services.moshi-hook = {
      Unit.Description = "moshi-hook daemon for the Moshi mobile terminal";
      Service = {
        ExecStart = "${lib.getExe package} serve";
        # Session context, the diff viewer, and dev-server discovery shell out
        # to herdr, tmux, git, and ps; a user unit does not inherit the login
        # shell PATH.
        Environment = [
          "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          "MOSHI_HERDR_PATH=${lib.getExe herdrPackage}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
