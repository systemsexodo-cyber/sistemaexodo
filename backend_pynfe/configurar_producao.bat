@echo off
REM ============================================
REM Script de Configuração de Produção - Windows
REM ============================================

echo ========================================
echo Configurando Backend NFC-e para PRODUCAO
echo ========================================
echo.

REM Verificar se está no diretório correto
if not exist "app.py" (
    echo ERRO: app.py nao encontrado!
    echo Execute este script no diretorio backend_pynfe
    pause
    exit /b 1
)

REM 1. Ativar ambiente virtual
if exist "venv\Scripts\activate.bat" (
    echo [1/6] Ativando ambiente virtual...
    call venv\Scripts\activate.bat
) else (
    echo [1/6] Criando ambiente virtual...
    python -m venv venv
    call venv\Scripts\activate.bat
)

REM 2. Instalar/Atualizar dependências
echo.
echo [2/6] Instalando dependencias...
pip install --upgrade pip
pip install -r requirements.txt
if errorlevel 1 (
    echo ERRO: Falha ao instalar dependencias
    pause
    exit /b 1
)

REM 3. Verificar .env.production
echo.
echo [3/6] Verificando configuracoes...
if not exist ".env.production" (
    echo AVISO: .env.production nao encontrado!
    echo Criando arquivo de exemplo...
    if exist ".env.production.example" (
        REM Copiar usando PowerShell para garantir codificacao UTF-8
        powershell -Command "$content = Get-Content '.env.production.example' -Raw -Encoding UTF8; $utf8 = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText((Resolve-Path '.env.production'), $content, $utf8)"
        echo Arquivo .env.production criado em UTF-8
        echo.
        echo IMPORTANTE: Configure o arquivo .env.production antes de continuar!
        echo Edite o arquivo e configure SECRET_KEY e outras variaveis.
        pause
    ) else (
        echo ERRO: .env.production.example nao encontrado!
        pause
        exit /b 1
    )
) else (
    echo .env.production encontrado
)

REM 4. Gerar SECRET_KEY se necessário
echo.
echo [4/6] Verificando SECRET_KEY...
findstr /C:"GERE-UMA-CHAVE-SECRETA-FORTE-AQUI" .env.production >nul 2>&1
if %errorlevel% == 0 (
    echo Gerando SECRET_KEY...
    for /f "delims=" %%i in ('python -c "import secrets; print(secrets.token_hex(32))"') do set SECRET_KEY=%%i
    REM Substituir mantendo codificacao UTF-8
    powershell -Command "$content = Get-Content '.env.production' -Raw -Encoding UTF8; $content = $content -replace 'GERE-UMA-CHAVE-SECRETA-FORTE-AQUI', '%SECRET_KEY%'; $utf8 = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText((Resolve-Path '.env.production'), $content, $utf8)"
    echo SECRET_KEY gerada e configurada
) else (
    echo SECRET_KEY ja configurada
)

REM 5. Criar diretórios necessários
echo.
echo [5/6] Criando diretorios...
if not exist "logs" mkdir logs
if not exist "logs\backups" mkdir logs\backups
if not exist "logs\empresas" mkdir logs\empresas
echo Diretorios criados

REM 6. Verificar instalação
echo.
echo [6/6] Verificando instalacao...
python -c "from app import app; print('OK: App importado com sucesso')" 2>nul
if errorlevel 1 (
    echo AVISO: Erro ao importar app (pode ser normal se faltar dependencias)
) else (
    echo OK: Aplicacao testada
)

echo.
echo ========================================
echo Configuracao concluida!
echo ========================================
echo.
echo Para iniciar o servidor de producao:
echo   start_production.bat
echo.
echo Ou manualmente:
echo   python wsgi.py
echo.
pause




