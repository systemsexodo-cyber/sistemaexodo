#!/usr/bin/env python3
"""
CORREÇÃO: Sincroniza o número de venda do banco local com o Supabase.

PROBLEMA: Dois bancos locais (máquinas diferentes) com números de venda
          divergentes. O Supabase tem o número correto (mais alto).

SOLUÇÃO:  Busca o maior número de venda no Supabase e atualiza a tabela
          exodo_config do banco local com a chave 'exodo_ultimo_numero_venda'.

COMO USAR:
  1. Feche o sistema Êxodo em TODAS as máquinas antes de rodar.
  2. Execute este script em CADA máquina com o banco local desatualizado.
  3. Após corrigir, abra o sistema normalmente.
"""

import os
import sys
import psycopg2
import requests
from dotenv import load_dotenv

# ─── Carrega variáveis de ambiente ───────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, '.env'))

# ─── Configurações ────────────────────────────────────────────────────────────
SUPABASE_URL  = os.getenv('SUPABASE_URL', '').rstrip('/')
SUPABASE_KEY  = os.getenv('SUPABASE_ANON_KEY', '')

PG_HOST = os.getenv('DB_HOST', 'localhost')
PG_PORT = os.getenv('DB_PORT', '5432')
PG_NAME = os.getenv('DB_NAME', 'exodo_db')
PG_USER = os.getenv('DB_USER', 'exodo_user')
PG_PASS = os.getenv('DB_PASSWORD', '')

CHAVE_CONFIG = 'exodo_ultimo_numero_venda'


def print_sep():
    print("─" * 60)


def buscar_maior_numero_supabase() -> int:
    """Busca o maior número de venda registrado no Supabase."""
    print("\n📡 Conectando ao Supabase...")

    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {SUPABASE_KEY}',
        'Content-Type': 'application/json',
    }

    # Tenta buscar na tabela de vendas balcão
    tabelas_candidatas = [
        ('vendas_balcao', 'numero_venda'),
        ('pedidos',       'numero_venda'),
        ('pedidos',       'numero'),
    ]

    maior = 0

    for tabela, coluna in tabelas_candidatas:
        try:
            url = f"{SUPABASE_URL}/rest/v1/{tabela}?select={coluna}&order={coluna}.desc&limit=1"
            resp = requests.get(url, headers=headers, timeout=10)
            if resp.status_code == 200:
                dados = resp.json()
                if dados and isinstance(dados, list) and dados[0].get(coluna) is not None:
                    valor = int(dados[0][coluna])
                    print(f"   ✓ Tabela '{tabela}'.{coluna}: maior número = {valor}")
                    if valor > maior:
                        maior = valor
            elif resp.status_code == 400:
                # Coluna não existe, ignora
                pass
            else:
                print(f"   ⚠ Tabela '{tabela}': HTTP {resp.status_code}")
        except Exception as e:
            print(f"   ⚠ Erro ao consultar '{tabela}': {e}")

    # Também busca o valor atual gravado na tabela exodo_config do Supabase (se existir)
    try:
        url = f"{SUPABASE_URL}/rest/v1/exodo_config?chave=eq.{CHAVE_CONFIG}&select=valor&limit=1"
        resp = requests.get(url, headers=headers, timeout=10)
        if resp.status_code == 200:
            dados = resp.json()
            if dados:
                valor = int(dados[0]['valor'])
                print(f"   ✓ Supabase exodo_config '{CHAVE_CONFIG}': {valor}")
                if valor > maior:
                    maior = valor
    except Exception as e:
        print(f"   ⚠ Não foi possível ler exodo_config do Supabase: {e}")

    return maior


def ler_numero_local() -> int:
    """Lê o número de venda atual no banco local."""
    try:
        conn = psycopg2.connect(
            host=PG_HOST, port=PG_PORT, dbname=PG_NAME,
            user=PG_USER, password=PG_PASS,
            connect_timeout=5
        )
        with conn.cursor() as cur:
            cur.execute(
                "SELECT valor FROM exodo_config WHERE chave = %s",
                (CHAVE_CONFIG,)
            )
            row = cur.fetchone()
        conn.close()
        if row:
            return int(row[0])
        return 0
    except psycopg2.OperationalError as e:
        print(f"\n❌ Não foi possível conectar ao PostgreSQL local:\n   {e}")
        print(f"\n   Verifique: host={PG_HOST}, porta={PG_PORT}, banco={PG_NAME}, usuário={PG_USER}")
        sys.exit(1)


def atualizar_numero_local(novo_numero: int):
    """Atualiza (ou insere) o número de venda no banco local."""
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_NAME,
        user=PG_USER, password=PG_PASS,
        connect_timeout=5
    )
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO exodo_config (chave, valor, updated_at)
            VALUES (%s, %s, NOW())
            ON CONFLICT (chave) DO UPDATE
              SET valor = EXCLUDED.valor,
                  updated_at = NOW()
        """, (CHAVE_CONFIG, str(novo_numero)))
    conn.commit()
    conn.close()


def main():
    print_sep()
    print("  CORREÇÃO DO NÚMERO DE VENDA - Sistema Êxodo")
    print_sep()

    if not SUPABASE_URL or not SUPABASE_KEY:
        print("\n❌ SUPABASE_URL ou SUPABASE_ANON_KEY não configurados no .env")
        sys.exit(1)

    # 1. Busca número atual local
    local_atual = ler_numero_local()
    print(f"\n📂 Número de venda atual no banco LOCAL: {local_atual}")

    # 2. Busca maior número no Supabase
    maior_supabase = buscar_maior_numero_supabase()

    if maior_supabase == 0:
        print("\n⚠  Não foi possível obter o número do Supabase.")
        resposta = input("   Digite manualmente o número correto (ex: 407) ou ENTER para cancelar: ").strip()
        if not resposta:
            print("❌ Operação cancelada.")
            sys.exit(0)
        maior_supabase = int(resposta)

    print_sep()
    print(f"\n📊 Resumo:")
    print(f"   Local atual  : {local_atual}")
    print(f"   Supabase     : {maior_supabase}")

    if maior_supabase <= local_atual:
        print(f"\n✅ O banco local já está atualizado (local={local_atual} >= supabase={maior_supabase}).")
        print("   Nenhuma alteração necessária.")
        input("\nPressione ENTER para sair...")
        return

    print(f"\n🔄 O banco local será atualizado de {local_atual} → {maior_supabase}")
    resposta = input("\n   Confirma a atualização? (s/N): ").strip().lower()
    if resposta != 's':
        print("❌ Operação cancelada pelo usuário.")
        sys.exit(0)

    # 3. Atualiza banco local
    atualizar_numero_local(maior_supabase)

    # 4. Verifica
    novo_local = ler_numero_local()
    print_sep()
    print(f"\n✅ BANCO LOCAL ATUALIZADO COM SUCESSO!")
    print(f"   Valor gravado: {novo_local}")
    print(f"\n   ➜ Pode abrir o sistema Êxodo normalmente nesta máquina.")
    print(f"   ➜ Execute este script também na OUTRA máquina se necessário.")
    print_sep()
    input("\nPressione ENTER para sair...")


if __name__ == '__main__':
    main()
