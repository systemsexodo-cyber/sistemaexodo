"""Limpeza única dos perfis tributários da EMPORIO (local + nuvem).

Mantém apenas os 6 perfis do sistema, define como padrão
`padrao_tributado_simples` (Simples Nacional) e `padrao_tributado_normal`
(Regime Normal) e remove os perfis extras criados por engano.

Uso:
    python tool/limpar_perfis_emporio.py            # executa
    python tool/limpar_perfis_emporio.py --dry-run  # só mostra
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EMPRESA_ID = "bd45d75b-fee4-4ac2-8975-0f36f61d01bf"
SISTEMA_IDS = [
    "padrao_tributado_simples",
    "padrao_nao_tributado_simples",
    "padrao_substituicao_simples",
    "padrao_tributado_normal",
    "padrao_nao_tributado_normal",
    "padrao_substituicao_normal",
]
PADROES = {"padrao_tributado_simples", "padrao_tributado_normal"}
# Nomes oficiais (com acentuação) usados pelo código em
# `_criarPerfisTributariosPadrao`. Os registros antigos estavam sem acento.
NOMES = {
    "padrao_tributado_simples": "Tributado (Simples Nacional)",
    "padrao_nao_tributado_simples": "Não Tributado (Simples Nacional)",
    "padrao_substituicao_simples": "Substituição Tributária (Simples Nacional)",
    "padrao_tributado_normal": "Tributado (Regime Normal)",
    "padrao_nao_tributado_normal": "Não Tributado (Regime Normal)",
    "padrao_substituicao_normal": "Substituição Tributária (Regime Normal)",
}

DRY = "--dry-run" in sys.argv


def ler_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for linha in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        k, v = linha.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def agora_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def main() -> None:
    env = ler_env()
    dsn = env["DATABASE_URL"]
    base = (env.get("SUPABASE_URL") or "http://127.0.0.1:8001").rstrip("/")
    key = (
        env.get("SUPABASE_SERVICE_ROLE_KEY")
        or env.get("SERVICE_ROLE_KEY")
        or env.get("ANON_KEY")
        or ""
    )

    import psycopg2
    from psycopg2.extras import Json

    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute(
        "SELECT configuracoes, updated_at FROM empresas WHERE id = %s FOR UPDATE",
        (EMPRESA_ID,),
    )
    linha = cur.fetchone()
    if not linha:
        raise SystemExit(f"Empresa {EMPRESA_ID} não encontrada no banco local")
    config = linha[0] or {}
    config_original = json.loads(json.dumps(config))
    perfis = config.get("perfis_tributarios") or []

    print(f"Local: {len(perfis)} perfis. Carimbo atual: {config.get('perfis_tributarios_atualizado_em')}")
    for p in perfis:
        print(f"  {p.get('id'):48} default={p.get('is_default')!s:5} {p.get('nome')!r}")

    manter = [p for p in perfis if p.get("id") in SISTEMA_IDS]
    if len(manter) != len(SISTEMA_IDS):
        encontrados = {p.get("id") for p in manter}
        faltando = [i for i in SISTEMA_IDS if i not in encontrados]
        raise SystemExit(f"Perfis do sistema faltando: {faltando}")

    for p in manter:
        p["is_default"] = p.get("id") in PADROES
        p["nome"] = NOMES[p["id"]]
    # Ordem estável: a mesma da lista do sistema.
    ordem = {pid: i for i, pid in enumerate(SISTEMA_IDS)}
    manter.sort(key=lambda p: ordem[p["id"]])

    novo_stamp = agora_iso()
    config["perfis_tributarios"] = manter
    config["perfis_tributarios_atualizado_em"] = novo_stamp

    backup_dir = ROOT / "tool" / "backups"
    backup_dir.mkdir(exist_ok=True)
    backup = backup_dir / f"emporio_perfis_{dt.datetime.now():%Y%m%d_%H%M%S}.json"
    backup.write_text(
        json.dumps(
            {
                "perfis": perfis,
                "config": config_original,
                "stamp_anterior": config_original.get("perfis_tributarios_atualizado_em"),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Backup salvo em {backup}")

    # Colunas reais da tabela local (para montar o INSERT).
    cur.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_schema = current_schema() AND table_name = 'perfis_tributarios'"
    )
    colunas = {r[0]: r[1] for r in cur.fetchall()}
    if not colunas:
        raise SystemExit("Tabela perfis_tributarios não encontrada no banco local")

    def linha_tabela(p: dict) -> dict:
        dados = {k: v for k, v in p.items() if k in colunas}
        dados["id"] = p["id"]
        dados["empresa_id"] = EMPRESA_ID
        dados.setdefault("ativo", True)
        dados["updated_at"] = novo_stamp
        dados.setdefault("created_at", novo_stamp)
        return dados

    if DRY:
        print("\n[DRY-RUN] Nada foi alterado.")
        conn.rollback()
        conn.close()
        return

    # 1) Configuração da empresa (local), com os triggers desligados para o
    #    updated_at/trilha não sobrescreverem o carimbo que acabamos de gravar.
    cur.execute("ALTER TABLE empresas DISABLE TRIGGER ALL")
    cur.execute(
        "UPDATE empresas SET configuracoes = %s, updated_at = now() WHERE id = %s",
        (Json(config), EMPRESA_ID),
    )
    cur.execute("ALTER TABLE empresas ENABLE TRIGGER ALL")

    # 2) Tabela dedicada local.
    #    O `id` é a chave primária GLOBAL desta tabela (o mesmo perfil de sistema
    #    é compartilhado entre empresas), então NÃO podemos apagar/reinserir por
    #    cima: isso quebraria a empresa que já possui a linha. Removemos apenas
    #    os extras da EMPORIO e criamos somente os perfis do sistema que faltam.
    extras = [p["id"] for p in perfis if p.get("id") not in SISTEMA_IDS]
    if extras:
        cur.execute(
            "DELETE FROM perfis_tributarios WHERE empresa_id = %s AND id = ANY(%s)",
            (EMPRESA_ID, extras),
        )
    cur.execute(
        "SELECT id FROM perfis_tributarios WHERE id = ANY(%s)", (SISTEMA_IDS,)
    )
    existentes = {r[0] for r in cur.fetchall()}
    faltando = [p for p in manter if p["id"] not in existentes]
    if faltando:
        cols = list(linha_tabela(faltando[0]).keys())
        placeholders = ", ".join(f"%({c})s" for c in cols)
        sql = (
            f'INSERT INTO perfis_tributarios ({", ".join(chr(34) + c + chr(34) for c in cols)}) '
            f"VALUES ({placeholders})"
        )
        for p in faltando:
            cur.execute(sql, linha_tabela(p))
    conn.commit()
    cur.close()
    conn.close()
    print(
        f"Local atualizado: {len(manter)} perfis, {len(extras)} extras removidos, "
        f"{len(faltando)} linhas criadas. Carimbo {novo_stamp}"
    )

    # 3) Nuvem: configuração da empresa.
    def rest(metodo: str, caminho: str, corpo=None, prefer: str | None = None):
        headers = {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        }
        dados = None
        if corpo is not None:
            dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if prefer:
            headers["Prefer"] = prefer
        req = urllib.request.Request(
            f"{base}/rest/v1/{caminho}", data=dados, headers=headers, method=metodo
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            texto = resp.read().decode("utf-8")
            return json.loads(texto) if texto.strip() else None

    atual = rest(
        "GET",
        f"empresas?id=eq.{EMPRESA_ID}&select=configuracoes",
    )
    cfg_nuvem = (atual[0]["configuracoes"] or {}) if atual else {}
    cfg_nuvem["perfis_tributarios"] = manter
    cfg_nuvem["perfis_tributarios_atualizado_em"] = novo_stamp
    rest(
        "PATCH",
        f"empresas?id=eq.{EMPRESA_ID}",
        {"configuracoes": cfg_nuvem, "updated_at": novo_stamp},
        prefer="return=minimal",
    )

    # 4) Nuvem: tabela dedicada (mesma regra de id compartilhado do local).
    lista_ids = ",".join(SISTEMA_IDS)
    existentes_nuvem = {
        r["id"]
        for r in (
            rest("GET", f"perfis_tributarios?select=id&id=in.({lista_ids})") or []
        )
    }
    if extras:
        rest(
            "DELETE",
            f"perfis_tributarios?empresa_id=eq.{EMPRESA_ID}&id=in.({','.join(extras)})",
            prefer="return=minimal",
        )
    faltando_nuvem = [p for p in manter if p["id"] not in existentes_nuvem]
    if faltando_nuvem:
        linhas = []
        for p in faltando_nuvem:
            d = {k: v for k, v in p.items() if k in colunas}
            d["empresa_id"] = EMPRESA_ID
            d.setdefault("ativo", True)
            d["updated_at"] = novo_stamp
            d["created_at"] = novo_stamp
            linhas.append(d)
        rest(
            "POST",
            "perfis_tributarios",
            linhas,
            prefer="return=minimal",
        )
    print(
        f"Nuvem atualizada: {len(extras)} extras removidos, "
        f"{len(faltando_nuvem)} linhas criadas."
    )

    # 5) Espelho de emergência desta máquina (não pode reintroduzir excluídos).
    cache_dir = Path(os.environ.get("APPDATA", "")) / "com.example" / "sistema_exodo_novo" / "cache_emergencia"
    chave = f"empresa_{EMPRESA_ID}_perfis_tributarios"
    nome = base64.urlsafe_b64encode(chave.encode()).decode().replace("=", "") + ".json"
    alvo = cache_dir / nome
    if alvo.exists():
        alvo.replace(alvo.with_suffix(".json.bak"))
        print(f"Cache de emergência movido para {alvo.name}.bak")
    print("Concluído.")


if __name__ == "__main__":
    main()
