#!/usr/bin/env bash
# Resolve every image in docker-compose.yml to an immutable digest and write .env.lock.
# Use:  scripts/pin-images.sh && set -a && . ./.env.lock && set +a && docker compose up -d
source "$(dirname "$0")/_lib.sh"; need docker; load_env
: > .env.lock
for v in PLATFORM_IMAGE STOREFRONT_IMAGE SQLSERVER_IMAGE ELASTICSEARCH_IMAGE REDIS_IMAGE; do
  ref="${!v}"; log "pulling $ref"; docker pull -q "$ref" >/dev/null
  digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$ref")"
  echo "$v=$digest" >> .env.lock
done
log "Wrote .env.lock:"; sed 's/^/  /' .env.lock
echo "Copy the digests (or human-readable version tags) into .env / docs/ARCHITECTURE.md section 3."
