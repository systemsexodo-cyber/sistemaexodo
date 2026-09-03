; ============================================================================
; 🚀 Instalador do Sistema Êxodo Completo
; Inno Setup Script - v1.0.35
; Design Profissional
; ============================================================================
; INSTRUÇÕES:
; ============================================================================
; 1. Tenha o Inno Setup instalado: https://jrsoftware.org/isdl.php
; 2. PostgreSQL ZIP extraído em: postgresql\pgsql\bin\initdb.exe (deve ter bin, lib E share\postgres.bki!)
; 3. App compilado: flutter build windows --release
; 4. Bridge na pasta: backend_nfce\dist\ExodoNfceBridge.exe
; 5. IMPORTANTE: copie para build\windows\x64\runner\Release\ as DLLs do VC Runtime
;    (vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll do C:\Windows\System32)
;    - isso garante que a máquina nova (sem Flutter/VC) rode o app sem erro;
;    - se a pasta Release for regenerada (flutter clean + build), recopie as DLLs.
; 6. Compile (F9) no Inno Setup Compiler
; ============================================================================

#define MyAppName "Sistema Êxodo"
#define MyAppVersion "1.0.36"
#define MyAppPublisher "Sistema Êxodo Tecnologia"
#define MyAppURL "https://febffvlpvxtiihvnfuts.supabase.co"
#define MyAppExeName "sistema_exodo_novo.exe"

[Setup]
; Identificação
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Diretórios
DefaultDirName=C:\SistemaExodo
DefaultGroupName=Sistema Êxodo
DisableProgramGroupPage=yes

