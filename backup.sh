#!/bin/bash

DATE=$(date +%Y-%m-%d_%H-%M)
REPO="/opt/backup-repo"
DB_DIR="$REPO/databases"
LOG="$REPO/logs/backup.log"
MYSQL_PASS="P@ssw0rd"

echo "=== Backup started: $DATE ===" >> "$LOG"

# Backup all 3 databases
for DB in discipline_committee_linux hospitalhandover plan_production; do
    FILE="$DB_DIR/${DB}_${DATE}.sql.gz"
    mysqldump -u root -p"$MYSQL_PASS" "$DB" | gzip > "$FILE"
    if [ $? -eq 0 ]; then
        echo "✓ $DB backed up successfully" >> "$LOG"
    else
        echo "✗ $DB FAILED" >> "$LOG"
    fi
done

# Delete local backups older than 30 days
find "$DB_DIR" -name "*.sql.gz" -mtime +30 -delete
echo "Old backups cleaned" >> "$LOG"

# Commit and push to GitHub
cd "$REPO"
git add -A
git commit -m "Automated backup: $DATE"
git push origin main

if [ $? -eq 0 ]; then
    echo "✓ Pushed to GitHub successfully" >> "$LOG"
else
    echo "✗ GitHub push FAILED" >> "$LOG"
fi

echo "=== Backup completed: $(date +%Y-%m-%d_%H-%M) ===" >> "$LOG"
echo "" >> "$LOG"
