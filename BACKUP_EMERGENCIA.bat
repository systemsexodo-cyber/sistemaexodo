@echo off
chcp 65001 >/dev/null
title Backup Emergencia - Sistema Exodo
setlocal

rem ============================================================
rem   BACKUP DE EMERGENCIA - SISTEMA EXODO
rem   Salva o banco local (exodo_db) em um arquivo .dump
rem   para guardar em pendrive/nuvem e restaurar depois.
rem
rem   USO:
rem     BACKUP_EMERGENCIA.bat
rem       -> salva em .\backups_postgresql\
rem     BACKUP_EMERGENCIA.bat D:\backups\meucliente
rem       -> salva em D:\backups\meucliente\
rem ============================================================

set "DEST=%~1"
if "%DEST%"=="" set "DEST=%~dp0backups_postgresql"

if not exist "%DEST%" mkdir "%DEST%"

echo.
echo ============================================
echo   BACKUP DE EMERGENCIA - SISTEMA EXODO
echo ============================================
echo.
echo Destino: %DEST%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_postgresql.ps1" -DiretorioBackup "%DEST%" -Modo completo

echo.
if %errorlevel% equ 0 (
    echo ============================================
    echo   BACKUP CONCLUIDO COM SUCESSO!
    echo ============================================
    echo.
    echo Arquivos salvos em: %DEST%
    echo Copie o .dump para um pendrive ou nuvem.
) else (
    echo ============================================
    echo   ERRO: backup falhou. Veja as mensagens acima.
    echo ============================================
)
echo.
pause