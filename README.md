# Virto Commerce on Docker and AWS (Floci)

This repo runs the Virto Commerce Platform and a storefront locally with Docker Compose. It also provisions AWS-style infrastructure on the Floci emulator with Terraform, and includes a design for a real AWS deployment.

**What was actually run, and what wasn't**

| Environment | What it is | Status |
|---|---|---|
| Local Docker | The real application: Platform, SQL Server, Elasticsearch, Redis, storefront | Built and tested |
| Floci | An AWS emulator on port 4566. Terraform creates a VPC, subnets, security groups, an ECS cluster, IAM, S3, logs and a secret | Applied (20 resources) and checked with the AWS CLI |
| Real AWS | Reference Terraform in `terraform/envs/aws` | Written only. Nothing was deployed and no AWS money was spent |

`docs/STATUS.md` lists exactly what was verified, where I changed the original plan, and what I did not do. Command output is saved in `evidence/`.

## Quick start

You need Docker (with Compose v2), Git, and Bash. On Windows use Git Bash.

```bash
git clone https://github.com/dussashivani/Project_Virto-Commerce-Platform_.git
cd Project_Virto-Commerce-Platform_

./scripts/generate-env.sh        # creates .env with random secrets (git-ignored)
./scripts/install-modules.sh     # one time: installs the Virto modules (the image ships with none)
./scripts/up.sh                  # SQL Server, Elasticsearch, Redis, Platform
```

If GitHub rate-limits the module download, run `export GITHUB_TOKEN=<any token, no scopes needed>` and try again.

Then open http://localhost:8090 and sign in as `admin` / `store`. Virto makes you change the password on first login. In the admin:

1. Install the sample data.
2. Go to More > Search index and rebuild the index. Products don't show in the storefront until this is done.

Start the storefront and run the checks:

```bash
./scripts/up.sh --with-storefront   # vc-frontend behind nginx, http://localhost:8080
./scripts/validate.sh               # health, connectivity, a real GraphQL query, search
./scripts/persistence-test.sh       # data survives a restart
./scripts/failure-drill.sh          # stop Redis, check the platform keeps working, recover
./scripts/backup-restore-test.sh    # back up, destroy data, restore, verify
```

The emulated AWS part:

```bash
./scripts/floci-up.sh        # start Floci and check the AWS CLI
./scripts/floci-apply.sh     # terraform apply against Floci, then verify with the CLI
./scripts/cleanup.sh         # stop everything (add --volumes to delete data too)
```

Static checks that need no Docker: `./scripts/test-all.sh`.

## What is in the repo

| Topic | Where to look |
|---|---|
| Architecture and technology choices | `docs/ARCHITECTURE.md` |
| Local deployment | `docker-compose.yml`, `.env.example`, `frontend/nginx.conf`, `scripts/up.sh` |
| Floci and Terraform | `docker-compose.floci.yml`, `terraform/envs/floci`, `terraform/envs/aws`, `scripts/floci-*.sh` |
| Automation and CI | `scripts/`, `.github/workflows/ci.yml`, `.github/workflows/floci-terraform.yml` |
| Security, operations, cost | `docs/SECURITY.md`, `docs/COST.md` |
| Testing and troubleshooting | `scripts/validate.sh`, `persistence-test.sh`, `failure-drill.sh`, `docs/TROUBLESHOOTING.md` |
| Runbook (deploy, backup, restore, rollback) | `docs/RUNBOOK.md` |
| Presentation | `docs/presentation/Virto-AWS-DevOps-presentation.pptx` (speaker notes included) |
| Proof of what ran | `evidence/` (command output and screenshots) |

## Known limitations

- Nothing runs on real AWS.
- Product photos are blank in the storefront. The Virto sample data creates the image records but ships no image files. Details are in `docs/TROUBLESHOOTING.md`.
- Elasticsearch 8.15.3 has 9 fixable critical findings in the Trivy scan, and I did not upgrade it. See `docs/SECURITY.md`.
- Local-only shortcuts, such as Elasticsearch security being off and plain HTTP, are listed in `docs/SECURITY.md` along with what production would use instead.
