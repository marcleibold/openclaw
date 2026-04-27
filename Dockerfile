# Stage 1: Build whisper-cli from source
FROM ubuntu:22.04 AS builder

RUN apt-get update && \
    apt-get install -y build-essential cmake git curl && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
RUN git clone --depth 1 --branch v1.8.0 https://github.com/ggml-org/whisper.cpp.git && \
    cd whisper.cpp && \
    cmake -B build && \
    cmake --build build -j$(nproc) && \
    cmake --install build --prefix /install

# Stage 2: Final image with openclaw base
FROM ghcr.io/openclaw/openclaw:2026.4.12

USER root

# Install Python 3.12, uv, and other dependencies
RUN apt-get update -qq && \
    apt-get install -y -qq curl gnupg ca-certificates > /dev/null 2>&1 && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    curl -kfsSL https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF53A94C3E6504F38 | apt-key add - && \
    echo "deb https://ppa.launchpad.net/deadsnakes/ppa/ubuntu jammy main" > /etc/apt/sources.list.d/deadsnakes.list && \
    apt-get update -qq && \
    apt-get install -y -qq gh ffmpeg libavdevice59 libavcodec59 libavfilter8 libavformat59 libavutil57 libpostproc56 libswresample4 libswscale6 python3.12 python3.12-venv python3.12-distutils curl && \
    curl -fsSL https://astral.sh/uv/install.sh | sh && \
    curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH="/root/.local/bin:$PATH"
ENV LAST30DAYS_PYTHON=python3.12

# Install yt-dlp for YouTube support
RUN curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp

# Copy whisper-cli and any shared libraries from install directory
COPY --from=builder /install/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --from=builder /install/lib/ /usr/local/lib/

# Download base model from HuggingFace at build time
RUN mkdir -p /usr/local/share/whisper && \
    curl -fsSL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o /usr/local/share/whisper/ggml-base.bin && \
    chmod 644 /usr/local/share/whisper/ggml-base.bin && \
    ldconfig || true

# Copy last30days skill
COPY skills/last30days/ /home/node/.openclaw/workspace/skills/last30days/

# Install Python dependencies for last30days
RUN uv pip install --system --python python3.12 requests

USER 1000:1000