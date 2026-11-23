# Virto Commerce on Docker + AWS (Floci) - DevOps assignment

Deploys **Virto Commerce Platform** and a **storefront** with Docker Compose, provisions AWS-shaped infrastructure on the **Floci** emulator with OpenTofu/Terraform, and documents a **real-AWS design**.

> **Read this first.** Local Docker (real app) ≠ Floci (emulated AWS) ≠ real AWS. **Nothing was deployed to real AWS.** The local stack and the Floci provisioning were run for real; see `docs/STATUS.md` for exactly what was verified, what deviated from the first draft, and what is not claimed. Evidence is in `evidence/`.

## Quick start
```bash
git clone <repo> && cd <repo-name>
./scripts/generate-env.sh           # random secrets -> .env (git-ignored)
./scripts/install-modules.sh        # ONE-TIME: install the Virto module bundle (platform image has no modules/admin UI)
./scripts/up.sh                     # db + search + redis + platform
# open http://localhost:8090 , log in admin / store (you must change the password), install the sample data,
# then More > Search index > Rebuild (products are invisible in the storefront until the index exists)
./scripts/up.sh --with-storefront   # vc-frontend (downloaded + served by nginx) on http://localhost:8080
./scripts/validate.sh               # health + connectivity + GraphQL/search checks
./scripts/persistence-test.sh       # data survives restart
./scripts/failure-drill.sh          # safe failure + recovery

./scripts/floci-up.sh               # emulated AWS + AWS CLI check
./scripts/floci-apply.sh            # provision emulated infra with OpenTofu
./scripts/cleanup.sh [--volumes]    # stop / delete
```

## Where things are
| Assignment task | Location |
|---|---|
| 1 Research/architecture | `docs/ARCHITECTURE.md` |
| 2 Local deployment | `docker-compose.yml`, `.env.example`, `scripts/up.sh` |
| 3 AWS + Floci | `docker-compose.floci.yml`, `terraform/envs/floci`, `terraform/envs/aws`, `scripts/floci-*.sh` |
| 4 Automation | `scripts/`, `.github/workflows/ci.yml`, rollback in `docs/RUNBOOK.md` §13 |
| 5 Security/ops/cost | `docs/SECURITY.md`, `docs/COST.md` |
| 6 Testing/troubleshooting | `scripts/validate.sh`, `persistence-test.sh`, `failure-drill.sh`, `docs/TROUBLESHOOTING.md` |
| 7 Docs | `docs/RUNBOOK.md` (16 sections), this README |
| 8 Presentation | `docs/presentation/Virto-AWS-DevOps-presentation.pptx` (speaker notes included) |

Offline static checks (no Docker daemon): `./scripts/test-all.sh`.

## Before you submit
1. Run everything above, pin real image tags/digests, fill `evidence/` and the "one issue" slide with your real incident.
2. Update `docs/STATUS.md` with what passed/failed.
3. Be able to explain every file (the brief requires it).
