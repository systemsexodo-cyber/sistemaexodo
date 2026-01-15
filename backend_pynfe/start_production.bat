@echo off
REM ============================================
REM Script para iniciar servidor de produção no Windows
REM ============================================

echo ========================================
echo Iniciando servidor de PRODUCAO
echo ========================================
echo.

REM Verificar se está no diretório correto
if not exist "app.py" (
    echo ERRO: app.py nao encontrado!
    echo Execute este script no diretorio backend_pynfe
    pause
    exit /b 1
)

REM Verificar .env.production
if not exist ".env.production" (
    echo AVISO: .env.production nao encontrado!
    echo Execute configurar_producao.bat primeiro
    echo.
    pause
    exit /b 1
)

REM Ativar ambiente virtual se existir
if exist "venv\Scripts\activate.bat" (
    echo Ativando ambiente virtual...
    call venv\Scripts\activate.bat
) else (
    echo AVISO: Ambiente virtual nao encontrado!
    echo Criando ambiente virtual...
    python -m venv venv
    call venv\Scripts\activate.bat
    echo Instalando dependencias...
    pip install -r requirements.txt
)

REM Verificar se waitress está instalado
python -c "import waitress" 2>nul
if errorlevel 1 (
    echo.
    echo AVISO: Waitress nao esta instalado!
    echo Instalando waitress...
    pip install waitress>=2.1.2
    if errorlevel 1 (
        echo ERRO: Falha ao instalar waitress
        pause
        exit /b 1
    )
)

REM Carregar variáveis de ambiente do .env.production
if exist ".env.production" (
    echo Carregando configuracoes de .env.production...
    for /f "usebackq tokens=1,2 delims==" %%a in (".env.production") do (
        if not "%%a"=="" if not "%%a"=="#" (
            set "%%a=%%b"
        )
    )
)

echo.
echo Iniciando servidor de producao com Waitress...
echo.

REM Iniciar servidor usando wsgi.py
python wsgi.py

pause

