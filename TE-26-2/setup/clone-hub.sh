#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/jozu-ai/jozu-hub-product.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/jozu-hub-product"

if [ -d "$TARGET_DIR" ]; then
  echo "jozu-hub-product already cloned at ${TARGET_DIR}"
  echo "To re-clone, remove the directory first: rm -rf ${TARGET_DIR}"
  exit 0
fi

echo "Shallow cloning jozu-hub-product..."
git clone --depth 1 "$REPO_URL" "$TARGET_DIR"
echo "Done. Cloned to ${TARGET_DIR}"
