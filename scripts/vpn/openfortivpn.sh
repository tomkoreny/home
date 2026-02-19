#!/usr/bin/env bash
set -euo pipefail

# Use sudo automatically when running manually without sufficient privileges.
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" "$@"
  fi

  echo "openfortivpn requires root privileges" >&2
  exit 1
fi

readonly config_path="${OPENFORTIVPN_CONFIG:-/run/openfortivpn.conf}"
readonly openfortivpn_bin="${OPENFORTIVPN_BIN:-openfortivpn}"

if [ ! -r "$config_path" ]; then
  echo "VPN config not readable: $config_path" >&2
  exit 1
fi

exec "$openfortivpn_bin" --config "$config_path" "$@"
