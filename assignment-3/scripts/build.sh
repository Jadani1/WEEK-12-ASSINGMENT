#!/usr/bin/env bash
# build.sh — Build the devops-tool image and run Docker smoke tests
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}" || exit 1

IMAGE="${IMAGE:-devops-tool:a3}"
PASS=0
FAIL=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
pass() { green "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { red "  FAIL  $*"; FAIL=$((FAIL + 1)); }

if ! command -v docker >/dev/null 2>&1; then
  red "docker is not installed or not on PATH"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  red "docker daemon is not running (start Docker Desktop / dockerd)"
  exit 1
fi

bold "=== docker build ==="
if docker build -t "${IMAGE}" .; then
  pass "docker build ${IMAGE}"
else
  fail "docker build failed"
  echo "Passed: ${PASS}  Failed: ${FAIL}"
  exit 1
fi

echo
bold "=== docker smoke tests ==="

# help
rc=0
out="$(docker run --rm "${IMAGE}" help 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] && grep -qiE 'usage|system-info|check-host' <<<"${out}"; then
  pass "docker run help (exit 0)"
else
  fail "docker run help (exit ${rc})"
fi

# system-info
rc=0
out="$(docker run --rm "${IMAGE}" system-info 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]] && grep -qiE 'hostname|kernel|system' <<<"${out}"; then
  pass "docker run system-info (exit 0)"
else
  fail "docker run system-info (exit ${rc})"
fi

# check-host
rc=0
out="$(docker run --rm "${IMAGE}" check-host 127.0.0.1 2>&1)" || rc=$?
if [[ "${rc}" -eq 0 ]]; then
  pass "docker run check-host 127.0.0.1 (exit 0)"
else
  fail "docker run check-host (exit ${rc})"
fi

# invalid command → exit 2
rc=0
out="$(docker run --rm "${IMAGE}" not-a-real-command 2>&1)" || rc=$?
if [[ "${rc}" -eq 2 ]]; then
  pass "docker run invalid command (exit 2)"
else
  fail "docker run invalid command (exit ${rc}, want 2)"
fi

# missing args → exit 2
rc=0
out="$(docker run --rm "${IMAGE}" check-port 2>&1)" || rc=$?
if [[ "${rc}" -eq 2 ]]; then
  pass "docker run check-port missing args (exit 2)"
else
  fail "docker run check-port missing args (exit ${rc}, want 2)"
fi

echo
bold "=== build summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  red "Docker build/smoke tests failed."
  exit 1
fi
green "Docker build/smoke tests passed."
exit 0
