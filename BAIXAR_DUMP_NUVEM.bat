@echo off
chcp 65001 >nul
title Baixar Dump PostgreSQL da Nuvem
echo ============================================================
echo   BAIXAR DUMP DA NUVEM (Supabase Storage)
echo ============================================================
echo.

REM ============================================================
REM 1. CARREGAR CREDENCIAIS DO .ENV (C:\SistemaExodo\.env)
REM ============================================================
if not exist "C:\SistemaExodo\.env" (
    echo [ERRO] Arquivo C:\SistemaExodo\.env nao encontrado.
    echo O instalador gera esse arquivo. Se nao existir, reinstale o sistema.
    pause
    exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%a in ("C:\SistemaExodo\.env") do (
    if "%%a"=="SUPABASE_URL" set "URL=%%b"
    if "%%a"=="SUPABASE_ANON_KEY" set "KEY=%%b"
)

if "%URL%"=="" (
    echo [ERRO] SUPABASE_URL nao encontrado no .env.
    pause
    exit /b 1
)
if "%KEY%"=="" (
    echo [ERRO] SUPABASE_ANON_KEY nao encontrado no .env.
    pause
    exit /b 1
)

REM ============================================================
REM 2. INFORMAR A EMPRESA
REM ============================================================
echo Informe o ID da empresa (padrao: Exodo sistemas).
echo.
set /p EMPRESA_ID="ID da empresa [66a880c8-51c7-496f-826b-d2ff9ab8ed2d]: "
if "%EMPRESA_ID%"=="" set "EMPRESA_ID=66a880c8-51c7-496f-826b-d2ff9ab8ed2d"

echo.
echo Buscando dumps na nuvem... (aguarde)
echo.

REM ============================================================
REM 3. LISTAR DUMPS DA EMPRESA
REM ============================================================
set "LIST_FILE=%TEMP%\dumps_lista_%RANDOM%.json"
curl -s -m 30 -X POST "%URL%/storage/v1/object/list/dumps" ^
  -H "apikey: %KEY%" ^
  -H "Authorization: Bearer %KEY%" ^
  -H "Content-Type: application/json" ^
  -d "{\"prefix\":\"%EMPRESA_ID%/\",\"limit\":100,\"offset\":0}" > "%LIST_FILE%"

echo Dumps encontrados na nuvem:
echo ----------------------------
powershell -NoProfile -Command "$j = Get-Content -Raw '%LIST_FILE%' | ConvertFrom-Json; $j | ForEach-Object { $_.name }"
echo ----------------------------

REM ============================================================
REM 4. ESCOLHER QUAL BAIXAR
REM ============================================================
echo.
set /p DUMP_NAME="Nome do dump para baixar (ex: exodo_backup_2026-09-05_115127.dump): "

if "%DUMP_NAME%"=="" (
    echo [ERRO] Nome vazio.
    pause
    exit /b 1
)

set "DESTINO=C:\ExodoBackups\%DUMP_NAME%"
echo.
echo Baixando %DUMP_NAME% para %DESTINO%... (aguarde)
curl -s -m 300 -o "%DESTINO%" "%URL%/storage/v1/object/authenticated/dumps/%EMPRESA_ID%/%DUMP_NAME%" ^
  -H "apikey: %KEY%" ^
  -H "Authorization: Bearer %KEY%"

if exist "%DESTINO%" (
    for %%F in ("%DESTINO%") do set "SZ=%%~zF"
    echo.
    echo ✅ Download concluido: %DESTINO%  (%SZ% bytes)
    echo Para restaurar, abra o app: Backup - Restaurar Dump PostgreSQL
) else (
    echo.
    echo [ERRO] Download falhou. Verifique o nome do dump.
)
echo.
pause