; Saída
OutputDir=dist\instalador
OutputBaseFilename=Setup_Sistema_Exodo_v{#MyAppVersion}

; Compressão
Compression=lzma2/max
SolidCompression=yes
InternalCompressLevel=max

; Aparência
WizardStyle=modern
WizardResizable=no
WizardImageFile=assets\wizard.bmp
WizardSmallImageFile=assets\wizard_small.bmp
SetupIconFile=exodo_logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} v{#MyAppVersion}

; Permissões e arquitetura
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

; Comportamento
DisableWelcomePage=no
DisableFinishedPage=no
DisableReadyPage=no
AlwaysShowDirOnReadyPage=yes
ShowComponentSizes=no
RestartIfNeededByRun=no

; Idiomas
[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

; ============================================================================
; MENSAGENS PERSONALIZADAS
; ============================================================================

[Messages]
; Welcome page
WelcomeLabel1=Bem-vindo ao Instalador do [name]
WelcomeLabel2=Este assistente vai instalar o [name/ver] no seu computador.%n%nO sistema inclui:%n• Sistema Êxodo (PDV + Gestão)%n• PostgreSQL 16 (banco de dados)%n• Bridge NFC-e (nota fiscal)%n%nA instalação pode levar alguns minutos.

; Finished page
FinishedHeadingLabel=Instalação Concluída com Sucesso!
FinishedLabelNoRun=A instalação foi concluída com sucesso!%n%nO Sistema Êxodo está pronto para uso.%n%nImportante:%n• O PostgreSQL foi configurado como serviço do Windows%n• O Bridge NFC-e está instalado em segundo plano
FinishedLabel=Clique em "Concluir" para finalizar a instalação.

; Buttons
ButtonNext=Avançar >
ButtonInstall=Instalar
ButtonFinish=Concluir
ButtonCancel=Cancelar

; ClickNext
ClickNext=Clique em "Avançar" para continuar.

; Dir
SelectDirDesc=Onde o Sistema Êxodo será instalado?
SelectDirLabel3=O instalador irá instalar o sistema em:

; Ready
ReadyLabel1=Pronto para Instalar
ReadyLabel2a=O instalador está pronto para instalar o Sistema Êxodo no seu computador.
ReadyLabel2b=Clique em "Instalar" para começar.

; Status
StatusInstalling=Instalando o Sistema Êxodo...
StatusExtractFiles=Extraindo arquivos...

; ============================================================================
; DIRETÓRIOS
; ============================================================================

[Dirs]
Name: "{app}\data"
Name: "{app}\pgdata"
Name: "{app}\scripts"
Name: "{app}\logs"
Name: "{app}\postgresql"
Name: "{app}\postgresql\bin"
Name: "{app}\postgresql\lib"
Name: "{app}\postgresql\share"
Name: "{app}\bridge"

; ============================================================================
; ARQUIVOS
; ============================================================================

[Files]
; --- App Flutter ---
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.exe"

; --- Visual C++ Runtime (necessário em máquinas sem VC Redistributable) ---
Source: "build\windows\x64\runner\Release\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "build\windows\x64\runner\Release\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "build\windows\x64\runner\Release\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; --- PostgreSQL Embarcado ---
Source: "postgresql\pgsql\bin\*"; DestDir: "{app}\postgresql\bin"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "postgresql\pgsql\lib\*"; DestDir: "{app}\postgresql\lib"; Flags: ignoreversion recursesubdirs createallsubdirs
; IMPORTANTE: a pasta share contém postgres.bki (ESSENCIAL para o initdb criar o banco)
Source: "postgresql\pgsql\share\*"; DestDir: "{app}\postgresql\share"; Flags: ignoreversion recursesubdirs createallsubdirs

; --- Bridge NFC-e ---
Source: "backend_nfce\dist\ExodoNfceBridge.exe"; DestDir: "{app}\bridge"; Flags: ignoreversion skipifsourcedoesntexist
Source: "backend_nfce\dist\ExodoNfceBridgeWatchdog.exe"; DestDir: "{app}\bridge"; Flags: ignoreversion skipifsourcedoesntexist
Source: "backend_nfce\dist\ExodoNfceBridge.exe"; DestDir: "C:\ExodoNFCe"; Flags: ignoreversion skipifsourcedoesntexist

; --- Sincronizador Nuvem (modo onedir - sem pasta temporaria _MEI, sem aviso de limpeza) ---
; Para compilar: execute compilar_sincronizador.bat
; IMPORTANTE: o tray deve ser compilado em modo ONEDIR (compilar_sincronizador.bat).
; skipifsourcedoesntexist: se o onedir nao existir, o instalador ignora (em vez de falhar).
Source: "dist\SincronizadorNuvem\SincronizadorNuvem.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "dist\SincronizadorNuvem\_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

; --- Scripts ---
Source: "scripts\setup_postgres.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\init_db.sql"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\abrir_pgadmin.bat"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\iniciar_postgres.bat"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\reparar_banco.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\reparar_banco.bat"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\migrar_schema.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "scripts\migrar_schema.bat"; DestDir: "{app}\scripts"; Flags: ignoreversion
; --- Backup automatico ---
Source: "backup_postgresql.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "AGENDAR_BACKUP_AUTOMATICO.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "BACKUP_EMERGENCIA.bat"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "RESTAURAR_BACKUP.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; --- Config ---
Source: ".env.example"; DestDir: "{app}"; DestName: ".env"; Flags: ignoreversion

; ============================================================================
; ATALHOS
; ============================================================================

[Icons]
; Menu Iniciar
Name: "{group}\⚡ Sistema Êxodo"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "Sistema de Gestão e PDV"
Name: "{group}\🌐 Bridge NFC-e"; Filename: "{app}\bridge\ExodoNfceBridge.exe"; WorkingDir: "{app}\bridge"; Comment: "Configurar Bridge NFC-e"
Name: "{group}\🔄 Sincronizador Nuvem"; Filename: "{app}\SincronizadorNuvem.exe"; WorkingDir: "{app}"; Comment: "Sincronizador em segundo plano"
Name: "{group}\📊 pgAdmin 4 - Ver Banco"; Filename: "{app}\scripts\abrir_pgadmin.bat"; WorkingDir: "{app}"; Comment: "Visualizar dados do banco"
Name: "{group}\🔧 Reparar Banco (criar exodo_db)"; Filename: "{app}\scripts\reparar_banco.bat"; WorkingDir: "{app}\scripts"; Comment: "Cria o banco exodo_db e as tabelas se nao existirem"
Name: "{group}\📁 Pasta do Sistema"; Filename: "{app}"; WorkingDir: "{app}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"

; Área de Trabalho (criado SEMPRE)
Name: "{commondesktop}\⚡ Sistema Êxodo"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "Sistema de Gestão e PDV"
Name: "{group}\🛠 Iniciar PostgreSQL"; Filename: "{app}\scripts\iniciar_postgres.bat"; WorkingDir: "{app}\scripts"; Comment: "Iniciar banco de dados manualmente"; Flags: runminimized

; ============================================================================
; AÇÕES PÓS-INSTALAÇÃO
; ============================================================================

[Run]
; 1. Configurar PostgreSQL
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\setup_postgres.ps1"" -PostgresDir ""{app}\postgresql"" -DataDir ""{app}\pgdata"" -AppDir ""{app}"""; StatusMsg: "🐘 Configurando banco de dados PostgreSQL... (pode levar alguns minutos)"

; 1b. Agendar backup automatico (diario 03:00 + inicializacao)
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\AGENDAR_BACKUP_AUTOMATICO.ps1"" -Silencioso"; StatusMsg: "Agendando backup automatico do banco (diario as 03:00)..."; Flags: runhidden
; 2. Iniciar Sincronizador Nuvem
Filename: "{app}\SincronizadorNuvem.exe"; Parameters: ""; StatusMsg: "🔄 Iniciando Sincronizador Nuvem..."; Flags: nowait skipifdoesntexist runhidden

; 3. Iniciar Bridge NFC-e
Filename: "{app}\bridge\ExodoNfceBridge.exe"; Parameters: ""; StatusMsg: "🔌 Iniciando Bridge NFC-e..."; Flags: nowait skipifdoesntexist runhidden

; 4. Executar app (opcional)
Filename: "{app}\{#MyAppExeName}"; Description: "🚀 Iniciar Sistema Êxodo agora"; Flags: nowait postinstall skipifsilent

; ============================================================================
; REGISTRO
; ============================================================================

[Registry]
; Adicionar PostgreSQL ao PATH do sistema
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\postgresql\bin"; \
    Check: NeedsAddPath('{app}\postgresql\bin')

; Iniciar Sincronizador automaticamente com o Windows
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
    ValueType: string; ValueName: "SincronizadorExodo"; \
    ValueData: "{app}\SincronizadorNuvem.exe"; \
    Flags: uninsdeletevalue; Check: FileExists(ExpandConstant('{app}\SincronizadorNuvem.exe'))

; ============================================================================
; DESINSTALAÇÃO
; ============================================================================

[UninstallRun]
; Parar Sincronizador
Filename: "taskkill.exe"; Parameters: "/F /IM SincronizadorNuvem.exe"; Flags: runhidden skipifdoesntexist
; Parar Bridge
Filename: "taskkill.exe"; Parameters: "/F /IM ExodoNfceBridge.exe"; Flags: runhidden skipifdoesntexist
; Parar PostgreSQL
Filename: "{app}\postgresql\bin\pg_ctl.exe"; Parameters: "-D ""{app}\pgdata"" stop -m fast"; Flags: runhidden
Filename: "sc.exe"; Parameters: "delete PostgreSQL_Exodo"; Flags: runhidden
; Remover tarefas de backup agendadas
Filename: "powershell.exe"; Parameters: "-NoProfile -Command ""Unregister-ScheduledTask -TaskName 'Exodo Backup Diario' -Confirm:$false -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName 'Exodo Backup Inicializacao' -Confirm:$false -ErrorAction SilentlyContinue"""; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\pgdata"
Type: filesandordirs; Name: "{app}\logs"

; ============================================================================
; CÓDIGO PERSONALIZADO
; ============================================================================

[Code]

// Verificar se o PATH já contém o diretório
function NeedsAddPath(Param: string): Boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKLM,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;

// Personalizar página de boas-vindas
procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel1.Font.Size := 14;
  
  // Adicionar crédito na página de confirmação
  WizardForm.PageDescriptionLabel.Caption := 'Sistema Êxodo - Gestão Completa para seu Negócio';
end;

// Verifica se o PostgreSQL esta respondendo na porta 5432
function IsPostgresRunning(): Boolean;
var
  ResultCode: Integer;
begin
  // netstat nao requer privilegios e funciona em todos os idiomas
  // O espaco apos 5432 evita falso positivo com portas como 54321
  if Exec('cmd.exe', '/c netstat -ano | findstr /C:":5432 " >nul 2>&1', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) then
  begin
    Result := (ResultCode = 0);
  end
  else
  begin
    Result := False;
  end;
end;

// Ações após instalação
procedure CurStepChanged(CurStep: TSetupStep);
var
  EnvFilePath: String;
  Tentativa: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    EnvFilePath := ExpandConstant('{app}\.env');
    if FileExists(EnvFilePath) then
    begin
      Log('✅ .env configurado em: ' + EnvFilePath);
    end;

    // Aguardar o PostgreSQL subir (pode levar alguns segundos apos o setup)
    for Tentativa := 1 to 6 do
    begin
      if IsPostgresRunning() then Break;
      Sleep(3000);
    end;

    if not IsPostgresRunning() then
    begin
      MsgBox('O PostgreSQL nao subiu automaticamente.' + #13#10 +
        'Use o atalho "Iniciar PostgreSQL" (Menu Iniciar > Sistema Exodo)' + #13#10 +
        'ou execute como Administrador: ' + #13#10 +
        ExpandConstant('{app}\scripts\iniciar_postgres.bat') + #13#10 + #13#10 +
        'Se continuar com problemas, veja o log: ' + #13#10 +
        ExpandConstant('{app}\logs\postgres_install.log'),
        mbInformation, MB_OK);
    end;
  end;
end;

// Verificar se pode desinstalar
function InitializeUninstall: Boolean;
begin
  Result := True;
end;

// Mostrar mensagem ao desinstalar
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    MsgBox('O Sistema Êxodo foi removido com sucesso.', mbInformation, MB_OK);
  end;
end;
