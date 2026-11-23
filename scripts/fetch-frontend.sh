#!/usr/bin/env bash
# Download the vc-frontend release that the Virto module bundle pins and unpack it for nginx.
# (frontend/artifact is git-ignored; this script makes the build reproducible.)
source "$(dirname "$0")/_lib.sh"; need curl; need unzip; load_env
: "${MODULES_BUNDLE_URL:?set MODULES_BUNDLE_URL in .env}"
url="${FRONTEND_ZIP_URL:-$(curl -fsSL "$MODULES_BUNDLE_URL" | grep -o '"ThemeB2BVue": *"[^"]*"' | cut -d'"' -f4)}"
[ -n "$url" ] || { echo "Could not determine frontend zip URL from the bundle manifest" >&2; exit 1; }
log "Downloading $url"
rm -rf frontend/artifact frontend/frontend.zip
curl -fL --retry 3 -o frontend/frontend.zip "$url"
unzip -q frontend/frontend.zip -d frontend/artifact
rm -f frontend/frontend.zip
[ -f frontend/artifact/default/index.html ] || { echo "Unexpected archive layout (no default/index.html)" >&2; exit 1; }
echo "$url" > frontend/artifact/SOURCE_URL.txt
log "vc-frontend unpacked to frontend/artifact/default"
