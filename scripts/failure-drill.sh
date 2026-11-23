#!/usr/bin/env bash
# Safe, reversible failure: stop Redis (cache) and observe/recover. No data is touched.
source "$(dirname "$0")/_lib.sh"; need docker; need curl; load_env
PP="${PLATFORM_HOST_PORT:-8090}"
code(){ curl -s -o /dev/null -w '%{http_code}' -m 20 "http://localhost:$PP/" || true; }
# Deeper probe: a real data request through the whole chain (browser -> nginx frontend -> platform -> DB/cache).
SP="${STOREFRONT_HOST_PORT:-8080}"
if [ "${VALIDATE_REQUIRE_DATA:-1}" = 1 ]; then GQ='{ store(storeId:\"B2B-store\"){ storeId } }'; EXPECT='"storeId":"B2B-store"'
else GQ='{ __typename }'; EXPECT='"__typename"'; fi
gql(){ curl -s -m 20 -X POST "http://localhost:$SP/graphql" -H 'Content-Type: application/json'   -d "{\"query\":\"$GQ\"}" -w ' http=%{http_code}' | cut -c1-160 || true; }
log "Baseline: platform -> $(code) ; graphql -> $(gql)"
log "INJECT: docker compose stop redis"; docker compose stop redis
sleep 10; echo "  during failure: platform -> $(code) ; graphql -> $(gql)"
echo "  (record this in evidence; behaviour depends on version)"
docker compose logs --no-color --tail 20 platform | sed 's/^/  | /'
log "RECOVER: docker compose start redis"; docker compose start redis
docker compose up -d --wait --wait-timeout 120 redis
sleep 10
r="$(code)"; [[ "$r" =~ ^(200|301|302)$ ]] && ok "platform recovered -> $r" || { bad "platform not recovered -> $r (try: docker compose restart platform)"; }
g="$(gql)"; echo "$g" | grep -qF "$EXPECT" && ok "graphql recovered -> $g" || bad "graphql not recovered -> $g"
[ "$FAILED" -eq 0 ]
