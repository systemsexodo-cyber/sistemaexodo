# Stage 1: Build dependencies
FROM python:3.10-slim as builder

WORKDIR /app

# Install build dependencies for lxml and cryptography
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    libxmlsec1-dev \
    pkg-config \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install dependencies (removing windows-specific ones from the target later if needed)
# For now, we'll just install everything and ignore failures for pywin32 on Linux if it fails
RUN pip install --no-cache-dir -r requirements.txt || \
    (sed -i '/pywin32/d' requirements.txt && \
     sed -i '/pystray/d' requirements.txt && \
     pip install --no-cache-dir -r requirements.txt)

# Stage 2: Regular image
FROM python:3.10-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libxslt1.1 \
    libxmlsec1 \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy source code
COPY . .

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV CLOUD_RUN=true

# Expose port (Cloud Run uses PORT env var, mapping it to 8080 by default)
EXPOSE 8080

# Command to run the application
# We use uvicorn directly. main:app is the FastAPI instance in main.py
CMD uvicorn main:app --host 0.0.0.0 --port $PORT
