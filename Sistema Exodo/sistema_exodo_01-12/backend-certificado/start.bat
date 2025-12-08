@echo off
echo Iniciando Backend de Certificados...
echo.
echo Certifique-se de ter Node.js instalado!
echo.
cd /d %~dp0
if not exist node_modules (
    echo Instalando dependencias...
    call npm install
)
echo.
echo Iniciando servidor na porta 3001...
echo.
call npm start

