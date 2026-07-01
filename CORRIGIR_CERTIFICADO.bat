@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    ASSISTENTE DE CORRECAO DO CERTIFICADO
echo ============================================
echo.
echo Vou te ajudar a resolver o problema do
echo certificado passo a passo.
echo.
pause

:menu
cls
echo.
echo ============================================
echo    O QUE ESTA ACONTECENDO?
echo ============================================
echo.
echo 1. Erro HTTP 400 ao emitir NFC-e
echo 2. Bridge online mas nao emite
echo 3. Quero verificar se certificado esta salvo
echo 4. Sair
echo.
set /p opcao="Escolha uma opcao (1-4): "

if "%opcao%"=="1" goto erro400
if "%opcao%"=="2" goto bridge_online
if "%opcao%"=="3" goto verificar
if "%opcao%"=="4" exit /b

goto menu

:erro400
cls
echo.
echo ============================================
echo    ERRO HTTP 400 - CAUSAS COMUNS
echo ============================================
echo.
echo O erro HTTP 400 da SEFAZ geralmente significa:
echo.
echo 1. CSC (Codigo de Seguranca) INVALIDO
echo    - CSC nao pode ser "1"
echo    - CSC deve ter 36 caracteres (token da SEFAZ)
echo.
echo 2. CERTIFICADO NAO ENVIADO
echo    - Certificado nao foi salvo na empresa
echo    - Certificado em formato errado (PEM ao inves de PFX)
echo.
echo 3. SENHA INCORRETA
echo    - Senha do certificado esta errada
echo.
echo 4. CERTIFICADO SEM CHAVE PRIVADA
echo    - Exportado sem "Incluir chave privada"
echo.
echo.
echo ============================================
echo    SOLUCAO PASSO A PASSO
echo ============================================
echo.
echo PASSO 1: Verificar CSC
echo ------------------------
echo Acesse: https://www.fazenda.sp.gov.br/
echo (ou o site da SEFAZ do seu estado)
echo.
echo 1. Faca login com certificado digital
echo 2. Va em: NFC-e ^> Codigo de Seguranca (CSC)
echo 3. Gere um novo CSC (se nao tiver)
echo 4. Copie o codigo COMPLETO (36 caracteres)
echo.
echo PASSO 2: Corrigir no App
echo ------------------------
echo 1. Abra o app Flutter
echo 2. Va em: Empresas ^> Editar
echo 3. No campo CSC, cole o codigo de 36 caracteres
echo 4. Salve
echo.
echo PASSO 3: Testar
echo ------------------------
echo 1. Reinicie o Bridge (clique direito no icone ^> Reiniciar)
echo 2. Tente emitir uma NFC-e de teste
echo.
pause
goto menu

:bridge_online
cls
echo.
echo ============================================
echo    BRIDGE ONLINE MAS NAO EMITE
echo ============================================
echo.
echo O Bridge esta verde (online) mas nao consegue
echo emitir porque:
echo.
echo 1. Certificado nao esta chegando ao Bridge
echo 2. Bridge nao consegue ler o certificado do Windows
echo.
echo ============================================
echo    SOLUCAO RECOMENDADA
echo ============================================
echo.
echo Opcao A - Usar Certificado do Windows:
echo -----------------------------------------
echo 1. No app, va em Empresas ^> Editar
echo 2. Selecione "Usar certificado instalado no Windows"
echo 3. Escolha o certificado da BMJ
echo 4. Digite a senha
echo 5. Salve
echo.
echo Opcao B - Exportar Certificado Manualmente:
echo --------------------------------------------
echo 1. Abra: Certmgr.msc (Gerenciador de Certificados)
echo 2. Va em: Pessoal ^> Certificados
echo 3. Encontre o certificado da empresa
echo 4. Clique direito ^> Todas as Tarefas ^> Exportar
echo 5. MARQUE: "Incluir chave privada"
echo 6. Formato: PFX
echo 7. Salve em: C:\ExodoNFCe\certificado.pfx
echo 8. Anote a senha usada
echo.
echo Opcao C - Verificar se Certificado esta Salvo:
echo -----------------------------------------------
echo Execute o app em modo DEBUG e procure no console:
echo    "certificadoDigitalBytes: presente"
echo Se aparecer "null", o certificado nao esta salvo!
echo.
pause
goto menu

:verificar
echo.
echo ============================================
echo    VERIFICAR CERTIFICADO (DEBUG)
echo ============================================
echo.
echo Para verificar se o certificado esta salvo:
echo.
echo 1. Execute o Flutter em modo DEBUG:
echo    flutter run -v
echo.
echo 2. No app, va em Empresas ^> Editar
echo 3. Abra o console do navegador (F12)
echo 4. Procure por:
echo    - "certificadoDigitalBytes"
echo    - "Certificado presente"
echo.
echo 3. Se ver "null", o certificado NAO esta salvo.
echo    Voce precisa selecionar novamente.
echo.
echo 4. Para salvar corretamente:
echo    - Use "Importar Certificado Digital (Arquivo)"
echo    - Selecione o arquivo .pfx
echo    - Digite a senha
echo    - Aguarde "Certificado carregado com sucesso"
echo    - Salve a empresa
echo.
pause
goto menu
