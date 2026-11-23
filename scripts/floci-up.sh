#!/usr/bin/env bash
# Start the Floci AWS emulator and prove AWS CLI connectivity. EMULATED AWS ONLY.
source "$(dirname "$0")/_lib.sh"; need docker; need aws
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}" AWS_DEFAULT_REGION=us-east-1 \
       AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test   # dummy emulator credentials, not real
docker compose -f docker-compose.floci.yml up -d
for i in $(seq 1 30); do curl -fsS -m 2 "$AWS_ENDPOINT_URL/" >/dev/null 2>&1 && break || sleep 1; done
log "aws sts get-caller-identity (emulator)"; aws sts get-caller-identity
log "aws s3 ls"; aws s3 ls || true
echo "Emulator ready at $AWS_ENDPOINT_URL"
