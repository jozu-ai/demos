#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/gray-falcon-imint-classifier"

echo "=== Scene 1A Setup ==="

# Check prerequisites
for cmd in kit cosign; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed"
    exit 1
  fi
done

# Generate placeholder model file (~10MB)
echo "Generating placeholder model file..."
dd if=/dev/urandom of="${PROJECT_DIR}/model/classifier-v3.safetensors" bs=1024 count=10240 2>/dev/null

# Generate placeholder dataset images
echo "Generating placeholder dataset images..."
for i in $(seq -w 1 5); do
  dd if=/dev/urandom of="${PROJECT_DIR}/data/validation-set/sample-${i}.jpg" bs=1024 count=1 2>/dev/null
done

# Generate cosign key pair (empty password for non-interactive demo)
echo "Generating cosign key pair..."
cd "${PROJECT_DIR}"
COSIGN_PASSWORD="" cosign generate-key-pair --output-key-prefix cosign 2>/dev/null
cd "${SCRIPT_DIR}"

echo "=== Scene 1A setup complete ==="
