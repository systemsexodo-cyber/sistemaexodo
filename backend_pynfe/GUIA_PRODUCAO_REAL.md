# 🚀 Guia Completo - Produção Real

## 📋 Checklist de Produção

### ✅ 1. Pré-requisitos

- [ ] Servidor Linux (Ubuntu 20.04+ recomendado)
- [ ] Python 3.8 ou superior
- [ ] Nginx instalado (para HTTPS)
- [ ] Certificado SSL/TLS (Let's Encrypt recomendado)
- [ ] Firewall configurado
- [ ] Domínio configurado (DNS apontando para o servidor)

### ✅ 2. Instalação

```bash
# 1. Clonar/baixar o projeto no servidor
cd /opt
git clone <seu-repositorio> nfce-backend
cd nfce-backend/backend_pynfe

# 2. Executar script de deploy
chmod +x deploy_production.sh
./deploy_production.sh
```

### ✅ 3. Configuração de Variáveis de Ambiente

Edite o arquivo `.env.production`:

```bash
nano .env.production
```

**Configurações obrigatórias:**

```env
# Gerar SECRET_KEY forte
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# Configurar CORS com seus domínios
CORS_ORIGINS=https://seu-dominio.com,https://app.seu-dominio.com

# Desabilitar debug
DEBUG=False
```

### ✅ 4. Configurar SSL/TLS (Let's Encrypt)

```bash
# Instalar Certbot
sudo apt install certbot python3-certbot-nginx

# Obter certificado
sudo certbot --nginx -d seu-dominio.com -d www.seu-dominio.com

# Renovação automática (já configurado)
sudo certbot renew --dry-run
```

### ✅ 5. Configurar Nginx

```bash
# Copiar configuração
sudo cp nginx.conf /etc/nginx/sites-available/nfce-backend

# Editar domínio
sudo nano /etc/nginx/sites-available/nfce-backend
# Substituir "seu-dominio.com" pelo seu domínio real

# Habilitar site
sudo ln -s /etc/nginx/sites-available/nfce-backend /etc/nginx/sites-enabled/

# Testar configuração
sudo nginx -t

# Reiniciar Nginx
sudo systemctl restart nginx
```

### ✅ 6. Configurar Systemd Service

```bash
# Editar arquivo de serviço
sudo nano /etc/systemd/system/nfce-backend.service

# Ajustar caminhos:
# - WorkingDirectory
# - ExecStart
# - EnvironmentFile

# Habilitar e iniciar
sudo systemctl daemon-reload
sudo systemctl enable nfce-backend
sudo systemctl start nfce-backend

# Verificar status
sudo systemctl status nfce-backend
```

### ✅ 7. Configurar Firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (redireciona para HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable

# Verificar
sudo ufw status
```

### ✅ 8. Monitoramento

#### Logs da Aplicação

```bash
# Ver logs em tempo real
tail -f logs/production.log

# Ver logs do systemd
sudo journalctl -u nfce-backend -f

# Ver logs do Nginx
sudo tail -f /var/log/nginx/nfce-backend-access.log
sudo tail -f /var/log/nginx/nfce-backend-error.log
```

#### Health Check

```bash
# Testar endpoint
curl https://seu-dominio.com/health

# Resposta esperada:
# {
#   "status": "ok",
#   "message": "Backend NFC-e está funcionando",
#   "local": true,
#   "pynfe_disponivel": true
# }
```

### ✅ 9. Backup

Configure backup automático dos XMLs:

```bash
# Criar script de backup
cat > /opt/backup-nfce.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/nfce-backend"
SOURCE_DIR="/opt/nfce-backend/backend_pynfe/logs"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/backup_$DATE.tar.gz $SOURCE_DIR

# Manter apenas últimos 30 dias
find $BACKUP_DIR -name "backup_*.tar.gz" -mtime +30 -delete
EOF

chmod +x /opt/backup-nfce.sh

# Adicionar ao crontab (backup diário às 2h)
crontab -e
# Adicionar: 0 2 * * * /opt/backup-nfce.sh
```

### ✅ 10. Segurança

#### Checklist de Segurança

- [ ] SSL/TLS configurado e funcionando
- [ ] SECRET_KEY forte configurada
- [ ] DEBUG=False em produção
- [ ] Firewall configurado
- [ ] CORS configurado apenas com domínios permitidos
- [ ] Logs não expõem informações sensíveis
- [ ] Certificados SSL renovando automaticamente
- [ ] Sistema atualizado (`sudo apt update && sudo apt upgrade`)
- [ ] Senhas fortes para todos os usuários
- [ ] Acesso SSH apenas com chaves (desabilitar senha)

#### Hardening Adicional

```bash
# Desabilitar login root via SSH
sudo nano /etc/ssh/sshd_config
# Alterar: PermitRootLogin no

# Instalar fail2ban (proteção contra brute force)
sudo apt install fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

## 🔧 Comandos Úteis

### Gerenciar Serviço

```bash
# Iniciar
sudo systemctl start nfce-backend

# Parar
sudo systemctl stop nfce-backend

# Reiniciar
sudo systemctl restart nfce-backend

# Ver status
sudo systemctl status nfce-backend

# Ver logs
sudo journalctl -u nfce-backend -f
```

### Gerenciar Nginx

```bash
# Testar configuração
sudo nginx -t

# Recarregar (sem downtime)
sudo nginx -s reload

# Reiniciar
sudo systemctl restart nginx

# Ver status
sudo systemctl status nginx
```

### Atualizar Aplicação

```bash
cd /opt/nfce-backend/backend_pynfe

# Atualizar código
git pull origin main

# Atualizar dependências
source venv/bin/activate
pip install -r requirements.txt

# Reiniciar serviço
sudo systemctl restart nfce-backend
```

## 📊 Monitoramento e Métricas

### Uso de Recursos

```bash
# CPU e Memória
htop

# Espaço em disco
df -h

# Uso de memória do Python
ps aux | grep python
```

### Performance

```bash
# Testar latência
curl -w "@-" -o /dev/null -s https://seu-dominio.com/health <<'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
```

## 🚨 Troubleshooting

### Serviço não inicia

```bash
# Ver logs detalhados
sudo journalctl -u nfce-backend -n 50

# Verificar permissões
ls -la /opt/nfce-backend/backend_pynfe

# Testar manualmente
cd /opt/nfce-backend/backend_pynfe
source venv/bin/activate
python wsgi.py
```

### Erro 502 Bad Gateway

- Verificar se o serviço Python está rodando
- Verificar porta 5000
- Verificar logs do Nginx

### Erro SSL

- Verificar certificados: `sudo certbot certificates`
- Renovar certificado: `sudo certbot renew`
- Verificar configuração Nginx

## 📝 Checklist Final

Antes de considerar produção:

- [ ] SSL/TLS funcionando
- [ ] Health check respondendo
- [ ] Logs sendo gerados
- [ ] Backup configurado
- [ ] Monitoramento ativo
- [ ] Firewall configurado
- [ ] Sistema atualizado
- [ ] Documentação atualizada
- [ ] Testes realizados
- [ ] Plano de rollback definido

## 🎯 Próximos Passos

1. **Monitoramento Avançado**: Configure Prometheus + Grafana
2. **Load Balancer**: Para múltiplas instâncias
3. **CDN**: Para assets estáticos
4. **Database**: Se necessário para persistência
5. **CI/CD**: Pipeline de deploy automático

---

**⚠️ IMPORTANTE**: Sempre teste em ambiente de staging antes de produção!


























