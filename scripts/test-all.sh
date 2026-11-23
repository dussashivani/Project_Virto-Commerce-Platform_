#!/usr/bin/env bash
# Offline static checks (no Docker daemon needed) - used by CI and before submitting.
source "$(dirname "$0")/_lib.sh"
log "Shell syntax";   for f in scripts/*.sh; do bash -n "$f" && ok "$f" || bad "$f"; done
log "Compose config"
if command -v docker >/dev/null 2>&1; then
  tmp=".env.ci-check.$$"; sed -e 's/^MSSQL_SA_PASSWORD=.*/MSSQL_SA_PASSWORD=Dummy_Passw0rd!/' -e 's/^REDIS_PASSWORD=.*/REDIS_PASSWORD=dummy/' .env.example > "$tmp"
  docker compose --env-file "$tmp" config -q && ok "docker-compose.yml" || bad "docker-compose.yml"
  docker compose -f docker-compose.floci.yml config -q && ok "docker-compose.floci.yml" || bad "floci compose"
  rm -f "$tmp"
fi
log "Secret scan (no real-looking secrets committed)"
if git ls-files --error-unmatch .env >/dev/null 2>&1; then bad ".env is tracked"; else ok ".env not tracked"; fi
if grep -RInE '(AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=evidence . ; then bad "secret-like string found"; else ok "no AWS keys/private keys"; fi
log "Template secrets are placeholders (.env.example)"
bad_lines="$(grep -E '^[A-Z_]*(PASSWORD|SECRET|TOKEN|KEY)[A-Z_]*=' .env.example | grep -vE '=(CHANGE_ME.*)?$' || true)"
if [ -n "$bad_lines" ]; then bad "non-placeholder secret in .env.example: $(echo "$bad_lines" | cut -d= -f1 | tr '
' ' ')"; else ok ".env.example secrets are placeholders"; fi
TF="$(command -v tofu || command -v terraform || true)"
if [ -n "$TF" ]; then log "IaC format"; "$TF" fmt -check -recursive terraform && ok "fmt" || bad "fmt"; fi
[ "$FAILED" -eq 0 ] && echo "STATIC CHECKS PASSED" || { echo "$FAILED FAILED"; exit 1; }
