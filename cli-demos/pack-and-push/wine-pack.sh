#!/usr/bin/env bash

###################################################
# Kit demo showing packing and pushing a ModelKit #
# Recorded with Asciinema                         #
###################################################

# Demo Magic configuration
source ../demo-magic.sh

# speed at which to simulate typing. bigger num = faster
TYPE_SPEED=70

# custom prompt
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# text color
# DEMO_CMD_COLOR=$BLACK

# Disable line wrapping (makes it easier to read kit list output)
printf '\e[?7l' 

# Make sure the local registry doesn't have our modelkit in it
kit remove jozu.ml/jozu-quickstarts/wine-quality:v2.0

# hide configuration
clear

cd wine-modelkit
pe "tree"

printf "\n"
pe "kit pack . -t wine-quality:v2.0"

printf "\n"
pe "kit list"

printf "\n"
pe "kit push wine-quality:v2.0 jozu.ml/jozu-quickstarts/wine-quality:v2.0"

printf "\n"
pe "kit list jozu.ml/jozu-quickstarts/wine-quality"

cd ..

# wait max 3 seconds until user presses
# PROMPT_TIMEOUT=3
# wait

# enters interactive mode and allows newly typed command to be executed
# cmd

# show a prompt so as not to reveal our true nature after
# the demo has concluded
printf "\n"
p ""