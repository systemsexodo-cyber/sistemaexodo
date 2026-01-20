@echo off
REM ============================================================================
REM Quick Start - Sistema Exodo
REM Execute este arquivo com duplo clique para setup rapido
REM ============================================================================

echo.
echo ============================================================
echo   Sistema Exodo - Quick Start
echo ============================================================
echo.

REM Verifica se PowerShell existe
where powershell >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERRO] PowerShell nao encontrado!
    pause
    exit /b 1
)

REM Executa o script de setup
echo [INFO] Executando configuracao automatica...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0setup_flutter.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERRO] Falha na configuracao!
    pause
    exit /b 1
)

pause
