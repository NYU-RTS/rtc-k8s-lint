#!/bin/sh -l
set -euo pipefail

# Use INPUT_<INPUT_NAME> to get the value of an input
# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=5, got input location as: $INPUT_LOCATION"

# Write outputs to the $GITHUB_OUTPUT file
manifest="$(kustomize build --enable-helm "$INPUT_LOCATION")"
echo "manifest=$manifest" >> "$GITHUB_OUTPUT"

# Validate output with flux schema
validation_json="$(echo "$manifest" | flux schema validate -s ecosystem -v -o json)"
echo "validation-json=$validation_json" >> "$GITHUB_OUTPUT"
