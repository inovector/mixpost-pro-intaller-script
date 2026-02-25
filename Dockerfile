FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Simulate a fresh VPS with systemd-like environment
RUN apt-get update -qq && \
    apt-get install -y -qq \
    sudo \
    curl \
    gnupg \
    ca-certificates \
    systemctl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/installer

# Copy all editions
COPY lite/ lite/
COPY pro/ pro/
COPY enterprise/ enterprise/

# Make scripts executable
RUN chmod +x lite/install.sh pro/install.sh enterprise/install.sh

# Default: open a shell for interactive testing
CMD ["/bin/bash"]
