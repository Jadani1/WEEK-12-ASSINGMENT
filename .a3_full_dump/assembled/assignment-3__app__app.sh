#!/usr/bin/env bash
# app.sh — DevOps diagnostic CLI (Assignment 3)
# Usage:
#   ./app/app.sh system-info
#   ./app/app.sh check-host <host>
#   ./app/app.sh check-port <host> <port>
#   ./app/app.sh help
set -uo pipefail

APP_NAME="devops-tool"
VERSION="1.0.0"

usage() {
  cat <<EOF
${APP_NAME} v${VERSION}

Usage:
  ${APP_NAME} <command> [arguments]

Commands:
  system-info              Display system information
  check-host <host>        Resolve / check a host
  check-port <host> <port> Validate port and check TCP connectivity
  help                     Display this usage message

Exit codes:
  0  success
  1  operational / runtime failure
  2  invalid command or input

Examples:
  ${APP_NAME} system-info
  ${APP_NAME} check-host example.com
  ${APP_NAME} check-port example.com 443
  ${APP_NAME} help
EOF
}

err() {
  printf '%s: %s\n' "${APP_NAME}" "$*" >&2
}

# ---------- system-info ----------
cmd_system_info() {
  local hostname_val user_val datetime_val os_val kernel_val uptime_val
  local cpu_val mem_total mem_avail mem_used

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
    local secs d h m
    secs="$(awk '{print int($1)}' /proc/uptime)"
    d=$((secs / 86400))
    h=$(((secs % 86400) / 3600))
    m=$(((secs % 3600) / 60))
    uptime_val="${d}d ${h}h ${m}m"
  else
    uptime_val="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
  fi

  if [[ -r /proc/cpuinfo ]]; then
    cpu_val="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
    [[ -z "${cpu_val}" ]] && cpu_val="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '?') CPU(s)"
  else
    cpu_val="$(nproc 2>/dev/null || echo unknown) CPU(s)"
  fi

  if [[ -r /proc/meminfo ]]; then
    mem_total="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    mem_avail="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
    if [[ -n "${mem_total}" && -n "${mem_avail}" ]]; then
      mem_used=$((mem_total - mem_avail))
    else
      mem_total=0
      mem_used=0
    fi
  else
    mem_total=0
    mem_used=0
  fi

  cat <<EOF
========== System Information ==========
Hostname         : ${hostname_val}
User             : ${user_val}
Date/Time        : ${datetime_val}
OS               : ${os_val}
Kernel           : ${kernel_val}
Uptime           : ${uptime_val}
CPU              : ${cpu_val}
Memory Total     : ${mem_total} kB
Memory Used      : ${mem_used} kB
========================================
EOF
  return 0
}

# ---------- check-host ----------
cmd_check_host() {
  local host="${1:-}"

  if [[ -z "${host}" ]]; then
    err "check-host requires a host argument"
    echo "Usage: ${APP_NAME} check-host <host>" >&2
    return 2
  fi

  if [[ ! "${host}" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    err "invalid host: ${host}"
    return 2
  fi

  local resolved=""
  echo "========== Host Check =========="
  echo "Host: ${host}"

  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "${host}" 2>/dev/null | awk '{print $1; exit}')"
  fi
  if [[ -z "${resolved}" ]] && command -v dig >/dev/null 2>&1; then
    resolved="$(dig +short "${host}" A 2>/dev/null | head -n1)"
  fi
  if [[ -z "${resolved}" ]] && command -v host >/dev/null 2>&1; then
    resolved="$(host "${host}" 2>/dev/null | awk '/has address/ {print $4; exit}')"
  fi
  if [[ -z "${resolved}" ]] && command -v nslookup >/dev/null 2>&1; then
    resolved="$(nslookup "${host}" 2>/dev/null | awk '/^Address: / && NR>2 {print $2; exit}')"
  fi
  if [[ -z "${resolved}" ]] && [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    resolved="${host}"
  fi
  if [[ -z "${resolved}" ]] && [[ "${host}" =~ : ]]; then
    resolved="${host}"
  fi

  if [[ -n "${resolved}" ]]; then
    echo "Resolved: ${resolved}"
    echo "Result  : OK"
    echo "================================"
    return 0
  fi

  echo "Resolved: (failed)"
  echo "Result  : FAILURE"
  echo "================================"
  return 1
}

# ---------- check-port ----------
cmd_check_port() {
  local host="${1:-}"
  local port="${2:-}"

  if [[ -z "${host}" ]]; then
    err "check-port requires a host argument"
    echo "Usage: ${APP_NAME} check-port <host> <port>" >&2
    return 2
  fi

  if [[ -z "${port}" ]]; then
    err "check-port requires a port argument"
    echo "Usage: ${APP_NAME} check-port <host> <port>" >&2
    return 2
  fi

  if [[ ! "${host}" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    err "invalid host: ${host}"
    return 2
  fi

  # Port must be numeric
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    err "port must be numeric: ${port}"
    return 2
  fi

  # Port range 1–65535 (leading zeros still numeric; strip for range check)
  local port_num=$((10#${port}))
  if (( port_num < 1 || port_num > 65535 )); then
    err "port out of range (1-65535): ${port}"
    return 2
  fi

  echo "========== Port Check =========="
  echo "Host: ${host}"
  echo "Port: ${port_num}"

  local ok=1

  # Prefer bash /dev/tcp when available (bash built-in)
  if (echo >/dev/tcp/"${host}"/"${port_num}") >/dev/null 2>&1; then
    ok=0
  elif command -v nc >/dev/null 2>&1; then
    if nc -z -w 3 "${host}" "${port_num}" >/dev/null 2>&1; then
      ok=0
    fi
  elif command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    if timeout 3 bash -c "echo >/dev/tcp/${host}/${port_num}" >/dev/null 2>&1; then
      ok=0
    fi
  fi

  if [[ "${ok}" -eq 0 ]]; then
    echo "TCP    : open / reachable"
    echo "Result : OK"
    echo "==============================="
    return 0
  fi

  echo "TCP    : closed / unreachable"
  echo "Result : FAILURE"
  echo "==============================="
  return 1
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
    system-info)
      cmd_system_info "$@"
      exit $?
      ;;
    check-host)
      cmd_check_host "$@"
      exit $?
      ;;
    check-port)
      cmd_check_port "$@"
      exit $?
      ;;
    help|-h|--help)
      usage
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
