#!/bin/bash
# ============================================================
# SCRIPT PARA INSTALAR OPENSSL NO LINUX/MACOS
# ============================================================

echo "========================================"
echo "  INSTALADOR DE OPENSSL"
echo "========================================"
echo ""

# Verificar se OpenSSL já está instalado
echo "Verificando se OpenSSL já está instalado..."
if command -v openssl &> /dev/null; then
    OPENSSL_VERSION=$(openssl version)
    echo "✓ OpenSSL já está instalado!"
    echo "Versão: $OPENSSL_VERSION"
    echo ""
    echo "OpenSSL está pronto para uso!"
    exit 0
fi

echo ""
echo "OpenSSL não está instalado."
echo ""

# Detectar sistema operacional
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    echo "Sistema detectado: Linux"
    echo ""
    
    # Detectar distribuição
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo "Distribuição: Debian/Ubuntu"
        echo ""
        echo "Instalando OpenSSL..."
        sudo apt-get update
        sudo apt-get install -y openssl
        
    elif [ -f /etc/redhat-release ]; then
        # RedHat/CentOS/Fedora
        echo "Distribuição: RedHat/CentOS/Fedora"
        echo ""
        
        if command -v dnf &> /dev/null; then
            echo "Instalando OpenSSL via dnf..."
            sudo dnf install -y openssl
        elif command -v yum &> /dev/null; then
            echo "Instalando OpenSSL via yum..."
            sudo yum install -y openssl
        fi
        
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        echo "Distribuição: Arch Linux"
        echo ""
        echo "Instalando OpenSSL..."
        sudo pacman -S --noconfirm openssl
        
    else
        echo "Distribuição não reconhecida."
        echo "Por favor, instale OpenSSL manualmente usando o gerenciador de pacotes da sua distribuição."
        exit 1
    fi
    
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "Sistema detectado: macOS"
    echo ""
    
    # Verificar se Homebrew está instalado
    if command -v brew &> /dev/null; then
        echo "✓ Homebrew encontrado!"
        echo ""
        echo "Instalando OpenSSL via Homebrew..."
        brew install openssl
    else
        echo "Homebrew não encontrado."
        echo ""
        echo "Opção 1: Instalar Homebrew primeiro"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo ""
        echo "Opção 2: Instalar OpenSSL via MacPorts"
        echo "  sudo port install openssl"
        echo ""
        echo "Opção 3: Baixar do site oficial"
        echo "  https://www.openssl.org/source/"
        exit 1
    fi
    
else
    echo "Sistema operacional não suportado: $OSTYPE"
    exit 1
fi

# Verificar instalação
echo ""
echo "Verificando instalação..."
if command -v openssl &> /dev/null; then
    OPENSSL_VERSION=$(openssl version)
    echo "✓ OpenSSL instalado com sucesso!"
    echo "Versão: $OPENSSL_VERSION"
    echo ""
    echo "========================================"
    echo "  PRONTO! O sistema detectará automaticamente"
    echo "========================================"
else
    echo "✗ Erro: OpenSSL não foi instalado corretamente"
    exit 1
fi




