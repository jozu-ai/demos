#!/usr/bin/env bash

###################################################
# Scene 2A: Agent Definition & Agent Guard Launch  #
# Shows signature verification + artifact admission#
###################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="registry.kind.cluster/gray-falcon"
PUB_KEY="${SCRIPT_DIR}/cosign.pub"

# Resolve the selected coding agent (AGENT env var, default claude-code).
# The agent-definition has no spec.framework, so this CLI name decides which
# coding agent AgentGuard launches.
source "${SCRIPT_DIR}/agent-config.sh"

# Demo Magic configuration
source "${SCRIPT_DIR}/../demo-magic.sh"

TYPE_SPEED=70

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Disable line wrapping
printf '\e[?7l'

# Pre-demo: ensure cosign has registry credentials
cosign login registry.kind.cluster --username gray-falcon --password test 2>/dev/null || true

clear

cd "${SCRIPT_DIR}/agent-definition"

# Show the agent definition
pe "cat agent-definition.yaml"

printf "\n"

# 1. Add the artifact admission policy — audience sees it loaded
pe "agentguard policy add ${REGISTRY}/artifact-admission-policy:v1 --plain-http"

printf "\n"

# 2. Attempt to launch the UNSIGNED agent — should be blocked
pe "agentguard run ${AGENT} --agent-ref ${REGISTRY}/imint-agent-unsigned:v1 --pub-key ${PUB_KEY} --plain-http -w ${SCRIPT_DIR}"

printf "\n"

# 3. Show untrusted agent definition
pe "cat ${SCRIPT_DIR}/agent-definition-untrusted/agent-definition.yaml"

printf "\n"

# 4. Launch agent with untrusted module — artifact admission blocks it
pe "agentguard run ${AGENT} --agent-ref ${REGISTRY}/imint-agent-untrusted:v1 --pub-key ${PUB_KEY} --plain-http -w ${SCRIPT_DIR}"

printf "\n"

# 5. Launch the signed, trusted agent — succeeds, transitions to scene 2B
pe "agentguard run ${AGENT} --agent-ref ${REGISTRY}/imint-agent:v1 --pub-key ${PUB_KEY} --plain-http -w ${SCRIPT_DIR}"

cd "${SCRIPT_DIR}"

printf "\n"
p ""
