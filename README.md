# Week 12 Capstone Assignments

Monorepo for Week 12 DevOps assignments.

| Folder | Topic |
|--------|--------|
| `assignment-1/` | Bash system diagnostics |
| `assignment-2/` | Dockerized diagnostic CLI |
| `assignment-3/` | CI/CD with GitHub Actions (local pipeline, no cloud deploy) |

## Assignment 3 (CI)

- App and scripts live under `assignment-3/`
- **Monorepo CI:** `.github/workflows/ci.yml` (repo root) runs lint → test → Docker smoke with `working-directory: assignment-3`
- **Standalone layout:** `assignment-3/.github/workflows/ci.yml` is also present for the required assignment structure (and if you push `assignment-3` alone as its own repo)

### Local checks

```bash
cd assignment-3
chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh
./grade.sh
```

Docker Desktop must be running for `./scripts/build.sh` and the CI **docker** job.

### Push

```bash
git add assignment-1 assignment-2 assignment-3 .github README.md
git commit -m "Add week 12 assignments 1-3 and monorepo CI"
git push -u origin main
```

Then open the **Actions** tab on GitHub to confirm the green CI run.
