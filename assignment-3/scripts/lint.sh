#!/usr/bin/env bash
# lint.sh — Validate required files and Bash syntax (bash -n)
# Optional: ShellCheck when available (warn-only; does not fail the job)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}" || exit 1

PASS=0
FAIL=0
WARN=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
pass() { green "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { red "  FAIL  $*"; FAIL=$((FAIL + 1)); }
warn() { yellow "  WARN  $*"; WARN=$((WARN + 1)); }

bold "=== lint: required files ==="

REQUIRED=(
  "README.md"
  "app/app.sh"
  "scripts/lint.sh"
  "scripts/build.sh"
  "tests/test.sh"
  "Dockerfile"
  "compose.yaml"
  ".dockerignore"
  "grade.sh"
  ".github/workflows/ci.yml"
)

for f in "${REQUIRED[@]}"; do
  if [[ -f "${f}" ]]; then
    pass "found ${f}"
  else
    fail "missing ${f}"
  fi
done

echo
bold "=== lint: bash -n (syntax) ==="

SCRIPTS=(
  "app/app.sh"
  "scripts/lint.sh"
  "scripts/build.sh"
  "tests/test.sh"
  "grade.sh"
)

for s in "${SCRIPTS[@]}"; do
  if [[ ! -f "${s}" ]]; then
    fail "skip bash -n (missing): ${s}"
    continue
  fi
  # Strip CR so Windows-checked-out files still pass on Linux runners
  if tr -d '\r' <"${s}" | bash -n 2>/tmp/lint-bash-n.err; then
    pass "bash -n ${s}"
  else
    fail "bash -n ${s}"
    cat /tmp/lint-bash-n.err >&2 || true
  fi
done
rm -f /tmp/lint-bash-n.err 2>/dev/null || true

echo
bold "=== lint: optional ShellCheck ==="

if command -v shellcheck >/dev/null 2>&1; then
  for s in app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh grade.sh; do
    [[ -f "${s}" ]] || continue
    # Optional tool: report findings as warnings only (do not fail CI)
    if shellcheck -x -e SC1091,SC2034,SC2086,SC2002 "${s}" >/tmp/lint-sc.out 2>&1; then
      pass "shellcheck ${s}"
    else
      warn "shellcheck ${s} (optional — not failing CI)"
      cat /tmp/lint-sc.out >&2 || true
    fi
  done
  rm -f /tmp/lint-sc.out 2>/dev/null || true
else
  echo "  (shellcheck not installed — skipped)"
fi

echo
bold "=== lint summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo "Warnings: ${WARN}"

if [[ "${FAIL}" -gt 0 ]]; then
  red "Lint failed."
  exit 1
fi
green "Lint passed."
exit 0
