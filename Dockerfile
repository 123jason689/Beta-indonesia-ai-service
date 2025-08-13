# --- STAGE 1: Build Environment ---
# This stage compiles Python and installs all dependencies.
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04 AS builder

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install all build-time system dependencies for Python and OpenCV
RUN apt-get update && apt-get install -y \
    build-essential wget libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils \
    tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Download and compile Python 3.12 into a specific directory
WORKDIR /tmp
RUN wget https://www.python.org/ftp/python/3.12.4/Python-3.12.4.tgz && \
    tar -xf Python-3.12.4.tgz && \
    cd Python-3.12.4 && \
    ./configure --enable-optimizations --prefix=/opt/python && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/*

# Create a virtual environment and install all Python packages into it
ENV VIRTUAL_ENV=/opt/venv
RUN /opt/python/bin/python3.12 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install all Python packages in one go for better layer caching
COPY requirements.txt .
RUN python3.12 -m pip install --no-cache-dir --upgrade pip && \
    python3.12 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && \
    python3.12 -m pip install --no-cache-dir \
    xformers diffusers transformers accelerate safetensors einops \
    peft controlnet_aux ip_adapter gunicorn -r requirements.txt

# --- STAGE 2: Final Runtime Environment ---
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install ONLY the essential runtime system dependencies
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy the custom Python installation and the virtual environment from the builder stage
COPY --from=builder /opt/python /opt/python
COPY --from=builder /opt/venv /opt/venv

# Set up the PATH to use the Python from the virtual environment
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/python/bin:$VIRTUAL_ENV/bin:$PATH"

# Set up the application directory
WORKDIR /app

# Copy your application code
COPY . .

# Expose the port the app runs on
EXPOSE 5000

# Run the application using Gunicorn with the correct python executable
CMD ["/opt/venv/bin/python3.12", "-m", "gunicorn", "--bind", "0.0.0.0:5000", "main:app"]