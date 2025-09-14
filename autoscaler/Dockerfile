# Use an official Python runtime as a parent image
FROM python:3.11-alpine

# Set the working directory in the container
WORKDIR /app

# Install system dependencies including build tools for psutil
RUN apk add --no-cache \
    docker-cli \
    gcc \
    python3-dev \
    musl-dev \
    linux-headers \
    && rm -rf /var/cache/apk/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create docker group and non-root user
# Use the same GID as the host docker group (usually 999)
RUN addgroup -g 999 -S docker 2>/dev/null || true && \
    addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup && \
    adduser appuser docker

# Copy application files
COPY autoscaler_swarm.py .
COPY .env* ./

# Change ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Set default environment variables
ENV REDIS_HOST=redis \
    REDIS_PORT=6379 \
    REDIS_PASSWORD= \
    QUEUE_NAME_PREFIX=bull \
    QUEUE_NAME=jobs \
    N8N_WORKER_SERVICE_NAME=n8n-worker \
    MIN_REPLICAS=1 \
    MAX_REPLICAS=5 \
    SCALE_UP_QUEUE_THRESHOLD=10 \
    SCALE_DOWN_QUEUE_THRESHOLD=2 \
    POLLING_INTERVAL_SECONDS=30 \
    COOLDOWN_PERIOD_SECONDS=300

# Specify the command to run on container start
CMD ["python", "-u", "autoscaler_swarm.py"]