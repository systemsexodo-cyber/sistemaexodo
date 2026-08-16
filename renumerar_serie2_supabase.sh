#!/usr/bin/env bash
# ==========================================================================
# RENUMERAÇÃO SÉRIE 2 (NFC-e) — Supabase
# --------------------------------------------------------------------------
# Espelha a renumeracao feita no banco local:
#   1. Renumera as 4 notas de homologacao da serie 2:
#        243 -> 1, 244 -> 2, 245 -> 3, 246 -> 4
#      (chave de acesso e QR Code recalculados).
#   2. Corrige o contador global 'ultimo_numero_nfce' da empresa para 242.
#
# EXECUTAR SOMENTE COM O APP FECHADO.
# ==========================================================================
set -euo pipefail

URL="https://febffvlpvxtiihvnfuts.supabase.co"
KEY=$(grep SUPABASE_ANON_KEY .env | cut -d= -f2)
[ -n "$KEY" ] || { echo "ERRO: SUPABASE_ANON_KEY nao encontrado no .env"; exit 1; }

renumera() {
  local id="$1" numero="$2" chave="$3" qr="$4"
  echo ">> Renumerando nota para $numero (id $id)..."
  curl -s -X PATCH "$URL/rest/v1/nfces?id=eq.$id" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "{\"numero\":\"$numero\",\"chave_acesso\":\"$chave\",\"qr_code\":\"$qr\",\"updated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
}

# --- 1. Renumerar as 4 notas da serie 2 ---
renumera 1786673172122 1 \
  35260804829400000165650020000000011956378402 \
  'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000011956378402|2|2|1|06CADAA4C8D3BD824BC28794CCF4865E32BE52F7'

renumera 1786804969893 2 \
  35260804829400000165650020000000021019291405 \
  'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000021019291405|2|2|1|3CB4AECD612345A4E63A045DE4BD21FC6C321E46'

renumera 1786808575633 3 \
  35260804829400000165650020000000031458439587 \
  'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000031458439587|2|2|1|71DFDB82A5DCC4B3792F840A6ECD1861DD65B8D1'

renumera 1786808646585 4 \
  35260804829400000165650020000000041841766908 \
  'https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx?p=35260804829400000165650020000000041841766908|2|2|1|E9F1141C960548B13A907C6DBC2EA12BBAB18CE4'

# --- 2. Corrigir contador global da empresa para 242 (serie 1 continua em 243) ---
# ATENCAO: configuracoes e um JSONB inteiro — PATCH parcial substituiria TODAS as
# configuracoes da empresa (certificado, ecommerce, etc.). Por isso buscamos o
# objeto completo, fazemos o merge com node e enviamos de volta.
echo ">> Corrigindo ultimo_numero_nfce da empresa -> 242 (merge JSONB)..."
curl -s -G "$URL/rest/v1/empresas" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=configuracoes" \
  --data-urlencode "id=eq.22ae2c16-a730-43f3-a4f9-19f105eb0d13" \
  > /tmp/exodo_empresa_config.json

MERGED=$(node -e "
const fs = require('fs');
const raw = JSON.parse(fs.readFileSync('/tmp/exodo_empresa_config.json','utf8'));
const cfg = raw[0]?.configuracoes ?? {};
cfg.ultimo_numero_nfce = '242';
console.log(JSON.stringify(cfg));
")
curl -s -X PATCH "$URL/rest/v1/empresas?id=eq.22ae2c16-a730-43f3-a4f9-19f105eb0d13" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d "{\"configuracoes\":$MERGED,\"updated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

echo ">> Validando notas da serie 2 no Supabase..."
curl -s -G "$URL/rest/v1/nfces" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=numero,serie,status" \
  --data-urlencode "serie=eq.2"
echo
echo ">> Concluido."
