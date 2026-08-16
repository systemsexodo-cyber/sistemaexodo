@echo off
title Backup Manual - Sistema Exodo
echo ========================================
echo   BACKUP MANUAL - SISTEMA EXODO
echo ========================================
echo.
echo Iniciando backup do PostgreSQL...
powershell -ExecutionPolicy Bypass -File "%~dp0backup_postgresql.ps1" -Modo completo
echo.
if %errorlevel% equ 0 (
    echo Backup concluido com sucesso!
) else (
    echo Backup falhou!
)
echo.
pause
