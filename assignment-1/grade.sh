#!/usr/bin/env bash
# grade.sh — Simple automated checks for the Linux diagnostic toolkit
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

PASS=0
FAIL=0

green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

check() {
  local name="$1"
  shift
  if "$@"; then
    green "PASS  ${name}"
    PASS=$((PASS + 1))
    return 0
  else
    red "FAIL  ${name}"
    FAIL=$((FAIL + 1))
    return 1
  fi
}

# Run a command with a soft timeout (seconds). Uses timeout(1) when present.
run_to() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${secs}" "$@"
  else
    "$@"
  fi
}

bold "=== Assignment 1 — grade.sh ==="
echo

# ---------- structure ----------
bold "Structure"
check "README.md exists"               test -f README.md
check "system-info.sh exists"          test -f system-info.sh
check "disk-check.sh exists"           test -f disk-check.sh
check "network-check.sh exists"        test -f network-check.sh
check "grade.sh exists"                test -f grade.sh
check "logs/ directory exists"         test -d logs
check "logs/.gitkeep exists"           test -f logs/.gitkeep
echo

# ---------- executability / shebang ----------
bold "Scripts"
check "system-info.sh is executable or runnable"  bash -n system-info.sh
check "disk-check.sh is executable or runnable"   bash -n disk-check.sh
check "network-check.sh is executable or runnable" bash -n network-check.sh
check "system-info.sh has shebang"     grep -q '^#!' system-info.sh
check "disk-check.sh has shebang"      grep -q '^#!' disk-check.sh
check "network-check.sh has shebang"   grep -q '^#!' network-check.sh
echo

# ---------- system-info ----------
bold "system-info.sh"
SYS_OUT="$(run_to 20 bash system-info.sh 2>&1)" || true
check "system-info prints Hostname"            grep -qi 'Hostname' <<<"${SYS_OUT}"
check "system-info prints Current User"        grep -qi 'User' <<<"${SYS_OUT}"
check "system-info prints Date/Time"           grep -qiE 'Date|Time' <<<"${SYS_OUT}"
check "system-info prints Operating System"    grep -qiE 'Operating System|OS' <<<"${SYS_OUT}"
check "system-info prints Kernel"              grep -qi 'Kernel' <<<"${SYS_OUT}"
check "system-info prints Uptime"              grep -qi 'Uptime' <<<"${SYS_OUT}"
check "system-info prints CPU"                 grep -qi 'CPU' <<<"${SYS_OUT}"
check "system-info prints Memory"              grep -qi 'Memory' <<<"${SYS_OUT}"
check "system-info prints Working Directory"   grep -qiE 'Working Directory|CWD' <<<"${SYS_OUT}"
check "system-info writes a log entry"         test -s logs/system-info.log
echo

# ---------- disk-check ----------
bold "disk-check.sh"
check "disk-check rejects missing args (exit 2)" \
  bash -c 'bash disk-check.sh >/dev/null 2>&1; test $? -eq 2'
check "disk-check rejects non-integer threshold (exit 2)" \
  bash -c 'bash disk-check.sh abc >/dev/null 2>&1; test $? -eq 2'
check "disk-check rejects threshold 0 (exit 2)" \
  bash -c 'bash disk-check.sh 0 >/dev/null 2>&1; test $? -eq 2'
check "disk-check rejects threshold 101 (exit 2)" \
  bash -c 'bash disk-check.sh 101 >/dev/null 2>&1; test $? -eq 2'
# usage on . should be parseable; threshold 100 usually passes or fails cleanly
DISK_RC=0
run_to 15 bash disk-check.sh 100 . >/dev/null 2>&1 || DISK_RC=$?
check "disk-check with threshold 100 on . exits 0 or 1" \
  bash -c "test ${DISK_RC} -eq 0 -o ${DISK_RC} -eq 1"
DISK_LOW_RC=0
run_to 15 bash disk-check.sh 1 . >/dev/null 2>&1 || DISK_LOW_RC=$?
check "disk-check with threshold 1 on . exits 0 or 1" \
  bash -c "test ${DISK_LOW_RC} -eq 0 -o ${DISK_LOW_RC} -eq 1"
check "disk-check prints usage percentage" \
  bash -c 'run_to(){ if command -v timeout >/dev/null 2>&1; then timeout 15 "$@"; else "$@"; fi; }; run_to bash disk-check.sh 100 . 2>&1 | grep -qE "[0-9]+%"'
check "disk-check writes a log entry" test -s logs/disk-check.log
echo

# ---------- network-check ----------
bold "network-check.sh"
check "network-check rejects missing host (exit 2)" \
  bash -c 'bash network-check.sh >/dev/null 2>&1; test $? -eq 2'
check "network-check rejects invalid host (exit 2)" \
  bash -c 'bash network-check.sh "bad host!" >/dev/null 2>&1; test $? -eq 2'
check "network-check rejects invalid port (exit 2)" \
  bash -c 'bash network-check.sh 127.0.0.1 99999 >/dev/null 2>&1; test $? -eq 2'
check "network-check rejects non-numeric port (exit 2)" \
  bash -c 'bash network-check.sh 127.0.0.1 xyz >/dev/null 2>&1; test $? -eq 2'

NET_OUT="$(run_to 25 bash network-check.sh 127.0.0.1 2>&1)" || true
check "network-check resolves/displays address for 127.0.0.1" \
  grep -qiE 'Resolved|127\.0\.0\.1' <<<"${NET_OUT}"
check "network-check shows interface information" \
  grep -qiE 'interface|adapter|inet |ipconfig|flags=' <<<"${NET_OUT}"
check "network-check does not map 127.0.0.1 to a public DNS IP" \
  bash -c 'grep -qi "Resolved address" <<<"'"${NET_OUT}"'" && ! grep -E "Resolved address:[[:space:]]+(8\.8\.8\.8|1\.1\.1\.1)" <<<"'"${NET_OUT}"'"'

# TCP check against localhost — port may be closed; must not crash (exit 0 or 1)
TCP_RC=0
run_to 25 bash network-check.sh 127.0.0.1 9 >/dev/null 2>&1 || TCP_RC=$?
check "network-check with port exits 0 or 1 (no crash)" \
  bash -c "test ${TCP_RC} -eq 0 -o ${TCP_RC} -eq 1"
check "network-check writes a log entry" test -s logs/network-check.log
echo

# ---------- logging format ----------
bold "Logging"
check "logs contain timestamps" \
  bash -c 'grep -qE "\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]" logs/*.log'
echo

# ---------- summary ----------
bold "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
if (( FAIL == 0 )); then
  green "All checks passed."
  exit 0
else
  red "Some checks failed."
  exit 1
fi
