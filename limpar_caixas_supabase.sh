#!/bin/bash
# =============================================================================
# LIMPEZA DE CAIXAS DUPLICADOS / FANTASMA - SUPABASE
# Gerado em 2026-08-15
# =============================================================================
# O que faz:
#   1. Exclui 8 aberturas de caixa (6 artefatos com id = string de data + 2 fantasmas).
#   2. Exclui todos os fechamentos corrompidos (dataFechamento nulo / ref perdida).
#   3. Repara o fechamento 1785777067105 (vincula ao caixa real 1785598832980).
#
# Pode ser executado com o app aberto ou fechado (o app só MESCLA o que existe
# na nuvem; não recria o que foi apagado). Preferencialmente rode junto com o
# script local, com o app fechado, para consistência total.
# =============================================================================
set -euo pipefail

URL="https://febffvlpvxtiihvnfuts.supabase.co/rest/v1"
KEY="$(grep SUPABASE_ANON_KEY .env | cut -d= -f2)"
AUTH=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -H "Prefer: return=minimal")

echo "== 1. Excluindo aberturas artefato/fantasma =="
for ID in \
  "2026-04-12T22:14:40.804000+00:00" \
  "2026-04-12T23:33:51.921000+00:00" \
  "2026-04-13T00:54:16.469000+00:00" \
  "2026-04-13T02:19:33.345000+00:00" \
  "2026-04-14T21:33:54.147000+00:00" \
  "2026-04-28T23:43:54.917000+00:00" \
  "1786758037420" \
  "1786758116938" ; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -G "$URL/aberturas_caixa" \
    "${AUTH[@]}" --data-urlencode "id=eq.${ID}")
  echo "  abertura $ID -> HTTP $CODE"
done

echo "== 2. Excluindo fechamentos corrompidos (todos exceto 1785777067105) =="
# Busca todos os ids de fechamentos e exclui os que não devem ser mantidos.
IDS=$(curl -s -G "$URL/fechamentos_caixa" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=id" 2>/dev/null | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || true)
for FID in $IDS; do
  if [ "$FID" != "1785777067105" ]; then
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -G "$URL/fechamentos_caixa" \
      "${AUTH[@]}" --data-urlencode "id=eq.${FID}")
    echo "  fechamento $FID -> HTTP $CODE"
  fi
done

echo "== 3. Reparando fechamento 1785777067105 -> caixa 1785598832980 =="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$URL/fechamentos_caixa?id=eq.1785777067105" \
  "${AUTH[@]}" -d '{"aberturaCaixaId":"1785598832980"}')
echo "  patch -> HTTP $CODE"

echo "== Concluido. Verificacao: =="
echo -n "  aberturas restantes: "
curl -s -G "$URL/aberturas_caixa" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=id" 2>/dev/null | grep -o '"id":"[^"]*"' | wc -l
echo -n "  aberturas com id-data restantes: "
curl -s -G "$URL/aberturas_caixa" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=id" --data-urlencode "id=like.20*" 2>/dev/null | grep -o '"id":"[^"]*"' | wc -l
echo -n "  fechamentos restantes: "
curl -s -G "$URL/fechamentos_caixa" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  --data-urlencode "select=id" 2>/dev/null | grep -o '"id":"[^"]*"' | wc -l
