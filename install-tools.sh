#!/usr/bin/env bash
set -euo pipefail

mkdir -p /out
cd /tmp

download_and_verify() {
  local archive="$1"
  local url="$2"
  local checksums="$3"

  curl -fLsSLO "$url/$archive"
  curl -fLsSL "$url/$checksums" -o checksums.txt
  grep " $archive\$" checksums.txt > checksum.txt
  sha256sum -c checksum.txt
}

kustomize_archive="kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz"
kustomize_url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"
download_and_verify "$kustomize_archive" "$kustomize_url" checksums.txt

gh_archive="gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz"
gh_url="https://github.com/cli/cli/releases/download/v${GH_VERSION}"
download_and_verify "$gh_archive" "$gh_url" "gh_${GH_VERSION}_checksums.txt"

flux_archive="flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz"
flux_url="https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}"
download_and_verify "$flux_archive" "$flux_url" "flux_${FLUX_VERSION}_checksums.txt"

tar -xzf "$kustomize_archive" -C /out kustomize
tar -xzf "$gh_archive" --strip-components=2 -C /out "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh"
tar -xzf "$flux_archive" -C /out flux
