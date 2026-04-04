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
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI
RUN curl -fsSL https://github.com/cli/cli/releases/download/v2.89.0/gh_2.89.0_linux_amd64.tar.gz \
    | tar -xz -C /tmp \
    && mv /tmp/gh_2.89.0_linux_amd64/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh_2.89.0_linux_amd64

WORKDIR /app

# Clone upstream nanobot at a pinned version
ARG NANOBOT_VERSION=v0.1.4.post6
RUN git clone --depth 1 --branch ${NANOBOT_VERSION} https://github.com/HKUDS/NanoBot.git . || \
    git clone --depth 1 https://github.com/HKUDS/NanoBot.git .

# Install Python dependencies with Matrix (E2EE) support
RUN uv pip install --system --no-cache ".[matrix]"

# Create config directory
RUN mkdir -p /root/.nanobot

# Gateway default port
EXPOSE 18790

ENTRYPOINT ["nanobot"]
CMD ["gateway"]
