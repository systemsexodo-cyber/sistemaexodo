#!/bin/bash
echo "Iniciando Backend de Certificados..."
echo ""
echo "Certifique-se de ter Node.js instalado!"
echo ""

cd "$(dirname "$0")"

if [ ! -d "node_modules" ]; then
    echo "Instalando dependências..."
    npm install
fi

echo ""
echo "Iniciando servidor na porta 3001..."
echo ""
npm start

