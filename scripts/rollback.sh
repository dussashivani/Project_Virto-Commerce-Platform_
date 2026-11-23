#!/usr/bin/env bash
# Roll back image versions: scripts/rollback.sh <previous .env.lock file>
# The lock file is KEY=image lines (e.g. PLATFORM_IMAGE=..., FRONTEND_IMAGE=...) of the previous release;
# only the keys it contains are overridden. Data rollback is separate (restore.sh). Always run backup.sh BEFORE an upgrade.
source "$(dirname "$0")/_lib.sh"; need docker
LOCK="${1:?usage: rollback.sh <env.lock-file-of-previous-release>}"
[ -f "$LOCK" ] || { echo "no such file $LOCK" >&2; exit 2; }
set -a; . ./.env; . "$LOCK"; set +a
# Profile services (frontend) are skipped by a plain `up`; keep them if they are currently running.
if docker compose ps --services --filter status=running | grep -qx frontend; then export COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}storefront"; fi
log "Pulling previous images"
docker compose pull
log "Recreating services on the previous images"
docker compose up -d --wait --wait-timeout 600
# Prove it: every image named in the lock file must really be running now (no silent no-op).
log "Verifying that the rolled-back images are running"
RUNNING="$(docker compose ps --format '{{.Image}}')"
while IFS='=' read -r key ref; do
  [[ "$key" =~ ^[A-Z_]+_IMAGE$ ]] || continue
  echo "$RUNNING" | grep -qxF "$ref" && ok "$key running as $ref" || bad "$key=$ref is NOT running (profile not active, or pull failed)"
done < "$LOCK"
"$(dirname "$0")/validate.sh"
[ "$FAILED" -eq 0 ]
