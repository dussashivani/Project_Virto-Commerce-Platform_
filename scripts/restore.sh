#!/usr/bin/env bash
# Restore from a backup dir produced by backup.sh.  Usage: scripts/restore.sh backups/<ts>
source "$(dirname "$0")/_lib.sh"; need docker; load_env
B="${1:?usage: restore.sh backups/<timestamp>}"; [ -f "$B/db.bak" ] || { echo "no $B/db.bak" >&2; exit 2; }
( cd "$B" && sha256sum -c SHA256SUMS )
if [ "${RESTORE_CONFIRM:-}" != restore ]; then   # non-interactive use: RESTORE_CONFIRM=restore (tests/automation)
  read -r -p "This OVERWRITES the current database and volumes. Type 'restore' to continue: " a; [ "$a" = restore ] || exit 1
fi
docker compose stop platform 2>/dev/null || true
docker compose cp "$B/db.bak" sqlserver:/var/opt/mssql/restore.bak
# On Linux, `cp` keeps the HOST uid/mode (e.g. 0640 runner) and the mssql user then gets "Access is denied" (OS error 5).
docker compose exec -T -u root sqlserver sh -c "chown mssql:root /var/opt/mssql/restore.bak && chmod 640 /var/opt/mssql/restore.bak"
docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b -Q \
 "ALTER DATABASE [$VC_DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; RESTORE DATABASE [$VC_DB_NAME] FROM DISK='/var/opt/mssql/restore.bak' WITH REPLACE; ALTER DATABASE [$VC_DB_NAME] SET MULTI_USER;"
docker compose exec -T sqlserver rm -f /var/opt/mssql/restore.bak
for v in platform_appdata cms_content; do
  docker run --rm -v "virto_${v}:/dst" -v "$PWD/$B:/in:ro" alpine:3.20 sh -c "rm -rf /dst/* /dst/.[!.]* 2>/dev/null; tar xzf /in/$v.tgz -C /dst"
done
docker compose up -d --wait --wait-timeout 600
log "Restore complete - run scripts/validate.sh"
