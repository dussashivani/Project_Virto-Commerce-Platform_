#!/usr/bin/env bash
# Install the Virto module bundle into the platform_modules volume (needed once; re-run to upgrade).
# The platform image contains no modules, so without this there is no admin UI and no commerce features.
source "$(dirname "$0")/_lib.sh"; need docker; load_env
: "${MODULES_BUNDLE_URL:?set MODULES_BUNDLE_URL in .env}"
log "Installing modules from $MODULES_BUNDLE_URL (downloads ~60 modules; several minutes)"
docker compose --profile init run --rm modules-init
log "Restarting platform to load modules"
docker compose up -d --force-recreate platform
