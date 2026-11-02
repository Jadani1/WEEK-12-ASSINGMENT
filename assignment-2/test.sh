#!/usr/bin/env bash
# test.sh — Smoke tests for the diagnostic-tool Docker image
# Covers: help, system, disk, and invalid command handling.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

IMAGE="${IMAGE:-diagnostic-tool}"
PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${actual}" -eq "${expected}" ]]; then
    green "  PASS  ${name} (exit ${actual})"
    PASS=$((PASS + 1))
  else
    red "  FAIL  ${name} (expected exit ${expected}, got ${actual})"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if grep -Fq -- "${needle}" <<<"${haystack}"; then
    green "  PASS  ${name}"
    PASS=$((PASS + 1))
  else
    red "  FAIL  ${name} (missing: ${needle})"
    FAIL=$((FAIL + 1))
  fi
}

bold "=== diagnostic-tool tests ==="
echo "Image: ${IMAGE}"
echo

# --- Build ---
bold "[1] Build image"
if docker build -t "${IMAGE}" . >/tmp/diagnostic-test-build.log 2>&1; then
  green "  PASS  docker build"
  PASS=$((PASS + 1))
else
  red "  FAIL  docker build"
  tail -n 40 /tmp/diagnostic-test-build.log 2>/dev/null || true
  FAIL=$((FAIL + 1))
  bold "Cannot continue without an image."
  echo "Passed: ${PASS}  Failed: ${FAIL}"
  exit 1
fi
echo

# --- help ---
bold "[2] help command"
HELP_OUT="$(docker run --rm "${IMAGE}" help 2>&1)" || HELP_RC=$?
HELP_RC="${HELP_RC:-0}"
assert_exit "help exits 0" 0 "${HELP_RC}"
assert_contains "help shows Usage" "Usage:" "${HELP_OUT}"
assert_contains "help lists system" "system" "${HELP_OUT}"
assert_contains "help lists network" "network" "${HELP_OUT}"
assert_contains "help lists disk" "disk" "${HELP_OUT}"
echo

# --- system ---
bold "[3] system command"
SYS_OUT="$(docker run --rm "${IMAGE}" system 2>&1)" || SYS_RC=$?
SYS_RC="${SYS_RC:-0}"
assert_exit "system exits 0" 0 "${SYS_RC}"
assert_contains "system shows hostname" "Hostname" "${SYS_OUT}"
assert_contains "system shows kernel or OS" "Kernel" "${SYS_OUT}"
echo

# --- disk ---
bold "[4] disk command"
DISK_OUT="$(docker run --rm "${IMAGE}" disk 2>&1)" || DISK_RC=$?
DISK_RC="${DISK_RC:-0}"
assert_exit "disk exits 0" 0 "${DISK_RC}"
assert_contains "disk shows header" "Disk" "${DISK_OUT}"
echo

# --- invalid command ---
bold "[5] invalid command handling"
INV_OUT="$(docker run --rm "${IMAGE}" not-a-real-command 2>&1)" || INV_RC=$?
INV_RC="${INV_RC:-0}"
assert_exit "invalid command exits 2" 2 "${INV_RC}"
assert_contains "invalid command mentions unknown/error" "unknown" "${INV_OUT}"
echo

# --- missing network host ---
bold "[6] network without host (invalid input)"
NET_OUT="$(docker run --rm "${IMAGE}" network 2>&1)" || NET_RC=$?
NET_RC="${NET_RC:-0}"
assert_exit "network without host exits 2" 2 "${NET_RC}"
echo

# --- default CMD (no args → help via CMD, but missing handled) ---
# ENTRYPOINT + CMD ["help"] means bare run should show help with 0
bold "[7] default container command (help)"
DEF_OUT="$(docker run --rm "${IMAGE}" 2>&1)" || DEF_RC=$?
DEF_RC="${DEF_RC:-0}"
assert_exit "default run exits 0" 0 "${DEF_RC}"
assert_contains "default run shows Usage" "Usage:" "${DEF_OUT}"
echo

# --- Summary ---
bold "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
rm -f /tmp/diagnostic-test-build.log 2>/dev/null || true

if [[ "${FAIL}" -gt 0 ]]; then
  red "Some tests failed."
  exit 1
fi
green "All tests passed."
exit 0
