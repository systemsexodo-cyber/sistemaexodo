# 📄 Script para Envio de XMLs para a Contabilidade - ORGANIZADO POR EMPRESA/MÊS
# Este script escaneia a pasta XML_EMITIDOS, compacta os XMLs por CNPJ/Mês e envia para o Drive.

$ProjectRoot = Get-Location
$XmlBaseFolder = Join-Path $ProjectRoot "backend_nfce\XML_EMITIDOS"
$DartScript = Join-Path $ProjectRoot "lib\scripts\gdrive_backup.dart"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   PREPARANDO XMLs ORGANIZADOS POR EMPRESA" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

if (-not (Test-Path $XmlBaseFolder)) {
    Write-Host "[ERRO] Pasta XML_EMITIDOS não encontrada!" -ForegroundColor Red
    exit
}

# 1. Listar pastas de CNPJ
$Cnpjs = Get-ChildItem -Path $XmlBaseFolder -Directory

foreach ($CnpjDir in $Cnpjs) {
    $Cnpj = $CnpjDir.Name
    Write-Host "`n>>> Empresa (CNPJ): $Cnpj" -ForegroundColor Green
    
    # 2. Listar subpastas (Meses: YYYY-MM)
    $Meses = Get-ChildItem -Path $CnpjDir.FullName -Directory
    
    foreach ($MesDir in $Meses) {
        $MesAno = $MesDir.Name
        Write-Host "   -> Mês: $MesAno" -ForegroundColor White
        
        # 3. Verificar se há arquivos XML
        $Files = Get-ChildItem -Path "$($MesDir.FullName)\*.xml"
        if ($null -eq $Files -or $Files.Count -eq 0) {
            Write-Host "      [PULANDO] Nenhum XML neste mês." -ForegroundColor DarkGray
            continue
        }
        
        # 4. Compactar
        $ZipName = "XMLs_Contabilidade_$Cnpj`_$MesAno.zip"
        $ZipPath = Join-Path $ProjectRoot $ZipName
        
        Write-Host "      Compactando $($Files.Count) arquivos..." -ForegroundColor Yellow
        try {
            Compress-Archive -Path "$($MesDir.FullName)\*" -DestinationPath $ZipPath -Force
        }
        catch {
            Write-Host "      [ERRO] Falha ao compactar: $_" -ForegroundColor Red
            continue
        }
        
        # 5. Enviar para o Drive com estrutura de pastas
        # Estrutura no Drive: Contabilidade / [CNPJ] / [YYYY-MM]
        $TargetPath = "Contabilidade/$Cnpj/$MesAno"
        
        if (Test-Path $DartScript) {
            Write-Host "      Enviando para o Drive: $TargetPath" -ForegroundColor Yellow
            Set-Location $ProjectRoot
            # Passa o arquivo, o nome amigável e o caminho remoto
            dart run $DartScript $ZipPath $ZipName "--target-path=$TargetPath"
            
            # Limpar o ZIP local após sucesso (opcional, mas recomendado para não poluir)
            Remove-Item $ZipPath -ErrorAction SilentlyContinue
        }
        else {
            Write-Host "      [AVISO] Script Dart não encontrado. ZIP mantido em: $ZipPath" -ForegroundColor DarkYellow
        }
    }
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   Processo concluído!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Cyan
# pause
