# Troubleshooting

Issues marked **(seen)** were actually hit while building this repo (see `evidence/`); the others are expected-but-not-observed.

| Symptom | Root cause | Fix |
|---|---|---|
| **(seen)** Platform page says *"No admin UI is installed on this instance"*; log `Loaded modules: 0` | The platform image ships **no modules**, so no admin UI or commerce features. The Docker Hub `:latest` platform (3.1101) is also newer than the stable module bundle (platform 3.1076.13). | Pin `ghcr.io/virtocommerce/platform:3.1076.13` and run `scripts/install-modules.sh` (installs the bundle with `vc-build` into the `platform_modules` volume). |
| **(seen)** `dotnet tool install VirtoCommerce.GlobalTool` -> *DotnetToolSettings.xml was not found in the package* | vc-build targets **.NET 10**; the .NET 8 SDK image cannot install it | `DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0` |
| **(seen)** *The user's home directory could not be determined* in `modules-init` | the container has no writable `$HOME` | `mkdir -p /tmp/home` and `DOTNET_CLI_HOME=/tmp/home` (in compose) |
| **(seen)** Admin login rejected in the browser although `admin`/`store` works against `/connect/token` | autofilled/typo'd password in the browser (account was fine: confirmed in DB and via API) | retype by hand; note 5 failures lock the account for 15 min |
| **(seen)** Legacy storefront: every page HTTP 500 | **API incompatibility** - see the worked example below | use `vc-frontend` (compose service `frontend`) |
| **(seen)** Platform logs every 5 min: *SearchException: There's no registered Search Provider* | `.env` had `SEARCH_PROVIDER=ElasticSearch`; the module registers as `ElasticSearch8`, so the platform fell back to a dummy provider (it overrides the compose default) | `SEARCH_PROVIDER=ElasticSearch8`, recreate platform, then **rebuild the index** in the admin (More > Search index). Products stay invisible in the storefront until you do. |
| **(seen)** `rollback.sh` printed *ALL CHECKS PASSED* but the frontend stayed on the new version | `docker compose up` ignores services in a profile (`frontend` is in `storefront`), and the script never checked what was actually running - a **silent false success** | `rollback.sh` now keeps the `storefront` profile when the frontend is running and verifies every `*_IMAGE` in the lock file is really running (fails otherwise). Test: `evidence/11-rollback.txt` |
| **(seen, CI only)** `restore.sh`: *Cannot open backup device '/var/opt/mssql/restore.bak' ... OS error 5 (Access is denied)* | on **Linux**, `docker compose cp` keeps the host uid/mode (runner, 0640) so SQL Server (user `mssql`) cannot read it; Docker Desktop on Windows hides this | `restore.sh` now `chown mssql` + `chmod 640` as root after the copy. Found by the GitHub Actions smoke job (a platform-difference bug no local Windows run could show) |
| **(seen, CI)** `install-modules.sh` fails: *RateLimitExceededException: API rate limit exceeded for <runner IP>* at `InstallPlatform` | `vc-build` calls the GitHub API **unauthenticated** (60 requests/hour per IP); shared CI runner IPs exhaust it, so the same code passed twice and then failed | pass `-GitHubToken` (compose env `GITHUB_TOKEN`; CI uses the built-in `secrets.GITHUB_TOKEN`) and retry 3x with 30 s backoff. Locally, export `GITHUB_TOKEN` if you hit it |
| **(seen)** `scripts/*.sh` exit **127** on Windows right after a `docker compose exec ... /opt/...` | Git Bash rewrites `/opt/...` into `C:/Program Files/Git/opt/...` | `MSYS_NO_PATHCONV=1` (set in `scripts/_lib.sh`); no effect on Linux/macOS |
| **(seen)** Windows: C: full, Docker engine will not start / pulls fail | WSL VM and images need ~15-20 GB | move Docker's disk image (Settings > Resources > Advanced > Disk image location) to another drive |
| `sqlserver` exits immediately, log: *password does not meet complexity* | SA password lacks upper/lower/digit/symbol or is < 8 chars | regenerate with `scripts/generate-env.sh` (adds a complexity suffix); `docker compose down -v` first if the volume was initialised with another password |
| `sqlserver` exits / hangs on Apple Silicon | amd64-only image | enable Rosetta emulation in Docker Desktop, or choose a different DB |
| `elasticsearch` restarts, log: *max virtual memory areas vm.max_map_count too low* | host kernel setting | `sudo sysctl -w vm.max_map_count=262144` (persist in `/etc/sysctl.d/`) |
| `platform` unhealthy for minutes on first run | initial DB migration and module load | wait; `docker compose logs -f platform`; healthcheck allows 90 s start + retries |
| Platform logs *Login failed for user 'sa'* | DB volume created with an old password | `down -v` then `up`, or reset password inside SQL Server |
| Floci `terraform apply` fails on one resource | emulator does not implement that operation | note the resource in `docs/STATUS.md`, remove it from the emulated env, keep it in `envs/aws` |

