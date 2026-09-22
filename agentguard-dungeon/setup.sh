#!/usr/bin/env bash
# Build everything the demo runs on. Slow the first time, idempotent after.
#
# Four artifacts go into a local registry on 127.0.0.1:5111:
#   - the runtime image, which is the dungeon master application
#   - the MCP server, as a ModelKit carrying one MCPB bundle
#   - the ToolPolicy, as a ModelKit
#   - the agent definition, which names all three
#
# Nothing here reaches the internet except the base image pull, and nothing
# spends provider credit: the model is on this machine.
set -euo pipefail

cd "$(dirname "$0")"

REGISTRY_PORT="${REGISTRY_PORT:-5111}"
REGISTRY="127.0.0.1:${REGISTRY_PORT}"
NS="agentguard-dungeon"
CONTAINER="${CONTAINER:-agentguard-dungeon-registry}"
MODEL="${MODEL:-qwen2.5:7b}"

say() { printf '\n== %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

say "checking what this needs"
for tool in docker kit mcpb agentguard curl; do
    command -v "$tool" >/dev/null || die "$tool is not on PATH"
done
docker info >/dev/null 2>&1 || die "Docker is not running"

# The model has to be on the host before the demo, because the guest has no way
# to pull one. Ollama's own OpenAI-compatible route is what the gateway will
# talk to, so check that rather than the native API.
say "checking the model is on this machine"
curl -fsS -m 5 http://127.0.0.1:11434/v1/models >/dev/null \
    || die "Ollama is not answering on 127.0.0.1:11434. Start it, then re-run."
curl -fsS -m 5 http://127.0.0.1:11434/v1/models | grep -q "\"$MODEL\"" \
    || die "Ollama does not have $MODEL. Run: ollama pull $MODEL"
printf '   %s is present and Ollama answers on /v1\n' "$MODEL"

say "starting a local registry on ${REGISTRY}"
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    printf '   %s already running\n' "$CONTAINER"
elif docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker start "$CONTAINER" >/dev/null
    printf '   restarted %s\n' "$CONTAINER"
else
    docker run -d -p "127.0.0.1:${REGISTRY_PORT}:5000" --name "$CONTAINER" registry:2 >/dev/null
    printf '   started %s\n' "$CONTAINER"
fi
# Port 5111 rather than 5000 because macOS's AirPlay receiver holds 5000.
for _ in $(seq 1 30); do
    curl -fsS -m 2 "http://${REGISTRY}/v2/" >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS -m 2 "http://${REGISTRY}/v2/" >/dev/null || die "the registry never came up on ${REGISTRY}"

say "building the runtime image"
docker build --platform linux/arm64 -t "${REGISTRY}/${NS}/dungeon-master:v1" agent
docker push "${REGISTRY}/${NS}/dungeon-master:v1"

say "packing the MCP server as a ModelKit"
# `mcpb pack` is a zip with manifest.json at the root. The Kitfile carries it
# under mcpServers:, which is the shape kitops v1.15.0 and later can unpack.
rm -f mcp-server/sunless-keep.mcpb
mcpb pack mcp-server mcp-server/sunless-keep.mcpb >/dev/null
kit pack mcp-server -t "${REGISTRY}/${NS}/sunless-keep:v1"
kit push "${REGISTRY}/${NS}/sunless-keep:v1" --plain-http

say "packing the policy as a ModelKit"
kit pack policy -t "${REGISTRY}/${NS}/sunless-keep-policy:v1"
kit push "${REGISTRY}/${NS}/sunless-keep-policy:v1" --plain-http

say "packing the agent definition"
kit pack agent-def -t "${REGISTRY}/${NS}/sunless-keep-agent:v1"
kit push "${REGISTRY}/${NS}/sunless-keep-agent:v1" --plain-http

# The agent definition declares the policy as a `type: policy` module, which is
# the shape this demo is meant to show. That alone does not enforce it today.
# The definition's policy is pulled into AgentGuard's global policy directory
# but recorded in the configuration as a workspace-scoped one, and the lookup
# that stages policies into the VM goes to the workspace directory, finds
# nothing there, and starts the gateway with no policies at all. The symptom is
# a run that pulls the policy, prints it in the session header, and then says
# "no policies loaded".
#
# Adding it here through the documented CLI puts a copy where that lookup goes.
# reset.sh takes it away again. Both steps disappear the day the definition's
# own module is enough.
say "registering the policy against the demo workspace"
mkdir -p workspace
agentguard policy add "${REGISTRY}/${NS}/sunless-keep-policy:v1" \
    -w "$(pwd)/workspace" --plain-http

say "ready"
cat <<EOF

   Play it:      ./play.sh
   Watch policy: agentguard logs        (in a second terminal)
   Put it back:  ./reset.sh

EOF
