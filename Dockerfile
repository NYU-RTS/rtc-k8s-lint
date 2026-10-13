FROM registry.access.redhat.com/hi/helm:4 AS helm

FROM registry.access.redhat.com/hi/core-runtime:latest-builder AS build

# Selects architecture-specific tool archives. BuildKit sets TARGETARCH;
# the amd64 default supports the legacy builder.
ARG TARGETARCH=amd64
ARG KUSTOMIZE_VERSION=5.8.3
ARG GH_VERSION=2.102.0
ARG FLUX_VERSION=2.9.6

USER 0

# Install git separately so only git and its runtime dependencies reach the image.
RUN dnf install -y \
      --installroot=/rootfs \
      --use-host-config \
      --setopt=install_weak_deps=0 \
      git-core && \
    dnf --installroot=/rootfs clean all

COPY install-tools.sh /tmp/install-tools.sh
RUN dnf install -y tar gzip && bash /tmp/install-tools.sh

COPY --from=helm /usr/bin/helm /out/helm
# entrypoint.sh resets HOME to /root so Flux can find this plugin at runtime.
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
