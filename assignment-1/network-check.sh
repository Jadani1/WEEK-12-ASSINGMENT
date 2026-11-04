#!/usr/bin/env bash
# network-check.sh — Basic network diagnostics
# Usage: ./network-check.sh <hostname-or-ip> [port]
#   hostname-or-ip  Target host (required)
#   port            Optional TCP port (1–65535)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/network-check.log"

log_msg() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "${ts}" "$*" >> "${LOG_FILE}"
}

usage() {
  cat <<'EOF'
Usage: ./network-check.sh <hostname-or-ip> [port]

  hostname-or-ip  Hostname or IPv4/IPv6 address to check
  port            Optional TCP port (1–65535)

Exit codes:
  0  checks succeeded (connectivity OK; TCP OK if port given)
  1  connectivity and/or TCP check failed
  2  invalid input
EOF
}

# Returns 0 if string looks like IPv4
is_ipv4() {
  local ip="$1"
  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  # shellcheck disable=SC2086
  set -- ${ip}
  local o
  for o in "$1" "$2" "$3" "$4"; do
    [[ "${o}" =~ ^[0-9]+$ ]] || return 1
    (( o >= 0 && o <= 255 )) || return 1
  done
  return 0
}

is_ipv6() {
  local ip="$1"
  # Practical check: contains colon and only hex/colon/dot (for v4-mapped)
  [[ "${ip}" == *:* ]] || return 1
  [[ "${ip}" =~ ^[0-9A-Fa-f:.]+$ ]]
}

