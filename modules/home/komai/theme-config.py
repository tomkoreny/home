import os
import sys
from pathlib import Path

import yaml


config_root = Path(sys.argv[1]).expanduser()
profiles_root = config_root / "profiles"
config_paths = sorted(profiles_root.glob("*/config.yml"))
if not config_paths:
    config_paths = [profiles_root / "default" / "config.yml"]

for config_path in config_paths:
    if config_path.exists():
        data = yaml.safe_load(config_path.read_text()) or {}
        mode = config_path.stat().st_mode & 0o777
    else:
        data = {}
        mode = 0o600

    if not isinstance(data, dict):
        raise TypeError(f"{config_path}: expected a YAML mapping")

    ui = data.setdefault("ui", {})
    if not isinstance(ui, dict):
        raise TypeError(f"{config_path}: ui must be a YAML mapping")

    theme = ui.setdefault("theme", {})
    if not isinstance(theme, dict):
        raise TypeError(f"{config_path}: ui.theme must be a YAML mapping")

    desired = {
        "slug": "dark-catppuccin-stylix",
        "mode": "auto",
    }
    if all(theme.get(key) == value for key, value in desired.items()):
        continue

    theme.update(desired)
    config_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = config_path.with_name(f".{config_path.name}.tmp")
    temporary_path.write_text(yaml.safe_dump(data, sort_keys=False))
    os.chmod(temporary_path, mode)
    os.replace(temporary_path, config_path)
