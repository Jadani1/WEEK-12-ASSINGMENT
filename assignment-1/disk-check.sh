#!/usr/bin/env bash
# disk-check.sh — Check disk usage against a threshold
# Usage: ./disk-check.sh <threshold> [path]
#   threshold: integer 1–100 (percent)
#   path:      filesystem path to check (default: /)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/disk-check.log"

log_msg() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "${ts}" "$*" >> "${LOG_FILE}"
}

usage() {
  cat <<'EOF'
Usage: ./disk-check.sh <threshold> [path]

  threshold  Integer from 1 to 100 (maximum allowed usage percent)
  path       Filesystem path to check (default: /)

Exit codes:
  0  usage is below the threshold
  1  usage reaches or exceeds the threshold
  2  invalid input
EOF
}

log_msg "Starting disk-check.sh args=$*"

# --- argument validation ---
if [[ $# -lt 1 ]]; then
  echo "Error: threshold is required." >&2
  usage >&2
  log_msg "ERROR: missing threshold argument"
  exit 2
fi

THRESHOLD="$1"
PATH_TO_CHECK="${2:-/}"

# Threshold must be integer 1–100
if ! [[ "${THRESHOLD}" =~ ^[0-9]+$ ]]; then
  echo "Error: threshold must be an integer between 1 and 100 (got: ${THRESHOLD})" >&2
  log_msg "ERROR: invalid threshold '${THRESHOLD}' (not an integer)"
  exit 2
fi

# Reject leading-zero oddities like 08 while still allowing 1–100
if [[ "${THRESHOLD}" -lt 1 || "${THRESHOLD}" -gt 100 ]]; then
  echo "Error: threshold must be an integer between 1 and 100 (got: ${THRESHOLD})" >&2
  log_msg "ERROR: threshold out of range '${THRESHOLD}'"
  exit 2
fi

if [[ ! -e "${PATH_TO_CHECK}" ]]; then
  echo "Error: path does not exist: ${PATH_TO_CHECK}" >&2
  log_msg "ERROR: path does not exist '${PATH_TO_CHECK}'"
  exit 2
fi

# --- collect usage ---
# df -P: POSIX format (stable columns). Prefer -k for 1K blocks when available.
DF_OUT=""
if DF_OUT="$(df -Pk "${PATH_TO_CHECK}" 2>/dev/null)"; then
  :
elif DF_OUT="$(df -P "${PATH_TO_CHECK}" 2>/dev/null)"; then
  :
else
  echo "Error: unable to read disk usage for: ${PATH_TO_CHECK}" >&2
  log_msg "ERROR: df failed for '${PATH_TO_CHECK}'"
  exit 2
fi

# Capacity column often looks like "88%"; strip non-digits.
USAGE_PCT="$(printf '%s\n' "${DF_OUT}" | awk 'NR==2 { gsub(/%/,"",$5); print $5 }')"
FS_LINE="$(printf '%s\n' "${DF_OUT}" | awk 'NR==2 {print}')"
MOUNTED_ON="$(printf '%s\n' "${DF_OUT}" | awk 'NR==2 {print $6}')"
FILESYSTEM="$(printf '%s\n' "${DF_OUT}" | awk 'NR==2 {print $1}')"

if ! [[ "${USAGE_PCT}" =~ ^[0-9]+$ ]]; then
  echo "Error: could not parse disk usage percentage from df output." >&2
  echo "df output was:" >&2
  echo "${DF_OUT}" >&2
  log_msg "ERROR: failed to parse usage from df for '${PATH_TO_CHECK}'"
  exit 2
fi

echo "========================================"
echo "           DISK USAGE CHECK"
echo "========================================"
echo "Path checked:     ${PATH_TO_CHECK}"
echo "Filesystem:       ${FILESYSTEM}"
echo "Mounted on:       ${MOUNTED_ON}"
echo "Usage:            ${USAGE_PCT}%"
echo "Threshold:        ${THRESHOLD}%"
echo "df summary:       ${FS_LINE}"
echo "========================================"

if (( USAGE_PCT >= THRESHOLD )); then
  echo "Result: FAIL — usage (${USAGE_PCT}%) is at or above threshold (${THRESHOLD}%)."
  log_msg "FAIL usage=${USAGE_PCT}% threshold=${THRESHOLD}% path=${PATH_TO_CHECK}"
  exit 1
else
  echo "Result: OK — usage (${USAGE_PCT}%) is below threshold (${THRESHOLD}%)."
  log_msg "OK usage=${USAGE_PCT}% threshold=${THRESHOLD}% path=${PATH_TO_CHECK}"
  exit 0
fi
