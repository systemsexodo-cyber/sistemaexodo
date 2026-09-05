@echo off
REM Script de instalacao do PostgreSQL usando Chocolatey
REM Execute como Administrador

cls
echo.
echo ========================================
echo   INSTALACAO DO POSTGRESQL
echo ========================================
echo.

REM Verificar se eh Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERRO] Este script requer privilegios de Administrador!
    echo Execute o Prompt de Comando como Administrador e tente novamente.
    pause
    exit /b 1
)

REM Verificar Chocolatey
echo [1/3] Verificando Chocolatey...
where choco >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [INFO] Chocolatey nao encontrado. Instalando...
    echo.
    powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
) else (
    echo [OK] Chocolatey encontrado
)

REM Instalar PostgreSQL
echo.
echo [2/3] Instalando PostgreSQL...
echo.
choco install postgresql --version=15.0 -y

REM Verificar instalacao
echo.
echo [3/3] Verificando PostgreSQL...
psql --version

if %errorLevel% neq 0 (
    echo.
    echo [ERRO] PostgreSQL nao foi instalado corretamente.
    pause
    exit /b 1
) else (
    echo [OK] PostgreSQL instalado com sucesso!
)

REM Criar arquivo .env
if not exist ".env" (
    echo.
    echo [CRIANDO] Arquivo .env...
    (
        echo DB_HOST=localhost
        echo DB_PORT=5432
        echo DB_NAME=exodo_db
        echo DB_USER=exodo_user
        echo DB_PASSWORD=senha123
        echo.
        echo DATABASE_URL=postgresql://exodo_user:senha123@localhost:5432/exodo_db
        echo SQLALCHEMY_ECHO=false
    ) > .env
    echo [OK] Arquivo .env criado
) else (
    echo [INFO] Arquivo .env ja existe
)

REM Instrucoes finais
echo.
echo ========================================
echo PROXIMAS ETAPAS:
echo ========================================
echo.
echo 1. Criar banco de dados (execute como Administrador):
echo.
echo    psql -U postgres
echo.
echo    Dentro do prompt psql, execute:
echo.
echo    CREATE USER exodo_user WITH PASSWORD 'senha123';
echo    CREATE DATABASE exodo_db OWNER exodo_user;
echo    GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
echo    ALTER ROLE exodo_user CREATEDB;
echo    \q
echo.
echo 2. Instalar driver Python:
echo.
echo    cd backend_pynfe
echo    pip install psycopg2-binary
echo.
echo 3. Testar conexao:
echo.
echo    python ../test_postgres_connection.py
echo.
echo [OK] PostgreSQL instalado! Siga as instrucoes acima.
echo.
pause
