@echo off
title Corrigir Numero de Venda - Sistema Exodo
chcp 65001 >nul
echo.
echo ============================================================
echo   CORRIGINDO NUMERO DE VENDA NO BANCO LOCAL
echo ============================================================
echo.

cd /d "%~dp0"

REM Tenta usar o python do venv primeiro
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" CORRIGIR_NUMERO_VENDA_LOCAL.py
) else if exist "venv\Scripts\python.exe" (
    "venv\Scripts\python.exe" CORRIGIR_NUMERO_VENDA_LOCAL.py
) else (
    python CORRIGIR_NUMERO_VENDA_LOCAL.py
)

if errorlevel 1 (
    echo.
    echo ERRO ao executar o script!
    pause
)
