#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/imint-classifier-compromised"

echo "=== Scene 1C Setup ==="

# Check prerequisites
for cmd in kit python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed"
    exit 1
  fi
done

# Ensure logged in
kit login registry.kind.cluster --tls-verify=false -u gray-falcon -p test 2>/dev/null || true

# Generate the malicious pickle model file
echo "Generating malicious model file..."
python3 "${PROJECT_DIR}/generate-malicious-model.py"

# Generate placeholder dataset images
echo "Generating placeholder dataset images..."
for i in $(seq -w 1 5); do
  dd if=/dev/urandom of="${PROJECT_DIR}/data/validation-set/sample-${i}.jpg" bs=1024 count=1 2>/dev/null
done

# Pack and push the compromised ModelKit (unsigned — no cosign sign)
echo "Packing compromised ModelKit..."
cd "${PROJECT_DIR}"
kit pack . -t registry.kind.cluster/gray-falcon/imint-classifier-compromised:v1.1

echo "Pushing compromised ModelKit..."
kit push registry.kind.cluster/gray-falcon/imint-classifier-compromised:v1.1 --tls-verify=false

cd "${SCRIPT_DIR}"

echo "=== Scene 1C setup complete ==="
echo "Compromised ModelKit pushed (unsigned, with malicious pickle payload)."
echo "Hub scanners should flag it as CRITICAL."
