# Evidence

Capture real output here after running (never include passwords/tokens). Suggested files:
```bash
docker compose version > evidence/versions.txt; docker version --format '{{.Server.Version}}' >> evidence/versions.txt
docker compose config --images > evidence/image-versions.txt
./scripts/up.sh --with-storefront 2>&1 | tee evidence/01-startup.txt
docker compose ps | tee evidence/02-ps-healthy.txt
./scripts/validate.sh 2>&1 | tee evidence/03-validate.txt
./scripts/persistence-test.sh 2>&1 | tee evidence/04-persistence.txt
./scripts/failure-drill.sh 2>&1 | tee evidence/05-failure-drill.txt
./scripts/floci-up.sh 2>&1 | tee evidence/06-floci-cli.txt
./scripts/floci-apply.sh 2>&1 | tee evidence/07-floci-apply.txt
```
Add screenshots (platform admin, storefront home) as `evidence/*.png`. `static-checks.txt` was generated during authoring.
