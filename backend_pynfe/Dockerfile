# Dockerfile para Google Cloud Run
FROM python:3.10-slim

# Variáveis de ambiente
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Diretório de trabalho
WORKDIR /app

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copiar requirements primeiro (cache de layers)
COPY requirements.txt .

# Instalar dependências Python
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copiar código da aplicação
COPY . .

# Criar diretórios necessários
RUN mkdir -p logs/backups logs/empresas

# Expor porta (Cloud Run usa PORT variável)
EXPOSE 8080

# Comando para iniciar (Cloud Run espera na porta $PORT)
CMD exec gunicorn --bind 0.0.0.0:$PORT --workers 2 --threads 4 --timeout 300 --access-logfile - --error-logfile - wsgi:application


























