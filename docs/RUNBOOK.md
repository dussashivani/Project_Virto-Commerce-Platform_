# Deployment runbook (Task 7)

Sections 1–16 follow the assignment's required list. Read `docs/ARCHITECTURE.md` first for the local / Floci / real-AWS distinction.

## 1. Architecture diagram
See `docs/ARCHITECTURE.md` §4 (local containers) and §7 (proposed AWS). Mermaid renders on GitHub/GitLab; to export an image: `npx -p @mermaid-js/mermaid-cli mmdc -i docs/ARCHITECTURE.md -o docs/diagram.png`.

## 2. Prerequisites and tool versions
| Tool | Tested/target version | Check |
|---|---|---|
| Docker Engine + Compose v2 | Engine ≥ 24, Compose ≥ 2.20 (authoring checked config with Compose v5.7.1 only) | `docker compose version` |
| RAM / disk | ≥ 8 GB free RAM (SQL Server ≥ 2 GB, ES 1 GB), ≥ 15 GB disk | |
| CPU arch | **linux/amd64.** SQL Server image has no native arm64 build; on Apple Silicon enable Rosetta emulation or use a PostgreSQL variant | |
| OpenTofu ≥ 1.6 (1.9.0 used for fmt check) or Terraform ≥ 1.6 | | `tofu version` |
| AWS CLI v2 | | `aws --version` |
| `curl`, `openssl`, `bash` | | |
| Linux only | `sudo sysctl -w vm.max_map_count=262144` (Elasticsearch) | |

## 3. Repository structure
```
docker-compose.yml          app stack (platform, frontend[profile storefront], modules-init[profile init],
                            legacy storefront[profile legacy], sqlserver, elasticsearch, redis)
frontend/nginx.conf         reverse proxy + static hosting for vc-frontend (artifact downloaded, git-ignored)
docker-compose.floci.yml    Floci AWS emulator (separate project)
.env.example                configuration template (no secrets)
scripts/                    up, validate, persistence-test, failure-drill, backup, restore, rollback,
                            pin-images, install-modules, fetch-frontend, generate-env, floci-up, floci-apply, cleanup, test-all
terraform/modules/network   VPC, 3 subnet tiers, SG chain
terraform/envs/floci        EMULATOR-ONLY (own provider config)
terraform/envs/aws          REAL AWS reference design (never applied)
.github/workflows/ci.yml    CI/CD
docs/                       ARCHITECTURE, RUNBOOK, SECURITY, COST, TROUBLESHOOTING, STATUS, PRESENTATION
evidence/                   test output and screenshots (no secrets)
```

## 4. Environment variables
Defined in `.env.example`. Key ones: image refs (`*_IMAGE`), `MSSQL_SA_PASSWORD`, `REDIS_PASSWORD`, `VC_DB_NAME`, `SEARCH_PROVIDER`, `MODULES_BUNDLE_URL` (module bundle = release set), `DOTNET_SDK_IMAGE`, `FRONTEND_IMAGE`, host ports. (`STOREFRONT_API_*` only matter for the legacy storefront.) `SEARCH_PROVIDER` must be `ElasticSearch8`. Create `.env`: `./scripts/generate-env.sh` (random secrets, mode 600). Never commit `.env`.

