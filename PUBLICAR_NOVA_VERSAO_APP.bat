@echo off
title Publicar Nova Versao - Sistema Exodo
chcp 65001 >nul
cls

echo ==================================================
echo   PUBLICADOR AUTOMÁTICO DE ATUALIZAÇÃO - ÊXODO
echo ==================================================
echo.

:: Verificar se Python está instalado
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python não está instalado ou não foi encontrado no PATH.
    echo Por favor, instale o Python antes de continuar.
    pause
    exit /b 1
)

:: Executar script python
python publicar_atualizacao_app.py

echo.
echo ==================================================
echo Processo finalizado.
echo ==================================================
pause
