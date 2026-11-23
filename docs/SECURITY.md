# Security and operations (Task 5)

Legend: **LOCAL** = implemented and checkable in this repo. **PROPOSED** = designed/IaC-referenced for real AWS, not deployed.

| Control | Status | Detail |
|---|---|---|
| No hard-coded secrets | LOCAL | `.env` generated with random secrets, git-ignored; `.env.example` has placeholders; `test-all.sh` scans for AWS keys/private keys. Emulator creds `test/test` are dummies by design. |
| Secrets in AWS | PROPOSED | Secrets Manager, injected by ECS `secrets`; random password in IaC (note: it lands in Terraform state, so use encrypted remote state). |
| Least-privilege IAM | LOCAL (emulator) + PROPOSED | Task role: GetSecretValue on one secret, S3 object RW on one bucket, logs write on two groups. Separate execution role for image pull/secret fetch. CI role (OIDC, no static keys) is proposed. |
| Network boundaries | LOCAL + PROPOSED | Compose: DB/ES/Redis unpublished, storefront cannot reach them, ports bound to 127.0.0.1. AWS: 3 subnet tiers, SG chain ALB→app→data. |
| TLS | PROPOSED | ALB HTTPS listener with ACM cert, TLS 1.3/1.2 policy; HTTP→HTTPS redirect to add; local runs plain HTTP on localhost. |
| DB access | LOCAL + PROPOSED | No host port; app uses `sa` locally (**weakness**). Production: dedicated least-privilege DB login, private RDS, SG from app tier only, encryption at rest. |
| Image pinning and scanning | IMPLEMENTED LOCALLY (scan), PROPOSED (gating) | Images pinned by digest (`evidence/image-versions.txt`). Trivy scan of every image: `scripts/scan-images.sh` -> `evidence/trivy/` (results below). CI gating / ECR scan-on-push / SBOM / Cosign are **proposed**; the `ci.yml` Trivy step is defined but was not run in GitHub Actions. |
| Logs | LOCAL + PROPOSED | json-file with rotation; `docker compose logs`. AWS: awslogs to CloudWatch, 30-day retention. |
| Health checks | LOCAL | container healthchecks and `validate.sh`. |
| Monitoring/alerting | PROPOSED | CloudWatch alarms (ALB 5xx, RDS CPU) → SNS; add ECS CPU/mem, RDS storage, Redis evictions. |
| Backup/restore | LOCAL + PROPOSED | `backup.sh`/`restore.sh` (native .bak + volume tarballs + checksums). AWS: RDS 14-day PITR and final snapshot, S3 versioning, AWS Backup for EFS. Restore drills still needed. |
| Availability/scaling | PROPOSED | 2 AZs, Multi-AZ RDS, ≥2 tasks, service autoscaling on CPU/ALB requests; single-writer concerns: see ARCHITECTURE §7. |
| Known local weaknesses | | ES security disabled; `sa` login; legacy storefront image kept behind profile `legacy` (known-incompatible, not started by default); admin default credentials must be changed at first login; no TLS locally. |


## Trivy scan results (run 2026-11-22, Trivy 0.58.1, HIGH+CRITICAL; `evidence/trivy/`)
| Image | HIGH | CRITICAL | CRITICAL with a fix | Assessment |
|---|---|---|---|---|
| `nginx:1.30.7-alpine` (frontend) | 1 | 0 | 0 | **Fixed by this scan:** first choice `nginx:1.27-alpine` had 67 HIGH / 3 CRITICAL (all fixable); moved to the 1.30 stable line, re-validated. |
| `ghcr.io/virtocommerce/platform:3.1076.13` | 4 | 0 | 0 | .NET runtime / SignalR-Redis packages (HIGH). Update by moving to the next platform + bundle release as a set. |
| `mssql/server:2022-latest` | 3 | 0 | 0 | Go `stdlib` inside the tools (HIGH). Pin a newer CU tag. Not published on the host. |
| `redis:7.4-alpine` | 0 | 0 | 0 | clean |
| `dotnet/sdk:10.0` (module install job only) | 0 | 0 | 0 | clean; runs once, no ports |
| `elasticsearch:8.15.3` | 112 | 9 | 9 | OS layer clean (0). Findings are **bundled Java jars** (netty-handler, tika-core, bcprov). Fix = newer 8.x patch release; must re-test with the `ElasticSearch8` module compatibility mode. Mitigation now: not published on the host, backend network only. **Not remediated.** |
| `virtocommerce/storefront:latest` (legacy) | 108 | 12 | 11 | Debian packages (openssl, libssl3, zlib, gnutls, perl, apt), out-of-support runtime. **Strongest argument for not using it**; behind compose profile `legacy`, not started by default. |

How to act on it: patch what is fixable and cheap (done for nginx), isolate what is not (ES/SQL/Redis unpublished, localhost-only ports), and gate in CI for production (`SCAN_FAIL_ON_CRITICAL_FIXABLE=1`) once the image set is upgraded. A scan is a point-in-time result; rerun it on every image bump.
