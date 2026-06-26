#!/bin/bash
# Backup: discipline_committee_linux, hospitalhandover, plan_production
# Pushes to git@github.com:HWD2025/servicehub-contracts.git
# Sends ntfy.sh push notifications on every run - success or failure.

REPO="/opt/backup-repo"
DB_DIR="$REPO/databases"
LOG="$REPO/logs/backup.log"
LOCKFILE="/tmp/servicehub-backup.lock"
MYSQL_CNF="/root/.backup_my.cnf"
NTFY_TOPIC="deder-eapts-backup-7f3k9q"
ALERT_PREFIX="[SERVICEHUB-17]"
DATE=$(date +%Y-%m-%d_%H-%M)
HAD_FAILURE=0

send_alert() {
    curl -sS -m 20 -d "$ALERT_PREFIX $1" "https://ntfy.sh/$NTFY_TOPIC" >> "$LOG" 2>&1
}

# ---- Prevent overlapping runs ----
exec 200>"$LOCKFILE"
flock -n 200 || {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  Previous run still in progress - skipping this run." >> "$LOG"
    exit 1
}

echo "=== Backup started: $DATE ===" >> "$LOG"

# ---- Backup all 3 databases ----
for DB in discipline_committee_linux hospitalhandover plan_production; do
    FILE="$DB_DIR/${DB}_${DATE}.sql.gz"
    mysqldump --defaults-extra-file="$MYSQL_CNF" "$DB" | gzip > "$FILE"
    STATUS=("${PIPESTATUS[@]}")   # [0]=mysqldump exit code, [1]=gzip exit code
    if [ "${STATUS[0]}" -eq 0 ] && [ -s "$FILE" ]; then
        echo "✓ $DB backed up successfully" >> "$LOG"
    else
        echo "✗ $DB FAILED (mysqldump exit ${STATUS[0]})" >> "$LOG"
        rm -f "$FILE"
        HAD_FAILURE=1
        send_alert "FAILED: $DB dump failed on $DATE"
    fi
done

# ---- Delete local backups older than 30 days ----
find "$DB_DIR" -name "*.sql.gz" -mtime +30 -delete
echo "Old backups cleaned" >> "$LOG"

# ---- Commit and push to GitHub ----
cd "$REPO" || exit 1
export GIT_TERMINAL_PROMPT=0
git add -A
if ! git diff --cached --quiet; then
    git commit -m "Automated backup: $DATE" >> "$LOG" 2>&1
    git push origin main >> "$LOG" 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ Pushed to GitHub successfully" >> "$LOG"
        if [ "$HAD_FAILURE" -eq 0 ]; then
            send_alert "OK: all 3 databases backed up and pushed successfully on $DATE"
        fi
    else
        echo "✗ GitHub push FAILED" >> "$LOG"
        send_alert "FAILED: GitHub push failed on $DATE - dumps exist locally but not pushed"
    fi
else
    echo "Nothing new to commit" >> "$LOG"
    if [ "$HAD_FAILURE" -eq 0 ]; then
        send_alert "OK: backup ran, no changes to push (dumps unchanged) on $DATE"
    fi
fi

echo "=== Backup completed: $(date +%Y-%m-%d_%H-%M) ===" >> "$LOG"
echo "" >> "$LOG"
