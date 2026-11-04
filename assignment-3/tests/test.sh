#!/usr/bin/env bash
# tests/test.sh — Application tests for devops-tool (Assignment 3)
# At least 8 meaningful tests:
#   help, system-info, invalid command, missing host,
#   valid host, missing port, non-numeric port, port range, missing args
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}" || exit 1

APP="app/app.sh"
PASS=0
FAIL=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

assert_exit() {
  local label="$1"
  local want="$2"
  local got="$3"
  if [[ "${got}" -eq "${want}" ]]; then
    green "  PASS  ${label} (exit ${got})"
    PASS=$((PASS + 1))
  else
    red "  FAIL  ${label} (exit ${got}, want ${want})"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if grep -qiE "${needle}" <<<"${haystack}"; then
    green "  PASS  ${label}"
    PASS=$((PASS + 1))
  else
    red "  FAIL  ${label} (missing: ${needle})"
    FAIL=$((FAIL + 1))
  fi
}

if [[ ! -x "${APP}" && -f "${APP}" ]]; then
  chmod +x "${APP}" 2>/dev/null || true
fi

if [[ ! -f "${APP}" ]]; then
  red "Missing application: ${APP}"
  exit 1
fi

bold "=== devops-tool unit/smoke tests ==="
echo

# 1) help
bold "[1] help"
rc=0
out="$("${APP}" help 2>&1)" || rc=$?
assert_exit "help exits 0" 0 "${rc}"
assert_contains "help shows usage" "usage" "${out}"
assert_contains "help lists system-info" "system-info" "${out}"
echo

# 2) system-info
bold "[2] system-info"
rc=0
out="$("${APP}" system-info 2>&1)" || rc=$?
assert_exit "system-info exits 0" 0 "${rc}"
assert_contains "system-info has hostname" "hostname" "${out}"
echo

# 3) invalid command
bold "[3] invalid command"
rc=0
out="$("${APP}" not-a-real-command 2>&1)" || rc=$?
assert_exit "invalid command exits 2" 2 "${rc}"
assert_contains "invalid command message" "unknown" "${out}"
echo

# 4) check-host missing host
bold "[4] check-host missing host"
rc=0
out="$("${APP}" check-host 2>&1)" || rc=$?
assert_exit "check-host without host exits 2" 2 "${rc}"
echo

# 5) check-host valid host (localhost / 127.0.0.1)
bold "[5] check-host valid host"
rc=0
out="$("${APP}" check-host 127.0.0.1 2>&1)" || rc=$?
assert_exit "check-host 127.0.0.1 exits 0" 0 "${rc}"
assert_contains "check-host shows OK or Resolved" "ok|resolved" "${out}"
echo

# 6) check-port missing port
bold "[6] check-port missing port"
rc=0
out="$("${APP}" check-port 127.0.0.1 2>&1)" || rc=$?
assert_exit "check-port without port exits 2" 2 "${rc}"
echo

# 7) check-port non-numeric port
bold "[7] check-port non-numeric port"
rc=0
out="$("${APP}" check-port 127.0.0.1 abc 2>&1)" || rc=$?
assert_exit "check-port non-numeric exits 2" 2 "${rc}"
echo

# 8) check-port out of range
bold "[8] check-port out of range"
rc=0
out="$("${APP}" check-port 127.0.0.1 0 2>&1)" || rc=$?
assert_exit "check-port 0 exits 2" 2 "${rc}"
echo

# 9) check-port missing host entirely
bold "[9] check-port missing host"
rc=0
out="$("${APP}" check-port 2>&1)" || rc=$?
assert_exit "check-port without args exits 2" 2 "${rc}"
echo

# 10) empty / missing top-level command
bold "[10] missing command"
rc=0
out="$("${APP}" 2>&1)" || rc=$?
assert_exit "no command exits 2" 2 "${rc}"
echo

bold "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  red "Some tests failed."
  exit 1
fi
green "All tests passed."
exit 0
