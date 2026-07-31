#!/bin/sh -l

# Use INPUT_<INPUT_NAME> to get the value of an input
# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=5, got input location as: $INPUT_LOCATION"

# Write outputs to the $GITHUB_OUTPUT file
echo "manifest=$(kustomize build --enable-helm $INPUT_LOCATION)" >> "$GITHUB_OUTPUT"

# Validate output with flux schema
echo "validation-json=$(kustomize build --enable-helm $INPUT_LOCATION | flux schema validate -s ecosystem -v -o json)" >> "$GITHUB_OUTPUT"

exit 0
