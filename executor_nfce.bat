@echo off
title Iniciar Emissor NFC-e Grátis
echo ===========================================
echo   SISTEMA EXODO - EMISSOR NFC-e GRÁTIS
echo ===========================================
cd backend_nfce
echo Instalando dependências necessárias...
pip install fastapi uvicorn pynfe cryptography firebase-admin
echo.
echo Iniciando servidor na porta 8000...
python main.py
pause
