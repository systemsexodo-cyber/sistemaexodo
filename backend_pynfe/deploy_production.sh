#!/bin/bash
# ============================================
# Script de Deploy para Produção Real
# ============================================

set -e  # Parar em caso de erro

echo "=========================================="
echo "🚀 Deploy Backend NFC-e - PRODUÇÃO REAL"
echo "=========================================="
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar se está rodando como root (para algumas operações)
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠️  Algumas operações podem precisar de sudo${NC}"
fi

# ============================================
# 1. Verificar pré-requisitos
# ============================================
echo "📋 Verificando pré-requisitos..."

# Verificar Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 não encontrado!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Python encontrado${NC}"

# Verificar pip
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}❌ pip3 não encontrado!${NC}"
    exit 1
fi
echo -e "${GREEN}✅ pip encontrado${NC}"

# Verificar se está no diretório correto
if [ ! -f "app.py" ]; then
    echo -e "${RED}❌ app.py não encontrado! Execute no diretório backend_pynfe${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Diretório correto${NC}"

# ============================================
# 2. Criar ambiente virtual (se não existir)
# ============================================
echo ""
echo "🐍 Configurando ambiente virtual..."

if [ ! -d "venv" ]; then
    echo "Criando ambiente virtual..."
    python3 -m venv venv
fi

source venv/bin/activate
echo -e "${GREEN}✅ Ambiente virtual ativado${NC}"

# ============================================
# 3. Instalar/Atualizar dependências
# ============================================
echo ""
echo "📦 Instalando dependências..."

pip install --upgrade pip
pip install -r requirements.txt

echo -e "${GREEN}✅ Dependências instaladas${NC}"

# ============================================
# 4. Configurar variáveis de ambiente
# ============================================
echo ""
echo "⚙️  Configurando variáveis de ambiente..."

if [ ! -f ".env.production" ]; then
    echo -e "${YELLOW}⚠️  .env.production não encontrado!${NC}"
    echo "Criando arquivo de exemplo..."
    cp .env.production .env.production.example 2>/dev/null || true
    echo -e "${YELLOW}⚠️  Configure o arquivo .env.production antes de continuar!${NC}"
    echo "Edite o arquivo e configure SECRET_KEY e outras variáveis."
    read -p "Pressione Enter após configurar o .env.production..."
fi

# Gerar SECRET_KEY se não estiver configurado
if grep -q "GERE-UMA-CHAVE-SECRETA-FORTE-AQUI" .env.production 2>/dev/null; then
    echo "Gerando SECRET_KEY..."
    SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s/GERE-UMA-CHAVE-SECRETA-FORTE-AQUI/$SECRET_KEY/" .env.production
    echo -e "${GREEN}✅ SECRET_KEY gerada automaticamente${NC}"
fi

echo -e "${GREEN}✅ Variáveis de ambiente configuradas${NC}"

# ============================================
# 5. Criar diretórios necessários
# ============================================
echo ""
echo "📁 Criando diretórios..."

mkdir -p logs
mkdir -p logs/backups
mkdir -p logs/empresas

chmod 755 logs
chmod 755 logs/backups
chmod 755 logs/empresas

echo -e "${GREEN}✅ Diretórios criados${NC}"

# ============================================
# 6. Configurar systemd (opcional)
# ============================================
echo ""
read -p "Deseja configurar systemd service? (s/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "Configurando systemd service..."
    
    # Solicitar caminho do projeto
    read -p "Digite o caminho completo do projeto: " PROJECT_PATH
    read -p "Digite o usuário para rodar o serviço (padrão: www-data): " SERVICE_USER
    SERVICE_USER=${SERVICE_USER:-www-data}
    
    # Criar arquivo de serviço
    SERVICE_FILE="/etc/systemd/system/nfce-backend.service"
    
    cat > /tmp/nfce-backend.service << EOF
[Unit]
Description=Backend NFC-e - Serviço de Produção
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$PROJECT_PATH
Environment="PATH=$PROJECT_PATH/venv/bin"
Environment="PYTHONUNBUFFERED=1"
EnvironmentFile=$PROJECT_PATH/.env.production

ExecStart=$PROJECT_PATH/venv/bin/python $PROJECT_PATH/wsgi.py

Restart=always
RestartSec=10

LimitNOFILE=65536
MemoryMax=2G

StandardOutput=journal
StandardError=journal
SyslogIdentifier=nfce-backend

[Install]
WantedBy=multi-user.target
EOF
    
    sudo cp /tmp/nfce-backend.service $SERVICE_FILE
    sudo systemctl daemon-reload
    sudo systemctl enable nfce-backend
    echo -e "${GREEN}✅ Systemd service configurado${NC}"
    echo "Para iniciar: sudo systemctl start nfce-backend"
    echo "Para ver status: sudo systemctl status nfce-backend"
fi

# ============================================
# 7. Configurar Nginx (opcional)
# ============================================
echo ""
read -p "Deseja configurar Nginx? (s/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    if command -v nginx &> /dev/null; then
        echo "Configurando Nginx..."
        read -p "Digite o domínio (ex: api.seudominio.com): " DOMAIN
        
        sudo cp nginx.conf /etc/nginx/sites-available/nfce-backend
        sudo sed -i "s/seu-dominio.com/$DOMAIN/g" /etc/nginx/sites-available/nfce-backend
        
        sudo ln -sf /etc/nginx/sites-available/nfce-backend /etc/nginx/sites-enabled/
        sudo nginx -t
        
        echo -e "${GREEN}✅ Nginx configurado${NC}"
        echo -e "${YELLOW}⚠️  Configure SSL/TLS antes de habilitar!${NC}"
        echo "Para habilitar: sudo systemctl restart nginx"
    else
        echo -e "${YELLOW}⚠️  Nginx não está instalado${NC}"
        echo "Instale com: sudo apt install nginx (Ubuntu/Debian)"
    fi
fi

# ============================================
# 8. Testar aplicação
# ============================================
echo ""
echo "🧪 Testando aplicação..."

python3 -c "from app import app; print('✅ App importado com sucesso')" || {
    echo -e "${RED}❌ Erro ao importar app${NC}"
    exit 1
}

echo -e "${GREEN}✅ Aplicação testada${NC}"

# ============================================
# 9. Resumo
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}✅ Deploy concluído!${NC}"
echo "=========================================="
echo ""
echo "📝 Próximos passos:"
echo ""
echo "1. Configure o arquivo .env.production"
echo "2. Configure SSL/TLS (Let's Encrypt recomendado)"
echo "3. Configure firewall (abrir porta 443)"
echo "4. Inicie o serviço:"
echo "   - Manual: python wsgi.py"
echo "   - Systemd: sudo systemctl start nfce-backend"
echo ""
echo "5. Monitore logs:"
echo "   - Aplicação: tail -f logs/production.log"
echo "   - Systemd: sudo journalctl -u nfce-backend -f"
echo ""
echo "6. Teste o endpoint:"
echo "   - http://localhost:5000/health"
echo ""


























