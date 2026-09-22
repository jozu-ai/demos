#!/usr/bin/env bash
# Put the machine back. Safe to run twice.
set -uo pipefail

cd "$(dirname "$0")"

CONTAINER="${CONTAINER:-agentguard-dungeon-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5111}"
POLICY_REF="127.0.0.1:${REGISTRY_PORT}/agentguard-dungeon/sunless-keep-policy:v1"

printf '== removing the workspace policy registration\n'
agentguard policy remove "$POLICY_REF" -w "$(pwd)/workspace" >/dev/null 2>&1 \
    && printf '   removed %s\n' "$POLICY_REF" \
    || printf '   not registered\n'

printf '== removing the local registry\n'
docker rm -f "$CONTAINER" >/dev/null 2>&1 && printf '   removed %s\n' "$CONTAINER" \
    || printf '   %s was not running\n' "$CONTAINER"

printf '== removing the packed bundle\n'
rm -f mcp-server/sunless-keep.mcpb
rm -rf workspace

printf '== the named environment\n'
printf '   the session overlay is several GB and lives in AgentGuard'"'"'s own storage.\n'
printf '   Leave it if you are presenting again today. To reclaim the space:\n\n'
printf '       agentguard env delete dungeon\n\n'
printf '   The runtime image, the ModelKits and the Ollama model are left alone.\n'
