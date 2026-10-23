@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM ===================================================================
REM  GERAR_APK.bat - Compila o APK do sistema (Android)
REM
REM  Use:  GERAR_APK.bat          -> APK de TESTE (debug)
REM        GERAR_APK.bat release  -> APK de PRODUCAO (release, assinado
REM                                   com a chave de debug - trocar depois)
REM ===================================================================

REM --- Caminhos das ferramentas instaladas nesta maquina ---
set "JAVA_HOME=C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
set "ANDROID_HOME=C:\Android\Sdk"
set "PATH=%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"

REM --- Caches do Gradle no drive F: (o C: estava quase cheio) ---
REM Se o F: nao existir, o Gradle usa o padrao (C:\Users\<voce>\.gradle).
if exist "F:\gradle-home" (
  set "GRADLE_USER_HOME=F:\gradle-home"
  echo Caches do Gradle em: F:\gradle-home
)

if not exist "%ANDROID_HOME%" (
  echo [ERRO] Android SDK nao encontrado em "%ANDROID_HOME%".
  echo        Instale o SDK ou ajuste ANDROID_HOME neste arquivo.
  pause
  exit /b 1
)

echo.
echo ==================================================
echo   Gerando APK do Sistema Exodo
echo ==================================================
echo.

if /I "%~1"=="release" (
  echo Modo: RELEASE ^(producao^)
  call flutter build apk --release
) else (
  echo Modo: DEBUG ^(teste - instala direto no celular^)
  call flutter build apk --debug
)

echo.
if exist "build\app\outputs\flutter-apk\*.apk" (
  echo ==================================================
  echo   APK gerado com sucesso!
  echo ==================================================
  dir /b "build\app\outputs\flutter-apk\*.apk"
  echo.
  echo Local: build\app\outputs\flutter-apk\
  echo Copie o .apk para o celular e instale.
) else (
  echo [ERRO] O APK nao foi gerado. Veja as mensagens acima.
)

echo.
pause
