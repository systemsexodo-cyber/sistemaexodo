#!/bin/bash
# Script para iniciar servidor de produção no Linux/Mac

echo "========================================"
echo "Iniciando servidor de PRODUÇÃO"
echo "========================================"
echo ""

# Verificar se está no diretório correto
if [ ! -f "app.py" ]; then
    echo "ERRO: app.py não encontrado!"
    echo "Execute este script no diretório backend_pynfe"
    exit 1
fi

# Ativar ambiente virtual se existir
if [ -f "venv/bin/activate" ]; then
    echo "Ativando ambiente virtual..."
    source venv/bin/activate
fi

# Verificar se waitress está instalado
python -c "import waitress" 2>/dev/null
if [ $? -ne 0 ]; then
    echo ""
    echo "AVISO: Waitress não está instalado!"
    echo "Instalando waitress..."
    pip install waitress>=2.1.2
    if [ $? -ne 0 ]; then
        echo "ERRO: Falha ao instalar waitress"
        exit 1
    fi
fi

echo ""
echo "Iniciando servidor de produção com Waitress..."
echo ""

# Definir variáveis de ambiente (opcional)
export PORT=${PORT:-5000}
export HOST=${HOST:-0.0.0.0}

# Iniciar servidor usando wsgi.py
python wsgi.py


























