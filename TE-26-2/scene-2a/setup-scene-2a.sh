#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="registry.kind.cluster/gray-falcon"

echo "=== Scene 2A Setup ==="

COSIGN_KEY="${SCRIPT_DIR}/cosign.key"
COSIGN_PUB="${SCRIPT_DIR}/cosign.pub"
REGISTRY_USER="gray-falcon"
REGISTRY_PASS="test"

for cmd in kit agentguard cosign; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is not installed"
    exit 1
  fi
done

# Ensure logged in
kit login registry.kind.cluster --tls-verify=false -u "${REGISTRY_USER}" -p "${REGISTRY_PASS}" 2>/dev/null || true
cosign login registry.kind.cluster --username "${REGISTRY_USER}" --password "${REGISTRY_PASS}" 2>/dev/null || true

# Generate cosign key pair for signing agent artifacts
echo "Generating cosign key pair..."
cd "${SCRIPT_DIR}"
export COSIGN_PASSWORD=""
rm -f cosign.key cosign.pub
cosign generate-key-pair --output-key-prefix cosign

# Pack and push tool policy (signed)
echo "Pushing tool policy..."
cd "${SCRIPT_DIR}/tool-policy"
kit pack . -t "${REGISTRY}/tool-control-policy:v1"
kit push "${REGISTRY}/tool-control-policy:v1" --tls-verify=false
cosign sign --key "${COSIGN_KEY}" --allow-insecure-registry --registry-username="${REGISTRY_USER}" --registry-password="${REGISTRY_PASS}" "${REGISTRY}/tool-control-policy:v1"

# Pack and push artifact admission policy (signed)
echo "Pushing artifact admission policy..."
cd "${SCRIPT_DIR}/artifact-policy"
kit pack . -t "${REGISTRY}/artifact-admission-policy:v1"
kit push "${REGISTRY}/artifact-admission-policy:v1" --tls-verify=false
cosign sign --key "${COSIGN_KEY}" --allow-insecure-registry --registry-username="${REGISTRY_USER}" --registry-password="${REGISTRY_PASS}" "${REGISTRY}/artifact-admission-policy:v1"

# Pack and push agent definition — SIGNED (trusted)
echo "Pushing signed agent definition..."
cd "${SCRIPT_DIR}/agent-definition"
kit pack . -t "${REGISTRY}/imint-agent:v1"
kit push "${REGISTRY}/imint-agent:v1" --tls-verify=false
cosign sign --key "${COSIGN_KEY}" --allow-insecure-registry --registry-username="${REGISTRY_USER}" --registry-password="${REGISTRY_PASS}" "${REGISTRY}/imint-agent:v1"

# Pack and push agent definition — UNSIGNED (for signature denial demo)
echo "Pushing unsigned agent definition..."
cd "${SCRIPT_DIR}/agent-definition"
kit pack . -t "${REGISTRY}/imint-agent-unsigned:v1"
kit push "${REGISTRY}/imint-agent-unsigned:v1" --tls-verify=false
# Intentionally NOT signed

# Pack and push agent definition — untrusted registry ref (for artifact admission demo)
echo "Pushing untrusted agent definition..."
cd "${SCRIPT_DIR}/agent-definition-untrusted"
kit pack . -t "${REGISTRY}/imint-agent-untrusted:v1"
kit push "${REGISTRY}/imint-agent-untrusted:v1" --tls-verify=false
cosign sign --key "${COSIGN_KEY}" --allow-insecure-registry --registry-username="${REGISTRY_USER}" --registry-password="${REGISTRY_PASS}" "${REGISTRY}/imint-agent-untrusted:v1"

cd "${SCRIPT_DIR}"

echo "=== Scene 2A setup complete ==="
