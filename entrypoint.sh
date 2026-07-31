#!/bin/sh -l
set -euo pipefail

# GitHub Actions overrides HOME to /github/home for container actions, but the
# flux schema plugin was installed under /root/.fluxcd during the image build.
# Reset HOME so flux finds it regardless of how the container is invoked.
export HOME=/root

# Use INPUT_<INPUT_NAME> to get the value of an input. Allow a positional
# argument for local debugging, but default to the action input.
INPUT_LOCATION="${1:-${INPUT_LOCATION:-.}}"

echo "::notice::linting manifests from $INPUT_LOCATION"

stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

if ! manifest="$(kustomize build --enable-helm "$INPUT_LOCATION" 2>"$stderr_file")"; then
  echo "::error::kustomize build failed for '$INPUT_LOCATION'"
  while IFS= read -r line; do echo "::error::$line"; done < "$stderr_file"
  exit 1
fi

# Write outputs to the $GITHUB_OUTPUT file
{
  echo "manifest<<EOF"
  printf '%s\n' "$manifest"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

: > "$stderr_file"
if ! validation_json="$(printf '%s' "$manifest" | flux schema validate -s ecosystem -v -o json 2>"$stderr_file")"; then
  echo "::error::flux schema validate failed"
  while IFS= read -r line; do echo "::error::$line"; done < "$stderr_file"
  exit 1
fi

{
  echo "validation-json<<EOF"
  printf '%s\n' "$validation_json"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
