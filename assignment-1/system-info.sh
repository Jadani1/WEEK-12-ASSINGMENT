#!/usr/bin/env bash
# system-info.sh — Collect and display basic system information at runtime
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/system-info.log"

log_msg() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "${ts}" "$*" >> "${LOG_FILE}"
}

# Human-readable bytes (1024-based)
human_bytes() {
  local bytes="${1:-0}"
  # strip non-digits
  bytes="$(printf '%s' "${bytes}" | tr -cd '0-9')"
  [[ -z "${bytes}" ]] && bytes=0
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "${bytes}" 2>/dev/null && return
  fi
  awk -v b="${bytes}" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s\n", b, u[i]
    else printf "%.1f %s\n", b, u[i]
  }'
}

kb_to_bytes() {
  local kb="${1:-0}"
  kb="$(printf '%s' "${kb}" | tr -cd '0-9')"
  [[ -z "${kb}" ]] && kb=0
  echo $((kb * 1024))
}

get_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${PRETTY_NAME:-${NAME:-Unknown OS}}"
  elif command -v sw_vers >/dev/null 2>&1; then
    sw_vers -productName 2>/dev/null
  else
    uname -s
  fi
}

get_cpu() {
  if [[ -r /proc/cpuinfo ]]; then
    local model cores
    model="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '?')"
    if [[ -n "${model}" ]]; then
      echo "${model} (${cores} logical CPU(s))"
      return
    fi
  fi
  if command -v sysctl >/dev/null 2>&1; then
    local brand
    brand="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    [[ -n "${brand}" ]] && { echo "${brand}"; return; }
  fi
  if command -v wmic >/dev/null 2>&1; then
    local w
    w="$(wmic cpu get name 2>/dev/null | sed -n '2p' | sed 's/[[:space:]]*$//')"
    [[ -n "${w}" ]] && { echo "${w}"; return; }
  fi
  uname -m
}

get_memory() {
  local total_b="" avail_b="" used_b=""

  if command -v free >/dev/null 2>&1; then
    # Prefer bytes for accuracy
    local line
    line="$(free -b 2>/dev/null | awk '/^Mem:/ {print $2, $3, $7}')"
    if [[ -n "${line}" ]]; then
      total_b="$(echo "${line}" | awk '{print $1}')"
      used_b="$(echo "${line}" | awk '{print $2}')"
      avail_b="$(echo "${line}" | awk '{print $3}')"
    fi
  fi

  if [[ -z "${total_b}" && -r /proc/meminfo ]]; then
    local total_kb free_kb avail_kb buffers_kb cached_kb
    total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    free_kb="$(awk '/^MemFree:/ {print $2}' /proc/meminfo)"
    avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
    buffers_kb="$(awk '/^Buffers:/ {print $2}' /proc/meminfo)"
    cached_kb="$(awk '/^Cached:/ {print $2}' /proc/meminfo)"
    total_b="$(kb_to_bytes "${total_kb}")"
    if [[ -n "${avail_kb}" ]]; then
      avail_b="$(kb_to_bytes "${avail_kb}")"
    else
      # Approximate available when MemAvailable is missing (e.g. some MSYS builds)
      avail_b="$(kb_to_bytes $(( ${free_kb:-0} + ${buffers_kb:-0} + ${cached_kb:-0} )))"
    fi
    used_b=$(( total_b - avail_b ))
    [[ ${used_b} -lt 0 ]] && used_b=0
  fi

  if [[ -z "${total_b}" ]] && command -v wmic >/dev/null 2>&1; then
    local tot free
    tot="$(wmic OS get TotalVisibleMemorySize /value 2>/dev/null | tr -d '\r' | awk -F= '/TotalVisibleMemorySize/ {print $2}')"
    free="$(wmic OS get FreePhysicalMemory /value 2>/dev/null | tr -d '\r' | awk -F= '/FreePhysicalMemory/ {print $2}')"
    if [[ -n "${tot}" ]]; then
      total_b="$(kb_to_bytes "${tot}")"
      avail_b="$(kb_to_bytes "${free:-0}")"
      used_b=$(( total_b - avail_b ))
    fi
  fi

  if [[ -z "${total_b}" ]]; then
    echo "Total: unknown | Used: unknown | Available: unknown"
    return
  fi

  echo "Total: $(human_bytes "${total_b}") | Used: $(human_bytes "${used_b:-0}") | Available: $(human_bytes "${avail_b:-0}")"
}

get_uptime() {
  if command -v uptime >/dev/null 2>&1; then
    # Prefer pretty form when available
    local pretty
    pretty="$(uptime -p 2>/dev/null || true)"
    if [[ -n "${pretty}" ]]; then
      echo "${pretty}"
      return
    fi
    uptime 2>/dev/null | sed 's/^ *//'
    return
  fi
  if [[ -r /proc/uptime ]]; then
    awk '{
      s=int($1)
      d=int(s/86400); s%=86400
      h=int(s/3600); s%=3600
      m=int(s/60)
      printf "up "
      if (d>0) printf "%d day%s, ", d, (d==1?"":"s")
      printf "%d hour%s, %d minute%s\n", h, (h==1?"":"s"), m, (m==1?"":"s")
    }' /proc/uptime
    return
  fi
  echo "unknown"
}

log_msg "Starting system-info.sh"

HOSTNAME_VAL="$(hostname 2>/dev/null || uname -n)"
CURRENT_USER="$(whoami 2>/dev/null || id -un 2>/dev/null || echo unknown)"
DATE_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
OS_VAL="$(get_os)"
KERNEL_VAL="$(uname -r)"
UPTIME_VAL="$(get_uptime)"
CPU_VAL="$(get_cpu)"
MEM_VAL="$(get_memory)"
CWD_VAL="$(pwd)"

echo "========================================"
echo "         SYSTEM INFORMATION"
echo "========================================"
echo "Hostname:           ${HOSTNAME_VAL}"
echo "Current User:       ${CURRENT_USER}"
echo "Date/Time:          ${DATE_TIME}"
echo "Operating System:   ${OS_VAL}"
echo "Kernel Version:     ${KERNEL_VAL}"
echo "Uptime:             ${UPTIME_VAL}"
echo "CPU:                ${CPU_VAL}"
echo "Memory:             ${MEM_VAL}"
echo "Working Directory:  ${CWD_VAL}"
echo "========================================"

log_msg "Collected system info host=${HOSTNAME_VAL} user=${CURRENT_USER} os=${OS_VAL} kernel=${KERNEL_VAL}"
log_msg "system-info.sh completed successfully"
exit 0
