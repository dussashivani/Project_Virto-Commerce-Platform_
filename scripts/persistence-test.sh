#!/usr/bin/env bash
# Prove DB + app data survive a container restart: write a marker table + marker file, restart, read back.
source "$(dirname "$0")/_lib.sh"; need docker; load_env
SQL=(/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b)
M="persist_$(date +%s)"
log "Writing markers ($M)"
docker compose exec -T sqlserver "${SQL[@]}" -Q "IF DB_ID('persist_test') IS NULL CREATE DATABASE persist_test;" >/dev/null
docker compose exec -T sqlserver "${SQL[@]}" -d persist_test -Q "IF OBJECT_ID('m') IS NULL CREATE TABLE m(v nvarchar(64)); INSERT m VALUES('$M');" >/dev/null
docker compose exec -T platform bash -c "echo $M > /opt/virtocommerce/platform/App_Data/persist-marker.txt"
# Real application data (created through the Platform admin / sample data), not just a synthetic marker.
counts() { docker compose exec -T sqlserver "${SQL[@]}" -d "${VC_DB_NAME}" -h -1 -W -Q \
  "SET NOCOUNT ON; SELECT CAST((SELECT COUNT(*) FROM AspNetUsers) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM Catalog) AS varchar)+'/'+CAST((SELECT COUNT(*) FROM Store) AS varchar);" | tr -d '[:space:]'; }
BEFORE="$(counts)"; log "App data before restart (users/catalogs/stores): $BEFORE"
log "Restarting sqlserver + platform"
docker compose restart sqlserver platform
docker compose up -d --wait --wait-timeout 300
log "Reading markers back"
docker compose exec -T sqlserver "${SQL[@]}" -d persist_test -h -1 -Q "SET NOCOUNT ON; SELECT v FROM m WHERE v='$M';" | tr -d '[:space:]' | grep -q "$M" \
  && ok "DB row survived restart" || bad "DB row lost"
docker compose exec -T platform cat /opt/virtocommerce/platform/App_Data/persist-marker.txt | grep -q "$M" \
  && ok "App_Data file survived restart" || bad "App_Data file lost"
AFTER="$(counts)"; log "App data after restart (users/catalogs/stores): $AFTER"
[ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ] && ok "Virto application data identical after restart ($AFTER)" || bad "Virto data changed: $BEFORE -> $AFTER"
docker compose exec -T sqlserver "${SQL[@]}" -Q "DROP DATABASE persist_test;" >/dev/null || true
docker compose exec -T platform rm -f /opt/virtocommerce/platform/App_Data/persist-marker.txt || true
[ "$FAILED" -eq 0 ]
