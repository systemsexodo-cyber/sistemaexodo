@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    DIAGNOSTICO DO CERTIFICADO DIGITAL
echo ============================================
echo.
echo Este script verifica se o certificado esta
eche sendo salvo e lido corretamente.
echo.
pause

echo.
echo 🔍 Verificando logs do Flutter...
echo.
echo Procure no console do Flutter por:
echo   - "certificadoDigitalBytes"
echo   - "certificado_base64"
echo   - "Certificado presente"
echo.
echo Se nao aparecer "Certificado presente: SIM", 
echo o certificado nao esta sendo salvo.
echo.

echo ============================================
echo Possiveis causas:
echo ============================================
echo.
echo 1. CERTIFICADO NAO SALVO:
echo    - Ao editar empresa, certificado nao e salvo no Supabase
echo.
echo 2. CERTIFICADO NAO CARREGADO:
echo    - Ao carregar empresa, certificado nao vem do Supabase
echo.
echo 3. CERTIFICADO WINDOWS:
echo    - Thumbprint salvo mas sem bytes base64
echo    - Bridge nao consegue ler certificado do Windows
echo.
echo 4. FORMATO INCORRETO:
echo    - Certificado em PEM ao inves de PFX
echo    - Certificado sem chave privada
echo.

echo ============================================
echo SOLUCAO DEFINITIVA:
echo ============================================
echo.
echo Opcao 1 - Usar certificado do ARQUIVO:
echo 1. Vai em Empresas ^> Editar
echo 2. Selecione "Importar Certificado Digital (Arquivo)"
echo 3. Escolha o arquivo .pfx
echo 4. Digite a senha
echo 5. Salve
echo.
echo Opcao 2 - Verificar se salvou:
echo 1. Abra o app em modo DEBUG (flutter run -v)
echo 2. Procure no console:
echo    "certificadoDigitalBytes: presente"
echo 3. Se aparecer "null", nao salvou
echo.
pause
