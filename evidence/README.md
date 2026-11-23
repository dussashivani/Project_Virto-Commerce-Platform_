# Evidence

Real output captured while building and verifying this repo (no passwords, tokens or keys).

| File | What it shows |
|---|---|
| `versions.txt`, `image-versions.txt` | Docker/Compose versions; pinned image digests and the platform/bundle version match |
| `modules-install.txt` | one-shot `vc-build` module installation (59 modules) |
| `01-startup.txt`, `01b-startup-storefront.txt`, `02-ps-healthy.txt` | stack start and container health |
| `03-validate.txt` | `scripts/validate.sh`: health, connectivity, GraphQL through nginx, search serves products |
| `04-persistence.txt` | marker row, `App_Data` file and real Virto data identical after a restart |
| `05-failure-drill.txt` | Redis stopped on purpose; app keeps serving; recovery |
| `06-floci-cli.txt`, `07-floci-apply.txt` | AWS CLI against the Floci emulator; 20 resources created by Terraform (EMULATED AWS) |
| `08-frontend-platform-comms.txt` | frontend <-> platform communication; the legacy storefront's 405 incompatibility |
| `09-backup-restore.txt` | backup, destroy, restore, verify |
| `10-trivy-run.txt`, `trivy/` | vulnerability scan of every image (per-image reports + `SUMMARY.txt`) |
| `11-rollback.txt` | image rollback and roll-forward |
| CI runs | GitHub Actions run history of this repository (`ci`, `Floci Terraform Infrastructure`), artifact `floci-terraform-evidence` |

Screenshots (add as `evidence/*.png`, cropped to the page - no browser tabs, bookmarks or account names): admin dashboard, storefront home with products, Docker Desktop container list, green Actions runs.

Regenerate any of the text files by running the script named in the table (see `docs/RUNBOOK.md`).
