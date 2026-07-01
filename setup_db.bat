@echo off
setlocal enabledelayedexpansion

set PGUSER=postgres
set PGHOST=localhost
set PGPORT=5432
set PATH=C:\Program Files\PostgreSQL\18\bin;%PATH%

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║       Preparando PostgreSQL para Migracao do Supabase         ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

REM Verificar se psql está disponível
where psql.exe >nul 2>nul
if !errorlevel! neq 0 (
    echo ERRO: psql.exe não encontrado
    exit /b 1
)

echo 1^. Conectando ao PostgreSQL...
echo.

REM Criar arquivo SQL com os comandos
(
    echo CREATE USER IF NOT EXISTS exodo_user WITH PASSWORD 'senha123';
    echo ALTER ROLE exodo_user CREATEDB;
    echo DROP DATABASE IF EXISTS exodo_db;
    echo CREATE DATABASE exodo_db OWNER exodo_user ENCODING 'UTF8';
    echo GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
) > setup_commands.sql

echo 2^. Executando comandos...
psql.exe -f setup_commands.sql

if !errorlevel! equ 0 (
    echo.
    echo SUCESSO: Banco PostgreSQL preparado!
    echo.
    echo Informacoes da conexao:
    echo   - Host: localhost
    echo   - Porta: 5432
    echo   - Banco: exodo_db
    echo   - Usuario: exodo_user
    echo   - Senha: senha123
    echo.
) else (
    echo.
    echo ERRO ao executar comandos
    exit /b 1
)

del setup_commands.sql >nul 2>nul
endlocal
