# Consistent dumps of the databases in running containers, written to $DUMP_DIR
# for restic to pick up. The volumes are backed up as files as well, but files
# copied from under a running database are not a backup of it.
#
# An engine is recognised by the environment variables its image defines, so a
# new compose project is covered without being listed here. The dump commands
# run inside the container and read its own credentials there.
#
# One failed dump never stops the others. Each failure is appended to
# $FAILURES; the backup unit still writes its snapshot and then fails.

dump_dir=${DUMP_DIR:?}
failures=${FAILURES:?}

# Built aside and swapped in, so the directory only ever holds this run's dumps.
new="$dump_dir.new"
rm -rf "$new"
install -d -m 0700 "$new"
: > "$failures"

record_failure() {
  echo "database dump failed: $1" >&2
  echo "$1" >> "$failures"
}

# shellcheck disable=SC2016 # these run inside the container
pg_dump='exec pg_dumpall -U "${POSTGRES_USER:-postgres}"'
# shellcheck disable=SC2016
mysql_dump='
  dump=$(command -v mariadb-dump || command -v mysqldump) || exit 1
  MYSQL_PWD="${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}" exec "$dump" \
    --user=root --all-databases --single-transaction --routines --events'
# SQL Server can only back up to a path it can write, so it writes .bak files
# inside the container and tar streams them out.
# shellcheck disable=SC2016
mssql_dump='
  sqlcmd=$(ls -d /opt/mssql-tools*/bin/sqlcmd 2>/dev/null | tail -n 1)
  [ -n "$sqlcmd" ] || exit 1
  case $sqlcmd in *tools18*) trust=-C ;; *) trust= ;; esac
  export SQLCMDPASSWORD="${MSSQL_SA_PASSWORD:-$SA_PASSWORD}"
  out=/var/opt/mssql/backup
  mkdir -p "$out" && rm -f "$out"/*.bak || exit 1
  databases=$("$sqlcmd" $trust -S localhost -U sa -b -h -1 -W \
    -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4") || exit 1
  for db in $databases; do
    "$sqlcmd" $trust -S localhost -U sa -b \
      -Q "BACKUP DATABASE [$db] TO DISK = N'"'"'$out/$db.bak'"'"' WITH INIT" >&2 || exit 1
  done
  exec tar -C "$out" -cf - .'

for id in $(docker ps --quiet); do
  name=$(docker inspect --format '{{.Name}}' "$id") || continue
  name=${name#/}
  variables=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" | cut -d= -f1) || continue

  if grep -qx -e PGDATA -e POSTGRES_USER <<< "$variables"; then
    engine=postgres command=$pg_dump out="$new/$name.pg.sql"
  elif grep -qx -e MARIADB_ROOT_PASSWORD -e MYSQL_ROOT_PASSWORD <<< "$variables"; then
    engine=mysql command=$mysql_dump out="$new/$name.mysql.sql"
  elif grep -qx -e MSSQL_SA_PASSWORD -e SA_PASSWORD <<< "$variables"; then
    engine=mssql command=$mssql_dump out="$new/$name.mssql.tar"
  else
    continue
  fi

  if docker exec "$id" sh -c "$command" > "$out" && [ -s "$out" ]; then
    echo "dumped $name ($engine, $(stat -c %s "$out") bytes)"
  else
    rm -f "$out"
    record_failure "$name ($engine)"
  fi
done

rm -rf "$dump_dir"
mv "$new" "$dump_dir"
