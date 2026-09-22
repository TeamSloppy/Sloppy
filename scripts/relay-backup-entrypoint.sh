#!/bin/sh
set -eu

chown postgres:postgres /backups
exec gosu postgres /bin/sh /scripts/relay-backup.sh
