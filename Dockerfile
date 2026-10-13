FROM registry.access.redhat.com/hi/helm:4 AS helm

# Build tools here; copy only the binaries and git runtime dependencies later.
FROM registry.access.redhat.com/hi/core-runtime:latest-builder AS build

# BuildKit sets TARGETARCH automatically. The default supports the legacy builder.
ARG TARGETARCH=amd64
ARG KUSTOMIZE_VERSION=5.8.3
ARG GH_VERSION=2.102.0
ARG FLUX_VERSION=2.9.6

USER 0

# Install git into a separate root so its package manager and other build tools
# stay out of the final image.
RUN dnf install -y \
      --installroot=/rootfs \
      --use-host-config \
      --setopt=install_weak_deps=0 \
      git-core && \
    dnf --installroot=/rootfs clean all

# Download and verify each release archive before extracting its binary.
RUN dnf install -y tar gzip && \
    mkdir -p /out && \
    cd /tmp && \
    download_and_verify() { \
      archive="$1"; \
      base_url="$2"; \
      checksum_file="$3"; \
      curl -fsSLO "$base_url/$archive" && \
      curl -fsSL "$base_url/$checksum_file" -o checksums.txt && \
      grep " $archive\$" checksums.txt > checksum.txt && \
      sha256sum -c checksum.txt; \
    } && \
    download_and_verify \
      "kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}" \
      checksums.txt && \
    download_and_verify \
      "gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}" \
      "gh_${GH_VERSION}_checksums.txt" && \
    download_and_verify \
      "flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" \
      "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}" \
      "flux_${FLUX_VERSION}_checksums.txt" && \
    tar -xzf "kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" \
      -C /out kustomize && \
    tar -xzf "gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
      --strip-components=2 \
      -C /out \
      "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" && \
    tar -xzf "flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" \
      -C /out flux

COPY --from=helm /usr/bin/helm /out/helm

# Install the schema plugin where entrypoint.sh can find it after resetting HOME.
RUN HOME=/root /out/flux plugin install schema

FROM registry.access.redhat.com/hi/core-runtime:latest

# Keep root so GitHub Actions' mounted command files remain writable.
USER 0

COPY --from=build /rootfs/ /
COPY --from=build /out/ /usr/local/bin/
COPY --from=build /root/.fluxcd /root/.fluxcd

WORKDIR /usr/src

COPY --chmod=755 entrypoint.sh .

ENTRYPOINT ["/usr/src/entrypoint.sh"]
