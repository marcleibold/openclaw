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

# Build Python 3.12 from source + install all deps in one RUN to avoid lock issues
RUN apt-get update && \
    apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev gh ffmpeg libavdevice59 libavcodec59 libavfilter8 libavformat59 libavutil57 libpostproc56 libswresample4 libswscale6 curl && \
    cd /tmp && \
    wget -q https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz && \
    tar -xf Python-3.12.0.tgz && \
    cd Python-3.12.0 && \
    ./configure --enable-optimizations --prefix=/usr/local --without-ensurepip && \
    make -j$(nproc) && \
    make altinstall && \
    cd /tmp && rm -rf Python-3.12.0* && \
    curl -fsSL https://astral.sh/uv/0.11.8/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    chmod +x /usr/local/bin/uv && \
    curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH="/usr/local/bin:$PATH"
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
RUN /usr/local/bin/uv pip install --system --python python3.12 requests

USER 1000:1000