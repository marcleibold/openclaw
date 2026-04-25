FROM ghcr.io/openclaw/openclaw:2026.4.12-slim

USER root

RUN apt-get update -qq && \
    apt-get install -y -qq curl gnupg > /dev/null 2>&1 && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install -y -qq gh ffmpeg libavdevice59 libavcodec59 libavfilter8 libavformat59 libavutil57 libpostproc56 libswresample4 libswscale6 > /dev/null 2>&1 && \
    curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install whisper.cpp - download the x64 binary zip and extract
RUN curl -fsSL https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.0/whisper-bin-x64.zip -o /tmp/whisper.zip && \
    unzip -q /tmp/whisper.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/whisper && \
    rm /tmp/whisper.zip

# Download base model for German - from huggingface mirror if needed
RUN mkdir -p /usr/local/share/whisper && \
    curl -fsSL https://huggingface.co/datasets/ggerganov/whisper.cpp/resolve/main/ggml-base.bin -o /usr/local/share/whisper/ggml-base.bin && \
    chmod 644 /usr/local/share/whisper/ggml-base.bin

USER 1000:1000