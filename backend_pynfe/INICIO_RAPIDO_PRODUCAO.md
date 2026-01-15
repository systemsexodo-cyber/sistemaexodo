# 🚀 Início Rápido - Produção Real

## ⚡ Passos Rápidos (5 minutos)

### 1. Preparar Ambiente

```bash
cd backend_pynfe
chmod +x deploy_production.sh
```

### 2. Configurar Variáveis

```bash
# Copiar arquivo de exemplo
cp .env.production.example .env.production

# Gerar SECRET_KEY
python -c "import secrets; print(secrets.token_hex(32))"

# Editar .env.production e colar a SECRET_KEY gerada
nano .env.production
```

### 3. Executar Deploy

```bash
./deploy_production.sh
```

### 4. Iniciar Servidor

**Opção A - Manual:**
```bash
python wsgi.py
```

**Opção B - Systemd (recomendado):**
```bash
sudo systemctl start nfce-backend
sudo systemctl status nfce-backend
```

### 5. Testar

```bash
curl http://localhost:5000/health
```

## 📋 Checklist Mínimo

- [ ] `.env.production` configurado
- [ ] `SECRET_KEY` gerada e configurada
- [ ] `DEBUG=False`
- [ ] Dependências instaladas
- [ ] Servidor iniciado
- [ ] Health check funcionando

## 🔒 Para Produção Real (Servidor Remoto)

1. **SSL/TLS**: Configure Let's Encrypt
2. **Nginx**: Configure como proxy reverso
3. **Firewall**: Abra apenas portas 80 e 443
4. **Systemd**: Configure serviço automático
5. **Backup**: Configure backup automático

Veja `GUIA_PRODUCAO_REAL.md` para detalhes completos.


























