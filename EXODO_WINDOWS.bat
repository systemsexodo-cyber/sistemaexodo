@echo off
color 0b
echo ==============================================
echo  INICIANDO SISTEMA EXODO (WINDOWS)
echo ==============================================
echo.

set PATH=C:\src\flutter\bin;%PATH%

flutter doctor > nul 2>&1
echo Iniciando o aplicativo Windows...
flutter run -d windows
pause
