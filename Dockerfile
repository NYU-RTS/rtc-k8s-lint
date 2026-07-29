# Set the base image to use for subsequent instructions.
FROM fedora:45

RUN dnf update -y && \
    dnf install -y kustomize helm && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Create a non-root user and switch to it.
RUN groupadd actiongroup && \
    useradd actionuser && \
    usermod -aG actiongroup actionuser
USER actionuser

# Configure the container to be run as an executable.
ENTRYPOINT ["kustomize"]
