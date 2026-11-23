# Status and deviations

Updated after a real run on Windows 11 + Docker Desktop (engine 29.9.3, Compose v5.7.0). Evidence files are in `evidence/`.

## What was verified (ran for real)
| Area | Result | Evidence |
|---|---|---|
| Local stack (SQL Server 2022, Elasticsearch 8.15.3, Redis 7.4, Platform 3.1076.13, 59 modules) | all healthy, restart policy brought it back after Docker was stopped | `01-startup.txt`, `02-ps-healthy.txt` |
| Platform admin | login works, default admin password changed, sample data loaded (9 catalogs, 1 store, 389 products) | `evidence/12-admin-login.png`, `14-admin-dashboard.png`, `15-admin-catalog.png` |
| Frontend (vc-frontend 2.59.1 + nginx) <-> Platform | GraphQL through nginx returns store `B2B-store`; search serves 147 products | `03-validate.txt`, `08-frontend-platform-comms.txt` |
| `scripts/validate.sh` | all checks pass | `03-validate.txt` |
| `scripts/persistence-test.sh` | marker row, `App_Data` file and real Virto data (5 users / 9 catalogs / 1 store) identical after restart | `04-persistence.txt` |
| `scripts/backup-restore-test.sh` | wrote markers, `backup.sh`, destroyed them (+ a post-backup change), `restore.sh` with checksum verification: DB marker, App_Data file and real data (5 users / 9 catalogs / 389 items) recovered; post-backup change rolled back; platform served 200 | `09-backup-restore.txt` |
| `scripts/failure-drill.sh` | Redis stopped: platform + GraphQL kept answering (cache layer degrades, logs `Redis disconnected`); recovered after start | `05-failure-drill.txt` |
| `scripts/rollback.sh` | rolled the frontend back from `nginx:1.30.7-alpine` to the previous `nginx:1.27-alpine` using a previous-release lock file, verified it was really running, validate passed; then rolled forward again. **Found and fixed a bug** (silent no-op for profile services). Image rollback only: DB schema rollback = `restore.sh` | `11-rollback.txt` |
| Trivy scan (`scripts/scan-images.sh`) | all 7 images scanned; nginx 1.27 (67 HIGH/3 CRIT) replaced by 1.30.7 (1 HIGH/0 CRIT) and revalidated; ES and legacy storefront have open CRITICALs (documented) | `10-trivy-run.txt`, `trivy/` |
| Floci + AWS CLI | `sts get-caller-identity` returns emulated account `000000000000` | `06-floci-cli.txt` |
| Terraform on Floci (envs/floci) | 20 resources created (VPC, subnets, SGs, ECS cluster, IAM role, S3 bucket, log groups, secret) and confirmed through the AWS CLI | `07-floci-apply.txt` |
| CI `floci-terraform.yml` (repo `main`, run 45148454371) | compose config, terraform fmt/init/validate, Floci start, AWS CLI check, plan, apply, resource verification: passed (1m17s); Floci logs uploaded as artifact `floci-terraform-evidence` | Actions run history |
| CI `ci.yml` (repo `main`, run 45147406040) | `static` (shell syntax, compose, secret/placeholder check, terraform fmt+validate) and full-stack `smoke` on a clean ubuntu runner: module install, stack + vc-frontend boot, validate (no-sample-data mode), persistence, failure drill, backup/restore: all passed (3m17s). Two real CI-only problems were found and fixed on the way: a Linux file-permission bug in `restore.sh`, and `vc-build` GitHub API rate limiting (token + retry). `image-scan` job exists but was **not** run in CI (local Trivy results only) | Actions run history |

## Where I changed the original plan (and why)
| Deviation | Reason |
|---|---|
| Platform pinned to `ghcr.io/virtocommerce/platform:3.1076.13`, not Docker Hub `:latest` | Hub `:latest` (3.1101) is newer than the stable module bundle; versions must match. Tag exists on ghcr.io only. |
| Modules installed by a one-shot `modules-init` job (`vc-build`, .NET 10 SDK) | image ships with no modules / no admin UI |
| Storefront = **vc-frontend 2.59.1 + nginx**, legacy `virtocommerce/storefront` kept under compose profile `legacy` | legacy image (built 2024-04-18) calls `GET /api/stores`, which Platform answers 405 -> every page 500 (`TROUBLESHOOTING.md`) |
| No setup wizard | there is none in this version; default `admin`/`store`, forced password change |
| `VirtoCommerce__AllowInsecureHttp=true` locally | token endpoint refuses plain HTTP otherwise; in AWS TLS ends at the ALB |
| Search provider `ElasticSearch8` + a manual index rebuild | provider id must match the module; index is not built automatically after sample data |
| Elasticsearch security disabled, no TLS, DB/ES/Redis unpublished | local only; production controls are *proposed* in `SECURITY.md` |

## Not done / not claimed
| Item | State |
|---|---|
| Real AWS | **Reference IaC only (`terraform/envs/aws`). Nothing deployed.** Floci proves the Terraform runs against an emulator, not that Virto runs on AWS. |
| OpenTofu | not used locally: Terraform 1.x was installed; CI also uses Terraform. Config is compatible with both. |
| Image vulnerability gating in CI / ECR scan-on-push | proposed. (Local Trivy scan **was run**; Elasticsearch 8.15.3 still has 9 fixable CRITICAL jar findings - not remediated, see SECURITY.md) |
| `vc-frontend` store/theme customisation | stock B2B theme only |
| frontend API user (`frontend`) | created for the legacy storefront test; **not needed by vc-frontend** (uses GraphQL) |
| Screenshots | admin and storefront are in `evidence/12-16`; no Docker Desktop or Actions screenshots, and none of the Elasticsearch index |
| Product images in the storefront | **Not shown (known sample-data limitation).** The sample data loads 1,186 image records but not the image files; the platform builds URLs on its default `https://localhost:5001/assets/...` and the files do not exist (404 on the platform too). Catalog, search, prices and variations work. See `TROUBLESHOOTING.md` |
