#!/bin/sh -l
set -euo pipefail

# GitHub Actions overrides HOME to /github/home for container actions, but the
# flux schema plugin was installed under /root/.fluxcd during the image build.
# Reset HOME so flux finds it regardless of how the container is invoked.
export HOME=/root

# Use INPUT_<INPUT_NAME> to get the value of an input. Allow a positional
# argument for local debugging, but default to the action input.
INPUT_LOCATION="${1:-${INPUT_LOCATION:-.}}"

echo "::notice file=entrypoint.sh,line=12::linting manifests from $INPUT_LOCATION"

# Write outputs to the $GITHUB_OUTPUT file
manifest="$(kustomize build --enable-helm "$INPUT_LOCATION")"
{
  echo "manifest<<EOF"
  printf '%s\n' "$manifest"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

# Validate output with flux schema
validation_json="$(printf '%s' "$manifest" | flux schema validate -s ecosystem -v -o json)"
{
  echo "validation-json<<EOF"
  printf '%s\n' "$validation_json"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
