#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Migra o banco LOCAL do sistema de WIN1252 para UTF8.

POR QUE ISSO É NECESSÁRIO
-------------------------
O PostgreSQL que acompanha o sistema foi inicializado com o locale do Windows
em português (Portuguese_Brazil.1252), então TODAS as bases nasceram em
**WIN1252**. Consequências práticas:

  * o app não consegue gravar símbolos que não existem no WIN1252 — setas (→),
    emojis (✅ ❌ ⚠), bullets (•). O Postgres recusa com o erro 22P05:
    "caractere com sequência de bytes 0xe2 0x86 0x92 na codificação UTF8 não
    tem equivalente na codificação WIN1252";
  * o histórico de produtos do app usa "→" ("Estoque: 10 → 8 unidades"), então
    essas linhas ficam de fora da base local e a conferência local × nuvem
    nunca fecha;
  * para driblar isso, o app e o sincronizador trocam os símbolos por ASCII
    ("→" vira "->"). Ou seja: o banco local guarda uma versão empobrecida do
    que existe na nuvem.

Em UTF8 nada disso acontece: o dado desce da nuvem exatamente como está.

COMO ESTA MIGRAÇÃO É FEITA (com rede de proteção)
-------------------------------------------------
  1. tira um dump completo do banco atual (formato binário) em
     C:\\ExodoBackups\\migracao_utf8\\;
  2. cria um banco NOVO em UTF8 com o mesmo nome + sufixo "_utf8_novo"
     (o banco atual continua intacto e em funcionamento);
  3. restaura o dump dentro do banco novo;
  4. confere tabela por tabela se a contagem de linhas bateu;
  5. só então troca os nomes: o antigo vira "<nome>_bkp_win1252_<data>" e o
     novo passa a ser o banco do sistema;
  6. confirma que o banco novo aceita gravar "→".

Se qualquer passo falhar antes da troca de nomes, NADA muda para o sistema —
o banco antigo continua no lugar. O banco antigo nunca é apagado.

Uso:
    python migrar_banco_local_utf8.py                (usa o banco do .env)
    python migrar_banco_local_utf8.py --banco NOME   (banco específico)
    python migrar_banco_local_utf8.py --simular      (só mostra o que faria)
