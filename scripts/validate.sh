#!/usr/bin/env bash
# Health + connectivity checks. Exit code != 0 on any failure.
source "$(dirname "$0")/_lib.sh"; need docker; need curl; load_env
PP="${PLATFORM_HOST_PORT:-8090}"; SP="${STOREFRONT_HOST_PORT:-8080}"
log "1. Container health"
for s in sqlserver elasticsearch redis platform; do
  st="$(docker compose ps --format '{{.Health}}' "$s" 2>/dev/null || true)"
  [ "$st" = healthy ] && ok "$s healthy" || bad "$s health='$st'"
done
log "2. Platform HTTP"
code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 "http://localhost:$PP/" || true)"
[[ "$code" =~ ^(200|301|302)$ ]] && ok "platform / -> $code" || bad "platform / -> $code"
hc="$(curl -s -o /dev/null -w '%{http_code}' -m 20 "http://localhost:$PP/health" || true)"
echo "  info: platform /health -> $hc (endpoint availability depends on platform version)"
log "3. Dependencies reachable from platform container (network-level)"
for t in sqlserver:1433 elasticsearch:9200 redis:6379; do
  docker compose exec -T platform bash -c "exec 3<>/dev/tcp/${t%%:*}/${t##*:}" 2>/dev/null \
    && ok "platform -> $t" || bad "platform -> $t"
done
log "4. DB / search / cache not exposed on the host"
for p in 1433 9200 6379; do
  (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && bad "host port $p is open" || ok "host port $p closed"
done
if docker compose ps --services --filter status=running | grep -qx frontend; then
  log "5. Frontend (vc-frontend + nginx) and frontend<->platform communication"
  st="$(docker compose ps --format '{{.Health}}' frontend 2>/dev/null || true)"
  [ "$st" = healthy ] && ok "frontend healthy" || bad "frontend health='$st'"
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 30 "http://localhost:$SP/" || true)"
  [[ "$code" =~ ^(200|301|302)$ ]] && ok "frontend / -> $code" || bad "frontend / -> $code"
  if [ "${VALIDATE_REQUIRE_DATA:-1}" = 1 ]; then
    # Real end-to-end proof: GraphQL goes browser -> nginx(frontend) -> platform -> database.
    gql="$(curl -s -m 30 -X POST "http://localhost:$SP/graphql" -H 'Content-Type: application/json'           -d '{"query":"{ store(storeId:\"B2B-store\"){ storeId } }"}' || true)"
    echo "$gql" | grep -q '"storeId":"B2B-store"'       && ok "frontend -> platform GraphQL returned store B2B-store (needs sample data)"       || bad "GraphQL through frontend failed: ${gql:0:150}"
    # Search proof: products come from Elasticsearch (not just the DB). Fails if the index was never built.
    pc="$(curl -s -m 30 -X POST "http://localhost:$SP/graphql" -H 'Content-Type: application/json'           -d '{"query":"{ products(storeId:\"B2B-store\", first:1){ totalCount } }"}' | grep -o '"totalCount":[0-9]*' | cut -d: -f2 || true)"
    [ "${pc:-0}" -gt 0 ] && ok "search index serves products (totalCount=$pc)"       || bad "no products via search (totalCount=${pc:-?}) - rebuild index in admin: More > Search index"
  else
    # Fresh install without sample data (CI smoke): prove the proxy chain only.
    gql="$(curl -s -m 30 -X POST "http://localhost:$SP/graphql" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' || true)"
    echo "$gql" | grep -q '"__typename"' && ok "frontend -> platform GraphQL answered (no sample data mode)"       || bad "GraphQL through frontend failed: ${gql:0:150}"
  fi
  docker compose logs --no-color --tail 200 frontend | grep -qE 'connect\(\) failed|upstream timed out|" (502|504) ' \
    && bad "frontend (nginx) logs show upstream errors" || ok "no upstream errors in frontend logs"
else
  echo "  skip: frontend not running (start with scripts/up.sh --with-storefront)"
fi
echo; [ "$FAILED" -eq 0 ] && { echo "ALL CHECKS PASSED"; exit 0; } || { echo "$FAILED CHECK(S) FAILED"; exit 1; }
