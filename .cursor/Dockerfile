# Cursor Cloud Agent base image for StarterApp.
# Linux-only: backend + Postgres + API contract tools. No Xcode / Tuist / Simulator.
# See AGENTS.md § "Cursor Cloud specific instructions".

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV MISE_DATA_DIR=/opt/mise
ENV MISE_CONFIG_DIR=/etc/mise
ENV MISE_CACHE_DIR=/var/cache/mise
ENV PATH="/root/.local/bin:${MISE_DATA_DIR}/shims:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    make \
    openssl \
    sudo \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

########################################################
# Docker (DinD-friendly defaults from Cursor docs)
########################################################

RUN install -m 0755 -d /etc/apt/keyrings && \
    curl --retry 3 --retry-delay 5 -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin \
      fuse-overlayfs \
      iptables \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/docker && \
    printf '%s\n' '{' \
    '  "storage-driver": "fuse-overlayfs"' \
    '}' > /etc/docker/daemon.json

RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

########################################################
# GitHub CLI (inspect iOS CI on PRs without a Mac)
########################################################

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
      https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

########################################################
# mise → Python 3.12 + uv (versions match .mise.toml; skip Tuist/SwiftLint)
########################################################

RUN curl --retry 3 --retry-delay 5 -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
RUN mise install python@3.12 uv@0.11.2 && mise use -g python@3.12 uv@0.11.2

########################################################
# Non-root ubuntu user (Cursor convention)
########################################################

RUN echo 'PasswordAuthentication no\nChallengeResponseAuthentication no\nUsePAM no' \
      > /etc/ssh/sshd_config.d/disable_password_auth.conf || true

RUN id -u ubuntu &>/dev/null || useradd -m -s /bin/bash ubuntu
RUN groupadd -f docker && usermod -aG docker ubuntu
RUN usermod -aG sudo ubuntu
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
RUN echo "ubuntu:ubuntu" | chpasswd

# Agent sessions run as ubuntu — keep mise data readable/writable for install refreshes.
RUN mkdir -p /home/ubuntu/.local/bin && \
    ln -sf /usr/local/bin/mise /home/ubuntu/.local/bin/mise && \
    chown -R ubuntu:ubuntu /home/ubuntu/.local /opt/mise /var/cache/mise /etc/mise

ENV PATH="/home/ubuntu/.local/bin:${MISE_DATA_DIR}/shims:/usr/local/bin:${PATH}"
