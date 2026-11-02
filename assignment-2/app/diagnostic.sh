#!/usr/bin/env bash
# diagnostic.sh — Dockerized diagnostic CLI
# Usage: diagnostic <command> [args]
#   system              Display Linux system information
#   network <host>      Check connectivity to the supplied host
#   disk                Display disk information
#   help                Show commands and usage
set -uo pipefail

APP_NAME="diagnostic"
VERSION="1.0.0"

# ---------- helpers ----------
usage() {
  cat <<EOF
${APP_NAME} v${VERSION} — Linux diagnostic CLI

Usage:
  ${APP_NAME} <command> [arguments]

Commands:
  system              Display useful Linux system information
  network <host>      Check connectivity to the supplied host
  disk                Display disk usage information
  help                Show this help message

Exit codes:
  0  success
  1  operational / runtime failure
  2  invalid command or input

Examples:
  ${APP_NAME} system
  ${APP_NAME} network example.com
  ${APP_NAME} disk
  ${APP_NAME} help
EOF
}

err() {
  printf '%s: %s\n' "${APP_NAME}" "$*" >&2
}

# Human-readable byte sizes
human_bytes() {
  local b="${1:-0}"
  awk -v b="$b" 'BEGIN {
    split("B KB MB GB TB PB", u, " ")
    for (i = 1; b >= 1024 && i < 6; i++) b /= 1024
    if (b == int(b)) printf "%d %s\n", b, u[i]
    else printf "%.1f %s\n", b, u[i]
  }'
}

# ---------- commands ----------
cmd_help() {
  usage
  return 0
}

cmd_system() {
  local hostname_val user_val datetime_val os_val kernel_val uptime_val
  local cpu_val mem_total mem_avail mem_used cwd_val

  hostname_val="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)"
  user_val="$(whoami 2>/dev/null || id -un 2>/dev/null || echo unknown)"
  datetime_val="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_val="${PRETTY_NAME:-${NAME:-Linux} ${VERSION_ID:-}}"
  else
    os_val="$(uname -s 2>/dev/null || echo Linux)"
  fi

  kernel_val="$(uname -r 2>/dev/null || echo unknown)"

  if [[ -r /proc/uptime ]]; then
    local secs
    secs="$(awk '{print int($1)}' /proc/uptime)"
    local d=$((secs / 86400)) h=$(((secs % 86400) / 3600)) m=$(((secs % 3600) / 60))
    uptime_val="${d}d ${h}h ${m}m"
  else
    uptime_val="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
  fi

  if [[ -r /proc/cpuinfo ]]; then
    cpu_val="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
    [[ -z "${cpu_val}" ]] && cpu_val="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) CPU(s)"
  else
    cpu_val="$(nproc 2>/dev/null || echo unknown) CPU(s)"
  fi

  if [[ -r /proc/meminfo ]]; then
    mem_total="$(awk '/MemTotal:/ {print $2 * 1024}' /proc/meminfo)"
    mem_avail="$(awk '/MemAvailable:/ {print $2 * 1024}' /proc/meminfo)"
    if [[ -n "${mem_total}" && -n "${mem_avail}" ]]; then
      mem_used=$((mem_total - mem_avail))
    else
      mem_used=0
      mem_total=0
    fi
  elif command -v free >/dev/null 2>&1; then
    read -r mem_total mem_used _ < <(free -b | awk '/Mem:/ {print $2, $3, $7}')
  else
    mem_total=0
    mem_used=0
  fi

  cwd_val="$(pwd 2>/dev/null || echo unknown)"

  cat <<EOF
========== System Information ==========
Hostname           : ${hostname_val}
Current User       : ${user_val}
Date/Time          : ${datetime_val}
Operating System   : ${os_val}
Kernel             : ${kernel_val}
Uptime             : ${uptime_val}
CPU                : ${cpu_val}
Memory Total       : $(human_bytes "${mem_total:-0}")
Memory Used        : $(human_bytes "${mem_used:-0}")
Working Directory  : ${cwd_val}
========================================
EOF
  return 0
}

