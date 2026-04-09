#!/usr/bin/env bash
set -euo pipefail

REQUIRED_CLIS=(kit cosign agentguard)
missing=0

for cli in "${REQUIRED_CLIS[@]}"; do
  if command -v "$cli" &>/dev/null; then
    printf "  %-15s %s\n" "$cli" "$(command -v "$cli")"
  else
    printf "  %-15s MISSING\n" "$cli"
    missing=1
  fi
done

if [ "$missing" -eq 1 ]; then
  echo ""
  echo "Install missing tools before running the demo."
  exit 1
else
  echo ""
  echo "All required CLIs are installed."
fi
