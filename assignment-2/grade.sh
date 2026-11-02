#!/usr/bin/env bash
# grade.sh — Automated grading checks for Assignment 2 (Dockerized Diagnostic CLI)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

PASS=0
FAIL=0
IMAGE="${IMAGE:-diagnostic-tool}"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { red "  FAIL  $*"; FAIL=$((FAIL + 1)); }

check_file() {
  local f="$1"
  if [[ -f "${f}" ]]; then
    pass "exists: ${f}"
  else
    fail "missing: ${f}"
  fi
}

bold "=== Assignment 2 — Structure ==="

check_file "README.md"
check_file "Dockerfile"
check_file "compose.yaml"
check_file ".dockerignore"
check_file "test.sh"
check_file "grade.sh"
check_file "app/diagnostic.sh"
check_file "app/health-check.sh"
echo

bold "=== Scripts are non-empty / shebang ==="
for f in app/diagnostic.sh app/health-check.sh test.sh grade.sh; do
  if [[ -s "${f}" ]] && head -n1 "${f}" | grep -q '^#!'; then
    pass "shebang + content: ${f}"
  else
    fail "bad script: ${f}"
  fi
done
echo

bold "=== Dockerfile requirements ==="
if [[ -f Dockerfile ]]; then
  grep -qiE '^FROM[[:space:]]+' Dockerfile \
    && pass "Dockerfile has FROM" || fail "Dockerfile missing FROM"

  grep -qiE 'alpine|debian|ubuntu|slim' Dockerfile \
    && pass "Dockerfile uses lightweight/common base" || fail "unexpected base image"

  grep -qiE 'COPY|ADD' Dockerfile \
    && pass "Dockerfile copies application" || fail "Dockerfile does not COPY/ADD app"

  grep -qiE 'chmod|\+x|executable' Dockerfile \
    && pass "Dockerfile sets executable permissions" || fail "Dockerfile may not set +x"

  grep -qiE '^ENTRYPOINT|^CMD' Dockerfile \
    && pass "Dockerfile sets ENTRYPOINT and/or CMD" || fail "Dockerfile missing ENTRYPOINT/CMD"
else
  fail "No Dockerfile to inspect"
fi
echo

bold "=== .dockerignore ==="
if [[ -f .dockerignore ]]; then
  grep -q '\.git' .dockerignore && pass ".dockerignore excludes .git" || fail ".dockerignore missing .git"
  grep -qiE 'log|\.tmp|tmp' .dockerignore && pass ".dockerignore excludes logs/temp" || fail ".dockerignore missing logs/temp"
else
  fail "missing .dockerignore"
fi
echo

bold "=== compose.yaml ==="
if [[ -f compose.yaml ]]; then
  grep -qiE 'services:' compose.yaml && pass "compose has services" || fail "compose missing services"
  grep -qiE 'build:|image:' compose.yaml && pass "compose builds or references image" || fail "compose missing build/image"
  grep -qiE 'diagnostic' compose.yaml && pass "compose defines diagnostic service" || fail "compose missing diagnostic service"
else
  fail "missing compose.yaml"
fi
echo

bold "=== CLI command surface (source) ==="
if [[ -f app/diagnostic.sh ]]; then
  for cmd in system network disk help; do
    grep -q "${cmd}" app/diagnostic.sh \
      && pass "diagnostic.sh references '${cmd}'" \
      || fail "diagnostic.sh missing '${cmd}'"
  done
  # Exit code 2 for invalid input
  grep -qE 'exit 2|return 2' app/diagnostic.sh \
    && pass "diagnostic.sh uses exit/return 2 for invalid input" \
    || fail "diagnostic.sh may not use exit code 2"
else
  fail "no diagnostic.sh"
fi
echo

# Docker-based checks only if docker is available
if command -v docker >/dev/null 2>&1; then
  bold "=== Docker build & run ==="
  if docker build -t "${IMAGE}" . >/tmp/assignment2-grade-build.log 2>&1; then
    pass "docker build -t ${IMAGE} ."

    # help
    out="$(docker run --rm "${IMAGE}" help 2>&1)" || rc=$?
    rc="${rc:-0}"
    [[ "${rc}" -eq 0 ]] && pass "run help → exit 0" || fail "run help → exit ${rc}"
    grep -qi 'usage\|help\|system' <<<"${out}" && pass "help output useful" || fail "help output empty/odd"

    # system
    rc=0
    out="$(docker run --rm "${IMAGE}" system 2>&1)" || rc=$?
    [[ "${rc}" -eq 0 ]] && pass "run system → exit 0" || fail "run system → exit ${rc}"

    # disk
    rc=0
    out="$(docker run --rm "${IMAGE}" disk 2>&1)" || rc=$?
    [[ "${rc}" -eq 0 ]] && pass "run disk → exit 0" || fail "run disk → exit ${rc}"

    # invalid
    rc=0
    out="$(docker run --rm "${IMAGE}" totally-invalid 2>&1)" || rc=$?
    [[ "${rc}" -eq 2 ]] && pass "invalid command → exit 2" || fail "invalid command → exit ${rc} (want 2)"

    # compose (if plugin available)
    if docker compose version >/dev/null 2>&1; then
      rc=0
      out="$(docker compose run --rm diagnostic help 2>&1)" || rc=$?
      [[ "${rc}" -eq 0 ]] && pass "compose run diagnostic help → 0" || fail "compose run failed (exit ${rc})"
    else
      echo "  (skip compose run — docker compose not available)"
    fi
  else
    fail "docker build failed"
    tail -n 20 /tmp/assignment2-grade-build.log 2>/dev/null || true
  fi
  rm -f /tmp/assignment2-grade-build.log 2>/dev/null || true
else
  echo "  (skip docker run checks — docker not in PATH)"
fi
echo

bold "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  red "Some checks failed."
  exit 1
fi
green "All grading checks passed."
exit 0
