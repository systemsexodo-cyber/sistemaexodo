# -*- coding: utf-8 -*-
"""Diagnóstico SOMENTE-LEITURA: cadastro de usuários e permissões.

Responde, com dados reais, onde os usuários e as permissões estão (ou não)
persistidos:

  1. Banco LOCAL  -> tabela `usuarios` + chave `usuarios` do cache_dados
  2. NUVEM        -> tabela `usuarios` no Supabase (colunas + linhas)

Nunca imprime senhas, chaves ou tokens: só contagens, e-mails, nomes de
colunas e códigos de erro HTTP.
"""

import json
import os
import sys

try:
    from dotenv import load_dotenv
    load_dotenv()
except Exception:
    pass

import requests

SAIDA = []


def log(*args):
    txt = " ".join(str(a) for a in args)
    SAIDA.append(txt)


# ── 1) BANCO LOCAL ───────────────────────────────────────────────────────────
def diagnosticar_local():
    log("=" * 70)
    log("1) BANCO LOCAL")
    log("=" * 70)
    try:
        import psycopg2
    except Exception as e:
        log("  psycopg2 indisponivel:", e)
        return

    try:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", "5432")),
            database=os.getenv("DB_NAME", "exodo_db"),
            user=os.getenv("DB_USER", "exodo_user"),
            password=os.getenv("DB_PASSWORD", ""),
            connect_timeout=5,
        )
    except Exception as e:
        log("  FALHA ao conectar no local:", str(e).split("\n")[0])
        return

    cur = conn.cursor()

    # 1a) tabela `usuarios` (usada pelo sincronizador)
    try:
        cur.execute("SELECT count(*) FROM usuarios")
        log("  tabela `usuarios` (local):", cur.fetchone()[0], "linha(s)")
        cur.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name='usuarios' ORDER BY ordinal_position"
        )
        cols = [r[0] for r in cur.fetchall()]
        log("  colunas dessa tabela:", ", ".join(cols) if cols else "(nenhuma)")
    except Exception as e:
        log("  tabela `usuarios` local: ERRO:", str(e).split("\n")[0])
        conn.rollback()

    # 1b) chave `usuarios` do cache_dados (fonte de LOGIN do app)
    try:
        cur.execute(
            "SELECT valor_json, ultima_atualizacao FROM cache_dados "
            "WHERE chave = 'usuarios'"
        )
        row = cur.fetchone()
        if not row:
            log("  cache_dados['usuarios']: AUSENTE (nada salvo!)")
        else:
            dados, quando = row
            try:
                lista = json.loads(dados) if dados else []
            except Exception:
                lista = []
            log(
                "  cache_dados['usuarios']:",
                len(lista),
                "usuario(s), atualizado em",
                quando,
            )
            for u in lista:
                if not isinstance(u, dict):
                    continue
                perm = [
                    k
                    for k in (
                        "permissoes_personalizadas",
                        "permissoesPersonalizadas",
                        "permissoes_negadas",
                        "permissoesNegadas",
                        "telas_ocultas",
                        "telasOcultas",
                    )
                    if u.get(k)
                ]
                log(
                    "    -",
                    u.get("email") or u.get("id"),
                    "| empresa_id:",
                    u.get("empresa_id") or u.get("empresaId") or "(vazio)",
                    "| senha:",
                    "tem" if u.get("senha") else "VAZIA",
                    "| tipo:",
                    u.get("tipo") or u.get("perfil") or "-",
                    "| permissoes:",
                    ", ".join(perm) if perm else "(nenhuma)",
                )
    except Exception as e:
        log("  cache_dados['usuarios']: ERRO:", str(e).split("\n")[0])
        conn.rollback()

    # 1b2) tabela `usuarios` local: e-mail/permissoes em dados_usuario/dados_app
    try:
        cur.execute(
            "SELECT email, perfil, ativo, empresa_id, "
            "COALESCE(dados_usuario::text,''), COALESCE(dados_app::text,'') "
            "FROM usuarios ORDER BY email"
        )
        for r in cur.fetchall():
            email, perfil, ativo, emp, duser, dapp = r
            tem_perm = any(
                s in (duser + dapp).lower()
                for s in ("permiss", "telas_ocultas", "permissoes")
            )
            log(
                "    *",
                email,
                "| perfil:",
                perfil,
                "| ativo:",
                ativo,
                "| empresa_id:",
                emp or "(vazio)",
                "| tem permissao em dados_usuario/app:",
                "SIM" if tem_perm else "nao",
            )
    except Exception as e:
        log("  leitura detalhada da tabela usuarios: ERRO:", str(e).split("\n")[0])
        conn.rollback()

    # 1c) erros de sync de usuario gravados pelo app
    try:
        cur.execute("SELECT valor_json FROM cache_dados WHERE chave = 'erros_sync_usuarios'")
        r = cur.fetchone()
        if r and r[0]:
            try:
                erros = json.loads(r[0])
                log("  erros_sync_usuarios:", len(erros), "registro(s)")
                for e in erros[:5]:
                    log(
                        "    *",
                        e.get("email"),
                        "->",
                        str(e.get("erro"))[:140],
                    )
            except Exception:
                pass
        else:
            log("  erros_sync_usuarios: (nenhum)")
    except Exception as e:
        log("  erros_sync_usuarios: ERRO:", str(e).split("\n")[0])
        conn.rollback()

    cur.close()
    conn.close()


