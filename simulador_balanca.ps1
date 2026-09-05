# ============================================================
#  SIMULADOR DE BALANCA - porta COM virtual (com0com / VSPE)
#  Simula uma balanca Toledo/Filizola enviando peso na serial.
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File simulador_balanca.ps1 -Porta COM5
#    powershell -ExecutionPolicy Bypass -File simulador_balanca.ps1 -Porta COM5 -Peso 2.350 -Continuo -IntervaloMs 800
#
#  Modos:
#    MANUAL (padrao) : ENTER envia 1 leitura. Ideal para o teste no app
#                      (o app le todo o buffer; 1 frame por vez = 100% confiavel)
#    CONTINUO        : envia o peso em loop, parecendo balanca real.
#                      Ate como balanca real, se o buffer acumular varias
#                      leituras o app pode nao extrair o peso - envie 1 frame
#                      e teste na hora (ou use o modo MANUAL).
# ============================================================
param(
    [string]$Porta = "COM5",
    [int]$BaudRate = 9600,
    [double]$Peso = 1.540,
    [int]$IntervaloMs = 1000,
    [switch]$Continuo
)

function Envia-Peso {
    # Formato Toledo Prix 3: peso com 3 casas decimais + CR/LF (ex: "001.540")
    # O BalancaService do app aceita "001.540" (com ponto) ou "01540" (sem ponto).
    $linha = "{0:F3}`r`n" -f $Peso
    try { $port.Write($linha) } catch { Write-Host "ERRO ao escrever: $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host ("  >> {0} kg" -f $Peso) -ForegroundColor DarkGray
}

$port = New-Object System.IO.Ports.SerialPort $Porta, $BaudRate, None, 8, one
$port.WriteTimeout = 1000

try { $port.Open() } catch {
    Write-Host "ERRO: nao consegui abrir $Porta. Crie o par virtual antes (com0com: setupc install PortName=COM5 PortName=COM6)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  SIMULADOR DE BALANCA" -ForegroundColor Cyan
Write-Host "  Porta: $Porta | Baud: $BaudRate (8N1) | Peso: $Peso kg | Modo: $(if ($Continuo) {'CONTINUO'} else {'MANUAL'})"
Write-Host "  ENTER envia 1 leitura. Ctrl+C para sair." -ForegroundColor DarkGray
Write-Host ""

try {
    while ($true) {
        if ([Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)   # ENTER -> envia 1 leitura
            Envia-Peso
        }
        if ($Continuo) {
            Envia-Peso
            Start-Sleep -Milliseconds $IntervaloMs
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
} finally {
    $port.Close()
    Write-Host "`nSimulador encerrado."
}
