#!/usr/bin/env bash
#
# Put everything back the way setup.sh left it, so you can run the demo again.
# Undoes the tamper, clears the built .mcpb and Kitfile, empties the registry.
# Keeps the cosign keys, the bundled dependencies and the registry container.

set -euo pipefail
cd "$(dirname "$0")"
source ./demo.env

ok()   { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[0;33m!\033[0m %s\n" "$1"; }

if [ -f "$PRISTINE_ENTRY" ]; then
  cp "$PRISTINE_ENTRY" "$BUNDLE_DIR/server/index.js"
  ok "restored untampered $BUNDLE_DIR/server/index.js"
else
  warn "no $PRISTINE_ENTRY snapshot; run ./setup.sh"
fi

rm -rf "${PKG_DIR:?}"/*
rm -f "$BUNDLE_DIR/manifest.json" "$PROVENANCE_FILE" "$SBOM_FILE"
ok "cleared generated files (manifest.json, .mcpb, Kitfile, provenance.json, sbom.json)"

kit remove "$KIT_REF" >/dev/null 2>&1 || true
ok "cleared local kit storage"

if docker ps --format '{{.Names}}' | grep -qx "$REG_CONTAINER"; then
  docker exec "$REG_CONTAINER" rm -rf /var/lib/registry/docker/registry/v2/repositories/mcp >/dev/null 2>&1 || true
  ok "emptied the registry"
else
  warn "registry container not running; run ./setup.sh"
fi

printf "\n\033[0;32mReset.\033[0m Run \033[1m./mcp-trust.sh\033[0m again.\n\n"
