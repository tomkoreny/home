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
  # context. Pairing (`moshi-hook pair --token ...`) writes a per-host secret
  # from a token the phone shows once, so it stays manual.
  options.tomkoreny.moshi-hook.enable = lib.mkEnableOption "the moshi-hook daemon for the Moshi mobile terminal";

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    # Writes Moshi-owned entries into each installed agent's config and skips
    # agents that are absent; re-running is a no-op. It never prompts: Codex's
    # daemon_auto_start is only reported, not changed. Runs after
    # linkGeneration for the same reason as herdrOmpIntegration: the OMP agent
    # directory may not exist earlier on a fresh host.
    home.activation.moshiHookInstall = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe package} install </dev/null
    '';

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
