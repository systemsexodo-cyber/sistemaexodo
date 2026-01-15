@echo off
REM ============================================
REM Script de Verificação de Produção
REM ============================================

echo ========================================
echo Verificando Configuracao de PRODUCAO
echo ========================================
echo.

set ERROS=0

REM 1. Verificar Python
echo [1/8] Verificando Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo   ERRO: Python nao encontrado!
    set /a ERROS+=1
) else (
    python --version
    echo   OK: Python encontrado
)

REM 2. Verificar ambiente virtual
echo.
echo [2/8] Verificando ambiente virtual...
if exist "venv\Scripts\python.exe" (
    echo   OK: Ambiente virtual encontrado
) else (
    echo   AVISO: Ambiente virtual nao encontrado
)

REM 3. Verificar dependências
echo.
echo [3/8] Verificando dependencias...
if exist "venv\Scripts\activate.bat" (
    call venv\Scripts\activate.bat
    python -c "import waitress" 2>nul
    if errorlevel 1 (
        echo   ERRO: Waitress nao instalado!
        set /a ERROS+=1
    ) else (
        echo   OK: Waitress instalado
    )
    
    python -c "import flask" 2>nul
    if errorlevel 1 (
        echo   ERRO: Flask nao instalado!
        set /a ERROS+=1
    ) else (
        echo   OK: Flask instalado
    )
    
    python -c "import nfelib" 2>nul
    if errorlevel 1 (
        echo   AVISO: nfelib nao instalado
    ) else (
        echo   OK: nfelib instalado
    )
) else (
    echo   AVISO: Ambiente virtual nao encontrado, pulando verificacao de dependencias
)

REM 4. Verificar .env.production
echo.
echo [4/8] Verificando .env.production...
if exist ".env.production" (
    echo   OK: .env.production encontrado
    
    REM Verificar SECRET_KEY
    findstr /C:"SECRET_KEY=" .env.production | findstr /V /C:"GERE-UMA-CHAVE" >nul 2>&1
    if errorlevel 1 (
        echo   AVISO: SECRET_KEY nao configurada ou usando valor padrao
    ) else (
        echo   OK: SECRET_KEY configurada
    )
    
    REM Verificar DEBUG
    findstr /C:"DEBUG=False" .env.production >nul 2>&1
    if errorlevel 1 (
        echo   AVISO: DEBUG pode estar habilitado (verificar)
    ) else (
        echo   OK: DEBUG desabilitado
    )
) else (
    echo   ERRO: .env.production nao encontrado!
    set /a ERROS+=1
)

REM 5. Verificar arquivos principais
echo.
echo [5/8] Verificando arquivos principais...
if exist "app.py" (
    echo   OK: app.py encontrado
) else (
    echo   ERRO: app.py nao encontrado!
    set /a ERROS+=1
)

if exist "wsgi.py" (
    echo   OK: wsgi.py encontrado
) else (
    echo   ERRO: wsgi.py nao encontrado!
    set /a ERROS+=1
)

REM 6. Verificar diretórios
echo.
echo [6/8] Verificando diretorios...
if exist "logs" (
    echo   OK: Diretorio logs existe
) else (
    echo   AVISO: Diretorio logs nao existe (sera criado automaticamente)
)

if exist "logs\backups" (
    echo   OK: Diretorio logs\backups existe
) else (
    echo   AVISO: Diretorio logs\backups nao existe
)

REM 7. Testar importação do app
echo.
echo [7/8] Testando importacao do app...
if exist "venv\Scripts\activate.bat" (
    call venv\Scripts\activate.bat
    python -c "from app import app; print('   OK: App importado com sucesso')" 2>nul
    if errorlevel 1 (
        echo   ERRO: Falha ao importar app
        set /a ERROS+=1
    )
) else (
    echo   AVISO: Ambiente virtual nao encontrado, pulando teste
)

REM 8. Verificar scripts
echo.
echo [8/8] Verificando scripts...
if exist "start_production.bat" (
    echo   OK: start_production.bat encontrado
) else (
    echo   AVISO: start_production.bat nao encontrado
)

if exist "wsgi.py" (
    echo   OK: wsgi.py encontrado
) else (
    echo   ERRO: wsgi.py nao encontrado!
    set /a ERROS+=1
)

REM Resumo
echo.
echo ========================================
if %ERROS% == 0 (
    echo Status: TUDO OK!
    echo.
    echo Para iniciar o servidor de producao:
    echo   start_production.bat
) else (
    echo Status: ENCONTRADOS %ERROS% ERRO(S)!
    echo.
    echo Execute configurar_producao.bat para corrigir
)
echo ========================================
echo.
pause


























