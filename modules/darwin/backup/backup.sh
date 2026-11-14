# The controller of the Mac's backup. default.nix sets the variables below and
# calls `main`; test_backup.py does the same with stand-ins for what needs a
# Mac.
#
#   RESTIC            restic with the repository, password and cache given
#   JQ                jq
#   HOST              the host name the snapshots carry
#   STATUS            where each finished run's outcome is recorded
#   LOG               the log both launchd jobs write
#   SNAPSHOT_JOB      launchd label of the job that takes the snapshot
#   SNAPSHOT_PROGRAM  that job's program, named when files could not be read
#   UNCONFIRMED       the tag that job gives every snapshot it writes
#   MINIO_HOST        MinIO's IPv6 address
#   MINIO_PORT
#   HOME_PREFIX       what the Mac's own IPv6 addresses start with at home

say() { echo "$(date '+%F %T') $*"; }

status_field() { "$JQ" -r ".$1 // 0" "$STATUS" 2>/dev/null || echo 0; }

# record RESULT ERROR: a finished run. RESULT is success, incomplete (restic
# wrote a snapshot but could not read every file) or failure.
record() {
  local result=$1 error=$2 now last_success last_incomplete
  now=$(date +%s)
  last_success=$(status_field lastSuccessAt)
  last_incomplete=$(status_field lastIncompleteAt)
  case "$result" in
    success) last_success=$now ;;
    incomplete) last_incomplete=$now ;;
  esac
  mkdir -p "$(dirname "$STATUS")"
  "$JQ" -n \
    --arg result "$result" \
    --arg error "$error" \
    --argjson finishedAt "$now" \
    --argjson lastSuccessAt "$last_success" \
    --argjson lastIncompleteAt "$last_incomplete" \
    '{result: $result, error: $error, finishedAt: $finishedAt, lastSuccessAt: $lastSuccessAt, lastIncompleteAt: $lastIncompleteAt}' \
    > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

# A snapshot a day is enough, and an incomplete one counts: without Full Disk
# Access every run is incomplete, and one every three hours would only pile
# them up. A run that failed is tried again at the next slot.
due() {
  local now last
  now=$(date +%s)
  for last in "$(status_field lastSuccessAt)" "$(status_field lastIncompleteAt)"; do
    [ $((now - last)) -ge $((20 * 3600)) ] || return 1
  done
}

on_mains() { pmset -g batt | grep -q "AC Power"; }

# At home the interface that leads to MinIO holds an address of the home's
# prefix, and MinIO answers. Anywhere else the first is not so, whichever way
# MinIO may be reached from there.
at_home() {
  local interface
  interface=$(route -n get -inet6 "$MINIO_HOST" 2>/dev/null | awk '/interface:/ { print $2 }')
  [ -n "$interface" ] || return 1
  ifconfig "$interface" 2>/dev/null | grep -q "inet6 $HOME_PREFIX" || return 1
  curl -g -fsS -m 5 -o /dev/null "http://[$MINIO_HOST]:$MINIO_PORT/minio/health/live" 2>/dev/null
}

# The id of this host's newest snapshot; nothing when there is none or the
# repository did not answer.
newest_snapshot() {
  "$RESTIC" snapshots --host "$HOST" --json 2>/dev/null | "$JQ" -r 'max_by(.time) | .id // empty' 2>/dev/null
}

log_size() { if [ -e "$LOG" ]; then wc -c < "$LOG" | tr -d ' '; else echo 0; fi; }

# The first line restic wrote about a failure after byte $1 of the log.
first_error() {
  tail -c "+$(($1 + 1))" "$LOG" 2>/dev/null | grep -m1 -i -E '^(fatal|error):' | cut -c1-200
}

# failed WHAT OFFSET: a run that did not end with a usable snapshot.
failed() {
  local error
  error=$(first_error "$2")
  say "backup failed: $1"
  record failure "${error:-$1}"
}

# Starts the snapshot job, waits for it and prints its exit status. The
# snapshot is a job of its own so that macOS judges SNAPSHOT_PROGRAM itself
# for Full Disk Access, not this script's interpreter.
take_snapshot() {
  launchctl kickstart "system/$SNAPSHOT_JOB" || return 1
  sleep 2
  while launchctl print "system/$SNAPSHOT_JOB" | grep -q 'state = running'; do
    sleep 15
  done
  launchctl print "system/$SNAPSHOT_JOB" | awk '/last exit code/ { print $5; exit }'
}

# finish CODE BEFORE OFFSET: what follows a snapshot job that ended with
# status CODE. BEFORE is the newest snapshot from before it ran, OFFSET where
# the log stood then.
#
# The job tags every snapshot UNCONFIRMED. Only here, after restic said that
# it read everything, does the tag come off, so whatever goes wrong on the
# way leaves a snapshot marked as one not to rely on.
finish() {
  local code=$1 before=$2 offset=$3 newest error
  case "$code" in
    0) ;;
    3)
      # restic wrote the snapshot but could not read some files. Nothing is
      # removed from the repository after a run like this.
      error=$(first_error "$offset")
      say "backup incomplete: some files could not be read"
      record incomplete "incomplete, some files could not be read (does $SNAPSHOT_PROGRAM have Full Disk Access?): $error"
      return 1
      ;;
    *)
      failed "restic backup exited with status $code" "$offset"
      return 1
      ;;
  esac

  newest=$(newest_snapshot)
  if [ -z "$newest" ] || [ "$newest" = "$before" ]; then
    failed "restic backup reported success, but the repository shows no new snapshot" "$offset"
    return 1
  fi
  if ! "$RESTIC" tag --remove "$UNCONFIRMED" "$newest" > /dev/null; then
    failed "the new snapshot could not be marked complete" "$offset"
    return 1
  fi
  # restic keeps the last snapshot of each day, week and month. Grouped by
  # tag, the unconfirmed ones are thinned out among themselves and can never
  # be the one kept in place of a complete snapshot.
  if ! "$RESTIC" forget --group-by host,paths,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune; then
    failed "restic forget failed" "$offset"
    return 1
  fi
  if ! "$RESTIC" check; then
    failed "restic check failed" "$offset"
    return 1
  fi
  say "backup finished"
  record success ""
}

main() {
  local before offset code
  # Not due, on battery, or not at home: nothing to do and nothing to record.
  due || return 0
  on_mains || return 0
  at_home || return 0

  say "backup started"
  # A run cut short by a reboot leaves its lock in the repository; this
  # removes only locks whose process is gone.
  "$RESTIC" unlock > /dev/null 2>&1
  before=$(newest_snapshot)
  offset=$(log_size)
  if ! code=$(take_snapshot); then
    failed "the snapshot job could not be started" "$offset"
    return 1
  fi
  finish "$code" "$before" "$offset"
}
