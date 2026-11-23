#!/usr/bin/env bash
# Start the stack. Phase 1: db/search/redis/platform. Phase 2 (--with-storefront): storefront.
source "$(dirname "$0")/_lib.sh"; need docker; load_env
WITH_SF=0; [ "${1:-}" = "--with-storefront" ] && WITH_SF=1
docker compose config -q
log "Starting dependencies + platform (first start initialises the DB, allow several minutes)"
docker compose up -d --wait --wait-timeout 600
if [ "$WITH_SF" = 1 ]; then
  # vc-frontend needs no Platform user (it uses GraphQL); it only needs the downloaded static artifact.
  [ -f frontend/artifact/default/index.html ] || "$(dirname "$0")/fetch-frontend.sh"
  log "Starting storefront (vc-frontend behind nginx)"
  docker compose --profile storefront up -d --wait --wait-timeout 300
fi
docker compose ps
echo; echo "Platform admin : http://localhost:${PLATFORM_HOST_PORT:-8090}"
echo "Storefront     : http://localhost:${STOREFRONT_HOST_PORT:-8080}  (only after --with-storefront)"
