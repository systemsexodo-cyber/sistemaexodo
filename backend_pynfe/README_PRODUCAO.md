# 🚀 Guia de Produção - Backend NFC-e

## 📋 Pré-requisitos

1. Python 3.8 ou superior
2. Todas as dependências instaladas (`pip install -r requirements.txt`)
3. Certificado digital configurado
4. Variáveis de ambiente configuradas (opcional)

## 🔧 Instalação

### 1. Instalar dependências

```bash
pip install -r requirements.txt
```

Isso instalará o **Waitress**, um servidor WSGI adequado para produção no Windows e Linux.

## 🚀 Iniciar Servidor de Produção

### Windows

```bash
start_production.bat
```

### Linux/Mac

```bash
chmod +x start_production.sh
./start_production.sh
```

### Ou manualmente

```bash
python wsgi.py
```

## ⚙️ Configuração

### Variáveis de Ambiente (opcional)

Crie um arquivo `.env` na raiz do projeto:

```env
# Servidor
PORT=5000
HOST=0.0.0.0

# Segurança
SECRET_KEY=sua-chave-secreta-aqui

# CORS (separar múltiplas origens por vírgula)
CORS_ORIGINS=http://localhost:3000,https://seu-dominio.com

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/production.log

# Waitress
WAITRESS_THREADS=4
WAITRESS_CHANNEL_TIMEOUT=120
```

## 📊 Diferenças entre Desenvolvimento e Produção

| Característica | Desenvolvimento | Produção |
|---------------|----------------|----------|
| Servidor | Flask built-in | Waitress (WSGI) |
| Debug | Ativado | Desativado |
| Auto-reload | Sim | Não |
| Threads | 1 | 4 (configurável) |
| Logging | Console | Arquivo + Console |
| Performance | Baixa | Alta |
| Segurança | Básica | Melhorada |

## 🔍 Verificar se está rodando

Acesse: `http://localhost:5000/health`

Você deve ver:
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando",
  "local": true,
  "pynfe_disponivel": true
}
```

## 🛠️ Comandos Úteis

### Ver logs em tempo real (Linux/Mac)

```bash
tail -f logs/production.log
```

### Parar o servidor

Pressione `Ctrl+C` no terminal onde o servidor está rodando.

### Verificar se o servidor está rodando

```bash
# Windows
netstat -ano | findstr :5000

# Linux/Mac
lsof -i :5000
```

## 🔒 Segurança em Produção

1. **Nunca** use `debug=True` em produção
2. Configure `SECRET_KEY` no `.env`
3. Use HTTPS (configure um proxy reverso como Nginx)
4. Configure firewall adequadamente
5. Monitore logs regularmente
6. Use variáveis de ambiente para dados sensíveis

## 🌐 Deploy em Servidor Remoto

### Opção 1: Usando Nginx como Proxy Reverso

1. Configure Nginx para fazer proxy para `http://localhost:5000`
2. Configure SSL/TLS no Nginx
3. Inicie o servidor Python com `start_production.sh`

### Opção 2: Usando systemd (Linux)

Crie um arquivo `/etc/systemd/system/nfce-backend.service`:

```ini
[Unit]
Description=Backend NFC-e
After=network.target

[Service]
User=seu-usuario
WorkingDirectory=/caminho/para/backend_pynfe
Environment="PATH=/caminho/para/venv/bin"
ExecStart=/caminho/para/venv/bin/python wsgi.py
Restart=always

[Install]
WantedBy=multi-user.target
```

Depois:
```bash
sudo systemctl enable nfce-backend
sudo systemctl start nfce-backend
```

## 📝 Notas

- O servidor Waitress é adequado para produção e funciona bem no Windows
- Para alta carga, considere usar Gunicorn (Linux) ou múltiplas instâncias com load balancer
- Os logs são salvos em `logs/production.log`
- O servidor suporta múltiplas requisições simultâneas (4 threads por padrão)

## ❓ Problemas Comuns

### Porta já em uso

```bash
# Windows
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Linux/Mac
lsof -i :5000
kill -9 <PID>
```

### Waitress não encontrado

```bash
pip install waitress>=2.1.2
```

### Erro de permissão (Linux/Mac)

```bash
chmod +x start_production.sh
chmod +x wsgi.py
```


























