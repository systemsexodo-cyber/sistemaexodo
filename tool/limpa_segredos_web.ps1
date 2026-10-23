# ===================================================================
#  limpa_segredos_web.ps1
#
#  Tira do bundle do site (build\web\assets\assets\app.env) as
#  credenciais que NAO podem ficar publicas.
#
#  POR QUE ISSO EXISTE
#  O Flutter empacota o MESMO `assets/app.env` no APK/celular e na web.
#  No PC e no celular esse arquivo fica no disco de quem tem o sistema.
#  Na web ele vira um arquivo estatico: qualquer pessoa que abrir
#  https://exodosystems-1541d.web.app/assets/assets/app.env le tudo.
#  Por isso, antes de publicar, o pacote web passa por aqui.
#
#  O que SAI do site:
#    NEON_AWS_ACCESS_KEY_ID / NEON_AWS_SECRET_ACCESS_KEY  (escrita nos buckets)
#    DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD  (Postgres da loja)
#    LAN_SYNC / LAN_DIAS_TOMBSTONE / LAN_INICIAL_COMPLETO (topologia da rede)
#
#  O que FICA (nao sao segredos e o site precisa):
#    NEON_DATA_API_URL, NEON_AUTH_BASE_URL, NEON_AUTH_JWKS_URL,
#    NEON_FUNCTION_HELLO_BASE_URL, NEON_AWS_ENDPOINT_URL_S3, NEON_AWS_REGION
#
#  OBSERVACAO: sem as chaves do S3, `NeonConfig.storageDisponivel` fica
#  false no navegador -> upload/gravacao de arquivo pelo site para de
#  funcionar (o PC e o celular continuam normais). A LEITURA dos buckets
#  publicos (ex: imagens) continua, porque a URL publica nao usa credencial.
#
#  Eh idempotente: rodar de novo nao estraga nada.
# ===================================================================

param(
    [string]$Raiz = (Join-Path $PSScriptRoot '..\build\web')
)

$ErrorActionPreference = 'Stop'

$raizCompleta = [System.IO.Path]::GetFullPath($Raiz)
$alvo = Join-Path $raizCompleta 'assets\assets\app.env'

$permitidas = @(
    'NEON_DATA_API_URL',
    # Chave da Data API do SUPABASE LOCAL (site aponta para a nuvem local).
    # Chave de cliente, por definicao: vai dentro do bundle de qualquer jeito
    # (o app web/celular precisa dela para falar com a API). Sem ela o site
    # recebe 401 do gateway. NAO e a senha do banco nem a do Neon.
    'NEON_DATA_API_KEY',
    'NEON_AUTH_BASE_URL',
    'NEON_AUTH_JWKS_URL',
    'NEON_FUNCTION_HELLO_BASE_URL',
    'NEON_AWS_ENDPOINT_URL_S3',
    'NEON_AWS_REGION'
)

if (-not (Test-Path $alvo)) {
    Write-Host "[ERRO] nao encontrei o arquivo de config do site:" -ForegroundColor Red
    Write-Host "       $alvo" -ForegroundColor Yellow
    Write-Host "       Rode 'flutter build web --release' antes." -ForegroundColor Yellow
    exit 1
}

$linhas = [System.IO.File]::ReadAllLines($alvo)
$saida = New-Object System.Collections.Generic.List[string]
$removidas = New-Object System.Collections.Generic.List[string]
$mantidas = New-Object System.Collections.Generic.List[string]

foreach ($linha in $linhas) {
    $t = $linha.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $chave = ($t -split '=', 2)[0].Trim()
    if ($permitidas -contains $chave) {
        $saida.Add($linha)
        $mantidas.Add($chave)
    } else {
        $removidas.Add($chave)
    }
}

if ($removidas.Count -eq 0) {
    Write-Host "[OK] o pacote web ja estava limpo ($($mantidas.Count) chaves publicas)." -ForegroundColor Green
    exit 0
}

$conteudo = New-Object System.Collections.Generic.List[string]
$conteudo.Add('# Config do site (Firebase Hosting) - gerado por tool/limpa_segredos_web.ps1')
$conteudo.Add('# Credenciais de escrita NAO entram aqui: este arquivo eh publico.')
foreach ($l in $saida) { $conteudo.Add($l) }

$utf8SemBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($alvo, $conteudo, $utf8SemBom)

Write-Host "[OK] pacote web limpo: $alvo" -ForegroundColor Green
Write-Host ("     removidas do site: " + ($removidas -join ', ')) -ForegroundColor Yellow
Write-Host ("     mantidas (publicas): " + ($mantidas -join ', ')) -ForegroundColor Cyan

# Trava de seguranca: nenhum dos segredos pode sobrar no arquivo publicado.
$texto = Get-Content $alvo -Raw
$proibidas = @('NEON_AWS_ACCESS_KEY_ID', 'NEON_AWS_SECRET_ACCESS_KEY', 'DB_PASSWORD')
$sobraram = @($proibidas | Where-Object { $texto -match [regex]::Escape($_) })
if ($sobraram.Count -gt 0) {
    Write-Host "[ERRO] ainda restou segredo no arquivo: $($sobraram -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] verificacao final: nenhum segredo no arquivo publicado." -ForegroundColor Green
exit 0
