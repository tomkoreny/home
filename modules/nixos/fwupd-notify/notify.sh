# Raise one desktop notification when fwupd has firmware to install.
#
# The same set of updates is announced once, and again after a week while it
# is still pending. $STATE_DIRECTORY remembers what was last announced.

state="${STATE_DIRECTORY:?}/announced"

# fwupdmgr exits 2 when there is nothing to update; anything else is an error.
rc=0
updates=$(fwupdmgr get-updates --json --no-unreported-check) || rc=$?
if [ "$rc" -eq 2 ]; then
  updates='{"Devices":[]}'
elif [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

pending=$(jq -r '
  .Devices[]?
  | select((.Releases // []) | length > 0)
  | "\(.Name): \(.Version) to \(.Releases[0].Version)"
' <<< "$updates")

if [ -z "$pending" ]; then
  rm -f "$state"
  exit 0
fi

if [ "$pending" = "$(cat "$state" 2> /dev/null)" ] && [ -n "$(find "$state" -mtime -7)" ]; then
  exit 0
fi

# systembus-notify relays this signal to the session's notification daemon.
dbus-send --system / net.nuetzlich.SystemNotifications.Notify \
  "string:Firmware updates available" \
  "string:$pending
Install with: fwupdmgr update"
printf '%s\n' "$pending" > "$state"
