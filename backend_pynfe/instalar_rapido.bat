@echo off
echo ========================================
echo Instalacao Rapida - Apenas Essencial
echo ========================================
echo.

REM Atualizar PATH
for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path') do set "SYSTEM_PATH=%%B"
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path') do set "USER_PATH=%%B"
set "PATH=%SYSTEM_PATH%;%USER_PATH%"

echo Criando ambiente virtual (se nao existir)...
if not exist venv (
    python -m venv venv
)

echo.
echo Ativando ambiente virtual...
call venv\Scripts\activate.bat

echo.
echo Instalando Flask e dependencias basicas...
python -m pip install Flask Flask-CORS python-dotenv --quiet

echo.
echo Criando arquivo .env...
if not exist .env (
    copy .env.example .env >nul 2>&1
)

echo.
echo ========================================
echo Instalacao basica concluida!
echo ========================================
echo.
echo O servidor pode ser iniciado agora (sem PyNFe).
echo Para instalar tudo depois, execute: instalar_tudo.bat
echo.
echo Para iniciar: start_local.bat
echo.
pause


