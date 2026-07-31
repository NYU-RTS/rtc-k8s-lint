# alpine/arch do not ship helm v4 as of this comment so use fedora
FROM fedora:45

RUN dnf update -y && \
    dnf install -y kustomize helm curl which && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# install fluxcd binary, there is no fedora rpm for it
RUN curl -s https://fluxcd.io/install.sh | sudo bash

# Set the working directory inside the container.
WORKDIR /usr/src

# Copy any source file(s) required for the action.
COPY entrypoint.sh .

RUN chmod +x /usr/src/entrypoint.sh

# Install the schema plugin at build time. Keep the runtime user as root so the
# mounted GitHub Actions command files remain writable.
RUN flux plugin install schema

# Configure the container to be run as an executable.
ENTRYPOINT ["/usr/src/entrypoint.sh"]
