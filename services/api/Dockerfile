# ===============================================================
# Jetson Nano / JetPack 4.6.3 (R32.7.3)
# CUDA 10.2 + TensorRT 8.2 + PyTorch 1.10 (already preinstalled)
# ===============================================================
FROM nvcr.io/nvidia/l4t-ml:r32.7.1-py3

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---------------------------------------------------------------
# 1. System dependencies
# ---------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libsndfile1 sox libsox-dev \
        libjpeg-turbo8 libpng16-16 zlib1g \
        libsm6 libxext6 libxrender1 libglib2.0-0 \
        git wget curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ---------------------------------------------------------------
# 2. Copy project files
# ---------------------------------------------------------------
COPY . .
COPY requirements.freeze.txt ./requirements.txt

# ---------------------------------------------------------------
# 3. Install Python dependencies (re-use cache)
# ---------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    echo "[INFO] Installing project requirements..." && \
    python3 -m pip install --upgrade pip==21.3.1 setuptools==57.5.0 wheel==0.37.1 && \
    python3 -m pip install --prefer-binary --no-deps -r requirements.txt && \
    echo "[OK] All requirements installed."

# ---------------------------------------------------------------
# 4. Optional: verify installation
# ---------------------------------------------------------------
RUN python3 - <<'PY'
import torch, pkg_resources
print("CUDA available:", torch.cuda.is_available())
print("Installed packages:", len(pkg_resources.working_set))
PY

# ---------------------------------------------------------------
# 5. Expose and run
# ---------------------------------------------------------------
EXPOSE 8000
CMD ["python3", "main.py"]
