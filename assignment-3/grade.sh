#!/usr/bin/env bash
# grade.sh — Assignment 3 grader (structure, syntax, workflow, behaviour, docker)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

PASS=0
FAIL=0
IMAGE="${IMAGE:-devops-tool}"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { red "  FAIL  $*"; FAIL=$((FAIL + 1)); }

check_file() {
  if [[ -f "$1" ]]; then pass "exists: $1"; else fail "missing: $1"; fi
}

bold "=== Assignment 3 — Structure ==="
check_file "README.md"
check_file "app/app.sh"
check_file "scripts/lint.sh"
check_file "scripts/build.sh"
check_file "tests/test.sh"
check_file ".github/workflows/ci.yml"
check_file "Dockerfile"
check_file "compose.yaml"
check_file ".dockerignore"
check_file "grade.sh"
echo

bold "=== Executable bits / shebang ==="
for f in app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh grade.sh; do
  if [[ -f "${f}" ]] && head -n1 "${f}" | grep -q '^#!'; then
    pass "shebang: ${f}"
  else
    fail "shebang: ${f}"
  fi
  # Best-effort +x (Windows may not persist; still try)
  chmod +x "${f}" 2>/dev/null || true
  if [[ -x "${f}" ]] || [[ "$(uname -s 2>/dev/null)" == MINGW* ]] || [[ "$(uname -s 2>/dev/null)" == MSYS* ]]; then
    pass "executable-or-gitbash: ${f}"
  else
    fail "not executable: ${f}"
  fi
done
echo

bold "=== Bash syntax (bash -n) ==="
for f in app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh grade.sh; do
  if [[ -f "${f}" ]] && bash -n "${f}" 2>/dev/null; then
    pass "bash -n ${f}"
  else
    fail "bash -n ${f}"
  fi
done
echo

bold "=== Workflow triggers & jobs ==="
WF=".github/workflows/ci.yml"
if [[ -f "${WF}" ]]; then
  grep -qE 'push:' "${WF}" && pass "workflow on: push" || fail "workflow missing push"
  grep -qE 'pull_request:' "${WF}" && pass "workflow on: pull_request" || fail "workflow missing pull_request"

  for job in validate test docker; do
    grep -qE "^[[:space:]]*${job}:" "${WF}" \
      && pass "job present: ${job}" \
      || fail "job missing: ${job}"
  done

  # needs: ordering — test needs validate; docker needs test
  # Allow flexible YAML formatting
  if grep -A20 -E '^[[:space:]]*test:' "${WF}" | grep -q 'needs:'; then
    if grep -A20 -E '^[[:space:]]*test:' "${WF}" | grep -q 'validate'; then
      pass "test needs: validate"
    else
      fail "test should need validate"
    fi
  else
    fail "test missing needs:"
  fi

  if grep -A20 -E '^[[:space:]]*docker:' "${WF}" | grep -q 'needs:'; then
    if grep -A20 -E '^[[:space:]]*docker:' "${WF}" | grep -q 'test'; then
      pass "docker needs: test"
    else
      fail "docker should need test"
    fi
  else
    fail "docker missing needs:"
  fi

  grep -q 'lint.sh' "${WF}" && pass "workflow runs lint.sh" || fail "workflow missing lint.sh"
  grep -q 'test.sh' "${WF}" && pass "workflow runs test.sh" || fail "workflow missing test.sh"
  grep -q 'build.sh' "${WF}" && pass "workflow runs build.sh" || fail "workflow missing build.sh"
else
  fail "missing workflow file"
fi
echo

bold "=== Application behaviour ==="
APP="app/app.sh"
chmod +x "${APP}" 2>/dev/null || true
if [[ -f "${APP}" ]]; then
  rc=0; out="$("${APP}" help 2>&1)" || rc=$?
  [[ "${rc}" -eq 0 ]] && pass "help → 0" || fail "help → ${rc}"

  rc=0; out="$("${APP}" system-info 2>&1)" || rc=$?
  [[ "${rc}" -eq 0 ]] && pass "system-info → 0" || fail "system-info → ${rc}"

  rc=0; out="$("${APP}" no-such-cmd 2>&1)" || rc=$?
  [[ "${rc}" -eq 2 ]] && pass "invalid command → 2" || fail "invalid command → ${rc}"

  rc=0; out="$("${APP}" check-host 2>&1)" || rc=$?
  [[ "${rc}" -eq 2 ]] && pass "missing host → 2" || fail "missing host → ${rc}"

  rc=0; out="$("${APP}" check-port 127.0.0.1 abc 2>&1)" || rc=$?
  [[ "${rc}" -eq 2 ]] && pass "non-numeric port → 2" || fail "non-numeric port → ${rc}"

  rc=0; out="$("${APP}" check-port 127.0.0.1 70000 2>&1)" || rc=$?
  [[ "${rc}" -eq 2 ]] && pass "out-of-range port → 2" || fail "out-of-range port → ${rc}"
else
  fail "app missing"
fi
echo

bold "=== Student tests (at least 8 cases) ==="
if [[ -f tests/test.sh ]]; then
  # Count assert_exit / test markers roughly
  count="$(grep -cE 'assert_exit|PASS|\\[\\d+\\]' tests/test.sh 2>/dev/null || echo 0)"
  if [[ "${count}" -ge 8 ]]; then
    pass "tests/test.sh has substantial coverage markers (${count})"
  else
    fail "tests/test.sh looks thin (${count} markers)"
  fi
  if bash tests/test.sh >/tmp/a3-tests.out 2>&1; then
    pass "tests/test.sh runs successfully"
  else
    fail "tests/test.sh failed"
    tail -n 30 /tmp/a3-tests.out 2>/dev/null || true
  fi
else
  fail "missing tests/test.sh"
fi
echo

bold "=== Linting ==="
if [[ -f scripts/lint.sh ]]; then
  if bash scripts/lint.sh >/tmp/a3-lint.out 2>&1; then
    pass "scripts/lint.sh passed"
  else
    fail "scripts/lint.sh failed"
    tail -n 20 /tmp/a3-lint.out 2>/dev/null || true
  fi
else
  fail "missing lint.sh"
fi
echo

bold "=== Docker build / smoke ==="
if command -v docker >/dev/null 2>&1; then
  if bash scripts/build.sh >/tmp/a3-build.out 2>&1; then
    pass "scripts/build.sh passed"
  else
    fail "scripts/build.sh failed"
    tail -n 40 /tmp/a3-build.out 2>/dev/null || true
  fi
else
  echo "  (docker not available — skip build.sh)"
fi
echo

bold "=== Basic git history (if repo) ==="
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commits="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
  if [[ "${commits}" -ge 1 ]]; then
    pass "git history has ${commits} commit(s)"
  else
    fail "no git commits"
  fi
else
  echo "  (not a git repo — skip history check)"
fi
echo

bold "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
rm -f /tmp/a3-tests.out /tmp/a3-lint.out /tmp/a3-build.out 2>/dev/null || true

if [[ "${FAIL}" -gt 0 ]]; then
  red "Some grading checks failed."
  exit 1
fi
green "All grading checks passed."
exit 0
