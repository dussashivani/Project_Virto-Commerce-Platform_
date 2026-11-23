#!/usr/bin/env bash
# Create .env from .env.example with random secrets. Refuses to overwrite an existing .env.
source "$(dirname "$0")/_lib.sh"
need openssl
[ -f .env ] && { echo ".env already exists - not overwriting." >&2; exit 1; }
# SQL Server needs upper+lower+digit(+symbol); random hex alone is not enough, so add a fixed suffix.
sa="$(openssl rand -hex 16)Aa1!"
redis="$(openssl rand -hex 16)"
sed -e "s|^MSSQL_SA_PASSWORD=.*|MSSQL_SA_PASSWORD=${sa}|" \
    -e "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${redis}|" .env.example > .env
chmod 600 .env
log ".env created (mode 600). Set STOREFRONT_API_PASSWORD after creating the frontend user in the Platform admin."
