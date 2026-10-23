# Varredura focused: model -> table with an EXPLICIT mapping (no guessing).
# Reports toMap() keys that have no matching column (silently dropped on write).
param([string]$Db = 'exodo_db', [string]$User = 'exodo_user')

$ErrorActionPreference = 'Stop'
$psql = Join-Path $PSScriptRoot '..\postgresql\pgsql\bin\psql.exe'

$raw = & $psql -U $User -d $Db -At -F '|' -c `
  "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public'"
$tableCols = @{}
foreach ($line in $raw) {
  $p = $line -split '\|', 2
  if ($p.Count -lt 2) { continue }
  if (-not $tableCols.ContainsKey($p[0])) { $tableCols[$p[0]] = @{} }
  $tableCols[$p[0]][$p[1]] = $true
}

function To-Snake([string]$k) {
  [regex]::Replace($k, '[A-Z]', { param($m) '_' + $m.Value.ToLower() })
}

# model file (without .dart) -> real table
$map = [ordered]@{
  'agendamento_servico'  = 'agendamentos_servico'
  'produto'              = 'produtos'
  'cliente'              = 'clientes'
  'entrega'              = 'entregas'
  'servico'              = 'servicos'
  'servico_realizado'    = 'servicos_realizados'
  'orcamento'            = 'orcamentos'
  'pedido'               = 'pedidos'
  'mesa_comanda'         = 'mesas_comandas'
  'venda_balcao'         = 'vendas_balcao'
  'funcionario'          = 'funcionarios'
  'produto_historico'    = 'produto_historico'
  'troca_devolucao'      = 'trocas_devolucoes'
  'conta_pagar'          = 'contas_pagar'
  'romaneio'             = 'romaneios'
  'motorista'            = 'motoristas'
  'nfce'                 = 'nfces'
  'nota_entrada'         = 'notas_entrada'
  'abertura_caixa'       = 'aberturas_caixa'
  'fechamento_caixa'     = 'fechamentos_caixa'
  'movimento_caixa'      = 'movimentos_caixa'
  'ajuste_estoque_lote'  = 'ajustes_estoque_lote'
  'estoque_historico'    = 'estoque_historico'
  'lote_produto'         = 'lotes_produto'
  'taxa_entrega'         = 'taxas_entrega'
  'ordem_servico'        = 'ordens_servico'
}

$models = Get-ChildItem -Path (Join-Path $PSScriptRoot '..\lib\models') -Filter *.dart
$linhas = @()

foreach ($m in $models) {
  if (-not $map.Contains($m.BaseName)) { continue }
  $tabela = $map[$m.BaseName]
  if (-not $tableCols.ContainsKey($tabela)) {
    $linhas += [pscustomobject]@{ Model=$m.BaseName; Tabela=$tabela; Faltando='(TABELA NAO EXISTE)'; Qtd='-' }
    continue
  }
  $text = Get-Content -Raw $m.FullName
  $ms = [regex]::Matches($text,
    'Map<\s*String\s*,\s*dynamic\s*>\s+toMap\s*\(\s*\)\s*\{(?<body>.*?)\n  \}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($ms.Count -eq 0) { continue }

  # Vários models por arquivo (classes aninhadas): cada toMap pertence à
  # classe DECLARADA MAIS PRÓXIMA para trás — sem isso, campos do modelo
  # filho (ItemVenda, EventoEntrega...) aparecem como "faltando" na tabela
  # pai, gerando falso positivo.
  $classes = @()
  foreach ($cm in [regex]::Matches($text, '\bclass\s+(?<n>\w+)')) {
    $classes += [pscustomobject]@{ Name = $cm.Groups['n'].Value; Pos = $cm.Index }
  }

  $keys = New-Object System.Collections.Generic.List[string]
  $modelBase = $m.BaseName.ToLower() -replace '_', ''
  foreach ($mm in $ms) {
    $classeAlvo = $null
    foreach ($c in $classes) {
      if ($c.Pos -le $mm.Index) { $classeAlvo = $c.Name } else { break }
    }
    # Só a classe que casa com o nome do arquivo (o model da tabela).
    # Comparação normalizada: AgendamentoServico == agendamento_servico.
    $normAlvo = if ($classeAlvo) { $classeAlvo.ToLower() -replace '_', '' } else { '' }
    if ($normAlvo -ne $modelBase) { continue }
    foreach ($km in [regex]::Matches($mm.Groups['body'].Value, "'(?<k>[A-Za-z_][A-Za-z0-9_]*)'\s*:")) {
      $keys.Add($km.Groups['k'].Value)
    }
  }
  if ($keys.Count -eq 0) { continue }
  $keys = $keys | Sort-Object -Unique

  $missing = @()
  foreach ($k in $keys) {
    $snake = To-Snake $k
    if (-not ($tableCols[$tabela].ContainsKey($k) -or $tableCols[$tabela].ContainsKey($snake))) {
      $missing += $k
    }
  }
  $linhas += [pscustomobject]@{
    Model     = $m.BaseName
    Tabela    = $tabela
    Faltando  = if ($missing) { $missing -join ', ' } else { '-' }
    Qtd       = "$($missing.Count)/$($keys.Count)"
  }
}

$linhas | Sort-Object Qtd -Descending | Format-Table -AutoSize -Wrap
