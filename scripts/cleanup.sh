#!/usr/bin/env bash
# Stop everything. --volumes also DELETES all data (db, search index, uploads).
source "$(dirname "$0")/_lib.sh"; need docker
if [ "${1:-}" = "--volumes" ]; then
  read -r -p "Delete ALL volumes/data? Type 'delete': " a; [ "$a" = delete ] || exit 1
  docker compose --profile storefront down -v --remove-orphans
else
  docker compose --profile storefront down --remove-orphans
fi
docker compose -f docker-compose.floci.yml down ${1:+-v} 2>/dev/null || true
log "Done."
