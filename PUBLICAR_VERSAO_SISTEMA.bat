@echo off
title Publicar Versao do Sistema - Exodo
chcp 65001 >nul
cls

echo ==================================================
echo   PUBLICADOR UNIFICADO DE VERSAO - EXODO
echo ==================================================
echo.

REM Verificar se Python esta instalado
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python nao esta instalado ou nao foi encontrado no PATH.
    echo Por favor, instale o Python antes de continuar.
    pause
    exit /b 1
)

REM Executar script python
python publicar_atualizacao_sistema.py

echo.
echo ==================================================
echo Processo finalizado.
echo ==================================================
pause
