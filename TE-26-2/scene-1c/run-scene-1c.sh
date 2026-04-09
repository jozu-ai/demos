#!/usr/bin/env bash

###################################################
# Scene 1C: Policy Gate — The Artifact That       #
# Doesn't Pass                                    #
###################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Demo Magic configuration
source "${SCRIPT_DIR}/../demo-magic.sh"

TYPE_SPEED=70

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Disable line wrapping
printf '\e[?7l'

# Login as falcon-ops (the operator pulling artifacts)
kit login registry.kind.cluster --tls-verify=false -u falcon-ops -p test 2>/dev/null || true

clear

cd "${SCRIPT_DIR}/imint-classifier-compromised"

# Attempt to pull the compromised artifact — should be blocked by policy
pe "kit pull registry.kind.cluster/gray-falcon/imint-classifier-compromised:v1.1 --tls-verify=false"

printf "\n"

# Pull the verified artifact — should succeed
pe "kit pull registry.kind.cluster/gray-falcon/imint-classifier:v1.0 --tls-verify=false"

cd "${SCRIPT_DIR}"

printf "\n"
p ""
