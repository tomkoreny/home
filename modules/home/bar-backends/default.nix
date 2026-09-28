{
  config,
  lib,
  pkgs,
  ...
}:
# Data backends shared by the desktop bars: the Quickshell bar on Linux and
# the SketchyBar port on macOS render the same Notion todos, work tasks and
# timers, so the helper executables and their secrets live here and each bar
# only consumes `config.tomkoreny.bar-backends.helpers`.
let
  cfg = config.tomkoreny.bar-backends;
  notionTodoAssigneeId = "c3045b6d-8e81-4f7a-a5fe-ebf07f041fef";

  timerHelper = pkgs.writeTextFile {
    name = "quickshell-timer";
    executable = true;
    destination = "/bin/quickshell-timer";
    text = builtins.replaceStrings [ "#!/usr/bin/env python3" ] [ "#!${pkgs.python3}/bin/python3" ] (
      builtins.readFile ./timer-backend.py
    );
  };

  notionTodoHelper = pkgs.writeTextFile {
    name = "notion-todos";
    executable = true;
    destination = "/bin/notion-todos";
    text =
      builtins.replaceStrings
        [
          "#!/usr/bin/env python3"
          "/run/secrets/notion-todos"
          "@notion-todos-assignee-id@"
        ]
        [
          "#!${pkgs.python3}/bin/python3"
          config.sops.secrets.notion-todos.path
          notionTodoAssigneeId
        ]
        (builtins.readFile ./notion-todos.py);
  };

  workConfig = pkgs.writeText "work-tasks-config.json" (
    builtins.toJSON {
      inherit (cfg.workTasks) provider baseUrl label;
      tokenFile = if cfg.workTasks.enable then config.sops.secrets.work-tasks.path else "";
    }
  );
  workTaskHelper = pkgs.runCommand "work-tasks" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p "$out/lib/work-tasks" "$out/bin"
    substitute ${./work-tasks.py} "$out/lib/work-tasks/work-tasks.py" \
      --replace-fail '@workConfig@' '${workConfig}'
    cp ${./mantis_tasks.py} "$out/lib/work-tasks/mantis_tasks.py"
    makeWrapper ${pkgs.python3}/bin/python3 "$out/bin/work-tasks" \
      --add-flags "$out/lib/work-tasks/work-tasks.py"
  '';
in
{
  options.tomkoreny.bar-backends = {
    enable = lib.mkEnableOption "the Notion todo, work task and timer helpers behind the desktop bars";

    workTasks = {
      enable = lib.mkEnableOption "independent provider-backed work tasks";
      provider = lib.mkOption {
        type = lib.types.enum [ "mantisbt" ];
        default = "mantisbt";
        description = "Work task provider adapter";
      };
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "HTTPS root URL of the work task provider";
      };
      label = lib.mkOption {
        type = lib.types.str;
        default = "Work provider";
        description = "Provider name shown in the work count tooltip";
      };
      sopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "SOPS-encrypted JSON containing the personal API token under token";
      };
    };

    helpers = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "Helper executables (timer, notion, work) for bar frontends to call";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.workTasks.enable || cfg.workTasks.sopsFile != null;
        message = "Work tasks require a SOPS-encrypted token file.";
      }
      {
        assertion = !cfg.workTasks.enable || lib.hasPrefix "https://" cfg.workTasks.baseUrl;
        message = "Work tasks require an HTTPS provider base URL.";
      }
    ];

    tomkoreny.bar-backends.helpers = {
      timer = timerHelper;
      notion = notionTodoHelper;
      work = workTaskHelper;
    };

    sops.secrets.notion-todos = {
      sopsFile = ../../../secrets/notion/todos.json;
      format = "binary";
      mode = "0400";
    };
    sops.secrets.work-tasks = lib.mkIf cfg.workTasks.enable {
      sopsFile = cfg.workTasks.sopsFile;
      format = "json";
      key = "token";
      mode = "0400";
    };

    home.packages = [
      timerHelper
      notionTodoHelper
    ]
    ++ lib.optional cfg.workTasks.enable workTaskHelper;
  };
}
