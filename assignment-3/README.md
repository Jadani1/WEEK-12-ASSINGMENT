# Assignment 3 — CI/CD with GitHub Actions

Local **CI pipeline** for a Bash application: validate the code, run tests, and build/smoke-test a Docker image. **No cloud deployment.**

## Required structure

```
assignment-3/
├── README.md
├── app/
│   └── app.sh
├── scripts/
│   ├── lint.sh
│   └── build.sh
├── tests/
│   └── test.sh
├── .github/
│   └── workflows/
│       └── ci.yml
├── Dockerfile
├── compose.yaml
├── .dockerignore
└── grade.sh
```

## Application CLI

```bash
./app/app.sh system-info
./app/app.sh check-host <host>
./app/app.sh check-port <host> <port>
./app/app.sh help
```

| Command | Behaviour |
|---------|-----------|
| `system-info` | Display system information |
| `check-host <host>` | Resolve / check a host |
| `check-port <host> <port>` | Validate port and check TCP connectivity |
| `help` | Display usage |

Invalid input returns **exit code 2**. Runtime/connectivity failures return **1**. Success returns **0**.

## Local workflow

```bash
chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh

# 1) Validate (required files + bash -n; ShellCheck if installed)
./scripts/lint.sh

# 2) Tests (≥8 cases: help, system-info, invalid cmd, missing host,
#    valid host, missing port, non-numeric port, out-of-range ports, …)
./tests/test.sh

# 3) Docker build + smoke (help, system-info, invalid command, …)
./scripts/build.sh

# Full grader
./grade.sh
```

### Docker directly

```bash
docker build -t devops-tool .
docker run --rm devops-tool help
docker run --rm devops-tool system-info
docker run --rm devops-tool check-host 127.0.0.1
docker run --rm devops-tool check-port example.com 443
```

### Compose

```bash
docker compose run --rm devops help
docker compose run --rm devops system-info
```

## GitHub Actions CI

File: `.github/workflows/ci.yml`

| Trigger | `push`, `pull_request` |
|---------|------------------------|
| Job order | **validate** → **test** → **docker** (via `needs:`) |

- **validate** — runs `./scripts/lint.sh`
- **test** — runs after validate; `./tests/test.sh`
- **docker** — runs after test; `./scripts/build.sh`

There is no deploy job.

## CI failure demonstration

Documented process for the assignment write-up:

1. Create a branch, e.g. `ci-fail-demo`.
2. Introduce a deliberate failure (syntax error in `app/app.sh`, or a bad assertion in `tests/test.sh`).
3. Commit and push; open a PR (or push to the branch) and confirm the **CI workflow fails** (red ✗) on GitHub Actions.
4. Fix the issue, commit, and push again.
5. Confirm the **final workflow run passes** (green ✓).

Example (run from a git remote that has Actions enabled):

```bash
git checkout -b ci-fail-demo
# e.g. break a test expectation, commit, push
git add -A && git commit -m "demo: break tests" && git push -u origin ci-fail-demo
# observe failed Actions run, then:
# fix files, commit, push — observe green CI
git checkout main   # or master
```

> **Monorepo (Week 12 root):** GitHub Actions only loads workflows from the **repository root**. This monorepo wires CI at `../.github/workflows/ci.yml` with `working-directory: assignment-3` (same validate → test → docker jobs). Keep this folder’s `.github/workflows/ci.yml` for the required layout.
>
> **Standalone repo:** If you push **only** `assignment-3` as its own GitHub repository, the workflow under `.github/workflows/ci.yml` in this folder is used. Initialize the repo, push, and enable Actions.

## Grading

```bash
chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh
./grade.sh
```

The grader checks repository structure, Bash syntax, executable permissions, workflow triggers, required jobs, job dependencies (`needs`), application behaviour, linting, Docker build/smoke tests, student tests, and basic Git history when available.

## Author

Capstone Week 12 — Assignment 3
