#!/bin/sh -l
set -euo pipefail

# GitHub Actions overrides HOME to /github/home for container actions, but the
# flux schema plugin was installed under /root/.fluxcd during the image build.
# Reset HOME so flux finds it regardless of how the container is invoked.
export HOME=/root

# Use INPUT_<INPUT_NAME> to get the value of an input. Allow a positional
# argument for local debugging, but default to the action input.
INPUT_LOCATION="${1:-${INPUT_LOCATION:-.}}"

# Kustomize can pull in remote bases from git (e.g. https://github.com/org/repo
# or git@github.com:org/repo), which it resolves by shelling out to the system
# git binary. Private repos need credentials the container doesn't otherwise
# have, so rewrite git/ssh/https references to the GitHub host into
# token-authenticated HTTPS URLs when a token is provided.
if [ -n "${INPUT_GITHUB_TOKEN:-}" ]; then
  host="${GITHUB_SERVER_URL#https://}"
  authenticated="https://x-access-token:${INPUT_GITHUB_TOKEN}@${host}/"
  git config --global "url.${authenticated}.insteadOf" "https://${host}/"
  git config --global "url.${authenticated}.insteadOf" "git@${host}:"
  git config --global "url.${authenticated}.insteadOf" "ssh://git@${host}/"
fi

echo "::notice::linting manifests from $INPUT_LOCATION"

# kustomize/flux write their own errors to stderr, which the runner already
# surfaces in the job log -- no need to capture and replay it ourselves.
manifest="$(kustomize build --enable-helm "$INPUT_LOCATION")" || {
  echo "::error::kustomize build failed for '$INPUT_LOCATION'"
  exit 1
}

# Write outputs to the $GITHUB_OUTPUT file
{
  echo "manifest<<EOF"
  printf '%s\n' "$manifest"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

# flux exits non-zero both when it finds schema violations (expected -- it
# still writes a full JSON report to stdout) and when it fails to run at all
# (stdout is empty in that case). Capture the exit code without letting
# `set -e` kill the script so we can tell those two cases apart.
validation_exit=0
validation_json="$(printf '%s' "$manifest" | flux schema validate -s ecosystem -v -o json)" || validation_exit=$?

if [ -z "$validation_json" ]; then
  echo "::error::flux schema validate produced no report (exit $validation_exit)"
  exit 1
fi

{
  echo "validation-json<<EOF"
  printf '%s\n' "$validation_json"
  echo "EOF"
} >> "$GITHUB_OUTPUT"

if [ "$validation_exit" -ne 0 ]; then
  echo "::error::flux schema validate found invalid manifests; see validation-json output for details"
  # Exit 0 because we need the next step to run, otherwise this error prevents the next step from being run
  exit 0
fi