# Hostnames: letters, digits, dots, hyphens; labels 1–63; overall reasonable length
is_valid_hostname() {
  local h="$1"
  local len=${#h}
  (( len >= 1 && len <= 253 )) || return 1
  # Disallow spaces and shell-dangerous junk early
  [[ "${h}" =~ [[:space:]] ]] && return 1
  [[ "${h}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "${h}" == -* || "${h}" == *- || "${h}" == .* || "${h}" == *. ]] && return 1
  # No empty labels
  [[ "${h}" == *..* ]] && return 1
  return 0
}

validate_host() {
  local h="$1"
  if is_ipv4 "${h}" || is_ipv6 "${h}" || is_valid_hostname "${h}"; then
    return 0
  fi
  return 1
}

resolve_host() {
  local target="$1"

  # Already an IP — do not query DNS (Windows nslookup returns the DNS server IP!)
  if is_ipv4 "${target}" || is_ipv6 "${target}"; then
    echo "${target}"
    return 0
  fi

  local resolved=""

  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "${target}" 2>/dev/null | awk 'NR==1 {print $1; exit}')"
  fi

  if [[ -z "${resolved}" ]] && command -v dig >/dev/null 2>&1; then
    resolved="$(dig +short "${target}" A 2>/dev/null | awk 'NF && $0 !~ /^;/ {print; exit}')"
    if [[ -z "${resolved}" ]]; then
      resolved="$(dig +short "${target}" AAAA 2>/dev/null | awk 'NF && $0 !~ /^;/ {print; exit}')"
    fi
  fi

  if [[ -z "${resolved}" ]] && command -v host >/dev/null 2>&1; then
    resolved="$(host -t A "${target}" 2>/dev/null | awk '/has address/ {print $NF; exit}')"
    if [[ -z "${resolved}" ]]; then
      resolved="$(host -t AAAA "${target}" 2>/dev/null | awk '/has IPv6 address/ {print $NF; exit}')"
    fi
  fi

  if [[ -z "${resolved}" ]] && command -v nslookup >/dev/null 2>&1; then
    # Skip the DNS server "Address:" lines; prefer answers after "Name:"
    resolved="$(
      nslookup "${target}" 2>/dev/null | awk '
        BEGIN { in_ans=0 }
        /^Name:/ { in_ans=1; next }
        in_ans && /^Address: / {
          addr=$2
          # strip trailing junk
          gsub(/\r/,"",addr)
          if (addr != "" && addr != "127.0.0.1") { print addr; exit }
          if (addr != "") { print addr; exit }
        }
        in_ans && /^Addresses: / {
          addr=$2
          gsub(/\r/,"",addr)
          if (addr != "") { print addr; exit }
        }
      '
    )"
  fi

  if [[ -z "${resolved}" ]] && command -v ping >/dev/null 2>&1; then
    # Linux/mac style
    resolved="$(ping -c 1 -W 2 "${target}" 2>/dev/null | head -n1 | grep -oE '\(([0-9.]+)\)' | tr -d '()' | head -n1)"
    if [[ -z "${resolved}" ]]; then
      # Windows ping: "Pinging host [1.2.3.4] with ..."
      resolved="$(ping -n 1 -w 2000 "${target}" 2>/dev/null | head -n2 | grep -oE '\[[0-9.]+\]' | tr -d '[]' | head -n1)"
    fi
  fi

  if [[ -n "${resolved}" ]]; then
    echo "${resolved}"
  else
    # Fall back to the original target so later checks can still run
    echo "${target}"
  fi
}

show_interfaces() {
  echo "--- Network interfaces ---"
  if command -v ip >/dev/null 2>&1; then
    ip -br addr 2>/dev/null || ip addr 2>/dev/null
    return
  fi
  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig -a 2>/dev/null
    return
  fi
  if command -v ipconfig >/dev/null 2>&1; then
    # Windows
    ipconfig 2>/dev/null
    return
  fi
  echo "(No ip/ifconfig/ipconfig available on this system.)"
}

ping_check() {
  local target="$1"
  # Prefer Linux/mac ping; fall back to Windows ping
  if ping -c 1 -W 3 "${target}" >/dev/null 2>&1; then
    return 0
  fi
  if ping -n 1 -w 3000 "${target}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

tcp_check() {
  local target="$1"
  local port="$2"

  # bash /dev/tcp (works on bash with network support)
  if (echo >/dev/tcp/"${target}/${port}") >/dev/null 2>&1; then
    return 0
  fi

  # timeout + bash fallback already failed; try nc
  if command -v nc >/dev/null 2>&1; then
    if nc -z -w 3 "${target}" "${port}" >/dev/null 2>&1; then
      return 0
    fi
    # Windows nmap ncat sometimes uses different flags
    if nc -z "${target}" "${port}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    if timeout 3 bash -c "echo >/dev/tcp/${target}/${port}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # PowerShell fallback on Windows
  if command -v powershell.exe >/dev/null 2>&1; then
    if powershell.exe -NoProfile -Command \
      "try { \$c = New-Object Net.Sockets.TcpClient; \$c.ReceiveTimeout=3000; \$c.SendTimeout=3000; \$iar=\$c.BeginConnect('${target}',${port},\$null,\$null); if (-not \$iar.AsyncWaitHandle.WaitOne(3000,\$false)) { \$c.Close(); exit 1 }; \$c.EndConnect(\$iar); \$c.Close(); exit 0 } catch { exit 1 }" \
      >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

# -------------------- main --------------------
log_msg "Starting network-check.sh args=$*"

if [[ $# -lt 1 ]]; then
  echo "Error: hostname-or-ip is required." >&2
  usage >&2
  log_msg "ERROR: missing host argument"
  exit 2
fi

HOST_ARG="$1"
PORT_ARG="${2:-}"

if ! validate_host "${HOST_ARG}"; then
  echo "Error: invalid hostname or IP: '${HOST_ARG}'" >&2
  log_msg "ERROR: invalid host '${HOST_ARG}'"
  exit 2
fi

if [[ -n "${PORT_ARG}" ]]; then
  if ! [[ "${PORT_ARG}" =~ ^[0-9]+$ ]]; then
    echo "Error: port must be an integer 1–65535 (got: ${PORT_ARG})" >&2
    log_msg "ERROR: invalid port '${PORT_ARG}'"
    exit 2
  fi
  if (( PORT_ARG < 1 || PORT_ARG > 65535 )); then
    echo "Error: port must be an integer 1–65535 (got: ${PORT_ARG})" >&2
    log_msg "ERROR: port out of range '${PORT_ARG}'"
    exit 2
  fi
fi

echo "========================================"
echo "         NETWORK CHECK"
echo "========================================"
echo "Target:             ${HOST_ARG}"
[[ -n "${PORT_ARG}" ]] && echo "Port:               ${PORT_ARG}"

RESOLVED="$(resolve_host "${HOST_ARG}")"
echo "Resolved address:   ${RESOLVED}"
log_msg "Resolved ${HOST_ARG} -> ${RESOLVED}"

# Connectivity (ICMP ping). Some hosts block ICMP; still report status.
echo
echo "--- Connectivity check (ping) ---"
PING_OK=0
if ping_check "${HOST_ARG}"; then
  echo "Ping:               OK (${HOST_ARG})"
  log_msg "Ping OK host=${HOST_ARG}"
  PING_OK=1
elif [[ "${RESOLVED}" != "${HOST_ARG}" ]] && ping_check "${RESOLVED}"; then
  echo "Ping:               OK (${RESOLVED})"
  log_msg "Ping OK host=${RESOLVED}"
  PING_OK=1
else
  echo "Ping:               FAILED (host unreachable or ICMP blocked)"
  log_msg "Ping FAILED host=${HOST_ARG} resolved=${RESOLVED}"
fi

echo
show_interfaces

OVERALL_STATUS=0
if (( PING_OK == 0 )); then
  OVERALL_STATUS=1
fi

if [[ -n "${PORT_ARG}" ]]; then
  echo
  echo "--- TCP connectivity check ---"
  TCP_TARGET="${RESOLVED}"
  # Prefer original host for name-based SNI-less TCP; IP is fine too
  if is_ipv4 "${HOST_ARG}" || is_ipv6 "${HOST_ARG}"; then
    TCP_TARGET="${HOST_ARG}"
  fi
  if tcp_check "${TCP_TARGET}" "${PORT_ARG}"; then
    echo "TCP ${TCP_TARGET}:${PORT_ARG}:  OPEN / reachable"
    log_msg "TCP OK ${TCP_TARGET}:${PORT_ARG}"
  else
    # One more try with the other form
    if [[ "${TCP_TARGET}" != "${HOST_ARG}" ]] && tcp_check "${HOST_ARG}" "${PORT_ARG}"; then
      echo "TCP ${HOST_ARG}:${PORT_ARG}:  OPEN / reachable"
      log_msg "TCP OK ${HOST_ARG}:${PORT_ARG}"
    else
      echo "TCP ${TCP_TARGET}:${PORT_ARG}:  CLOSED / unreachable"
      log_msg "TCP FAIL ${TCP_TARGET}:${PORT_ARG}"
      OVERALL_STATUS=1
    fi
  fi
fi

echo "========================================"
if (( OVERALL_STATUS == 0 )); then
  echo "Overall:            SUCCESS"
  log_msg "network-check.sh completed SUCCESS host=${HOST_ARG} port=${PORT_ARG:-none}"
else
  echo "Overall:            FAILURE (see details above)"
  log_msg "network-check.sh completed FAILURE host=${HOST_ARG} port=${PORT_ARG:-none}"
fi
echo "========================================"

exit "${OVERALL_STATUS}"
