#!/usr/bin/env bash

###################################################
# Kit demo showing packing and pushing a ModelKit #
# Recorded with Asciinema                         #
###################################################

# Demo Magic configuration
. demo-magic.sh

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

printf "\e[1;37mI have an ML project to predict wine quality that includes: \n\e[0m"
printf "\e[1;37m - Training data \n\e[0m"
printf "\e[1;37m - A Jupyter notebook \n\e[0m"
printf "\e[1;37m - An MLFlow experiment (plus resulting metrics) \n\e[0m"
printf "\e[1;37m - A README.md \n\e[0m"
printf "\e[1;37m - License for data (CDLA-Permissive-2.0) \n\e[0m"
printf "\e[1;37m - License for the project (Apache 2.0) \n\e[0m"

printf "\n"
cd wine-modelkit
pe "tree"

printf "\n"
printf "\e[1;37mNow I want to pack this up into a single project \n\e[0m"
printf "\e[1;37mthat I can share with anyone. \n\e[0m"

printf "\n"
pe "kit pack . -t wine-quality:v2.0"

printf "\n"
pe "kit list"

printf "\n"
printf "\e[1;37mI can see my ML project is stored in my local registry \n\e[0m"
printf "\e[1;37mNow I'll push it to a cloud registry for sharing with my team \n\e[0m"

printf "\n"
pe "kit push wine-quality:v2.0 jozu.ml/jozu-quickstarts/wine-quality:v2.0"

printf "\n"
pe "kit list jozu.ml/jozu-quickstarts/wine-quality"

printf "\n"
printf "\e[1;37mAnyone can now pull, unpack, and use it locally! \n\e[0m"

# wait max 3 seconds until user presses
# PROMPT_TIMEOUT=3
# wait

# enters interactive mode and allows newly typed command to be executed
# cmd

# show a prompt so as not to reveal our true nature after
# the demo has concluded
printf "\n"
p ""