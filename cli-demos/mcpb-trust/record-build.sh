#!/usr/bin/env bash
#
# Emit SLSA v1 provenance for the .mcpb that was just built.
#
# Everything written here is observed from the build that actually ran: the
# source the bundle was assembled from, the digest of the generated manifest,
# the outputs it produced, and the versions of the tools that did the work.
# Nothing is asserted that this script cannot see - which is why there is no
# startedOn, and no CI workflow claimed as the builder.

set -euo pipefail
cd "$(dirname "$0")"
source ./demo.env

[ -f "$MCPB_FILE" ] || { echo "no $MCPB_FILE - run mcpb pack first" >&2; exit 1; }

MANIFEST_SHA=$(shasum -a 256 "$BUNDLE_DIR/manifest.json" | awk '{print $1}')
MCPB_SHA=$(shasum -a 256 "$MCPB_FILE" | awk '{print $1}')
FINISHED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# The SBOM is produced separately, by npm itself. This script only records that
# it was one of the build's outputs.
[ -f "$SBOM_FILE" ] || { echo "no $SBOM_FILE - run npm sbom first" >&2; exit 1; }
SBOM_SHA=$(shasum -a 256 "$SBOM_FILE" | awk '{print $1}')
COMPONENTS=$(jq '.components | length' "$SBOM_FILE")

jq -n \
  --arg buildType "$BUILD_TYPE" \
  --arg srcUri "$SOURCE_URI" --arg srcCommit "$SOURCE_COMMIT" --arg entry "$SOURCE_ENTRYPOINT" \
  --arg manifestSha "$MANIFEST_SHA" --arg mcpbSha "$MCPB_SHA" \
  --arg mcpbVer "$(mcpb --version)" --arg nodeVer "$(node --version)" \
  --arg finished "$FINISHED" --arg invocation "mcpb-pack-${MCPB_SHA:0:12}" \
  --arg sbomSha "$SBOM_SHA" '
{
  buildDefinition: {
    buildType: $buildType,
    externalParameters: {
      source: { uri: $srcUri, digest: { gitCommit: $srcCommit }, entryPoint: $entry },
      manifest: { digest: { sha256: $manifestSha } }
    },
    resolvedDependencies: [ { uri: $srcUri, digest: { gitCommit: $srcCommit } } ]
  },
  runDetails: {
    builder: { id: "https://github.com/modelcontextprotocol/mcpb",
               version: { mcpb: $mcpbVer, node: $nodeVer } },
    metadata: { invocationId: $invocation, finishedOn: $finished }
  },
  byproducts: [ { name: "server-everything.mcpb", digest: { sha256: $mcpbSha } },
                { name: "sbom.json", digest: { sha256: $sbomSha } } ]
}' > "$PROVENANCE_FILE"

echo "wrote $PROVENANCE_FILE"
echo "  source      $SOURCE_COMMIT ($SOURCE_ENTRYPOINT)"
echo "  manifest    sha256:$MANIFEST_SHA"
echo "  mcpb        sha256:$MCPB_SHA"
echo "  builder     mcpb $(mcpb --version), node $(node --version)"
echo "  sbom        $SBOM_FILE, $COMPONENTS components (recorded as a byproduct)"
