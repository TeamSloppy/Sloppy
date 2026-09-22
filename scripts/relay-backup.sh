#!/bin/sh
set -eu

# Run only in the Compose maintenance container, as the postgres user. The
# /backups mount must be dedicated to one environment (test or production).
BACKUP_ROOT=${SLOPPY_RELAY_BACKUP_ROOT:-/backups}
DB_HOST=${SLOPPY_RELAY_DB_HOST:-postgres}
DB_PORT=${SLOPPY_RELAY_DB_PORT:-5432}
DB_USER=${SLOPPY_RELAY_DB_USER:-relay_service}
DB_NAME=${SLOPPY_RELAY_DB_NAME:-relay}
PASSWORD_FILE=${SLOPPY_RELAY_DB_PASSWORD_FILE:-/run/secrets/postgres_password}
SOCKET_PORT=55434
LOGICAL_PORT=55435

case "$BACKUP_ROOT" in
    /backups|/tmp/sloppy-relay-backup-*) ;;
    *) echo "Refusing an unexpected backup root" >&2; exit 2 ;;
esac
if [ ! -d "$BACKUP_ROOT" ] || [ ! -f "$PASSWORD_FILE" ]; then
    echo "Missing dedicated backup volume or database password secret" >&2
    exit 2
fi

PGPASSWORD=$(tr -d '\r\n' <"$PASSWORD_FILE")
export PGPASSWORD
PGCONNECT_TIMEOUT=10
export PGCONNECT_TIMEOUT

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
STAGE=$(mktemp -d "$BACKUP_ROOT/.incomplete.XXXXXXXX")
PHYSICAL_STARTED=0
LOGICAL_STARTED=0
SUCCESS=0

cleanup() {
    if [ "$PHYSICAL_STARTED" -eq 1 ]; then
        pg_ctl -D "$STAGE/restore-physical" -m immediate stop >/dev/null 2>&1 || true
    fi
    if [ "$LOGICAL_STARTED" -eq 1 ]; then
        pg_ctl -D "$STAGE/restore-logical" -m immediate stop >/dev/null 2>&1 || true
    fi
    if [ "$SUCCESS" -eq 0 ] && [ -d "$STAGE" ]; then
        rm -r -- "$STAGE"
    fi
}
trap cleanup EXIT HUP INT TERM

pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Fc -f "$STAGE/logical.dump"
pg_basebackup -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -D "$STAGE/physical" -Ft -X stream --checkpoint=fast

mkdir -p "$STAGE/restore-physical"
tar -xf "$STAGE/physical/base.tar" -C "$STAGE/restore-physical"
chmod 700 "$STAGE/restore-physical"
mkdir -p "$STAGE/restore-physical/pg_wal"
tar -xf "$STAGE/physical/pg_wal.tar" -C "$STAGE/restore-physical/pg_wal"
pg_ctl -D "$STAGE/restore-physical" \
    -o "-k $STAGE -p $SOCKET_PORT -c listen_addresses=''" start >/dev/null
PHYSICAL_STARTED=1
psql -h "$STAGE" -p "$SOCKET_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -Atqc "SELECT count(*) FROM personal_spaces" >/dev/null
pg_ctl -D "$STAGE/restore-physical" -m immediate stop >/dev/null
PHYSICAL_STARTED=0

initdb -D "$STAGE/restore-logical" -A trust -U "$DB_USER" >/dev/null
pg_ctl -D "$STAGE/restore-logical" \
    -o "-k $STAGE -p $LOGICAL_PORT -c listen_addresses=''" start >/dev/null
LOGICAL_STARTED=1
createdb -h "$STAGE" -p "$LOGICAL_PORT" -U "$DB_USER" "$DB_NAME"
pg_restore -h "$STAGE" -p "$LOGICAL_PORT" -U "$DB_USER" \
    -d "$DB_NAME" --exit-on-error "$STAGE/logical.dump"
psql -h "$STAGE" -p "$LOGICAL_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -Atqc "SELECT count(*) FROM personal_spaces" >/dev/null
pg_ctl -D "$STAGE/restore-logical" -m immediate stop >/dev/null
LOGICAL_STARTED=0

rm -r -- "$STAGE/restore-physical" "$STAGE/restore-logical"
(
    cd "$STAGE"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum logical.dump physical/base.tar physical/pg_wal.tar > SHA256SUMS.txt
        sha256sum -c SHA256SUMS.txt >/dev/null
    else
        shasum -a 256 logical.dump physical/base.tar physical/pg_wal.tar > SHA256SUMS.txt
        shasum -a 256 -c SHA256SUMS.txt >/dev/null
    fi
)
printf '%s\n' "physical and logical restore smoke passed" > "$STAGE/RESTORE_OK.txt"
mv -- "$STAGE" "$BACKUP_ROOT/$STAMP"
SUCCESS=1
trap - EXIT HUP INT TERM

# All matching children are timestamped backup sets in this dedicated volume.
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name '20??????T??????Z' -mtime +13 -exec rm -r -- {} +
printf '%s\n' "Backup and restore smoke complete: $STAMP"