"""

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime

RAIZ = os.path.dirname(os.path.abspath(__file__))
PASTA_BACKUP = r"C:\ExodoBackups\migracao_utf8"
BINARIOS = [
    os.path.join(RAIZ, "postgresql", "pgsql", "bin"),
    r"C:\Program Files\PostgreSQL\16\bin",
    r"C:\Program Files\PostgreSQL\15\bin",
]


# ─────────────────────────────────────────────────────────────────────────────
# Utilidades
# ─────────────────────────────────────────────────────────────────────────────

def log(mensagem, tipo="INFO"):
    marcas = {
        "INFO": "   ",
        "OK": "[OK] ",
        "ERRO": "[ERRO] ",
        "AVISO": "[AVISO] ",
        "PASSO": "\n[paso] ",
    }
    print(f"{marcas.get(tipo, '')}{mensagem}", flush=True)


def ler_env():
    valores = {}
    caminho = os.path.join(RAIZ, ".env")
    if not os.path.exists(caminho):
        raise SystemExit("[ERRO] Arquivo .env não encontrado em " + RAIZ)
    with open(caminho, "r", encoding="utf-8", errors="replace") as arquivo:
        for linha in arquivo:
            linha = linha.strip()
            if not linha or linha.startswith("#") or "=" not in linha:
                continue
            chave, valor = linha.split("=", 1)
            valores[chave.strip()] = valor.strip().strip('"').strip("'")
    return valores


def achar_binario(nome):
    exe = nome + (".exe" if os.name == "nt" else "")
    for pasta in BINARIOS:
        caminho = os.path.join(pasta, exe)
        if os.path.exists(caminho):
            return caminho
    return exe  # deixa o PATH resolver


def rodar(binario, argumentos, senha, banco=None):
    """Roda um binário do Postgres e devolve (returncode, saída)."""
    ambiente = dict(os.environ)
    ambiente["PGPASSWORD"] = senha
    ambiente["PGCLIENTENCODING"] = "UTF8"
    ambiente["PGCONNECT_TIMEOUT"] = "15"
    comando = [binario] + list(argumentos)
    if banco is not None:
        comando += ["-d", banco]
    resultado = subprocess.run(
        comando, env=ambiente, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    saida = (resultado.stdout or "") + (resultado.stderr or "")
    return resultado.returncode, saida.strip()


class Postgres:
    """Acesso ao banco via psql (sem precisar instalar driver Python)."""

    def __init__(self, env, banco="postgres"):
        self.psql = achar_binario("psql")
        self.senha = env.get("DB_PASSWORD", "")
        self.host = "127.0.0.1" if env.get("DB_HOST", "localhost").lower() == "localhost" else env["DB_HOST"]
        self.porta = env.get("DB_PORT", "5432")
        self.usuario = env.get("DB_USER", "postgres")
        self.banco = banco

    def executar(self, sql, banco=None):
        """Roda um SQL e devolve as linhas (texto puro, separado por |)."""
        codigo, saida = rodar(
            self.psql,
            ["-h", self.host, "-p", self.porta, "-U", self.usuario,
             "-X", "-q", "-A", "-t", "-F", "|", "-c", sql],
            self.senha,
            banco=banco or self.banco,
        )
        if codigo != 0:
            raise RuntimeError(f"SQL falhou: {sql}\n{saida}")
        return [linha for linha in saida.splitlines() if linha != ""]

    def escalar(self, sql, banco=None):
        linhas = self.executar(sql, banco=banco)
        return linhas[0] if linhas else None

    def existe_banco(self, nome):
        return self.escalar(
            "select 1 from pg_database where datname = '%s'" % nome.replace("'", "''")
        ) is not None


def contagens(banco_pg, nome_banco):
    """Quantas linhas cada tabela do schema public tem neste banco."""
    linhas = banco_pg.executar(
        "select table_name from information_schema.tables "
        "where table_schema = 'public' and table_type = 'BASE TABLE' "
        "order by table_name",
        banco=nome_banco,
    )
    tabelas = [t for t in linhas if "|" not in t]
    resultado = {}
    for tabela in tabelas:
        try:
            total = banco_pg.escalar(
                'select count(*) from public."%s"' % tabela.replace('"', '""'),
                banco=nome_banco,
            )
            resultado[tabela] = int(total) if total is not None else 0
        except RuntimeError:
            resultado[tabela] = None
    return resultado


# ─────────────────────────────────────────────────────────────────────────────
# Migração
# ─────────────────────────────────────────────────────────────────────────────

def migrar(nome_banco, simular=False):
    env = ler_env()
    pg = Postgres(env)

    print("=" * 68)
    print("  MIGRAÇÃO DO BANCO LOCAL PARA UTF8")
    print("=" * 68)
    log(f"banco: {nome_banco}  (host {pg.host}:{pg.porta}, usuário {pg.usuario})")

    if not pg.existe_banco(nome_banco):
        raise SystemExit(f"[ERRO] O banco \"{nome_banco}\" não existe.")

    encoding_atual = pg.escalar(
        "select pg_encoding_to_char(encoding) from pg_database "
        "where datname = '%s'" % nome_banco.replace("'", "''")
    )
    collate = pg.escalar(
        "select datcollate from pg_database where datname = '%s'"
        % nome_banco.replace("'", "''")
    )
    log(f"encoding atual: {encoding_atual} | collation: {collate}")

    if encoding_atual == "UTF8":
        log("Este banco já está em UTF8 — nada a fazer.", "OK")
        return 0

    # Ninguém conectado: renomear banco exige isso, e o sincronizador da
    # bandeja reconecta sozinho — por isso ele precisa estar fechado.
    ativos = pg.executar(
        "select usename || '@' || coalesce(client_addr::text, 'local') || ' pid ' || pid "
        "from pg_stat_activity where datname = '%s' and pid <> pg_backend_pid()"
        % nome_banco.replace("'", "''")
    )
    if ativos:
        log("Existem conexões abertas nesse banco:", "ERRO")
        for linha in ativos:
            log("   " + linha)
        log("Feche o sistema (janela) e o SincronizadorNuvem (ícone da bandeja → Sair) "
            "e rode este script de novo.", "ERRO")
        return 2
    log("nenhuma conexão aberta no banco", "OK")

    sufixo = datetime.now().strftime("%Y%m%d_%H%M")
    novo_banco = f"{nome_banco}_utf8_novo"
    banco_antigo = f"{nome_banco}_bkp_win1252_{sufixo}"
    arquivo_dump = os.path.join(PASTA_BACKUP, f"{nome_banco}_{sufixo}.dump")

    if simular:
        log(f"[simulação] dump para {arquivo_dump}")
        log(f"[simulação] criar banco {novo_banco} em UTF8")
        log(f"[simulação] restaurar o dump nele e comparar as contagens")
        log(f"[simulação] renomear {nome_banco} → {banco_antigo} e {novo_banco} → {nome_banco}")
        return 0

    os.makedirs(PASTA_BACKUP, exist_ok=True)

    # 1) Dump do banco atual -------------------------------------------------
    log(f"1/6 tirando dump do banco atual...", "PASSO")
    codigo, saida = rodar(
        achar_binario("pg_dump"),
        ["-h", pg.host, "-p", pg.porta, "-U", pg.usuario,
         "-Fc", "--no-owner", "-f", arquivo_dump, "-d", nome_banco],
        pg.senha,
    )
    if codigo != 0 or not os.path.exists(arquivo_dump):
        log(saida, "ERRO")
        raise SystemExit("[ERRO] O dump falhou — nada foi alterado.")
    tamanho = os.path.getsize(arquivo_dump) / 1024
    log(f"dump: {arquivo_dump} ({tamanho:.0f} kB)", "OK")

    # 2) Banco novo em UTF8 --------------------------------------------------
    log("2/6 criando o banco novo em UTF8...", "PASSO")
    if pg.existe_banco(novo_banco):
        pg.executar(f'DROP DATABASE "{novo_banco}"')
    pg.executar(
        f'CREATE DATABASE "{novo_banco}" WITH OWNER "{pg.usuario}" '
        f"ENCODING 'UTF8' LC_COLLATE '{collate}' LC_CTYPE '{collate}' "
        f"TEMPLATE template0"
    )
    log(f"banco {novo_banco} criado em UTF8", "OK")

    try:
        # 3) Restauração -----------------------------------------------------
        log("3/6 restaurando o dump no banco novo...", "PASSO")
        codigo, saida = rodar(
            achar_binario("pg_restore"),
            ["-h", pg.host, "-p", pg.porta, "-U", pg.usuario,
             "--no-owner", "--no-privileges", "-d", novo_banco, arquivo_dump],
            pg.senha,
        )
        erros = [l for l in saida.splitlines() if re.search(r"error|erro", l, re.I)]
        if codigo != 0 and erros:
            for linha in erros[:10]:
                log(linha, "ERRO")
            raise SystemExit("[ERRO] A restauração falhou — o sistema continua "
                             f"no banco antigo. O dump está em {arquivo_dump}")
        if erros:
            log(f"{len(erros)} aviso(s) durante a restauração (normalmente inofensivo):", "AVISO")
            for linha in erros[:5]:
                log("   " + linha)
        log("dump restaurado no banco novo", "OK")

        # 4) Contagens antes × depois ----------------------------------------
        log("4/6 conferindo as contagens tabela por tabela...", "PASSO")
        antes = contagens(pg, nome_banco)
        depois = contagens(pg, novo_banco)
        divergentes = [
            (t, antes.get(t), depois.get(t))
            for t in sorted(set(antes) | set(depois))
            if antes.get(t) != depois.get(t)
        ]
        total_antes = sum(v for v in antes.values() if v)
        total_depois = sum(v for v in depois.values() if v)
        log(f"tabelas: {len(antes)} → {len(depois)} | linhas: {total_antes} → {total_depois}")
        if divergentes:
            log("Tabelas com contagem diferente (%d):" % len(divergentes), "ERRO")
            for tabela, a, d in divergentes[:15]:
                log(f"   {tabela}: {a} → {d}", "ERRO")
            raise SystemExit("[ERRO] As contagens não batem — NADA foi trocado. "
                             f"O banco atual continua no lugar. Dump: {arquivo_dump}")
        log("todas as contagens idênticas", "OK")

        # 5) Troca de nomes --------------------------------------------------
        log("5/6 trocando os nomes dos bancos...", "PASSO")
        pg.executar(f'ALTER DATABASE "{nome_banco}" RENAME TO "{banco_antigo}"')
        try:
            pg.executar(f'ALTER DATABASE "{novo_banco}" RENAME TO "{nome_banco}"')
        except RuntimeError:
            # Desfaz para não deixar o sistema sem banco com o nome esperado.
            pg.executar(f'ALTER DATABASE "{banco_antigo}" RENAME TO "{nome_banco}"')
            raise
        log(f"banco antigo guardado como {banco_antigo}", "OK")

        # 6) Prova de que o banco novo aceita símbolo -------------------------
        log("6/6 testando símbolos que o banco antigo não aceitava...", "PASSO")
        pg.executar(
            "create temp table _prova (x text); "
            "insert into _prova values ('estoque: 10 → 8 ✅'); "
            "select length(x) from _prova",
            banco=nome_banco,
        )
        log('o banco novo gravou "estoque: 10 → 8 ✅"', "OK")

    except BaseException:
        log(f"o banco novo ({novo_banco}) ficou no servidor para conferência; "
            f"o dump está em {arquivo_dump}", "AVISO")
        raise

    print()
    print("=" * 68)
    print("  MIGRAÇÃO CONCLUÍDA")
    print("=" * 68)
    log(f"banco em uso: {nome_banco} (UTF8)")
    log(f"banco antigo: {banco_antigo} (WIN1252 — pode ser apagado depois que "
        f"tudo estiver conferido, ex.: DROP DATABASE \"{banco_antigo}\";)")
    log(f"dump: {arquivo_dump}")
    log("Abra o sistema de novo: os símbolos (→, ✅) agora são gravados como na nuvem.")
    return 0


def preparar_saida():
    """O console do Windows costuma estar em cp1252 — o próprio "→" que este
    script existe para resolver derrubaria o print. Aqui a saída vira UTF-8 e,
    se o console não aceitar algum símbolo, ele é substituído em vez de estourar."""
    for fluxo in (sys.stdout, sys.stderr):
        try:
            fluxo.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def main():
    preparar_saida()
    analisador = argparse.ArgumentParser(description="Migra o banco local para UTF8.")
    analisador.add_argument("--banco", help="nome do banco (padrão: o do .env)")
    analisador.add_argument("--simular", action="store_true",
                            help="mostra o que seria feito, sem alterar nada")
    argumentos = analisador.parse_args()

    nome_banco = argumentos.banco
    if not nome_banco:
        nome_banco = ler_env().get("DB_NAME", "exodo_db")

    try:
        return migrar(nome_banco, simular=argumentos.simular)
    except RuntimeError as erro:
        log(str(erro), "ERRO")
        return 1


if __name__ == "__main__":
    sys.exit(main())
