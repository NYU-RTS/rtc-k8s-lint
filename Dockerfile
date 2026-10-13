# Hummingbird's minimal core-runtime base (glibc + bash) keeps the image small.
# Its rpm repos ship git but not kustomize, gh, or flux, so those come from
# upstream release tarballs and helm comes from the Hummingbird helm image.
FROM registry.access.redhat.com/hi/helm:4 AS helm

FROM registry.access.redhat.com/hi/core-runtime:latest-builder AS build

# Set automatically by BuildKit; default for the legacy builder.
ARG TARGETARCH=amd64
ARG KUSTOMIZE_VERSION=5.8.3
ARG GH_VERSION=2.102.0
ARG FLUX_VERSION=2.9.6

USER 0

# Install git into a separate root so only it and its deps reach the final image.
RUN dnf install -y --installroot=/rootfs --use-host-config --setopt=install_weak_deps=0 git-core && \
    dnf --installroot=/rootfs clean all

# Download each tool and verify it against its release's checksums file.
RUN dnf install -y tar gzip && \
    mkdir -p /out && cd /tmp && \
    fetch() { \
      curl -fsSLO "$1/$2" && \
      curl -fsSL "$1/$3" | grep " $2\$" | sha256sum -c -; \
    } && \
    fetch "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}" \
      "kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" checksums.txt && \
    fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}" \
      "gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" "gh_${GH_VERSION}_checksums.txt" && \
    fetch "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}" \
      "flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" "flux_${FLUX_VERSION}_checksums.txt" && \
    tar -xzf "kustomize_v${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" -C /out kustomize && \
    tar -xzf "gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" --strip-components=2 -C /out \
      "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" && \
    tar -xzf "flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" -C /out flux

COPY --from=helm /usr/bin/helm /out/helm

# Install the schema plugin at build time; entrypoint.sh resets HOME to /root
# so flux finds it.
RUN HOME=/root /out/flux plugin install schema

FROM registry.access.redhat.com/hi/core-runtime:latest

# Hummingbird images default to a non-root user. Keep the runtime user as root
# so the mounted GitHub Actions command files remain writable.
USER 0

COPY --from=build /rootfs/ /
COPY --from=build /out/ /usr/local/bin/
COPY --from=build /root/.fluxcd /root/.fluxcd

# Set the working directory inside the container.
WORKDIR /usr/src

# Copy any source file(s) required for the action.
COPY --chmod=755 entrypoint.sh .

# Configure the container to be run as an executable.
ENTRYPOINT ["/usr/src/entrypoint.sh"]
