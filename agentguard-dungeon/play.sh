#!/usr/bin/env bash
# Run the demo. `./setup.sh` first.
#
# --plain-http because the local registry has no TLS.
# --no-sync to skip the remote policy refresh; the definition's own policy
#   module is pulled either way, so the rules on stage are the ones in
#   policy/keep-rules.yaml and nothing else.
# --env to give the session a named environment, so the second run of the
#   afternoon does not re-import the runtime image.
set -euo pipefail

cd "$(dirname "$0")"

REGISTRY_PORT="${REGISTRY_PORT:-5111}"
REF="127.0.0.1:${REGISTRY_PORT}/agentguard-dungeon/sunless-keep-agent:v1"
WORKSPACE="${WORKSPACE:-$(pwd)/workspace}"

mkdir -p "$WORKSPACE"

exec agentguard run "$REF" \
    --plain-http \
    --no-sync \
    --env dungeon \
    -w "$WORKSPACE"
