# -*- coding: utf-8 -*-
"""
Ajusta a lista de perfis tributarios da empresa EMPORIO:

  - "Tributado (Simples Nacional)" passa a ser o PADRAO do Simples
    (e o nome perde o "1" acidental do final);
  - "Substituicao Tributaria (Simples Nacional)" deixa de ser padrao;
  - carimba a lista com o horario atual para ela vencer a copia antiga
    que ainda existe na nuvem / no navegador.

Uso:
    python tool/ajustar_perfis_padrao.py
"""
import json
from datetime import datetime, timezone

import psycopg2

EMPRESA_ID = "bd45d75b-fee4-4ac2-8975-0f36f61d01bf"
LOCAL_DSN = "host=localhost port=5432 dbname=exodo_db user=exodo_user password=ex@#$"
CHAVE = "perfis_tributarios"
CHAVE_CARIMBO = "perfis_tributarios_atualizado_em"


def main():
    conn = psycopg2.connect(LOCAL_DSN)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT configuracoes FROM empresas WHERE id = %s FOR UPDATE",
                (EMPRESA_ID,),
            )
            row = cur.fetchone()
            if not row:
                raise SystemExit("empresa nao encontrada")
            config = row[0] or {}
            if isinstance(config, str):
                config = json.loads(config)

            perfis = config.get(CHAVE) or []
            if not isinstance(perfis, list):
                raise SystemExit("configuracoes.perfis_tributarios invalida")

            # Garante que o perfil PADRAO do Simples exista (ele pode ter sido
            # apagado num teste de exclusao).
            tem_tributado = any(
                isinstance(p, dict) and p.get("id") == "padrao_tributado_simples"
                for p in perfis
            )
            if not tem_tributado:
                perfis.insert(
                    0,
                    {
                        "id": "padrao_tributado_simples",
                        "nome": "Tributado (Simples Nacional)",
                        "cfop": "5102",
                        "csosn": "102",
                        "icms_cst": "",
                        "pis_cst": "99",
                        "cofins_cst": "000",
                        "cst_ibs": "000",
                        "aliquota_ibs": 0.1,
                        "cst_cbs": "000",
                        "aliquota_cbs": 0.9,
                        "c_class_trib": "000001",
                        "is_default": True,
                    },
                )
                print("perfil Tributado (Simples) recriado")

            for perfil in perfis:
                if not isinstance(perfil, dict):
                    continue
                pid = str(perfil.get("id") or "")
                nome = str(perfil.get("nome") or "")
                if pid == "padrao_tributado_simples":
                    perfil["nome"] = "Tributado (Simples Nacional)"
                    perfil["is_default"] = True
                    print("PADRAO -> %s" % perfil["nome"])
                elif pid == "padrao_substituicao_simples":
                    perfil["is_default"] = False
                elif pid == "padrao_tributado_normal":
                    # O outro regime continua com o padrao dele.
                    perfil["is_default"] = True
                if nome.endswith("1") and "Tributado (Simples Nacional)" in nome:
                    perfil["nome"] = "Tributado (Simples Nacional)"

            carimbo = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            config[CHAVE] = perfis
            config[CHAVE_CARIMBO] = carimbo

            cur.execute(
                "UPDATE empresas SET configuracoes = %s, updated_at = NOW() "
                "WHERE id = %s",
                (json.dumps(config, ensure_ascii=False), EMPRESA_ID),
            )
            print("local atualizado, carimbo = %s" % carimbo)
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    main()
