# Dockerfile para o Monitor Redis Queue
FROM python:3.11-alpine

# Define o diretório de trabalho
WORKDIR /app

# Instala dependências do sistema
RUN apk add --no-cache gcc musl-dev

# Copia o arquivo de requisitos
COPY requirements.txt .

# Instala dependências Python
RUN pip install --no-cache-dir -r requirements.txt

# Copia o código da aplicação
COPY monitor_redis_queue.py .

# Cria usuário não-root para segurança
RUN adduser -D -s /bin/sh monitor
USER monitor

# Define variáveis de ambiente padrão
ENV REDIS_HOST=localhost
ENV REDIS_PORT=6379
ENV REDIS_PASSWORD=
ENV QUEUE_NAME_PREFIX=bull
ENV QUEUE_NAME=jobs
ENV POLL_INTERVAL_SECONDS=5

# Comando para executar a aplicação
CMD ["python", "monitor_redis_queue.py"]