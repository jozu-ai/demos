#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${SCRIPT_DIR}/.."

echo "=== Resetting demo state ==="

# Login
kit login registry.kind.cluster --tls-verify=false -u gray-falcon -p test 2>/dev/null || true

# Remove scene-1a artifacts from local kit storage
echo "Cleaning scene-1a local artifacts..."
kit remove registry.kind.cluster/gray-falcon/imint-classifier:v1.0 2>/dev/null || true

# Remove scene-1c artifacts from local kit storage
echo "Cleaning scene-1c local artifacts..."
kit remove registry.kind.cluster/gray-falcon/imint-classifier-compromised:v1.1 2>/dev/null || true

# Remove scene-2a artifacts from local kit storage
echo "Cleaning scene-2a local artifacts..."
kit remove registry.kind.cluster/gray-falcon/imint-agent:v1 2>/dev/null || true
kit remove registry.kind.cluster/gray-falcon/imint-agent-unsigned:v1 2>/dev/null || true
kit remove registry.kind.cluster/gray-falcon/imint-agent-untrusted:v1 2>/dev/null || true
kit remove registry.kind.cluster/gray-falcon/tool-control-policy:v1 2>/dev/null || true
kit remove registry.kind.cluster/gray-falcon/artifact-admission-policy:v1 2>/dev/null || true

# Remove generated files from scene-1a
echo "Cleaning scene-1a generated files..."
rm -f "${DEMO_DIR}/scene-1a/gray-falcon-imint-classifier/model/classifier-v3.safetensors"
rm -f "${DEMO_DIR}/scene-1a/gray-falcon-imint-classifier/data/validation-set/sample-"*.jpg
rm -f "${DEMO_DIR}/scene-1a/gray-falcon-imint-classifier/cosign.key"
rm -f "${DEMO_DIR}/scene-1a/gray-falcon-imint-classifier/cosign.pub"

# Remove generated files from scene-1c
echo "Cleaning scene-1c generated files..."
rm -f "${DEMO_DIR}/scene-1c/imint-classifier-compromised/model/classifier-v3.pkl"
rm -f "${DEMO_DIR}/scene-1c/imint-classifier-compromised/data/validation-set/sample-"*.jpg

# Remove generated files from scene-2a
echo "Cleaning scene-2a generated files..."
rm -f "${DEMO_DIR}/scene-2a/cosign.key"
rm -f "${DEMO_DIR}/scene-2a/cosign.pub"

# Remove agentguard policies
echo "Cleaning agentguard policies..."
agentguard policy remove --all 2>/dev/null || true

# Clean Hub database (gray-falcon org data only)
echo "Cleaning Hub database..."
kubectl exec -n jozu-hub postgres-1 -- psql -U postgres -d jozu_hub -c "
  DELETE FROM catalog.attestation_security_scans WHERE attestation_id IN (
    SELECT a.id FROM catalog.attestations a
    JOIN catalog.modelkits m ON a.modelkit_id = m.id
    JOIN catalog.repositories r ON m.repository_id = r.id
    JOIN catalog.organizations o ON r.organization_id = o.id
    WHERE o.name = 'gray-falcon'
  );
  DELETE FROM catalog.attestations WHERE modelkit_id IN (
    SELECT m.id FROM catalog.modelkits m
    JOIN catalog.repositories r ON m.repository_id = r.id
    JOIN catalog.organizations o ON r.organization_id = o.id
    WHERE o.name = 'gray-falcon'
  );
  DELETE FROM catalog.modelscans WHERE modelkit_id IN (
    SELECT m.id FROM catalog.modelkits m
    JOIN catalog.repositories r ON m.repository_id = r.id
    JOIN catalog.organizations o ON r.organization_id = o.id
    WHERE o.name = 'gray-falcon'
  );
  DELETE FROM catalog.tags WHERE modelkit_id IN (
    SELECT m.id FROM catalog.modelkits m
    JOIN catalog.repositories r ON m.repository_id = r.id
    JOIN catalog.organizations o ON r.organization_id = o.id
    WHERE o.name = 'gray-falcon'
  );
  DELETE FROM catalog.modelkits WHERE repository_id IN (
    SELECT r.id FROM catalog.repositories r
    JOIN catalog.organizations o ON r.organization_id = o.id
    WHERE o.name = 'gray-falcon'
  );
  DELETE FROM catalog.repositories WHERE organization_id IN (
    SELECT id FROM catalog.organizations WHERE name = 'gray-falcon'
  );
" 2>/dev/null || true

# Restart registry to wipe emptyDir storage
echo "Restarting registry (emptyDir — wipes all OCI artifacts)..."
kubectl rollout restart deploy/jozu-registry -n jozu-hub
kubectl rollout status deploy/jozu-registry -n jozu-hub --timeout=60s

# Restart Hub API to clear caches
echo "Restarting Hub API..."
kubectl rollout restart deploy/jozu-hub-api -n jozu-hub
kubectl rollout status deploy/jozu-hub-api -n jozu-hub --timeout=60s

echo "=== Demo reset complete ==="
echo "Run setup scripts to re-initialize:"
echo "  scene-1a/setup-scene-1a.sh"
echo "  scene-1c/setup-scene-1c.sh"
echo "  scene-2a/setup-scene-2a.sh"
