#!/bin/bash
set -o pipefail

DATE=$(date +%Y-%m-%d_%H-%M)
REPO="/opt/backup-repo"
DB_DIR="$REPO/databases"
LOG="$REPO/logs/backup.log"
LOCKFILE="/tmp/backup.lock"
MYSQL_DEFAULTS_FILE="/root/.backup_my.cnf"   # see note below — move creds here, chmod 600

# Prevent overlapping runs (e.g. if a previous run is hung on git push)
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "$(date): Previous backup still running — skipping this run." >> "$LOG"
    exit 1
fi

{
echo "=== Backup started: $DATE ==="

for DB in discipline_committee_linux hospitalhandover plan_production; do
    FILE="$DB_DIR/${DB}_${DATE}.sql.gz"
    ERRFILE="$REPO/logs/${DB}_${DATE}.err"

    mysqldump --defaults-extra-file="$MYSQL_DEFAULTS_FILE" "$DB" 2> "$ERRFILE" | gzip > "$FILE"
    DUMP_STATUS=${PIPESTATUS[0]}
    GZIP_STATUS=${PIPESTATUS[1]}

    if [ "$DUMP_STATUS" -eq 0 ] && [ "$GZIP_STATUS" -eq 0 ]; then
        echo "✓ $DB backed up successfully"
        rm -f "$ERRFILE"
    else
        echo "✗ $DB FAILED (mysqldump exit=$DUMP_STATUS, gzip exit=$GZIP_STATUS) — see $(basename "$ERRFILE")"
        rm -f "$FILE"   # don't leave a broken/empty dump sitting in the repo
    fi
done

# Delete local backups older than 30 days
find "$DB_DIR" -name "*.sql.gz" -mtime +30 -delete
echo "Old backups cleaned"

# Commit and push to GitHub
cd "$REPO" || { echo "✗ Could not cd into $REPO"; exit 1; }
git add -A

if git diff --cached --quiet; then
    echo "Nothing new to commit"
else
    if git commit -m "Automated backup: $DATE"; then
        # GIT_TERMINAL_PROMPT=0 makes push FAIL FAST instead of hanging
        # forever waiting for credentials that will never arrive on cron
        if GIT_TERMINAL_PROMPT=0 git push origin main; then
            echo "✓ Pushed to GitHub successfully"
        else
            echo "✗ GitHub push FAILED (auth/network issue — check credential helper / token expiry)"
        fi
    else
        echo "✗ git commit FAILED"
    fi
fi

echo "=== Backup completed: $(date +%Y-%m-%d_%H-%M) ==="
echo ""
} >> "$LOG" 2>&1

flock -u 200
