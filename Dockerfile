# alpine/arch do not ship helm v4 as of this comment so use fedora
FROM fedora:45

RUN dnf update -y && \
    dnf install -y kustomize helm curl which && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# install fluxcd binary, there is no fedora rpm for it 
RUN curl -s https://fluxcd.io/install.sh | sudo bash

# install the schema plugin
RUN flux plugin install schema


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
