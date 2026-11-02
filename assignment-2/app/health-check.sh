#!/usr/bin/env bash
# health-check.sh — Container health probe for the diagnostic CLI image
# Verifies the CLI binary is present, executable, and responds to help.
set -uo pipefail

CLI="${DIAGNOSTIC_CLI:-/app/diagnostic.sh}"

if [[ ! -f "${CLI}" ]]; then
  echo "health-check: missing ${CLI}" >&2
  exit 1
fi

if [[ ! -x "${CLI}" ]]; then
  echo "health-check: ${CLI} is not executable" >&2
  exit 1
fi

# help must succeed quickly with exit 0
if ! "${CLI}" help >/dev/null 2>&1; then
  echo "health-check: '${CLI} help' failed" >&2
  exit 1
fi

echo "health-check: ok"
exit 0
