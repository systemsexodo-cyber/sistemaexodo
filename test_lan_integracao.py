#!/usr/bin/env python3
"""
Teste de INTEGRAÇÃO da sincronização LAN (dois PostgreSQL de verdade).

Sobe DOIS clusters PostgreSQL temporários (PC-A e PC-B), aplica o schema real
(`scripts/init_db.sql`) nos dois e prova o que o usuário precisa que seja
verdade:

  1. INSERT feito em A aparece em B depois de UM ciclo da LAN;
  2. UPDATE feito em A (que só chega se o trigger `set_updated_at` carimbar
     `updated_at`) aparece em B;
  3. DELETE feito em A some de B (via `_exodo_deletados`);
  4. a réplica aplicada em B NÃO volta para a fila (`_exodo_sync_log` limpo);
  5. o cadastro de `empresas` chega INTEIRO, mesmo as linhas cujo `empresa_id`
     é de outra empresa e mesmo com `updated_at` antigo (era isso que deixava a
     tela de selecao com UMA empresa só);
  6. tudo dentro de "segundos" — é o ciclo que o loop dedicado (`LAN_INTERVALO`,
     padrão 2s) roda no tray.

Se os binários do PostgreSQL não forem encontrados, o teste é PULADO (retorna 0)
para não quebrar um ambiente sem banco. Aponte a pasta com `EXODO_PG_BIN` se
estiver em outro lugar.

Rodar: .venv\\Scripts\\python.exe test_lan_integracao.py
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, '.')
import psycopg2  # noqa: E402

import sincronizador_lan as L  # noqa: E402
import sincronizar_local_supabase as S  # noqa: E402

RAIZ = Path(__file__).resolve().parent
USUARIO = 'exodo_user'
EMPRESA = 'E1'
DB = 'postgres'


# ─────────────────────────── Localizar o PostgreSQL ───────────────────────────

def _achar_pg_bin():
    """Devolve a pasta com initdb/pg_ctl, ou None se não houver PostgreSQL."""
    candidatos = []
    env = os.environ.get('EXODO_PG_BIN')
    if env:
        candidatos.append(Path(env))
    candidatos.append(Path(r'C:\SistemaExodo\postgresql\bin'))
    prog = Path(r'C:\Program Files\PostgreSQL')
    if prog.is_dir():
        versoes = sorted(
            (p / 'bin' for p in prog.iterdir() if (p / 'bin').is_dir()),
            key=lambda p: p.parent.name, reverse=True)
        candidatos.extend(versoes)

    for pasta in candidatos:
        if (pasta / 'initdb.exe').exists() or (pasta / 'initdb').exists():
            return pasta

    achado = shutil.which('initdb')
    if achado:
        return Path(achado).parent
    return None


def _bin(pasta, nome):
    exe = pasta / f'{nome}.exe'
    return str(exe if exe.exists() else pasta / nome)


# ─────────────────────────── Ciclo de vida do cluster ───────────────────────────

def _porta_livre():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


# CREATE_NO_WINDOW: abre o postgres sem janela e, principalmente, sem herdar os
# pipes do processo Python — sem isso o `communicate()` fica esperando para
# sempre no Windows.
CREATE_NO_WINDOW = 0x08000000


def _rodar(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def _initdb(pg, datadir):
    r = _rodar([_bin(pg, 'initdb'), '-D', str(datadir), '-U', USUARIO,
                '--auth=trust', '--encoding=UTF8', '--locale=C', '--no-sync'])
    if r.returncode != 0:
        raise RuntimeError(f'initdb falhou: {r.stdout}\n{r.stderr}')


def _iniciar(pg, datadir, porta):
    """Sobe o `postgres` direto (não o `pg_ctl`).

    No Windows, o `pg_ctl start` no ambiente MSYS/bash não retorna (o postgres
    filho segura os pipes) e os backends podem morrer com 0xC0000142. Abrir o
    `postgres.exe` via Popen com CREATE_NO_WINDOW é a forma estável.
    """
    log = datadir.parent / f'{datadir.name}.log'
    arquivo = open(log, 'w', encoding='utf-8')
    proc = subprocess.Popen(
        [_bin(pg, 'postgres'), '-D', str(datadir), '-p', str(porta),
         '-c', 'listen_addresses=127.0.0.1', '-c', 'fsync=off',
         '-c', 'full_page_writes=off'],
        stdout=arquivo, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        creationflags=CREATE_NO_WINDOW)
    proc._log_file = arquivo  # fecha no _parar
    proc._log_path = log
    return proc


def _parar(pg, datadir, proc):
    # Encerramento limpo pelo pg_ctl; se não der, derruba o processo.
    try:
        _rodar([_bin(pg, 'pg_ctl'), '-D', str(datadir), '-m', 'immediate',
                '-w', '-t', '20', 'stop'], timeout=25)
    except Exception:
        pass
    if proc is not None:
        try:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            proc._log_file.close()
        except Exception:
            pass


def _conectar(porta):
    """Conecta no cluster recém-subido, esperando ele aceitar."""
    ultimo = None
    for _ in range(60):
        try:
            return psycopg2.connect(
                host='127.0.0.1', port=porta, dbname=DB, user=USUARIO,
                password='', connect_timeout=3)
        except Exception as e:  # noqa: BLE001
            ultimo = e
            time.sleep(0.5)
    raise RuntimeError(f'não conectou na porta {porta}: {ultimo}')


def _aplicar_schema(conn):
    sql = (RAIZ / 'scripts' / 'init_db.sql').read_text(encoding='utf-8')
    with conn.cursor() as cur:
        cur.execute(sql)
        # O dump começa com `set_config('search_path', '')` para qualificar
        # tudo por schema. Sem restaurar o public, as consultas seguintes do
        # sincronizador (que usam nomes sem schema, ex. `_sync_controle`)
        # falhariam nesta sessão.
        cur.execute('SET search_path TO public')
    conn.commit()


# ─────────────────────────── Apoio ───────────────────────────

def _cfg(porta, nome):
    return {
        'host': '127.0.0.1', 'port': str(porta), 'dbname': DB, 'user': USUARIO,
        'password': '', 'nome': nome, 'dias_tombstone': 30,
        'inicial_completo': False,
    }


def _definir_empresa_ativa(conn, empresa):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO cache_dados (chave, valor_json, ultima_atualizacao) "
            "VALUES ('exodo_empresa_ativa', %s, NOW()) "
            "ON CONFLICT (chave) DO UPDATE SET valor_json = EXCLUDED.valor_json",
            (empresa,))
    conn.commit()


def _ler_produto(conn, pid):
    with conn.cursor() as cur:
        cur.execute('SELECT nome, updated_at FROM produtos WHERE id=%s', (pid,))
        return cur.fetchone()


def _log_pendente(conn, pid):
    with conn.cursor() as cur:
        cur.execute('SELECT COUNT(*) FROM _exodo_sync_log WHERE record_id=%s', (pid,))
        return cur.fetchone()[0]


def _falhou(msg):
    print(f'  [FALHOU] {msg}')
    # Retorna código de saída, não bool: `False == 0` é True em Python e o
    # `sys.exit(0 if ok == 0 ...)` do fim do arquivo passaria a falha como sucesso.
    return 1


# ─────────────────────────── Teste ───────────────────────────

def executar():
    pg = _achar_pg_bin()
    if pg is None:
        print('SKIP: binários do PostgreSQL não encontrados '
              '(defina EXODO_PG_BIN para apontar a pasta bin/).')
        return 0

    base = Path(tempfile.mkdtemp(prefix='exodo_lan_'))
    a_dir, b_dir = base / 'A', base / 'B'
    a_porta, b_porta = _porta_livre(), _porta_livre()
    print(f'[postgres] bin={pg}')
    print(f'[postgres] PC-A porta {a_porta} | PC-B porta {b_porta}')

    conn_a = conn_b = None
    proc_a = proc_b = None
    try:
        _initdb(pg, a_dir)
        _initdb(pg, b_dir)
        proc_a = _iniciar(pg, a_dir, a_porta)
        proc_b = _iniciar(pg, b_dir, b_porta)

        conn_a = _conectar(a_porta)
        conn_b = _conectar(b_porta)
        _aplicar_schema(conn_a)
        _aplicar_schema(conn_b)
        _definir_empresa_ativa(conn_a, EMPRESA)
        _definir_empresa_ativa(conn_b, EMPRESA)

        cfg_a = _cfg(a_porta, 'PC-A')   # como B enxerga A
        cfg_b = _cfg(b_porta, 'PC-B')   # como A enxerga B

        # Silencia o log do sincronizador e garante o controle.
        S.garantir_tabela_controle(conn_a)
        S.garantir_tabela_controle(conn_b)

        # Warm-up: 1º contato fixa os cursores "de agora" (por design).
        L.sincronizar_com_par(conn_a, cfg_b)
        L.sincronizar_com_par(conn_b, cfg_a)

        # ── 1. INSERT propaga em um ciclo ──
        print('1) INSERT no PC-A aparece no PC-B em um ciclo')
        with conn_a.cursor() as cur:
            cur.execute(
                "INSERT INTO produtos (id, empresa_id, nome, updated_at) "
                "VALUES ('P1', %s, 'COCA', NOW())", (EMPRESA,))
        conn_a.commit()
        if _log_pendente(conn_a, 'P1') == 0:
            return _falhou('o INSERT não entrou na fila (_exodo_sync_log)')

        t0 = time.perf_counter()
        resumo = L.sincronizar_com_par(conn_b, cfg_a)
        decorrido = time.perf_counter() - t0
        linha = _ler_produto(conn_b, 'P1')
        if linha is None:
            return _falhou(f'P1 não chegou ao PC-B (resumo={resumo})')
        if linha[0] != 'COCA':
            return _falhou(f'nome errado no PC-B: {linha[0]}')
        if decorrido > 10:
            return _falhou(f'ciclo demorou {decorrido:.1f}s (esperado < 10s)')
        print(f'  [ok] chegou em {decorrido:.2f}s '
              f'({resumo["recebidos"]} recebido(s))')

        # ── 2. UPDATE propaga (só funciona se o trigger carimbar updated_at) ──
        print('2) UPDATE no PC-A aparece no PC-B (trigger set_updated_at)')
        with conn_a.cursor() as cur:
            cur.execute("SELECT updated_at FROM produtos WHERE id='P1'")
            antes = cur.fetchone()[0]
            # Sem sync_mode='on' = escrita do usuário; o trigger deve carimbar.
            cur.execute("UPDATE produtos SET nome='COCA ZERO' WHERE id='P1'")
            cur.execute("SELECT updated_at FROM produtos WHERE id='P1'")
            depois = cur.fetchone()[0]
        conn_a.commit()
        if not (depois and antes and depois > antes):
            return _falhou(f'updated_at não avançou: {antes} -> {depois}')

        L.sincronizar_com_par(conn_b, cfg_a)
        linha = _ler_produto(conn_b, 'P1')
        if linha is None or linha[0] != 'COCA ZERO':
            return _falhou(f'UPDATE não chegou ao PC-B: {linha}')
        print('  [ok] updated_at avançou e a alteração chegou')

        # ── 3. DELETE propaga via _exodo_deletados ──
        print('3) DELETE no PC-A some do PC-B (tombstone)')
        with conn_a.cursor() as cur:
            cur.execute("DELETE FROM produtos WHERE id='P1'")
        conn_a.commit()
        L.sincronizar_com_par(conn_b, cfg_a)
        if _ler_produto(conn_b, 'P1') is not None:
            return _falhou('P1 deveria ter sido apagado no PC-B')
        print('  [ok] apagado replicado')

        # ── 4. Réplica não volta para a fila ──
        print('4) o que o PC-B aplicou não entra na fila dele')
        pendentes = _log_pendente(conn_b, 'P1')
        if pendentes != 0:
            return _falhou(f'PC-B registrou a réplica como pendente ({pendentes})')
        print('  [ok] _exodo_sync_log do PC-B limpo')

        # ── 5. Empresas de OUTRO dono replicam ──
        # Em `empresas` cada linha aponta para ela mesma (empresa_id = id).
        # Filtrar por `empresa_id = empresa_ativa` — que vale para TODA outra
        # tabela — faria o PC-B receber só a empresa que já está ativa nele, e a
        # tela de seleção ficaria com uma empresa só. E2 ainda traz um
        # `updated_at` de 2020, antigo: um cadastro lido por cursor a pularia.
        print('5) empresas de outras empresas replicam (inclusive antigas)')
        with conn_a.cursor() as cur:
            cur.execute(
                "INSERT INTO empresas "
                "(id, razao_social, empresa_id, ativo, updated_at) VALUES "
                "('E1', 'Empresa ativa aqui', 'E1', TRUE, NOW()), "
                "('E2', 'Outra empresa', 'E2', TRUE, "
                " TIMESTAMP '2020-01-01 00:00:00+00')")
        conn_a.commit()

        L.sincronizar_com_par(conn_b, cfg_a)
        with conn_b.cursor() as cur:
            cur.execute('SELECT id FROM empresas ORDER BY id')
            ids = [r[0] for r in cur.fetchall()]
        faltando = [e for e in ('E1', 'E2') if e not in ids]
        if faltando:
            return _falhou(
                f'empresas não replicaram no PC-B (faltando {faltando}; '
                f'PC-B tem {ids})')
        print(f'  [ok] {len(ids)} empresa(s) no PC-B: {", ".join(ids)}')

        # ── 6. empresas IGUAIS nao sao reescritas a cada ciclo ──
        # `empresas` e relida inteira todo ciclo. Reescrever a mesma linha
        # dispara o trigger, cria fila de envio e o ciclo seguinte reencontra
        # tudo "pendente": um laco de escrita sem fim. Aqui limpamos a fila
        # (o que upload_tabela faz) e exigimos ZERO gravacoes.
        print('6) empresas iguais nao sao reescritas; alteracao real continua passando')
        with conn_b.cursor() as cur:
            cur.execute("DELETE FROM _exodo_sync_log WHERE table_name = 'empresas'")
        conn_b.commit()

        resumo = L.sincronizar_com_par(conn_b, cfg_a)
        if resumo.get('recebidos', 0) != 0:
            return _falhou(
                f"o ciclo reescreveu empresas sem mudanca ({resumo.get('recebidos')})")

        # E agora o opposites: mudanca DE VERDADE tem que chegar.
        with conn_a.cursor() as cur:
            cur.execute(
                "UPDATE empresas SET razao_social = 'EXODO SYSTEMS LTDA - ALTERADA' "
                "WHERE id = 'E1'")
        conn_a.commit()
        L.sincronizar_com_par(conn_b, cfg_a)
        with conn_b.cursor() as cur:
            cur.execute("SELECT razao_social FROM empresas WHERE id = 'E1'")
            row = cur.fetchone()
        if not row or 'ALTERADA' not in (row[0] or ''):
            return _falhou(f'alteracao real de empresa nao chegou ao PC-B: {row}')
        print('  [ok] 0 reescritas no ciclo ocioso e a alteracao real chegou')

        print('\n6/6 etapas de integração passaram')
        return 0
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        return _e_falha(e)
    finally:
        for conn in (conn_a, conn_b):
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass
        _parar(pg, a_dir, proc_a)
        _parar(pg, b_dir, proc_b)
        shutil.rmtree(base, ignore_errors=True)


def _e_falha(e):
    print(f'  [FALHOU] exceção: {e}')
    return 1


if __name__ == '__main__':
    ok = executar()
    sys.exit(0 if ok == 0 or ok is True else 1)