# ── 2) NUVEM (Supabase / PostgREST) ──────────────────────────────────────────
def diagnosticar_nuvem():
    log("")
    log("=" * 70)
    log("2) NUVEM (Supabase REST)")
    log("=" * 70)

    url = (os.getenv("SUPABASE_URL") or "").strip()
    if not url:
        log("  SUPABASE_URL nao configurada no .env — pulando.")
        return
    url = url.rstrip("/")

    chave = ""
    for var in ("SUPABASE_ANON_KEY", "SUPABASE_ACCESS_TOKEN", "SUPABASE_KEY"):
        v = (os.getenv(var) or "").strip()
        if v:
            chave = v
            log("  chave usada: variavel", var, "(valor nao exibido)")
            break
    if not chave:
        log("  nenhuma chave REST encontrada no .env — pulando.")
        return

    cabecalhos = {
        "apikey": chave,
        "Authorization": f"Bearer {chave}",
        "Accept": "application/json",
    }

    # 2-0) papel da chave (só o campo `role` do JWT — nenhum segredo)
    try:
        import base64

        partes = chave.split(".")
        if len(partes) == 3:
            payload = partes[1] + "=" * (-len(partes[1]) % 4)
            dados = json.loads(base64.urlsafe_b64decode(payload))
            log("  papel da chave (role):", dados.get("role"), "| ref:", dados.get("iss", "")[:60])
        else:
            log("  chave nao e JWT (formato opaque/sb_secret_)")
    except Exception as e:
        log("  nao foi possivel identificar o papel da chave:", str(e)[:100])

    # 2-a0) contagens com header count=exact (RLS tambem afeta a contagem)
    # Tabelas com política conhecida para `anon` (servem de sonda: se tiverem
    # linhas, o papel anon GRAVA/LÊ de verdade e o banco está vivo).
    for tabela in (
        "usuarios",
        "empresas",
        "clientes",
        "produtos",
        "exodo_config",
        "sync_logs",
        "sync_status",
        "vendas_balcao",
        "estoque_historico",
        "aberturas_caixa",
    ):
        try:
            h = dict(cabecalhos)
            h["Prefer"] = "count=exact"
            r = requests.get(
                f"{url}/rest/v1/{tabela}",
                headers=h,
                params={"select": "id", "limit": "1"},
                timeout=15,
            )
            cr = r.headers.get("content-range", "")
            log(
                f"  contagem `{tabela}`: HTTP {r.status_code} | content-range: {cr or '(nenhum)'}"
            )
            if r.status_code != 200:
                log("    corpo:", r.text[:200])
        except Exception as e:
            log(f"  contagem `{tabela}`: FALHA", str(e)[:120])

    # 2a) schema: quais colunas a tabela aceita
    try:
        r = requests.get(
            f"{url}/rest/v1/usuarios",
            headers=cabecalhos,
            params={"select": "*", "limit": "1"},
            timeout=15,
        )
        log("  GET /rest/v1/usuarios -> HTTP", r.status_code)
        if r.status_code == 200:
            colunas = sorted({k for linha in r.json() for k in linha}) or (
                sorted(r.json()[0].keys()) if r.json() else []
            )
            log("  colunas visiveis:", ", ".join(colunas) if colunas else "(0 linhas)")
        else:
            log("  corpo:", r.text[:300])
    except Exception as e:
        log("  FALHA na consulta:", str(e)[:200])

    # 2b) linhas
    try:
        r = requests.get(
            f"{url}/rest/v1/usuarios",
            headers=cabecalhos,
            params={
                "select": "id,email,empresa_id,ativo,perfil,created_at,updated_at",
                "limit": "100",
            },
            timeout=15,
        )
        if r.status_code == 200:
            linhas = r.json()
            log("  usuarios na nuvem:", len(linhas))
            for l in linhas[:15]:
                log(
                    "    -",
                    l.get("email"),
                    "| empresa_id:",
                    l.get("empresa_id") or "(vazio)",
                    "| ativo:",
                    l.get("ativo"),
                )
        else:
            log("  listagem -> HTTP", r.status_code, r.text[:300])
    except Exception as e:
        log("  FALHA na listagem:", str(e)[:200])

    # 2c) existe coluna de permissao na nuvem?
    for col in ("permissoes_personalizadas", "permissoes_negadas", "telas_ocultas", "senha"):
        try:
            r = requests.get(
                f"{url}/rest/v1/usuarios",
                headers=cabecalhos,
                params={"select": col, "limit": "1"},
                timeout=15,
            )
            if r.status_code == 200:
                log(f"  coluna `{col}`: EXISTE (HTTP 200)")
            else:
                log(
                    f"  coluna `{col}`: NAO EXISTE/bloqueada (HTTP {r.status_code}):",
                    r.text[:120],
                )
        except Exception as e:
            log(f"  coluna `{col}`: FALHA", str(e)[:100])


def main():
    diagnosticar_local()
    diagnosticar_nuvem()
    texto = "\n".join(SAIDA)
    print(texto)
    try:
        with open("diag_usuarios_resultado.txt", "w", encoding="utf-8") as f:
            f.write(texto)
        print("\n[gravado em diag_usuarios_resultado.txt]")
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
