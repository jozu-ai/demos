#!/usr/bin/env bash
#
###################################################################
# Build an MCPB bundle, package it as an OCI artifact with kit,   #
# sign and attest it with cosign, and verify it before an agent   #
# would ever load it.                                             #
#                                                                 #
# Run ./setup.sh first. Run ./reset.sh to do it again.            #
###################################################################

source ./demo-magic.sh
source ./demo.env

TYPE_SPEED=70
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"

# Disable line wrapping; keeps long digests from mangling the screen.
printf '\e[?7l'

clear

# mcpb init refuses to overwrite an existing manifest, and its error message
# suggests a --force flag that does not exist in mcpb 2.1.2. Clear it quietly
# so a re-run without ./reset.sh cannot fail on the very first command.
rm -f "$BUNDLE_DIR/manifest.json"

printf "\n"
pe "mcpb init -y $BUNDLE_DIR"

printf "\n"
pe "cat $BUNDLE_DIR/manifest.json"

printf "\n"
pe "mcpb pack $BUNDLE_DIR $MCPB_FILE | tail -11"

printf "\n"
pe "mcpb info $MCPB_FILE"

printf "\n"
pe "npm sbom --prefix $BUNDLE_DIR --sbom-format=cyclonedx > $SBOM_FILE"

printf "\n"
pe "jq '{bomFormat, specVersion, components: (.components|length), sample: [.components[0:2][].purl]}' $SBOM_FILE"

printf "\n"
pe "./record-build.sh"

printf "\n"
pe "jq '{buildType: .buildDefinition.buildType, source: .buildDefinition.externalParameters.source, builder: .runDetails.builder, byproducts: [.byproducts[].name]}' $PROVENANCE_FILE"

printf "\n"
pe "kit init $PKG_DIR \\
  --name server-everything \\
  --desc 'MCP server that exercises all the features of the MCP protocol' \\
  --author 'jozu.com' \\
  --force"

printf "\n"
pe "cat $PKG_DIR/Kitfile"

printf "\n"
pe "kit pack $PKG_DIR -t $KIT_REF"

printf "\n"
pe "kit push $KIT_REF --plain-http"

printf "\n"
pe "kit inspect --remote $KIT_REF --plain-http | jq '.kitfile'"

printf "\n"
pe "crane manifest --insecure $KIT_REF | jq '{config: .config.mediaType, layers: [.layers[] | {mediaType, size}]}'"

printf "\n"
pe "shasum -a 256 $MCPB_FILE | awk '{print \$1}'; crane manifest --insecure $KIT_REF | jq -r '.layers[0].digest'"

printf "\n"
pe "DIGEST=\$(crane digest --insecure $KIT_REF); echo \$DIGEST"

printf "\n"
pe "cosign sign --key $COSIGN_KEY --signing-config $SIGNING_CONFIG -y $REPO@\$DIGEST"

printf "\n"
pe "cosign attest --key $COSIGN_KEY --signing-config $SIGNING_CONFIG \\
  --type slsaprovenance1 --predicate provenance.json \\
  -y $REPO@\$DIGEST"

printf "\n"
pe "cosign attest --key $COSIGN_KEY --signing-config $SIGNING_CONFIG \\
  --type cyclonedx --predicate sbom.json \\
  -y $REPO@\$DIGEST"

printf "\n"
pe "cosign verify --key $COSIGN_PUB --insecure-ignore-tlog=true $REPO@\$DIGEST | jq '.[0].critical'"

printf "\n"
pe "cosign verify-attestation --key $COSIGN_PUB --type slsaprovenance1 \\
  --insecure-ignore-tlog=true $REPO@\$DIGEST 2>/dev/null \\
  | jq -r '.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.source'"

printf "\n"
pe "cosign tree $REPO@\$DIGEST"

printf "\n"
pe "echo '// exfiltrate credentials to attacker.example' >> $BUNDLE_DIR/server/index.js"

printf "\n"
pe "mcpb pack $BUNDLE_DIR $MCPB_FILE | tail -4 \\
  && kit pack $PKG_DIR -t $KIT_REF | tail -2 \\
  && kit push $KIT_REF --plain-http"

printf "\n"
pe "crane digest --insecure $KIT_REF; echo \"signed digest was \$DIGEST\""

printf "\n"
pe "cosign verify --key $COSIGN_PUB --insecure-ignore-tlog=true $KIT_REF"

printf "\n"
pe "cosign verify --key $COSIGN_PUB --insecure-ignore-tlog=true $REPO@\$DIGEST | jq -r '.[0].critical.image'"

printf "\n"
p ""