## Worked example: the official storefront image does not work with current Platform

1. **Symptom.** `virtocommerce/storefront:latest` starts and reports *healthy*, but `curl http://localhost:8080/` returns **HTTP 500** for every URL. Storefront log:
   `Microsoft.Rest.HttpOperationException: Operation returned an invalid status code 'MethodNotAllowed'`.
2. **Investigation.**
   - `docker compose logs storefront` showed `POST http://platform/connect/token` succeeded, then `GET http://platform/api/stores` -> **405**. So credentials, DNS and networking were fine.
   - Replayed the token call from a throw-away container on the compose network: HTTP 200 (rules out network/Host-header).
   - Called the platform directly with a valid token: `GET /api/stores` -> **405**, while `POST /graphql` -> **200**.
   - Image metadata: storefront image created **2024-04-18**; platform is **3.1076.13** (2026).
3. **Root cause.** The legacy ASP.NET storefront uses the old REST endpoint `GET /api/stores`, which current Platform no longer serves. The *healthcheck is only a TCP probe*, which is why the container looked healthy.
4. **Resolution.** Replaced it with the current official frontend **vc-frontend 2.59.1** (Vue SPA, GraphQL) served by nginx; nginx proxies `/graphql`, `/connect/token`, `/files`, `/cms-content` to the platform (`frontend/nginx.conf`). The legacy image stays behind the compose profile `legacy` as documented evidence.
5. **Prevention.** `scripts/validate.sh` now checks the real chain (`browser -> nginx -> platform -> search`): GraphQL returns store `B2B-store` and `products.totalCount > 0`, not just an open port. Evidence: `evidence/03-validate.txt`, `evidence/08-frontend-platform-comms.txt`.

## Third example (data, not infrastructure): product images are blank
- **Symptom.** Storefront product cards show a placeholder icon instead of a photo; everything else (categories, search, prices, variations) works.
- **Investigation.** GraphQL `imgSrc` returns `https://localhost:5001/assets/catalog/.../x.jpg`. The same path on the platform (`:8090/assets/...`) and through nginx (`:8080/assets/...`) returns 404. The database holds 1,186 relative image paths (`CatalogImage`), but the platform container has no `wwwroot/assets` directory and no image files.
- **Root cause.** The sample data package creates the image records but does not ship the files (upstream tracks this in VirtoCommerce/vc-sample-data PR #19). The `localhost:5001` host is only the platform's default public asset URL, a second, separate misconfiguration.
- **Decision.** Not fixed: images are content, not part of deploying or operating the stack. Fixing the URL alone would not help because the files are absent. If needed: set `Assets__FileSystem__PublicUrl`, proxy `/assets` in nginx, and upload images through the admin or restore them from a backup.

## Second example (silent failure): search provider
Container health was green and the site answered 200, yet products were missing. The only sign was a recurring `no registered Search Provider` error in the platform log. Root cause and fix are in the table above. Lesson: **a green healthcheck is not a working application** - validate with a data request.
