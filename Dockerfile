# Build whisper-cli from source (no official prebuilt Linux binary available)
FROM ubuntu:22.04 AS builder

RUN apt-get update && \
    apt-get install -y build-essential cmake git curl && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
RUN git clone --depth 1 --branch v1.8.0 https://github.com/ggml-org/whisper.cpp.git && \
    cd whisper.cpp && \
    cmake -B build && \
    cmake --build build -j$(nproc)

# Final image
FROM ghcr.io/openclaw/openclaw:2026.4.12-slim

USER root

RUN apt-get update -qq && \
    apt-get install -y -qq curl gnupg ca-certificates > /dev/null 2>&1 && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install -y -qq gh ffmpeg libavdevice59 libavcodec59 libavfilter8 libavformat59 libavutil57 libpostproc56 libswresample4 libswscale6 > /dev/null 2>&1 && \
    curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy whisper-cli from builder
COPY --from=builder /app/whisper.cpp/build/bin/whisper-cli /usr/local/bin/whisper-cli
RUN chmod +x /usr/local/bin/whisper-cli

# Download base model at build time
RUN mkdir -p /usr/local/share/whisper && \
    curl -fsSL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o /usr/local/share/whisper/ggml-base.bin && \
    chmod 644 /usr/local/share/whisper/ggml-base.bin

USER 1000:1000