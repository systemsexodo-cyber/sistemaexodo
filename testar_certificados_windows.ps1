# Script para testar listagem de certificados do Windows

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TESTE: Listar Certificados do Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    $certificados = Get-ChildItem -Path Cert:\CurrentUser\My
    
    if ($certificados.Count -eq 0) {
        Write-Host "❌ Nenhum certificado encontrado no repositório 'Pessoal' (CurrentUser\My)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Certifique-se de que o certificado está instalado:" -ForegroundColor Yellow
        Write-Host "  1. Duplo clique no arquivo .pfx" -ForegroundColor White
        Write-Host "  2. Siga o assistente de importação" -ForegroundColor White
        Write-Host "  3. Selecione 'Localizar automaticamente o repositório'" -ForegroundColor White
        Write-Host "  4. Marque 'Marcar esta chave como exportável'" -ForegroundColor White
        exit 1
    }
    
    Write-Host "✅ Encontrados $($certificados.Count) certificado(s):" -ForegroundColor Green
    Write-Host ""
    
    $resultado = @()
    $index = 0
    
    foreach ($cert in $certificados) {
        $index++
        $subject = $cert.Subject
        $issuer = $cert.Issuer
        $thumbprint = $cert.Thumbprint
        $notAfter = $cert.NotAfter
        $hasPrivateKey = $cert.HasPrivateKey
        
        Write-Host "[$index] $subject" -ForegroundColor Yellow
        Write-Host "     Emitido por: $issuer" -ForegroundColor Gray
        Write-Host "     Thumbprint: $thumbprint" -ForegroundColor Gray
        Write-Host "     Válido até: $notAfter" -ForegroundColor Gray
        Write-Host "     Tem chave privada: $hasPrivateKey" -ForegroundColor $(if ($hasPrivateKey) { "Green" } else { "Red" })
        Write-Host ""
        
        if ($hasPrivateKey) {
            $resultado += @{
                Subject = $subject
                Issuer = $issuer
                Thumbprint = $thumbprint
                NotAfter = $notAfter.ToString("yyyy-MM-ddTHH:mm:ss")
                HasPrivateKey = $true
            }
        }
    }
    
    if ($resultado.Count -eq 0) {
        Write-Host "❌ Nenhum certificado com chave privada encontrado!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Certifique-se de que o certificado foi importado com a chave privada." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Certificados com chave privada: $($resultado.Count)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "JSON (para Flutter):" -ForegroundColor Yellow
    $resultado | ConvertTo-Json
    
} catch {
    Write-Host "❌ ERRO: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}




