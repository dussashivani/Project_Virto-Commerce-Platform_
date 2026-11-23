#!/usr/bin/env bash
# Vulnerability-scan every image the compose project uses (all profiles) with Trivy.
# Reports go to evidence/trivy/<image>.txt ; summary to stdout. Report-only by default (third-party images);
# set SCAN_FAIL_ON_CRITICAL_FIXABLE=1 to exit non-zero when a CRITICAL vulnerability with a fix exists.
source "$(dirname "$0")/_lib.sh"; need docker; load_env
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.58.1}"
OUT="evidence/trivy"; mkdir -p "$OUT"
mapfile -t IMAGES < <(docker compose --profile storefront --profile legacy --profile init config --images | sort -u | grep -E "${SCAN_ONLY:-.}")   # SCAN_ONLY=regex to rescan one image
log "Scanning ${#IMAGES[@]} images with $TRIVY_IMAGE (first run downloads the vulnerability DB)"
CRIT_FIXABLE=0
printf '%-62s %8s %8s %12s\n' IMAGE HIGH CRITICAL "CRIT(fixable)"
for img in "${IMAGES[@]}"; do
  name="$(echo "${img%%@*}" | tr '/:' '__')"
  run() { docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
            -v "$PWD/$OUT:/out" "$TRIVY_IMAGE" image --no-progress --quiet --timeout "${TRIVY_TIMEOUT:-20m}" "$@"; }
  run --severity HIGH,CRITICAL --format table --output "/out/$name.txt" "$img" || { echo "scan failed: $img" >&2; continue; }
  h="$(grep -o 'HIGH: [0-9]*' "$OUT/$name.txt" | awk '{s+=$2} END{print s+0}')"
  c="$(grep -o 'CRITICAL: [0-9]*' "$OUT/$name.txt" | awk '{s+=$2} END{print s+0}')"
  cf="$(run --severity CRITICAL --ignore-unfixed --format json "$img" | grep -c '"VulnerabilityID"' || true)"
  CRIT_FIXABLE=$((CRIT_FIXABLE + cf))
  printf '%-62s %8s %8s %12s\n' "${img%%@*}" "$h" "$c" "$cf"
done | tee "$OUT/SUMMARY.txt${SCAN_ONLY:+.partial}"
echo; echo "Per-image reports: $OUT/*.txt  (HIGH+CRITICAL). 'fixable' = a patched version exists."
[ "${SCAN_FAIL_ON_CRITICAL_FIXABLE:-0}" = 1 ] && grep -qE ' [1-9][0-9]*$' <(awk 'NR>1{print $NF}' "$OUT/SUMMARY.txt") && exit 1 || exit 0
