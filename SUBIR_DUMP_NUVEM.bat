@echo off
chcp 65001 >nul
title Subir Dump PostgreSQL para a Nuvem
echo ============================================================
echo   SUBIR DUMP PARA A NUVEM (Supabase Storage)
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
REM 2. ESCOLHER O ARQUIVO DUMP
REM ============================================================
echo Escolha o arquivo .dump para subir (ex: C:\ExodoBackups\exodo_backup.dump)
echo.
set /p DUMP_PATH="Caminho do arquivo dump: "

if not exist "%DUMP_PATH%" (
    echo.
    echo [ERRO] Arquivo nao encontrado: %DUMP_PATH%
    echo.
    pause
    exit /b 1
)

for %%F in ("%DUMP_PATH%") do set "DUMP_NAME=%%~nxF"
for %%F in ("%DUMP_PATH%") do set "DUMP_SIZE=%%~zF"

echo.
echo Arquivo: %DUMP_NAME%  (tamanho: %DUMP_SIZE% bytes)
echo.

REM ============================================================
REM 3. INFORMAR A EMPRESA
REM ============================================================
echo Informe o ID da empresa (padrao: Exodo sistemas).
echo.
set /p EMPRESA_ID="ID da empresa [66a880c8-51c7-496f-826b-d2ff9ab8ed2d]: "
if "%EMPRESA_ID%"=="" set "EMPRESA_ID=66a880c8-51c7-496f-826b-d2ff9ab8ed2d"

echo.
echo Enviando para a nuvem... (aguarde)
echo.

REM ============================================================
REM 4. GARANTIR QUE O BUCKET EXISTE
REM ============================================================
curl -s -m 30 -X POST "%URL%/storage/v1/bucket" ^
  -H "apikey: %KEY%" ^
  -H "Authorization: Bearer %KEY%" ^
  -H "Content-Type: application/json" ^
  -d "{\"id\":\"dumps\",\"name\":\"dumps\",\"public\":false}" >nul 2>&1

REM ============================================================
REM 5. ENVIAR O DUMP
REM ============================================================
set "STORAGE_PATH=%EMPRESA_ID%/%DUMP_NAME%"
curl -s -m 300 -X POST "%URL%/storage/v1/object/dumps/%STORAGE_PATH%" ^
  -H "apikey: %KEY%" ^
  -H "Authorization: Bearer %KEY%" ^
  -H "Content-Type: application/octet-stream" ^
  --data-binary "@%DUMP_PATH%"

echo.
echo.
echo ============================================================
echo   RESULTADO ACIMA: se aparecer {"Key":"dumps/..."} = SUCESSO
echo ============================================================
echo.
echo O dump %DUMP_NAME% foi enviado para a nuvem.
echo Em outra maquina, abra o app: Backup - Baixar Dump da Nuvem
echo.
pause