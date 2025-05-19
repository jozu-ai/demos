#!/usr/bin/env bash

#################################################
# Kit demo showing pulling and local dev with a #
# ModelKit. Recorded with Asciinema             #
#################################################

# Demo Magic configuration
source ../demo-magic.sh

# speed at which to simulate typing. bigger num = faster
TYPE_SPEED=80

# custom prompt
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
DEMO_PROMPT="${CYAN}➜ ${GREEN}\W ${COLOR_RESET}"

# text color
# DEMO_CMD_COLOR=$BLACK

# Disable line wrapping (makes it easier to read kit list output)
printf '\e[?7l' 

# Make sure the local registry doesn't have our modelkit in it
kit remove jozu.ml/brad/pdl32:v0.8

# hide configuration
clear

printf "\n"
pe "kit unpack --filter=model jozu.ml/brad/pdl32:v0.8 -d model-only --progress cherry"

printf "\n"
cd model-only
pe "tree"

printf "\n"
pe "kit list"

printf "\n"
pe "kit pull jozu.ml/brad/pdl32:v0.8 --progress cherry"

printf "\n"
pe "kit list"

printf "\n"
cd ..
pe "kit unpack jozu.ml/brad/pdl32:v0.8 -d pdl32-project --progress cherry"

cd pdl32-project
pe "tree"

# wait max 3 seconds until user presses
# PROMPT_TIMEOUT=3
# wait

# enters interactive mode and allows newly typed command to be executed
# cmd

# show a prompt so as not to reveal our true nature after
# the demo has concluded
printf "\n"
p ""