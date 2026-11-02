# Assignment 2 — Dockerized Diagnostic CLI

Turn a Bash diagnostic tool into a **Dockerized application** that can be built and run locally.

## Layout

```
assignment-2/
├── README.md
├── app/
│   ├── diagnostic.sh      # Main CLI
│   └── health-check.sh    # Container health probe
├── Dockerfile
├── compose.yaml
├── .dockerignore
├── test.sh
└── grade.sh
```

## CLI

The container entrypoint is the `diagnostic` CLI:

| Command | Description |
|---------|-------------|
| `diagnostic system` | Display useful Linux system information |
| `diagnostic network <host>` | Check connectivity to the supplied host |
| `diagnostic disk` | Display disk information |
| `diagnostic help` | Show commands and usage |

Invalid commands and missing arguments are rejected with a clear message.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Operational / runtime failure |
| `2` | Invalid command or input |

## Prerequisites

- Docker Engine (or Docker Desktop)
- Docker Compose v2 (`docker compose`)

## Build

```bash
docker build -t diagnostic-tool .
```

## Run with Docker

```bash
docker run --rm diagnostic-tool system
docker run --rm diagnostic-tool disk
docker run --rm diagnostic-tool help
docker run --rm diagnostic-tool network example.com
```

Default command (no args) is `help`:

```bash
docker run --rm diagnostic-tool
```

## Run with Docker Compose

```bash
docker compose run --rm diagnostic system
docker compose run --rm diagnostic disk
docker compose run --rm diagnostic help
docker compose run --rm diagnostic network 1.1.1.1
```

## Dockerfile notes

- **Base image:** `alpine:3.20` (lightweight)
- **Packages:** `bash`, `coreutils`, `procps`, `iproute2`, `iputils`, `bind-tools`
- App copied to `/app` with executable permissions
- `ENTRYPOINT ["/app/diagnostic.sh"]` and `CMD ["help"]`
- `HEALTHCHECK` runs `health-check.sh`

## .dockerignore

Excludes `.git`, logs, temp files, docs, and host-side scripts (`test.sh`, `grade.sh`, compose files) so the build context stays small.

## Tests & grading

```bash
# Smoke tests (build + help/system/disk/invalid)
chmod +x test.sh grade.sh
./test.sh

# Structure + Docker grading checks
./grade.sh
```

On Windows (Git Bash):

```bash
bash test.sh
bash grade.sh
```

## Author

Capstone Week 12 — Assignment 2
