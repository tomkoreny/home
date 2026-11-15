# One order for PATH on the Mac, whatever order shell start-up left it in.
# Start-up leaves several:
#
# - a login shell from a clean environment: nix-darwin sets the Nix profiles
#   and the system directories, then `brew shellenv` puts Homebrew in front;
# - a login shell started inside another one, as every terminal of the Herdr
#   app is: path_helper in /etc/profile moves the system directories to the
#   front, nix-darwin does not set PATH a second time, and Homebrew ends up
#   wherever `brew shellenv` finds a `brew` to ask;
# - a login shell that is not interactive (`bash -lc`): no Homebrew at all,
#   because /etc/bashrc stops before `brew shellenv`.
#
# The order made here: Nix profiles, the user's own tool directories,
# Homebrew, system. A directory none of those lists name keeps its side of
# the Nix profiles: what someone put in front of them stays in front (a
# virtualenv, `nix shell`, Rex), anything behind them goes between Homebrew
# and the system directories.
#
# default.nix sources this file on Darwin and calls `standard_path` at the end
# of ~/.profile and of ~/.bashrc; test_path_order.py calls `path_in_order`.

# path_in_order CURRENT NIX OWN HOMEBREW SYSTEM
# Each argument is a colon-separated list. Prints CURRENT in the order above;
# every directory of the four lists is in the result, once.
path_in_order() {
  local current=$1 nix=$2 own=$3 homebrew=$4 system=$5
  local listed=":$nix:$own:$homebrew:$system:" seen=: front='' behind='' past_nix='' entry
  local -a entries
  IFS=: read -r -a entries <<< "$current"
  for entry in "${entries[@]}"; do
    [ -n "$entry" ] || continue
    case "$seen" in *":$entry:"*) continue ;; esac
    seen="$seen$entry:"
    case ":$nix:" in *":$entry:"*)
      past_nix=1
      continue
      ;;
    esac
    case "$listed" in *":$entry:"*) continue ;; esac
    if [ -n "$past_nix" ]; then
      behind="$behind:$entry"
    else
      front="$front:$entry"
    fi
  done
  entry="$front:$nix:$own:$homebrew$behind:$system"
  printf '%s\n' "${entry#:}"
}

# The directories macOS puts on PATH, read the way path_helper reads them.
system_path() {
  local file line list=
  for file in /etc/paths /etc/paths.d/*; do
    [ -r "$file" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && list="$list:$line"
    done < "$file"
  done
  printf '%s\n' "${list#:}"
}

# Puts this machine's PATH in order.
standard_path() {
  local npm=${NPM_CONFIG_PREFIX:-$HOME/.local/share/npm} pnpm=${PNPM_HOME:-$HOME/.local/share/pnpm}
  PATH=$(path_in_order "$PATH" \
    "$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin" \
    "$HOME/.local/bin:$npm/bin:$pnpm:$pnpm/bin" \
    "/opt/homebrew/bin:/opt/homebrew/sbin" \
    "$(system_path)")
  export PATH
}
