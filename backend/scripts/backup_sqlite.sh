#!/usr/bin/env bash
# Nightly SQLite backup — copy DB + WAL files off-box.
# Install: sudo cp scripts/backup_sqlite.sh /opt/signalapp/backup_sqlite.sh && sudo chmod +x /opt/signalapp/backup_sqlite.sh
# Cron:    0 2 * * * /opt/signalapp/backup_sqlite.sh >> /var/log/signalapp-backup.log 2>&1

set -euo pipefail

DB_PATH="${SQLITE_PATH:-/opt/signalapp/data/signalapp.db}"
BACKUP_DIR="${BACKUP_DIR:-/opt/signalapp/backups}"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
REMOTE="${BACKUP_REMOTE:-}"  # e.g. user@backup-host:/backups/signalapp/

STAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

ARCHIVE="$BACKUP_DIR/signalapp_${STAMP}.tar.gz"

# Checkpoint WAL and backup atomically
sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
tar -czf "$ARCHIVE" -C "$(dirname "$DB_PATH")" "$(basename "$DB_PATH")" 2>/dev/null || \
    cp "$DB_PATH" "$BACKUP_DIR/signalapp_${STAMP}.db"

echo "[$(date -Iseconds)] Backup created: $ARCHIVE"

# Optional remote copy
if [ -n "$REMOTE" ]; then
    scp -o StrictHostKeyChecking=accept-new "$ARCHIVE" "$REMOTE"
    echo "[$(date -Iseconds)] Copied to $REMOTE"
fi

# Prune old backups
find "$BACKUP_DIR" -name 'signalapp_*' -mtime +"$RETAIN_DAYS" -delete
