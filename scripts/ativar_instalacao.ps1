# ============================================================================
# Ativação da licença de instalação (30 dias)
# ============================================================================
# Roda automaticamente no fim do setup, já elevado:
#
#   powershell -ExecutionPolicy Bypass -File scripts\ativar_instalacao.ps1 -AppDir C:\SistemaExodo
#
# Lê o .env do sistema (SUPABASE_URL / SUPABASE_ANON_KEY), calcula o ID deste
# computador (o MESMO MachineGuid hasheado que o app usa) e pede a licença à
# função `licenca-instalacao`. O arquivo `licenca_instalacao.json` é gravado ao
# lado do executável, que é onde o app procura.
#
# IMPORTANTE: NUNCA falha a instalação. Se a nuvem estiver fora, o app abre na
# tela de ativação e o cliente/suporte libera por lá.
# ============================================================================

param(
  [Parameter(Mandatory = $true)][string]$AppDir,
  # Código de ativação por venda (uso único). Pode vir vazio: nesse caso o app
  # abre na tela de ativação para o cliente/suporte informar.
  [string]$CodigoAtivacao = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$logDir = Join-Path $AppDir 'logs'
$logFile = Join-Path $logDir 'ativacao_instalacao.log'

function Registrar([string]$mensagem) {
  try {
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $linha = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $mensagem
    Add-Content -Path $logFile -Value $linha -Encoding UTF8
  } catch { }
}

function Ler-Env([string]$caminho) {
  $valores = @{}
  if (-not (Test-Path $caminho)) { return $valores }
  foreach ($linha in Get-Content -Path $caminho -Encoding UTF8) {
    $texto = $linha.Trim()
    if ([string]::IsNullOrWhiteSpace($texto)) { continue }
    if ($texto.StartsWith('#')) { continue }
    $indice = $texto.IndexOf('=')
    if ($indice -le 0) { continue }
    $chave = $texto.Substring(0, $indice).Trim()
    $valor = $texto.Substring($indice + 1).Trim()
    if ($valor.Length -ge 2) {
      if (($valor.StartsWith('"') -and $valor.EndsWith('"')) -or
          ($valor.StartsWith("'") -and $valor.EndsWith("'"))) {
        $valor = $valor.Substring(1, $valor.Length - 2)
      }
    }
    $valores[$chave] = $valor
  }
  return $valores
}

function Obter-IdComputador {
  $guid = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
  if ([string]::IsNullOrWhiteSpace($guid)) { throw 'MachineGuid não encontrado.' }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes('EXODO-MACHINE-V1|' + $guid.ToLower())
    $hash = $sha.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
  } finally {
    $sha.Dispose()
  }
}

try {
  Registrar '--- Iniciando ativação da licença de instalação ---'

  $envPath = Join-Path $AppDir '.env'
  $config = Ler-Env $envPath

  # Endereços da função de licenciamento, na ordem em que serão tentados.
  # O `.env` de instalações antigas aponta SUPABASE_URL para o projeto Supabase
  # que foi DESATIVADO (o domínio não resolve mais): usar só ele fazia a
  # ativação falhar com "sem conexão" mesmo com internet. A nuvem atual
  # (Funnel, o mesmo endereço do resto do sistema) é a alternativa final.
  $sufixoLicenca = '/functions/v1/licenca-instalacao'
  $urlsLicenca = New-Object System.Collections.Generic.List[string]
  $vistas = @{}
  foreach ($candidato in @(
      $config['EXODO_LICENSE_URL'],
      $config['SUPABASE_URL'],
      $config['SUPABASE_FUNCTIONS_URL'])) {
    if ([string]::IsNullOrWhiteSpace($candidato)) { continue }
    $base = $candidato.Trim().TrimEnd('/')
    # Aceita tanto a raiz da nuvem quanto a URL de outra função.
    $base = ($base -replace '/functions/v1/[^/]+$', '').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($base)) { continue }
    $url = $base + $sufixoLicenca
    if ($vistas.ContainsKey($url)) { continue }
    $vistas[$url] = $true
    $urlsLicenca.Add($url)
  }
  $urlPadrao = 'https://exodosystems.tail9b4943.ts.net' + $sufixoLicenca
  if (-not $vistas.ContainsKey($urlPadrao)) { $urlsLicenca.Add($urlPadrao) }

  $maquinaId = Obter-IdComputador
  Registrar "ID do computador: $maquinaId"

  $headers = @{ 'Content-Type' = 'application/json' }
  $anon = $config['SUPABASE_ANON_KEY']
  if (-not [string]::IsNullOrWhiteSpace($anon)) {
    $headers['apikey'] = $anon
    $headers['Authorization'] = "Bearer $anon"
  }
  $chaveSetup = $config['EXODO_LICENSE_SETUP_KEY']
  if (-not [string]::IsNullOrWhiteSpace($chaveSetup)) {
    $headers['x-exodo-setup-key'] = $chaveSetup
  }

  $corpo = @{
    action          = 'ativar'
    machine_id      = $maquinaId
    machine_name    = $env:COMPUTERNAME
    codigo_ativacao = $CodigoAtivacao.Trim()
  } | ConvertTo-Json -Compress

  $resposta = $null
  $falhas = New-Object System.Collections.Generic.List[string]
  foreach ($url in $urlsLicenca) {
    try {
      Registrar "Chamando $url"
      $resposta = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $corpo -TimeoutSec 30
      Registrar "Resposta recebida de $url"
      break
    } catch {
      $status = 0
      if ($_.Exception.Response) {
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
      }
      $falhas.Add("$url -> HTTP $status $($_.Exception.Message)")
      Registrar "FALHA em $url (HTTP $status): $($_.Exception.Message)"
      # A nuvem respondeu e RECUSOU a ativação (código/chave): trocar de
      # endereço não resolve, então para aqui e registra o motivo real.
      if ($status -ge 400) { throw }
    }
  }
  if ($null -eq $resposta) {
    throw ('Nenhum endereço da nuvem de licenças respondeu. ' + ($falhas -join ' | '))
  }

  if ($null -eq $resposta -or $null -eq $resposta.documento) {
    throw 'A nuvem não devolveu a licença.'
  }

  $destino = Join-Path $AppDir 'licenca_instalacao.json'
  $conteudo = $resposta.documento | ConvertTo-Json -Depth 6
  $utf8SemBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($destino, $conteudo, $utf8SemBom)

  Registrar "Licença gravada em $destino (expira em $($resposta.documento.payload.expires_at))."
} catch {
  # Falhar aqui NÃO pode abortar a instalação: o app mostra a tela de ativação.
  Registrar "FALHA na ativação automática: $($_.Exception.Message)"
}
