#!/usr/bin/env bash

###################################################
# Scene 1A: Packaging an AI Artifact              #
# USSOCOM Demo - Gray Falcon IMINT Classifier     #
###################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Demo Magic configuration
source "${SCRIPT_DIR}/../demo-magic.sh"

TYPE_SPEED=70

DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Disable line wrapping
printf '\e[?7l'

# Cosign credentials for non-interactive signing
export COSIGN_PASSWORD=""
REGISTRY_USER="gray-falcon"
REGISTRY_PASS="test"

# Pre-demo setup (hidden from audience)
kit login registry.kind.cluster --tls-verify=false -u gray-falcon -p test 2>/dev/null || true
kit remove registry.kind.cluster/gray-falcon/imint-classifier:v1.0 2>/dev/null || true

clear

cd "${SCRIPT_DIR}/gray-falcon-imint-classifier"

pe "tree"

printf "\n"
pe "cat Kitfile"

printf "\n"
pe "kit pack . -t registry.kind.cluster/gray-falcon/imint-classifier:v1.0"

printf "\n"
pe "kit push registry.kind.cluster/gray-falcon/imint-classifier:v1.0 --tls-verify=false"

printf "\n"
pe "cosign sign --key cosign.key --allow-insecure-registry --registry-username=${REGISTRY_USER} --registry-password=${REGISTRY_PASS} registry.kind.cluster/gray-falcon/imint-classifier:v1.0"

printf "\n"
pe "cosign verify --key cosign.pub --allow-insecure-registry --registry-username=${REGISTRY_USER} --registry-password=${REGISTRY_PASS} registry.kind.cluster/gray-falcon/imint-classifier:v1.0"

cd "${SCRIPT_DIR}"

printf "\n"
p ""
