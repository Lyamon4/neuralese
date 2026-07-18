FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NEURALESE_RUNTIME_MODE=local_school \
    NEURALESE_STORAGE_DIR=/data/jobs \
    NEURALESE_PUBLIC_DATASET_DIR=/data/datasets \
    NEURALESE_MAX_PARALLEL_JOBS=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY onprem_runtime/requirements-runtime.txt /app/onprem_runtime/requirements-runtime.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /app/onprem_runtime/requirements-runtime.txt

COPY onprem_runtime /app/onprem_runtime

RUN mkdir -p /data/jobs /data/datasets \
    && useradd --create-home --uid 10001 neuralese \
    && chown -R neuralese:neuralese /app /data

USER neuralese

EXPOSE 8010

CMD ["uvicorn", "onprem_runtime.api.server:app", "--host", "0.0.0.0", "--port", "8010"]
