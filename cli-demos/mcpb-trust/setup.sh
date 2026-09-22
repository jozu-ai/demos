#!/usr/bin/env bash
#
# Run this BEFORE you walk on stage, while you still have network.
# It does everything slow, network-dependent or boring so the live demo does not.
# Safe to re-run: every step is idempotent.

set -euo pipefail
cd "$(dirname "$0")"
source ./demo.env

ok()   { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
step() { printf "\n\033[1;37m%s\033[0m\n" "$1"; }
die()  { printf "\n\033[0;31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

step "Checking tools"
for t in mcpb kit cosign docker crane jq npm node; do
  command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
  ok "$t $(command -v $t)"
done
docker info >/dev/null 2>&1 || die "Docker is not running"
ok "docker daemon is up"

step "Checking the MCP server is vendored and pre-built"
[ -f "$SERVER_DIR/dist/index.js" ] || die "$SERVER_DIR/dist is missing - the demo must not compile on stage"
ok "$SERVER_DIR/ present, dist/ already built"

step "Assembling the MCPB bundle"
# An MCPB is self-contained: manifest + server + its production dependencies.
# Bundling those deps is the whole point of the format, so we really install them.
mkdir -p "$BUNDLE_DIR/server"
rm -rf "$BUNDLE_DIR/server"/*
cp -a "$SERVER_DIR/dist"/* "$BUNDLE_DIR/server"/
cp "$SERVER_DIR/README.md" "$BUNDLE_DIR/README.md" 2>/dev/null || true
ok "copied built server into $BUNDLE_DIR/server/"

if [ -d "$BUNDLE_DIR/node_modules" ]; then
  ok "production dependencies already bundled"
else
  ( cd "$BUNDLE_DIR" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1 ) \
    || die "npm install failed in $BUNDLE_DIR (this step needs network)"
  ok "bundled production dependencies ($(du -sh "$BUNDLE_DIR/node_modules" | cut -f1))"
fi

# The manifest is generated live on stage by `mcpb init`. Generate one here
# too: it proves the inputs are good and the warm pack below needs it. The
# final clearing step deletes it so the demo starts from nothing.
rm -f "$BUNDLE_DIR/manifest.json"
mcpb init -y "$BUNDLE_DIR" >/dev/null 2>&1 || die "mcpb init failed in $BUNDLE_DIR"
mcpb validate "$BUNDLE_DIR/manifest.json" >/dev/null 2>&1 || die "generated manifest does not validate"
ok "mcpb init produces a valid manifest"

step "Backing up the bundle entry point (so reset.sh can undo the tamper)"
cp "$BUNDLE_DIR/server/index.js" "$PRISTINE_ENTRY"
ok "saved $PRISTINE_ENTRY"

step "Starting the local OCI registry on :$REG_PORT"
docker rm -f "$REG_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$REG_CONTAINER" -p "${REG_PORT}:5000" registry:2 >/dev/null
for i in $(seq 1 20); do
  curl -fsS "http://${REG_HOST}/v2/" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -fsS "http://${REG_HOST}/v2/" >/dev/null 2>&1 || die "registry did not come up on :$REG_PORT"
ok "registry listening on $REG_HOST"

step "Generating cosign key material"
mkdir -p "$KEYS_DIR"
if [ -f "$COSIGN_KEY" ] && [ -f "$COSIGN_PUB" ]; then
  ok "reusing existing keypair in $KEYS_DIR/"
else
  ( cd "$KEYS_DIR" && cosign generate-key-pair >/dev/null 2>&1 )
  ok "generated $COSIGN_KEY and $COSIGN_PUB"
fi

# An empty signing config means no Fulcio and no Rekor, so sign and attest work
# with zero network. That is what you want on a conference connection.
if [ -f "$SIGNING_CONFIG" ]; then
  ok "reusing offline signing config"
else
  cosign signing-config create --out "$SIGNING_CONFIG" >/dev/null 2>&1
  ok "created $SIGNING_CONFIG (no transparency log, fully offline)"
fi

step "Warming caches so the first on-stage command is not the slow one"
mkdir -p "$PKG_DIR"
mcpb pack "$BUNDLE_DIR" "$MCPB_FILE" >/dev/null 2>&1
kit init "$PKG_DIR" --name server-everything --desc "warm" --force >/dev/null 2>&1
kit pack "$PKG_DIR" -t "$KIT_REF" >/dev/null 2>&1
kit push "$KIT_REF" --plain-http >/dev/null 2>&1
ok "warm mcpb pack / kit pack / push succeeded"

step "Clearing everything the demo is supposed to create live"
kit remove "$KIT_REF" >/dev/null 2>&1 || true
docker exec "$REG_CONTAINER" rm -rf /var/lib/registry/docker/registry/v2/repositories/mcp >/dev/null 2>&1 || true
rm -rf "${PKG_DIR:?}"/*
rm -f "$BUNDLE_DIR/manifest.json" "$PROVENANCE_FILE" "$SBOM_FILE"
ok "registry, kit storage, $PKG_DIR/, manifest and provenance are cleared"

printf "\n\033[0;32mReady.\033[0m Run \033[1m./mcp-trust.sh\033[0m for the demo.\n"
printf "Between runs, or if a run goes wrong, use \033[1m./reset.sh\033[0m.\n\n"
