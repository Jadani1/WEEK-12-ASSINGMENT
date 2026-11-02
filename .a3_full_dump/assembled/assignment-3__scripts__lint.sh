#!/usr/bin/env bash
# lint.sh — Validate required files and Bash syntax (bash -n)
# Optional: ShellCheck when available
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { red "  FAIL  $*"; FAIL=$((FAIL + 1)); }

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
    pass "exists ${f}"
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
  if bash -n "${s}" 2>/tmp/lint-bash-n.err; then
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
  for s in app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh; do
    [[ -f "${s}" ]] || continue
    # SC1091: sourced files; SC2034: unused in some helpers — keep default severity
    if shellcheck -x "${s}" 2>/tmp/lint-sc.err; then
      pass "shellcheck ${s}"
    else
      # Soft-fail optional tool: warn but still count as fail so CI stays strict if installed
      fail "shellcheck ${s}"
      cat /tmp/lint-sc.err >&2 || true
    fi
  done
  rm -f /tmp/lint-sc.err 2>/dev/null || true
else
  echo "  (shellcheck not installed — skipped)"
fi

echo
bold "=== lint summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  red "Lint failed."
  exit 1
fi
green "Lint passed."
exit 0
