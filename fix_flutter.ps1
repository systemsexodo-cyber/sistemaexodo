# ============================================================================
# Script de Correção de Problemas do Flutter
# ============================================================================
# Use este script quando o Flutter apresentar erros de "pub upgrade"
# ou "caminho não encontrado"
# ============================================================================

Write-Host "============================================================" -ForegroundColor Red
Write-Host "  Correção de Problemas do Flutter" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""

$ErrorActionPreference = "SilentlyContinue"

# ============================================================================
# PASSO 1: Matar todos os processos Flutter/Dart
# ============================================================================
Write-Host "[PASSO 1/6] Encerrando processos Flutter/Dart..." -ForegroundColor Yellow

$processes = Get-Process | Where-Object { $_.Name -like '*flutter*' -or $_.Name -like '*dart*' }
if ($processes) {
    $processes | Stop-Process -Force
    Write-Host "[OK] Processos encerrados: $($processes.Count)" -ForegroundColor Green
    Start-Sleep -Seconds 3
}
else {
    Write-Host "[INFO] Nenhum processo em execução" -ForegroundColor Gray
}

# ============================================================================
# PASSO 2: Encontrar diretório do Flutter
# ============================================================================
Write-Host "`n[PASSO 2/6] Localizando Flutter..." -ForegroundColor Yellow

try {
    $flutterCmd = Get-Command flutter -ErrorAction Stop
    $flutterPath = Split-Path (Split-Path $flutterCmd.Source -Parent)
    Write-Host "[OK] Flutter encontrado em: $flutterPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERRO] Flutter não encontrado no PATH!" -ForegroundColor Red
    pause
    exit 1
}

# ============================================================================
# PASSO 3: Remover lock files
# ============================================================================
Write-Host "`n[PASSO 3/6] Removendo arquivos de bloqueio..." -ForegroundColor Yellow

$lockFiles = @(
    "$flutterPath\bin\cache\flutter.bat.lock",
    "$flutterPath\bin\cache\lockfile"
)

foreach ($lockFile in $lockFiles) {
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
        Write-Host "[OK] Removido: $lockFile" -ForegroundColor Green
    }
}

# ============================================================================
# PASSO 4: Verificar e corrigir Dart SDK
# ============================================================================
Write-Host "`n[PASSO 4/6] Verificando Dart SDK..." -ForegroundColor Yellow

$dartSdkPath = "$flutterPath\bin\cache\dart-sdk"
$dartExePath = "$dartSdkPath\bin\dart.exe"

if (Test-Path $dartExePath) {
    Write-Host "[OK] Dart SDK válido" -ForegroundColor Green
}
else {
    Write-Host "[ERRO] Dart SDK corrompido!" -ForegroundColor Red
    Write-Host "[INFO] Corrigindo..." -ForegroundColor Yellow
    
    # Remover dart-sdk corrompido
    if (Test-Path $dartSdkPath) {
        Write-Host "[INFO] Removendo Dart SDK corrompido..." -ForegroundColor Yellow
        Remove-Item $dartSdkPath -Recurse -Force
    }
    
    # Remover stamps
    Write-Host "[INFO] Removendo arquivos stamp..." -ForegroundColor Yellow
    Remove-Item "$flutterPath\bin\cache\*.stamp" -Force
    
    Write-Host "[INFO] Forçando download do Dart SDK..." -ForegroundColor Yellow
    Write-Host "[INFO] Aguarde, isso pode demorar alguns minutos..." -ForegroundColor Yellow
}

# ============================================================================
# PASSO 5: Executar flutter doctor
# ============================================================================
Write-Host "`n[PASSO 5/6] Executando flutter doctor..." -ForegroundColor Yellow
Write-Host ""

flutter doctor

# ============================================================================
# PASSO 6: Verificar correção
# ============================================================================
Write-Host "`n[PASSO 6/6] Verificando correção..." -ForegroundColor Yellow

if (Test-Path "$dartSdkPath\bin\dart.exe") {
    Write-Host "[OK] Dart SDK instalado corretamente!" -ForegroundColor Green
    
    # Testar flutter --version
    Write-Host "`n[INFO] Testando Flutter..." -ForegroundColor Yellow
    flutter --version
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n============================================================" -ForegroundColor Green
        Write-Host "  Correção concluída com sucesso!" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "[INFO] Flutter está pronto para uso!" -ForegroundColor Green
    }
    else {
        Write-Host "`n[ERRO] Flutter ainda apresenta problemas" -ForegroundColor Red
    }
}
else {
    Write-Host "[ERRO] Falha na correção automática" -ForegroundColor Red
    Write-Host "[INFO] Tente reinstalar o Flutter manualmente" -ForegroundColor Yellow
}

Write-Host ""
pause
