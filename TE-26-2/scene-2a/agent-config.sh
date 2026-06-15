#!/usr/bin/env bash
#
# Shared agent selection for Scene 2A.
#
# The agent-definition deliberately omits spec.framework, so the coding agent
# is decided by the CLI: `agentguard run ${AGENT}`. Select it with the AGENT
# env var (defaults to claude-code):
#
#   AGENT=codex  ./setup-scene-2a.sh
#   AGENT=codex  ./run-scene-2a.sh
#
# Supported agents: claude-code, codex, gemini

AGENT="${AGENT:-claude-code}"

case "${AGENT}" in
  claude-code|codex|gemini) ;;
  *)
    echo "ERROR: unsupported AGENT '${AGENT}' (supported: claude-code, codex, gemini)" >&2
    exit 1
    ;;
esac

export AGENT
