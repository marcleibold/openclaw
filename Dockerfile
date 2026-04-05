FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        wget \
        unzip \
        zip \
        tmux \
        nano \
        less \
        vim-tiny \
        jq \
        rsync \
        openssh-client \
        tesseract-ocr \
        tesseract-ocr-eng \
        imagemagick \
        libimage-exiftool-perl \
        poppler-utils \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI
RUN curl -fsSL https://github.com/cli/cli/releases/download/v2.89.0/gh_2.89.0_linux_amd64.tar.gz \
    | tar -xz -C /tmp \
    && mv /tmp/gh_2.89.0_linux_amd64/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh_2.89.0_linux_amd64

# Install kubectl for Kubernetes access
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

WORKDIR /app

# Clone upstream nanobot at a pinned version
ARG NANOBOT_VERSION=v0.1.4.post6
RUN git clone --depth 1 --branch ${NANOBOT_VERSION} https://github.com/HKUDS/NanoBot.git . || \
    git clone --depth 1 https://github.com/HKUDS/NanoBot.git .

# Install Python dependencies with Matrix (E2EE) support and image processing
RUN uv pip install --system --no-cache ".[matrix]" Pillow

# Create config directory
RUN mkdir -p /root/.nanobot

# Symlink ~/.ssh into the PVC-backed data dir so SSH keys survive pod restarts.
# The ssh/ subdir is created at runtime by the entrypoint (PVC mounts overlay
# the build-time directory, so we can't rely on build-time mkdir for it).
RUN ln -s /root/.nanobot/ssh /root/.ssh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Gateway default port
EXPOSE 18790

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
