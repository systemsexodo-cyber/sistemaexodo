#!/bin/bash

echo "========================================"
echo "  CONVERSOR DE CERTIFICADO PFX PARA PEM"
echo "========================================"
echo

# Verificar se OpenSSL está disponível
if ! command -v openssl &> /dev/null; then
    echo "[ERRO] OpenSSL não encontrado!"
    echo
    echo "Por favor, instale o OpenSSL:"
    echo "  - Ubuntu/Debian: sudo apt-get install openssl"
    echo "  - macOS: brew install openssl"
    echo "  - Ou use o gerenciador de pacotes do seu sistema"
    echo
    exit 1
fi

echo "[OK] OpenSSL encontrado!"
echo

# Solicitar arquivo PFX
read -p "Digite o caminho completo do arquivo PFX: " arquivo_pfx

if [ ! -f "$arquivo_pfx" ]; then
    echo "[ERRO] Arquivo não encontrado: $arquivo_pfx"
    exit 1
fi

echo
read -sp "Digite a senha do certificado PFX: " senha
echo
echo

# Obter diretório e nome base
diretorio=$(dirname "$arquivo_pfx")
nome_base=$(basename "$arquivo_pfx" .pfx)
nome_base=$(basename "$nome_base" .p12)

echo "========================================"
echo "  Convertendo certificado..."
echo "========================================"
echo

# Extrair certificado público
echo "[1/2] Extraindo certificado público..."
openssl pkcs12 -in "$arquivo_pfx" -clcerts -nokeys -out "$diretorio/$nome_base.crt" -passin pass:"$senha"

if [ $? -ne 0 ]; then
    echo "[ERRO] Falha ao extrair certificado público!"
    echo "Verifique se a senha está correta."
    exit 1
fi

echo "[OK] Certificado público salvo em: $diretorio/$nome_base.crt"
echo

# Extrair chave privada
echo "[2/2] Extraindo chave privada..."
openssl pkcs12 -in "$arquivo_pfx" -nocerts -nodes -out "$diretorio/${nome_base}_chave_privada.pem" -passin pass:"$senha"

if [ $? -ne 0 ]; then
    echo "[ERRO] Falha ao extrair chave privada!"
    echo "Verifique se a senha está correta."
    exit 1
fi

echo "[OK] Chave privada salva em: $diretorio/${nome_base}_chave_privada.pem"
echo

echo "========================================"
echo "  CONVERSÃO CONCLUÍDA COM SUCESSO!"
echo "========================================"
echo
echo "Arquivos gerados:"
echo "  - $nome_base.crt (certificado público)"
echo "  - ${nome_base}_chave_privada.pem (chave privada)"
echo
echo "Localização: $diretorio"
echo
echo "NOTA: A chave privada não tem senha (flag -nodes)."
echo "      Mantenha esses arquivos seguros!"
echo




