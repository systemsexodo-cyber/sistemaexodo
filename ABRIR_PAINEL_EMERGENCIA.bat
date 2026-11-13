@echo off
setlocal
cd /d "%~dp0"
if not exist "%USERPROFILE%\Documents\ExodoLicencasPrivadas\chave_privada_exodo.pem" (
  echo ERRO: chave privada de licenca nao encontrada.
  echo Confira a pasta Documents\ExodoLicencasPrivadas.
  pause
  exit /b 1
)
start "Painel de Licenca Exodo" /min cmd /c "node tools\licencas\painel_emergencia.js"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8797"
echo.
echo Painel aberto no navegador.
echo Para fechar, encerre a janela minimizada "Painel de Licenca Exodo".
endlocal