cmd_disk() {
  echo "========== Disk Information =========="
  if ! command -v df >/dev/null 2>&1; then
    err "df is not available"
    return 1
  fi

  # Portable df output: filesystem, size, used, avail, use%, mount
  if df -h -P / >/dev/null 2>&1; then
    df -h -P 2>/dev/null | awk '
      NR == 1 { printf "%-20s %8s %8s %8s %6s  %s\n", "Filesystem", "Size", "Used", "Avail", "Use%", "Mounted on"; next }
      { printf "%-20s %8s %8s %8s %6s  %s\n", $1, $2, $3, $4, $5, $6 }
    '
  else
    df -h 2>/dev/null || df
  fi

  echo
  echo "--- Root filesystem summary ---"
  local root_line use_pct
  root_line="$(df -P / 2>/dev/null | awk 'NR==2 {print}')"
  if [[ -n "${root_line}" ]]; then
    use_pct="$(awk '{gsub(/%/,"",$5); print $5}' <<<"${root_line}")"
    printf "Mount / usage: %s%%\n" "${use_pct:-?}"
    printf "Detail: %s\n" "${root_line}"
  else
    err "could not read disk usage for /"
    echo "======================================"
    return 1
  fi
  echo "======================================"
  return 0
}

cmd_network() {
  local host="${1:-}"
  if [[ -z "${host}" ]]; then
    err "network requires a host argument"
    echo "Usage: ${APP_NAME} network <host>" >&2
    return 2
  fi

  # Basic validation: reject empty/whitespace and obviously illegal characters
  if [[ ! "${host}" =~ ^[A-Za-z0-9._:/-]+$ ]] || [[ "${host}" =~ [[:space:]] ]]; then
    err "invalid host: ${host}"
    return 2
  fi

  local overall=0
  local resolved=""

  echo "========== Network Check =========="
  echo "Target host : ${host}"

  # Resolve
  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "${host}" 2>/dev/null | awk '{print $1; exit}')"
  fi
  if [[ -z "${resolved}" ]] && command -v dig >/dev/null 2>&1; then
    resolved="$(dig +short "${host}" A 2>/dev/null | head -n1)"
  fi
  if [[ -z "${resolved}" ]] && command -v host >/dev/null 2>&1; then
    resolved="$(host "${host}" 2>/dev/null | awk '/has address/ {print $4; exit}')"
  fi
  # Literal IP
  if [[ -z "${resolved}" ]] && [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    resolved="${host}"
  fi
  if [[ -z "${resolved}" ]] && [[ "${host}" =~ : ]]; then
    resolved="${host}"
  fi

  if [[ -n "${resolved}" ]]; then
    echo "Resolved    : ${resolved}"
  else
    echo "Resolved    : (could not resolve)"
    overall=1
  fi

  # Ping (1–2 packets, short timeout). May be restricted in some containers.
  echo
  echo "--- Connectivity (ping) ---"
  local ping_ok=0
  if command -v ping >/dev/null 2>&1; then
    if ping -c 2 -W 3 "${host}" >/tmp/diagnostic-ping.out 2>&1 || \
       ping -c 2 -w 3 "${host}" >/tmp/diagnostic-ping.out 2>&1; then
      ping_ok=1
      echo "Ping        : OK"
      tail -n 3 /tmp/diagnostic-ping.out 2>/dev/null || true
    else
      echo "Ping        : FAILED"
      tail -n 5 /tmp/diagnostic-ping.out 2>/dev/null || true
      overall=1
    fi
  else
    echo "Ping        : unavailable (ping not installed)"
    overall=1
  fi
  rm -f /tmp/diagnostic-ping.out 2>/dev/null || true

  # Interfaces
  echo
  echo "--- Network interfaces ---"
  if command -v ip >/dev/null 2>&1; then
    ip -br addr 2>/dev/null || ip addr 2>/dev/null || true
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null || true
  else
    echo "(no ip/ifconfig available)"
  fi

  echo "==================================="
  if (( overall == 0 )); then
    echo "Result: SUCCESS"
    return 0
  else
    echo "Result: FAILURE (connectivity issues)"
    return 1
  fi
}

# ---------- main ----------
main() {
  local cmd="${1:-}"

  if [[ -z "${cmd}" ]]; then
    err "missing command"
    usage >&2
    exit 2
  fi

  shift || true

  case "${cmd}" in
    system)
      cmd_system "$@"
      exit $?
      ;;
    disk)
      cmd_disk "$@"
      exit $?
      ;;
    network)
      cmd_network "$@"
      exit $?
      ;;
    help|-h|--help)
      cmd_help
      exit 0
      ;;
    *)
      err "unknown command: ${cmd}"
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
