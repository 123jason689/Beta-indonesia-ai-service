# --- STAGE 1: Build Environment for GPU Optimization ---
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential wget libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils \
    tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Build Python 3.12 with optimizations
WORKDIR /tmp
RUN wget https://www.python.org/ftp/python/3.12.4/Python-3.12.4.tgz && \
    tar -xf Python-3.12.4.tgz && \
    cd Python-3.12.4 && \
    ./configure --enable-optimizations --prefix=/opt/python && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/*

# Create virtual environment with GPU-optimized packages
ENV VIRTUAL_ENV=/opt/venv
RUN /opt/python/bin/python3.12 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy requirements and install packages with retry logic
COPY requirements.txt .
RUN python3.12 -m pip install --no-cache-dir --upgrade pip && \
    # Install PyTorch with CUDA 12.1 support with retry logic
    for i in $(seq 1 3); do \
        python3.12 -m pip install --no-cache-dir --timeout=300 torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && break || \
        (echo "PyTorch install attempt $i failed, cleaning cache and retrying..." && python3.12 -m pip cache purge && sleep 15); \
    done && \
    # Install AI packages optimized for GPU with retry logic
    for i in $(seq 1 3); do \
        python3.12 -m pip install --no-cache-dir --timeout=300 \
        xformers \
        diffusers \
        transformers \
        accelerate \
        safetensors \
        einops \
        peft \
        controlnet_aux \
        ip_adapter \
        azure-storage-blob \
        -r requirements.txt && break || \
        (echo "AI packages install attempt $i failed, cleaning cache and retrying..." && python3.12 -m pip cache purge && sleep 15); \
    done

# --- STAGE 2: Optimized Runtime Environment ---
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal runtime dependencies
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy Python and virtual environment
COPY --from=builder /opt/python /opt/python
COPY --from=builder /opt/venv /opt/venv

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/python/bin:$VIRTUAL_ENV/bin:$PATH"

# GPU optimizations
ENV CUDA_VISIBLE_DEVICES=0
ENV CUDA_DEVICE_ORDER=PCI_BUS_ID

WORKDIR /app

# Copy application code (already copied by deployment script)
COPY ailibs/ ./ailibs/
COPY RAG/ ./RAG/
COPY Recommendation/ ./Recommendation/
COPY chroma_db/ ./chroma_db/
COPY .env .
COPY multi_service_processor.py .

# Set entrypoint that accepts job_id as argument
ENTRYPOINT ["/opt/venv/bin/python3.12", "multi_service_processor.py"]
