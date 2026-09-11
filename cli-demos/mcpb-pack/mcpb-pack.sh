#!/usr/bin/env bash

########################################################
# Kit demo showing MCP servers packaged as ModelKits,  #
# each carrying one MCPB bundle                        #
# Recorded with Asciinema                              #
########################################################

# Demo Magic configuration
source ../demo-magic.sh

# speed at which to simulate typing. bigger num = faster
TYPE_SPEED=70

# custom prompt
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Disable line wrapping (makes it easier to read kit list output)
printf '\e[?7l'

# One server keeps the demo short; drop the argument to pack all seven.
SERVER=time
WORKDIR=$(mktemp -d)

# Start from a clean slate so the pack output is the thing on screen.
kit remove mcp/$SERVER:0.6.2 2>/dev/null

# hide configuration
clear

# The packaging script: clone the upstream monorepo, vendor each server's
# dependency closure for linux/arm64, write an MCPB manifest, pack the bundle,
# and wrap it in a ModelKit.
pe "./package-mcp-servers.sh --out $WORKDIR --keep $SERVER"

printf "\n"
pe "kit list | head -3"

# The Kitfile carries the bundle under mcpServers:, one server per kit.
printf "\n"
pe "cat $WORKDIR/kits/$SERVER/Kitfile"

# And the bundle itself is a zip with the MCPB manifest at its root.
printf "\n"
pe "unzip -l $WORKDIR/kits/$SERVER/$SERVER.mcpb | head -12"

printf "\n"
pe "kit inspect mcp/$SERVER:0.6.2 | head -20"

rm -rf "$WORKDIR"

# show a prompt so as not to reveal our true nature after
# the demo has concluded
printf "\n"
