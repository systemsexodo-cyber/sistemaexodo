FROM python:3.12-alpine

# Sem dependencias externas: o bot usa apenas a biblioteca padrao do Python.
# tzdata garante que a janela de horario (BOT_ACTIVE_HOURS) use o fuso da loja.
# pg8000 e python puro (sem compilar nada) e serve so para consultar os pedidos do
# cliente no banco da loja, em modo leitura. Sem ele o bot continua subindo.
RUN apk add --no-cache tzdata \
 && pip install --no-cache-dir "pg8000==1.31.2"
ENV TZ=America/Sao_Paulo

WORKDIR /app
COPY bot.py /app/bot.py
# Prompt padrao (opcional). Em producao pode ser montado por cima e editado sem restart.
COPY prompt.txt /app/prompt.txt
# Dados basicos da loja. Em producao o compose monta ./bot/negocio.json em
# /config/negocio.json, que e o arquivo efetivamente usado.
COPY negocio.json /app/negocio.json
EXPOSE 8096
CMD ["python3", "-u", "/app/bot.py"]