## 5. Local setup and deployment
```bash
./scripts/generate-env.sh            # random secrets -> .env
./scripts/pin-images.sh              # optional: records digests in .env.lock
./scripts/install-modules.sh         # ONE-TIME: vc-build installs the 59-module bundle into volume platform_modules,
                                     # then recreates the platform (the image ships with no modules / no admin UI)
./scripts/up.sh                      # sqlserver, elasticsearch, redis, platform (first start: minutes)
```
If `install-modules.sh` fails with *API rate limit exceeded*, the module installer is being throttled by GitHub (60 anonymous requests/hour per IP): wait, or `export GITHUB_TOKEN=<any GitHub token, no scopes>` first (it retries 3 times on its own).
Then in the browser (http://localhost:8090):
1. Log in `admin` / `store` (documented Virto default). The platform **forces a password change** - choose a strong one.
2. Install the **sample data** (gives the `B2B-store`, 9 catalogs, ~389 products).
3. **More > Search index > Rebuild** for products/categories. Without this the storefront shows no products (nothing is indexed automatically after sample data).
```bash
./scripts/up.sh --with-storefront    # downloads vc-frontend (scripts/fetch-frontend.sh) and starts nginx on :8080
./scripts/validate.sh
```
Stop: `docker compose --profile storefront down` (data kept). Start again: `./scripts/up.sh --with-storefront`. After a host reboot, containers return by themselves (`restart: unless-stopped`) once Docker is running.
Windows: run the scripts from Git Bash with Docker Desktop (WSL2) running; put Docker's disk on a drive with >=15 GB free.

## 6. Floci setup and resource provisioning (EMULATED AWS)
```bash
./scripts/floci-up.sh       # starts Floci, runs `aws sts get-caller-identity` / `aws s3 ls` against :4566
./scripts/floci-apply.sh    # tofu init/apply in terraform/envs/floci, then verifies via AWS CLI
```
Emulator config is isolated in `terraform/envs/floci/provider.tf` (endpoint overrides, dummy keys, skip_* flags). The real env uses a different directory, backend and provider block. Emulated services used: S3, EC2 (VPC/subnets/SG), IAM, Secrets Manager, CloudWatch Logs, ECS. Limitations: see ARCHITECTURE §9. If a resource type is unsupported by the emulator, comment it out and record it in `docs/STATUS.md` rather than claiming it works.

## 7. Real AWS deployment design and steps (PROPOSED, not performed)
Prerequisite: written authorization for paid resources, AWS account, a domain + ACM certificate, ECR repos, remote state bucket.
1. `aws ecr create-repository` for platform/storefront; mirror pinned upstream images (`docker pull` → `docker tag` → `docker push`) and scan (ECR scan-on-push).
2. `cd terraform/envs/aws && cp terraform.tfvars.example terraform.tfvars` (fill; file is git-ignored) then `tofu init -backend-config=...`.
3. `tofu plan -out plan.bin`, review, then `tofu apply plan.bin` (only with approval).
4. Complete gaps the reference does not yet cover: search tier, storefront ECS service/task definition (mirror the platform ones), DB connection-string assembly from the Secrets Manager JSON (small entrypoint script or SSM-to-env pattern), S3 asset provider configuration, `cms-content` delivery (bake into image or EFS), HTTP→HTTPS redirect, WAF, autoscaling.
5. Run the module installation (init task), then log in once through the ALB as `admin` and change the default password immediately; restrict `/admin` by IP/WAF.
6. Validate: ALB target health, `curl -I https://<host>/`, CloudWatch logs, alarm test.

## 8. Ports and endpoints
| Endpoint | Where | Notes |
|---|---|---|
| `http://localhost:8090` | Platform admin/API | published on 127.0.0.1 |
| `http://localhost:8080` | Storefront (vc-frontend via nginx; `/graphql` proxied to platform) | profile `storefront` |
| `http://localhost:8081` | LEGACY storefront (known-incompatible, evidence only) | profile `legacy` |
| `sqlserver:1433`, `elasticsearch:9200`, `redis:6379` | internal network only | not published |
| `http://localhost:4566` | Floci | emulator |
| AWS: `:443` ALB → `:80` tasks | | TLS terminates at ALB |

## 9. Database initialization and persistence
The Platform creates and migrates the `VC_DB_NAME` database on first start (connection string from env). Data lives in volume `mssql_data`; `platform_modules` holds the installed modules (reinstallable with `install-modules.sh`); `platform_appdata` holds uploads/license; `cms_content` holds themes. Prove persistence: `./scripts/persistence-test.sh` (writes DB row + file, restarts, reads back). `docker compose down` keeps volumes; `-v`/`cleanup.sh --volumes` deletes them.

## 10. Health checks and testing
`docker compose ps` (health column) · `./scripts/validate.sh` · `./scripts/persistence-test.sh` · `./scripts/failure-drill.sh` · `./scripts/test-all.sh` (offline static checks, also in CI). Manual: open both URLs; log in to the admin; browse the storefront (categories and products must appear); real end-to-end probe: `curl -s -X POST localhost:8080/graphql -H 'Content-Type: application/json' -d '{"query":"{ products(storeId:\"B2B-store\", first:1){ totalCount } }"}'`. A green container healthcheck alone is not proof (see TROUBLESHOOTING).

### CI/CD pipeline (GitHub Actions, `.github/workflows/`)
| Workflow / job | Trigger | What it proves |
|---|---|---|
| `ci` / `static` | every push to `main`, every PR | shell syntax, `docker compose config`, no committed secrets (placeholders only in `.env.example`), `terraform fmt` + `validate` for `envs/floci` and `envs/aws` |
| `ci` / `smoke` | every push to `main`, or manually (*Run workflow*, `run_smoke`) | boots the real stack on a clean runner: module install, platform, vc-frontend, then `validate`, `persistence-test`, `failure-drill`, `backup-restore-test` (fresh install, so `VALIDATE_REQUIRE_DATA=0`: proxy chain checked, catalog content is not) |
| `ci` / `image-scan` | manual only (`run_scan`) | Trivy over every image, report only; reports uploaded as artifact `trivy-reports` |
| `Floci Terraform Infrastructure` | pushes touching `terraform/` or `docker-compose.floci.yml`, PRs, manually | starts the Floci emulator, runs `terraform plan/apply` against it, verifies the resources with the AWS CLI; logs uploaded as `floci-terraform-evidence` |

Read results: repository **Actions** tab -> pick a run -> click a job for step logs; artifacts are at the bottom of the run page. The pipeline does **not** host the application (runners are deleted after the run); to use the app, run it locally (section 5). Nothing in the pipeline touches real AWS.

## 11. Logs and troubleshooting
`docker compose logs -f platform` (or any service), `docker compose ps -a`, `docker inspect --format '{{json .State.Health}}' <container>`. Common errors: `docs/TROUBLESHOOTING.md`.

## 12. Security considerations
`docs/SECURITY.md` (what is implemented locally vs proposed).

## 13. Backup, restore, rollback
- Verify the whole cycle any time: `./scripts/backup-restore-test.sh`.
- Backup: `./scripts/backup.sh` → `backups/<ts>/{db.bak,platform_appdata.tgz,cms_content.tgz,SHA256SUMS}`.
- Restore: `./scripts/restore.sh backups/<ts>` (verifies checksums, asks to confirm, stops platform, restores, restarts). Then `validate.sh`.
- Rollback of a bad upgrade: (1) `backup.sh` before upgrading; (2) keep the previous `.env.lock`; (3) `./scripts/rollback.sh <previous-release lock file>` (KEY=image lines; save a copy of `.env.lock` per release, e.g. `releases/2026-11-22.lock`); if the new version already migrated the DB schema, also restore the backup (migrations are not reversible).
- AWS: ECS circuit-breaker auto-rolls back failed deployments; redeploy previous task-definition revision; RDS point-in-time restore to a new instance.

## 14. Cleanup
`./scripts/cleanup.sh` (stops, keeps data) · `./scripts/cleanup.sh --volumes` (deletes all data + Floci state). Emulated infra: `cd terraform/envs/floci && tofu destroy`. Real AWS: `tofu destroy` (RDS has deletion protection and a final snapshot; disable deliberately).

## 15. Cost
`docs/COST.md` (estimates, assumptions). Local and Floci cost nothing; no AWS spend occurred.

## 16. Known limitations and improvements
- The legacy storefront image is incompatible with the current Platform (verified; see ARCHITECTURE §6). vc-frontend is used.
- Verified by running: compose stack, validate, persistence, failure drill, Floci + Terraform (see STATUS). `backup.sh` + `restore.sh` verified end-to-end by `scripts/backup-restore-test.sh` (`evidence/09-backup-restore.txt`). Image scan: `scripts/scan-images.sh` (results in SECURITY.md). `rollback.sh` verified by a real rollback and roll-forward (`evidence/11-rollback.txt`); it only reverts **images** - schema changes need `restore.sh`. Backups do not include the `platform_modules` volume or the Elasticsearch index: both are rebuilt (`install-modules.sh`, admin search-index rebuild).
- Module installation needs internet access (GitHub, NuGet, Azure blob) and ~10 minutes the first time.
- Search index is not built automatically after sample data; rebuild it manually.
- AWS IaC lacks the search tier, frontend service, module installation step (bake modules into an image or run the init job as an ECS task), redirect/WAF and autoscaling.
- Local `sa` DB login and disabled ES security. Improve: dedicated DB user, ES TLS/auth.
- Pin all images by digest; add SBOM + Cosign signing; add Renovate/Dependabot.
