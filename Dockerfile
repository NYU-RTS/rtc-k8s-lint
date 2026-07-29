# Set the base image to use for subsequent instructions.
FROM fedora:45

RUN dnf update -y && \
    dnf install -y kustomize helm && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Set the working directory inside the container.
WORKDIR /usr/src

# Copy any source file(s) required for the action.
COPY entrypoint.sh .

# Create a non-root user, set file permissions, switch to it.
RUN groupadd actiongroup && \
    useradd actionuser && \
    usermod -aG actiongroup actionuser
RUN chown -R actionuser:actiongroup /usr/src && \
    chmod +x /usr/src/entrypoint.sh
USER actionuser

# Configure the container to be run as an executable.
ENTRYPOINT ["/usr/src/entrypoint.sh"]
