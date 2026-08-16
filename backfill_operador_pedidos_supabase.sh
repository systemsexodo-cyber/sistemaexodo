#!/usr/bin/env bash
# ==========================================================================
# BACKFILL: OPERADOR (RESPONSÁVEL) NOS PEDIDOS DE DELIVERY — Supabase
# --------------------------------------------------------------------------
# Copia o 'operador' da vendas_balcao para o pedido com o mesmo ID,
# para o histórico de vendas mostrar o responsável nos deliveries antigos.
#
# EXECUTAR SOMENTE COM O APP FECHADO.
# ==========================================================================
set -euo pipefail

URL="https://febffvlpvxtiihvnfuts.supabase.co"
KEY=$(grep SUPABASE_ANON_KEY .env | cut -d= -f2)
[ -n "$KEY" ] || { echo "ERRO: SUPABASE_ANON_KEY nao encontrado no .env"; exit 1; }

# Buscar pedidos delivery sem operador que têm venda balcão correspondente com operador
echo ">> Buscando pedidos sem operador com venda balcão correspondente..."
curl -s -G "$URL/rest/v1/vendas_balcao" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=id,operador" \
  --data-urlencode "operador=neq." \
  > /tmp/exodo_vb_operador.json

TOTAL=$(node -e "
const fs = require('fs');
const rows = JSON.parse(fs.readFileSync('/tmp/exodo_vb_operador.json','utf8'));
console.log(rows.filter(r => r.id && r.operador).length);
")
echo ">> Vendas balcão com operador: $TOTAL"

# Para cada venda, atualizar o pedido correspondente se estiver sem operador
node -e "
const fs = require('fs');
const rows = JSON.parse(fs.readFileSync('/tmp/exodo_vb_operador.json','utf8'));
for (const r of rows) {
  if (r.id && r.operador) {
    console.log(r.id + '|' + r.operador);
  }
}
" > /tmp/exodo_backfill_lista.txt

CONT=0
while IFS='|' read -r pid operador; do
  [ -z "$pid" ] && continue
  # Atualizar apenas se o pedido existir e estiver sem operador (PATCH com filtro no operador)
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$URL/rest/v1/pedidos?id=eq.$pid&operador=is.null" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "{\"operador\":\"$operador\"}")
  # Se não casou (operador não é null), tentar com string vazia
  if [ "$HTTP" = "404" ]; then
    curl -s -o /dev/null -X PATCH "$URL/rest/v1/pedidos?id=eq.$pid&operador=eq." \
      -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -H "Prefer: return=minimal" \
      -d "{\"operador\":\"$operador\"}" || true
  fi
  CONT=$((CONT+1))
done < /tmp/exodo_backfill_lista.txt

echo ">> Processados: $CONT pedidos"
echo ">> Concluido."
