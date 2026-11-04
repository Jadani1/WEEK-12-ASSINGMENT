# Assignment 1 — Linux, Bash & Networking

A small **Linux diagnostic toolkit** written in Bash. The scripts collect system information, check disk usage against a threshold, and run basic network diagnostics. Runtime logs are written under `logs/`.

## Project structure

```
assignment-1/
├── README.md
├── system-info.sh
├── disk-check.sh
├── network-check.sh
├── grade.sh
├── logs/
│   └── .gitkeep
└── .gitignore
```

## Requirements

- Bash (Linux, macOS, or Git Bash / MSYS on Windows)
- Common utilities: `df`, `ping`, and either `ip` / `ifconfig` / `ipconfig`
- Optional: `getent`, `dig`, `host`, `nslookup`, `nc` (improve DNS / TCP checks)

```bash
chmod +x system-info.sh disk-check.sh network-check.sh grade.sh   # Linux/macOS
```

## Scripts

### `system-info.sh`

Collects values from the live system and prints:

| Field | Source (examples) |
| --- | --- |
| Hostname | `hostname` |
| Current user | `whoami` |
| Date/time | `date` |
| Operating system | `/etc/os-release`, `uname` |
| Kernel version | `uname -r` |
| Uptime | `uptime` / `/proc/uptime` |
| CPU | `/proc/cpuinfo`, `wmic` (Windows) |
| Memory | `free`, `/proc/meminfo`, `wmic` |
| Working directory | `pwd` |

```bash
./system-info.sh
```

### `disk-check.sh`

```bash
./disk-check.sh <threshold> [path]
```

- **threshold** — integer **1–100** (percent). Required.
- **path** — filesystem path to measure (default: `/`).
- Prints the disk usage percentage for that path.
- **Exit 0** — usage is **below** the threshold.
- **Exit 1** — usage is **at or above** the threshold.
- **Exit 2** — invalid input (bad threshold, missing args, missing path).

Examples:

```bash
./disk-check.sh 80
./disk-check.sh 90 /home
./disk-check.sh 100 .
```

### `network-check.sh`

```bash
./network-check.sh <hostname-or-ip> [port]
```

- Validates the host argument (hostname or IP).
- Resolves the host and displays the resolved address (IPs are used as-is).
- Performs a basic connectivity check (`ping`).
- Displays network interface information (`ip`, `ifconfig`, or `ipconfig`).
- If **port** is supplied (1–65535), checks TCP connectivity.
- Invalid input returns a **non-zero** status and does not crash the script.
- **Exit 0** — checks succeeded.
- **Exit 1** — connectivity and/or TCP check failed.
- **Exit 2** — invalid input.

Examples:

```bash
./network-check.sh example.com
./network-check.sh 8.8.8.8 53
./network-check.sh 127.0.0.1 22
```

## Logging

Each script appends timestamped entries under `logs/`:

| Script | Log file |
| --- | --- |
| `system-info.sh` | `logs/system-info.log` |
| `disk-check.sh` | `logs/disk-check.log` |
| `network-check.sh` | `logs/network-check.log` |

Format:

```text
[YYYY-MM-DD HH:MM:SS] description of the operation
```

`logs/*.log` is gitignored; `logs/.gitkeep` keeps the directory in version control.

## Automated checks

```bash
./grade.sh
```

`grade.sh` verifies project layout, script syntax, required output fields, argument validation / exit codes, and that logs are written.

## Git workflow (assignment)

This repository was developed with:

- Multiple meaningful commits (clear messages)
- At least one feature branch off `main` / `master`
- Feature branch merged back into `main`

Typical flow:

```bash
git checkout -b feature/diagnostic-scripts
# ... implement scripts ...
git add -A && git commit -m "Add system-info, disk-check, and network-check scripts"
git checkout main
git merge feature/diagnostic-scripts
```

## Author

Capstone Week 12 — Assignment 1
