#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Backup de segurança dos usuários do Sistema Êxodo.

Exporta para um arquivo JSON datado:
  - A tabela `usuarios` do PostgreSQL local
  - A chave `usuarios` (lista de login com senha) do cache_dados

Uso:
  python backup_usuarios.py
Gera: backups_usuarios/usuarios_AAAA-MM-DD_HHMMSS.json
"""
import datetime
import json
import os
import subprocess

PASTA_BACKUP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backups_usuarios")
PSQL = r"C:/SistemaExodo/postgresql/bin/psql"


def _carregar_env():
    """Carrega credenciais do C:/SistemaExodo/.env (ou .env local) se existir.

    NÃO trata '#' como comentário: senhas como 'ex@#$' seriam cortadas. Só
    linhas que COMEÇAM com '#' (sem '=' antes) são ignoradas.
    """
    env = {}
    for caminho in ("C:/SistemaExodo/.env", os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")):
        if os.path.isfile(caminho):
            try:
                with open(caminho, "r", encoding="utf-8", errors="replace") as f:
                    for linha in f:
                        linha = linha.strip()
                        if not linha or "=" not in linha:
                            continue
                        k, v = linha.split("=", 1)
                        k = k.strip()
                        v = v.strip()
                        if v.startswith('"') and v.endswith('"') and len(v) >= 2:
                            v = v[1:-1]
                        elif v.startswith("'") and v.endswith("'") and len(v) >= 2:
                            v = v[1:-1]
                        env[k] = v
            except Exception:
                pass
            break
    return env


ENV = _carregar_env()
# PRIORIDADE para o .env: variáveis de ambiente do shell podem estar com
# valores truncados (ex: senha com '#' cortada). O .env é a fonte confiável.
def _cfg(chave: str, padrao: str) -> str:
    if chave in ENV and ENV[chave]:
        return ENV[chave]
    return os.environ.get(chave, padrao)


DB_HOST = _cfg("DB_HOST", "localhost")
DB_PORT = _cfg("DB_PORT", "5432")
DB_NAME = _cfg("DB_NAME", "exodo_db")
DB_USER = _cfg("DB_USER", "exodo_user")
DB_PASSWORD = _cfg("DB_PASSWORD", "")


def rodar_psql(sql: str) -> str:
    env = dict(os.environ)
    env["PGPASSWORD"] = DB_PASSWORD
    args = [PSQL, "-h", DB_HOST, "-p", DB_PORT, "-U", DB_USER, "-d", DB_NAME, "-t", "-A", "-c", sql]
    r = subprocess.run(args, capture_output=True, text=True, env=env, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout


def main():
    os.makedirs(PASTA_BACKUP, exist_ok=True)
    agora = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    destino = os.path.join(PASTA_BACKUP, f"usuarios_{agora}.json")

    dados = {
        "gerado_em": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "tabela_usuarios": [],
        "lista_login_cache": [],
    }

    # 1) Tabela usuarios
    try:
        saida = rodar_psql(
            "SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) FROM (SELECT * FROM usuarios) t"
        )
        dados["tabela_usuarios"] = json.loads(saida.strip() or "[]")
    except Exception as e:
        dados["tabela_usuarios"] = [{"erro_leitura": str(e)}]

    # 2) cache_dados chave usuarios (lista de login com senha)
    try:
        saida2 = rodar_psql("SELECT valor_json FROM cache_dados WHERE chave = 'usuarios'")
        dados["lista_login_cache"] = json.loads(saida2.strip() or "[]")
    except Exception as e:
        dados["lista_login_cache"] = [{"erro_leitura": str(e)}]

    with open(destino, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)

    print(f"[OK] Backup gerado: {destino}")
    print(f"     - {len(dados['tabela_usuarios'])} registro(s) na tabela usuarios")
    print(f"     - {len(dados['lista_login_cache'])} usuario(s) na lista de login")
    if isinstance(dados["tabela_usuarios"], list) and dados["tabela_usuarios"] and "erro_leitura" in dados["tabela_usuarios"][0]:
        print("     ATENCAO: houve erro ao ler a tabela usuarios:", dados["tabela_usuarios"][0]["erro_leitura"])


if __name__ == "__main__":
    main()
