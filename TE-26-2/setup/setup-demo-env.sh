#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DEV_DIR="${SCRIPT_DIR}/jozu-hub-product/tools/local-dev"

if [ ! -d "$LOCAL_DEV_DIR" ]; then
  echo "Error: jozu-hub-product not found. Run clone-hub.sh first."
  exit 1
fi

export CLUSTER_NAME="demo"
export TEST_USER="gray-falcon"

echo "Updating Helm values with latest images..."
"${LOCAL_DEV_DIR}/update-values-images.sh"

echo "Setting up local demo environment (kind cluster: ${CLUSTER_NAME})..."
exec "${LOCAL_DEV_DIR}/all.sh"
