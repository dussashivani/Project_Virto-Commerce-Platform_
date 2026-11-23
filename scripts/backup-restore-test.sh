#!/usr/bin/env bash
# Prove that backup.sh + restore.sh really recover data: write markers, back up, DESTROY the markers,
# restore, and check the markers and the real Virto data are back. A backup never restored is not a backup.
source "$(dirname "$0")/_lib.sh"; need docker; need curl; load_env
SQL=(/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b)
Q() { docker compose exec -T sqlserver "${SQL[@]}" -d "$VC_DB_NAME" -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '[:space:]'; }
counts() { Q "SELECT CAST((SELECT COUNT(*) FROM AspNetUsers) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM Catalog) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM Item) AS varchar)"; }
M="dr_$(date +%s)"
log "1. Write markers ($M) and record real data counts (users/catalogs/items)"
Q "IF OBJECT_ID('dr_marker') IS NOT NULL DROP TABLE dr_marker; CREATE TABLE dr_marker(v nvarchar(64)); INSERT dr_marker VALUES('$M');" >/dev/null
docker compose exec -T platform bash -c "echo $M > /opt/virtocommerce/platform/App_Data/dr-marker.txt"
BEFORE="$(counts)"; echo "  counts: $BEFORE"
log "2. Backup"
"$(dirname "$0")/backup.sh"
B="$(ls -1d backups/*/ | sort | tail -1)"; B="${B%/}"; echo "  using $B"
log "3. DESTROY: drop marker table, delete marker file, add a 'post-backup' table"
Q "DROP TABLE dr_marker; CREATE TABLE dr_after_backup(x int);" >/dev/null
docker compose exec -T platform rm -f /opt/virtocommerce/platform/App_Data/dr-marker.txt
[ "$(Q "SELECT COUNT(*) FROM sys.tables WHERE name='dr_marker'")" = 0 ] && ok "damage confirmed (marker table gone)" || bad "damage not applied"
log "4. Restore"
RESTORE_CONFIRM=restore "$(dirname "$0")/restore.sh" "$B"
log "5. Verify recovery"
[ "$(Q "SELECT v FROM dr_marker")" = "$M" ] && ok "DB marker row recovered" || bad "DB marker not recovered"
[ "$(Q "SELECT COUNT(*) FROM sys.tables WHERE name='dr_after_backup'")" = 0 ] && ok "post-backup change rolled back (point-in-time)" || bad "post-backup table still present"
docker compose exec -T platform cat /opt/virtocommerce/platform/App_Data/dr-marker.txt 2>/dev/null | grep -q "$M" \
  && ok "App_Data marker file recovered" || bad "App_Data marker file not recovered"
AFTER="$(counts)"; [ "$BEFORE" = "$AFTER" ] && ok "real Virto data identical ($AFTER)" || bad "data differs: $BEFORE -> $AFTER"
code="$(curl -s -o /dev/null -w '%{http_code}' -m 30 "http://localhost:${PLATFORM_HOST_PORT:-8090}/" || true)"
[[ "$code" =~ ^(200|301|302)$ ]] && ok "platform serving after restore ($code)" || bad "platform not serving ($code)"
log "6. Cleanup markers"
Q "DROP TABLE IF EXISTS dr_marker" >/dev/null
docker compose exec -T platform rm -f /opt/virtocommerce/platform/App_Data/dr-marker.txt || true
[ "$FAILED" -eq 0 ] && echo "BACKUP/RESTORE VERIFIED" || { echo "$FAILED CHECK(S) FAILED"; exit 1; }
