#!/bin/bash

echo "========================================"
echo "Iniciando Backend NFC-e (Local)"
echo "========================================"
echo ""

# Verificar se o ambiente virtual existe
if [ ! -d "venv" ]; then
    echo "Criando ambiente virtual..."
    python3 -m venv venv
fi

# Ativar ambiente virtual
echo "Ativando ambiente virtual..."
source venv/bin/activate

# Verificar se as dependências estão instaladas
echo "Verificando dependências..."
if ! pip show flask &> /dev/null; then
    echo "Instalando dependências..."
    pip install -r requirements.txt
    echo ""
    echo "Tentando instalar PyNFe do GitHub..."
    pip install git+https://github.com/TadaSoftware/PyNFe.git
fi

# Criar arquivo .env se não existir
if [ ! -f ".env" ]; then
    echo "Criando arquivo .env..."
    cp .env.example .env
    echo ""
    echo "ATENÇÃO: Configure o arquivo .env com suas configurações!"
fi

echo ""
echo "========================================"
echo "Iniciando servidor..."
echo "========================================"
echo ""
echo "Servidor será iniciado em: http://localhost:5000"
echo "Pressione Ctrl+C para parar"
echo ""

python app.py


