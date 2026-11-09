"""Compara tabelas locais x nuvem e mostra o que entra no ciclo de sync.

Nao imprime credenciais: apenas nomes de tabelas.
"""
import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ))
sys.path.insert(0, str(RAIZ / "scripts"))

import portal_nuvem  # noqa: E402

nuvem = json.loads((RAIZ / "temp/diag_sync/nuvem.json").read_text(encoding="utf-8"))
nuvem_tabelas = sorted(set(nuvem.get("tabelas") or []))

conn = portal_nuvem._get_local_pg_conn()
if conn is None:
    print("ERRO: nao consegui conectar no Postgres local")
    sys.exit(1)

with conn.cursor() as cur:
    cur.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema='public' AND table_type='BASE TABLE'
        ORDER BY table_name
    """)
    local_todas = [r[0] for r in cur.fetchall()]
conn.close()

EXCLUIDAS = {
    'cache_dados', 'bridge_status', 'bridge_commands', 'exodo_sync_conflitos',
    'exodo_config', 'sync_status', 'configuracoes_locais', 'sync_logs', 'usuarios',
}


def entra_no_sync(nome: str) -> bool:
    if nome.startswith('_') or nome.startswith('vw_') or nome.startswith('view_'):
        return False
    if '_bkp_' in nome:
        return False
    return nome not in EXCLUIDAS


local_sync = [t for t in local_todas if entra_no_sync(t)]
nuvem_sync = [t for t in nuvem_tabelas if entra_no_sync(t)]

so_local = sorted(set(local_sync) - set(nuvem_sync))
so_nuvem = sorted(set(nuvem_sync) - set(local_sync))
ambas = sorted(set(local_sync) & set(nuvem_sync))

print("LOCAL  total=%d | no ciclo de sync=%d" % (len(local_todas), len(local_sync)))
print("NUVEM  total=%d | no ciclo de sync=%d" % (len(nuvem_tabelas), len(nuvem_sync)))
print("EM AMBAS (sincronizadas de fato)=%d" % len(ambas))
print()
print("--- LOCAL mas NAO na nuvem (%d) -> 404, ficam em cooldown ---" % len(so_local))
print("  " + (", ".join(so_local) if so_local else "(nenhuma)"))
print()
print("--- NUVEM mas NAO local (%d) -> nunca descem/sobem ---" % len(so_nuvem))
print("  " + (", ".join(so_nuvem) if so_nuvem else "(nenhuma)"))
print()
print("--- LOCAL: infraestrutura fora do ciclo (%d) ---" % (len(local_todas) - len(local_sync)))
print("  " + ", ".join(t for t in local_todas if not entra_no_sync(t)))
print()
print("--- NUVEM: infraestrutura/backups fora do ciclo (%d) ---" % (len(nuvem_tabelas) - len(nuvem_sync)))
print("  " + ", ".join(t for t in nuvem_tabelas if not entra_no_sync(t)))
