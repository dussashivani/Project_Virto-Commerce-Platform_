#!/usr/bin/env bash
# Backup SQL Server DB (native .bak) + App_Data/cms-content volumes into ./backups/<timestamp>/
source "$(dirname "$0")/_lib.sh"; need docker; load_env
TS="$(date +%Y%m%d-%H%M%S)"; OUT="backups/$TS"; mkdir -p "$OUT"
log "DB backup"
docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -b \
  -Q "BACKUP DATABASE [$VC_DB_NAME] TO DISK='/var/opt/mssql/backup-$TS.bak' WITH INIT, COMPRESSION, CHECKSUM"
docker compose cp "sqlserver:/var/opt/mssql/backup-$TS.bak" "$OUT/db.bak"
docker compose exec -T sqlserver rm -f "/var/opt/mssql/backup-$TS.bak"
log "Volume backups"
for v in platform_appdata cms_content; do
  docker run --rm -v "virto_${v}:/src:ro" -v "$PWD/$OUT:/out" alpine:3.20 tar czf "/out/$v.tgz" -C /src .
done
( cd "$OUT" && sha256sum * > SHA256SUMS ); ls -la "$OUT"; echo "Backup: $OUT"
