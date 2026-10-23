import os
import sys
import threading
import time
import psycopg2
from PIL import Image, ImageDraw
import pystray
from pystray import MenuItem as item

# Redirecionar stdout/stderr se forem None (evita crashes no PyInstaller --noconsole)
if sys.stdout is None:
    class DummyWriter:
        def write(self, *args, **kwargs): pass
        def flush(self, *args, **kwargs): pass
    sys.stdout = DummyWriter()
if sys.stderr is None:
    class DummyWriter:
        def write(self, *args, **kwargs): pass
        def flush(self, *args, **kwargs): pass
    sys.stderr = DummyWriter()

# Importar as lógicas já desenvolvidas
import setup_sync_local
import sincronizar_local_supabase
import sincronizador_lan

# Diretorio base: quando congelado (exe), a pasta do executavel; senao, a pasta do script.
# IMPORTANTE: no PyInstaller onefile, o .env precisa ser apontado explicitamente para
# a pasta do executavel -- nao para a pasta temporaria _MEIxxxx. Por isso usamos
# carregar_arquivos_env(self.base_dir) em vez de load_dotenv() sem caminho.
def get_base_dir():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

BASE_DIR = get_base_dir()


class SyncTrayApp:
    def __init__(self):
        self.icon = None
        self.running = True
        self.sync_thread = None
        self.lan_thread = None
        self.status = "Iniciando..."
        self.last_sync = "Nunca"
        self.total_synced = 0
        self.base_dir = BASE_DIR

        # Carregar o .env (e o .env.neon, com as credenciais do Neon) SEMPRE a
        # partir da pasta do executavel
        env_path = os.path.join(self.base_dir, '.env')
        env_existe = os.path.exists(env_path)
        sincronizar_local_supabase.carregar_arquivos_env(self.base_dir)

        # Poda o log já na subida: mantém só os últimos 7 dias (e o teto de
        # tamanho). Sem isso o sincronizador.log crescia sem limite e a opção
        # "Ver Logs" ficava pesada.
        try:
            sincronizar_local_supabase.podar_log(forcar=True)
        except Exception:
            pass

        # Nuvem ATIVA: Neon (principal) ou Supabase (reserva). Ver resolver_nuvem.
        try:
            self.nuvem_provedor, self.supabase_url, self.api_key = \
                sincronizar_local_supabase.resolver_nuvem()
        except Exception as e_nuvem:
            self.nuvem_provedor, self.supabase_url, self.api_key = None, None, None
            sincronizar_local_supabase.print_log(
                f"[INIT] Nuvem nao configurada: {e_nuvem}",
                sincronizar_local_supabase.Colors.RED)

        self.db_host = os.getenv('DB_HOST', 'localhost')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')

        # Log de inicializacao para facilitar diagnostico (agora vai para sincronizador.log)
        faltando = [v for v in ('DB_NAME', 'DB_USER', 'DB_PASSWORD') if not os.getenv(v)]
        if not (self.supabase_url and self.api_key):
            faltando.append('NEON_DATA_API_URL (ou SUPABASE_URL, de reserva)')
        if not env_existe:
            sincronizar_local_supabase.print_log(
                f"[INIT] AVISO: .env nao encontrado em {env_path}. Copie o .env para a pasta do executavel.",
                sincronizar_local_supabase.Colors.YELLOW)
        elif faltando:
            sincronizar_local_supabase.print_log(
                f"[INIT] AVISO: .env incompleto em {env_path}. Faltando: {faltando}",
                sincronizar_local_supabase.Colors.YELLOW)
        else:
            sincronizar_local_supabase.print_log(
                f"[INIT] .env carregado de {env_path} | Nuvem: {self.nuvem_provedor} "
                f"({self.supabase_url}) | Banco local: "
                f"{self.db_user}@{self.db_host}:{self.db_port}/{self.db_name}",
                sincronizar_local_supabase.Colors.GREEN)

        # Intervalo do loop dedicado da LAN (segundos). Curto de propósito:
        # é o que faz a mudança feita no outro PC aparecer aqui em poucos
        # segundos, sem depender da nuvem. Ajustável por LAN_INTERVALO no .env.
        try:
            self.lan_intervalo = max(1.0, float(os.getenv('LAN_INTERVALO') or '2'))
        except Exception:
            self.lan_intervalo = 2.0

        # Intervalo do loop rápido do CATÁLOGO (segundos). É o que faz a
        # alteração de produto feita no site aparecer no app local em poucos
        # segundos, sem esperar o ciclo completo de ~30 s. Ajustável por
        # PRODUTOS_INTERVALO no .env; 0 desliga.
        try:
            self.produtos_intervalo = max(
                0.0, float(os.getenv('PRODUTOS_INTERVALO') or '3'))
        except Exception:
            self.produtos_intervalo = 3.0

        # Verdadeiro enquanto o ciclo completo está rodando: o loop rápido espera
        # (as duas rotinas escrevem nas MESMAS tabelas e dividem o cursor).
        self._em_ciclo_completo = False

        # Sincronização pela REDE LOCAL (par). None = desligada.
        self.par_cfg = sincronizador_lan.config_do_par()
        if self.par_cfg:
            sincronizar_local_supabase.print_log(
                f"[INIT] LAN ativa para o par {self.par_cfg['nome']} "
                f"({self.par_cfg['host']}:{self.par_cfg['port']}/{self.par_cfg['dbname']}).",
                sincronizar_local_supabase.Colors.GREEN)
        else:
            sincronizar_local_supabase.print_log(
                "[INIT] LAN desligada (no sistema: tela inicial > botao "
                "'Rede LAN' para sincronizar direto com o outro PC).",
                sincronizar_local_supabase.Colors.CYAN)

    def create_image(self, color=(52, 152, 219)):
        # Cria um ícone de nuvem simples para a bandeja com a cor fornecida
        width = 64
        height = 64
        image = Image.new('RGBA', (width, height), (0, 0, 0, 0))
        dc = ImageDraw.Draw(image)
        dc.ellipse([10, 30, 30, 50], fill=color)
        dc.ellipse([20, 20, 45, 50], fill=color)
        dc.ellipse([35, 30, 55, 50], fill=color)
        dc.rectangle([20, 40, 45, 50], fill=color)
        return image

    def update_status_icon(self, state_type, status_text=None):
        """Atualiza a cor do ícone de nuvem com base no estado atual da sincronização."""
        if not self.icon:
            return
            
        colors = {
            'online': (46, 204, 113),    # Verde
            'syncing': (230, 126, 34),   # Laranja
            'offline': (231, 76, 60),    # Vermelho
            'conflict': (241, 196, 15),  # Amarelo
            'paused': (149, 165, 166),   # Cinza
        }
        
        color = colors.get(state_type, (52, 152, 219)) # Azul fallback
        self.icon.icon = self.create_image(color)
        
        if status_text is not None:
            self.status = status_text
        elif state_type == 'offline':
            self.status = "Offline (veja sincronizador.log)"
        elif state_type == 'syncing':
            self.status = "Sincronizando..."
        elif state_type == 'conflict':
            self.status = f"Conflitos pendentes | Ultima: {self.last_sync}"
        elif state_type == 'paused':
            self.status = 'Nuvem pausada para esta empresa'
        self.update_icon_tooltip()

    def run_setup_transparently(self):
        try:
            self.status = "Configurando banco local..."
            self.update_icon_tooltip()
            setup_sync_local.main()
        except Exception as e:
            self.status = "Erro no setup do banco local"
            self.update_icon_tooltip()
            sincronizar_local_supabase.print_log(f"[SETUP] Erro no setup do banco local: {e}",
                                                 sincronizar_local_supabase.Colors.RED)

    def _tentar_iniciar_postgres(self):
        """Tenta iniciar o PostgreSQL embarcado (C:\\SistemaExodo\\postgresql\\bin).
        Usado quando o banco local esta fora do ar - o tray se auto-recupera."""
        import subprocess
        pg_ctl = os.path.join(self.base_dir, 'postgresql', 'bin', 'pg_ctl.exe')
        # O banco real fica em pgdata (mesmo data dir do servico). a pasta "data"
        # era o path antigo e hoje costuma ter so assets do Flutter; usar ela
        # fazia o tray subir/setar o banco no cluster vazio.
        data_dir = None
        for candidato in ('pgdata', 'data'):
            tentativa = os.path.join(self.base_dir, candidato)
            if os.path.isfile(os.path.join(tentativa, 'postgresql.conf')):
                data_dir = tentativa
                break
        if not os.path.exists(pg_ctl) or data_dir is None:
            sincronizar_local_supabase.print_log(
                f"[PG] pg_ctl nao encontrado ({pg_ctl}) ou data dir valido nao encontrado "
                f"({os.path.join(self.base_dir, 'pgdata')} ou "
                f"{os.path.join(self.base_dir, 'data')})",
                sincronizar_local_supabase.Colors.YELLOW)
            return False
        log_path = os.path.join(self.base_dir, 'logs', 'postgresql.log')
        try:
            # Garantir que a pasta de logs existe (instalacoes antigas podem nao ter)
            try:
                os.makedirs(os.path.dirname(log_path), exist_ok=True)
            except Exception:
                pass
            # Se a maquina desligou com o banco aberto, sobra um postmaster.pid obsoleto
            # que faz o pg_ctl start falhar. Se nenhum postgres.exe estiver rodando, remove.
            pid_file = os.path.join(data_dir, 'postmaster.pid')
            if os.path.exists(pid_file) and not self._postgres_processando():
                sincronizar_local_supabase.print_log(
                    "[PG] Removendo postmaster.pid obsoleto (nenhum postgres.exe ativo).",
                    sincronizar_local_supabase.Colors.YELLOW)
                try:
                    os.remove(pid_file)
                except Exception:
                    pass
            r = subprocess.run(
                [pg_ctl, '-D', data_dir, '-l', log_path, 'start', '-w', '-t', '30'],
                capture_output=True, text=True, timeout=45,
                creationflags=0x08000000)  # CREATE_NO_WINDOW
            if r.returncode == 0:
                sincronizar_local_supabase.print_log(
                    "[PG] PostgreSQL iniciado automaticamente pelo tray.",
                    sincronizar_local_supabase.Colors.GREEN)
                return True
            sincronizar_local_supabase.print_log(
                f"[PG] pg_ctl start falhou: {r.stdout.strip()} {r.stderr.strip()}",
                sincronizar_local_supabase.Colors.RED)
            return False
        except Exception as e:
            sincronizar_local_supabase.print_log(
                f"[PG] Erro ao tentar iniciar PostgreSQL: {e}",
                sincronizar_local_supabase.Colors.RED)
            return False

    def _postgres_processando(self):
        """True se existe algum postgres.exe rodando (evita apagar pid em uso)."""
        import subprocess
        try:
            r = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq postgres.exe'],
                               capture_output=True, text=True, timeout=15,
                               creationflags=0x08000000)
            return 'postgres.exe' in r.stdout
        except Exception:
            return False

    def sync_cycle(self, force=False):
        if not all([self.supabase_url, self.api_key, self.db_name, self.db_user, self.db_password]):
            self.status = "Erro: .env incompleto!"
            sincronizar_local_supabase.print_log(
                "[CICLO] .env incompleto! Verifique o arquivo .env ao lado do executavel.",
                sincronizar_local_supabase.Colors.RED)
            self.update_icon_tooltip()
            return

        conn = None
        try:
            # 1. Conectar no banco LOCAL (exodo_user@localhost:5432/exodo_db)
            try:
                conn = psycopg2.connect(
                    host=self.db_host, port=self.db_port, dbname=self.db_name,
                    user=self.db_user, password=self.db_password, connect_timeout=5
                )
            except Exception as e_db:
                sincronizar_local_supabase.print_log(
                    f"[CICLO] ERRO ao conectar no PostgreSQL local "
                    f"({self.db_user}@{self.db_host}:{self.db_port}/{self.db_name}): {e_db}",
                    sincronizar_local_supabase.Colors.RED)
                # AUTO-RECUPERACAO: tenta iniciar o PostgreSQL embarcado
                if self._tentar_iniciar_postgres():
                    sincronizar_local_supabase.print_log(
                        "[CICLO] PostgreSQL iniciado pelo tray, tentando reconectar...",
                        sincronizar_local_supabase.Colors.YELLOW)
                    time.sleep(5)
                    try:
                        conn = psycopg2.connect(
                            host=self.db_host, port=self.db_port, dbname=self.db_name,
                            user=self.db_user, password=self.db_password, connect_timeout=8
                        )
                    except Exception as e_retry:
                        self.update_status_icon('offline',
                            f"Banco local indisponivel ({self.db_host}:{self.db_port})")
                        sincronizar_local_supabase.print_log(
                            f"[CICLO] Reconexao falhou apos iniciar PostgreSQL: {e_retry}",
                            sincronizar_local_supabase.Colors.RED)
                        return
                else:
                    self.update_status_icon('offline',
                        f"Banco local indisponivel ({self.db_host}:{self.db_port})")
                    return

            # Garantir tabela de controle
            sincronizar_local_supabase.garantir_tabela_controle(conn)

            # ── REDE LOCAL (par) ──
            # A LAN saiu daqui: agora tem um loop PRÓPRIO e mais rápido
            # (`lan_loop`, a cada LAN_INTERVALO segundos). Antes ela rodava só
            # dentro deste ciclo de ~10s, então uma mudança no outro PC podia
            # demorar até 10s para aparecer — e dependia da nuvem para acelerar.
            # O ciclo da nuvem segue cuidando só da nuvem.
            lan = None

            # Executa o ciclo otimizado de sincronização com o callback de mudança de estado
            # Renova o token da nuvem (o do Neon expira em ~1h) a cada ciclo.
            try:
                _provedor, nuvem_url, api_key = sincronizar_local_supabase.resolver_nuvem()
            except Exception as e_res:
                nuvem_url, api_key = self.supabase_url, self.api_key
                sincronizar_local_supabase.print_log(
                    f"[CICLO] Nuvem indisponivel ({e_res}); usando a ultima credencial.",
                    sincronizar_local_supabase.Colors.YELLOW)
            self._em_ciclo_completo = True
            try:
                enviados, recebidos = sincronizar_local_supabase.executar_ciclo_sincronizacao(
                    conn, nuvem_url, api_key, on_state_change=self.update_status_icon
                )
            finally:
                self._em_ciclo_completo = False

            self.total_synced += enviados
            self.last_sync = time.strftime("%H:%M:%S")
            sufixo_lan = ''
            if enviados > 0 or recebidos > 0:
                self.status = f"Sync {self.last_sync} | +{enviados} ↑ {recebidos} ↓{sufixo_lan}"
            else:
                qtd_conflitos = sincronizar_local_supabase.obter_qtd_conflitos_pendentes(conn)
                if qtd_conflitos > 0:
                    self.status = f"Online ({qtd_conflitos} Conflitos) | Ultima: {self.last_sync}{sufixo_lan}"
                else:
                    self.status = f"Online | Ultima: {self.last_sync}{sufixo_lan}"
            self.update_icon_tooltip()

        except Exception as e:
            self.update_status_icon('offline', "Erro na sincronizacao (Off)")
            sincronizar_local_supabase.print_log(f"[CICLO] Erro no ciclo: {e}",
                                                 sincronizar_local_supabase.Colors.RED)
        finally:
            if conn is not None:
                try:
                    conn.close()
                except:
                    pass

    def _resumo_lan(self, lan):
        """Sufixo do status com o resultado do passo na rede local."""
        if not self.par_cfg or not lan:
            return ''
        if lan.get('erro'):
            return ' | LAN off'
        partes = []
        if lan.get('recebidos'):
            partes.append(f"+{lan['recebidos']}")
        if lan.get('apagados'):
            partes.append(f"-{lan['apagados']}")
        detalhe = f" {' '.join(partes)}" if partes else ''
        return f" | LAN {self.par_cfg['nome']}{detalhe}"

    def lan_loop(self):
        """Loop DEDICADO da rede local, separado do ciclo da nuvem.

        Roda a cada `LAN_INTERVALO` segundos (padrão 2s) para que uma mudança
        feita no outro PC apareça aqui em poucos segundos, mesmo com a internet
        fora. Cada volta abre a sua própria conexão no banco local; o
        `sincronizar_com_par` cuida de conectar no par e nunca levanta exceção.
        """
        INTERVALO = self.lan_intervalo
        while self.running:
            conn = None
            try:
                conn = psycopg2.connect(
                    host=self.db_host, port=self.db_port, dbname=self.db_name,
                    user=self.db_user, password=self.db_password, connect_timeout=5
                )
                resumo = sincronizador_lan.sincronizar_com_par(conn, self.par_cfg)
                if resumo and not resumo.get('erro'):
                    recebidos = int(resumo.get('recebidos') or 0)
                    apagados = int(resumo.get('apagados') or 0)
                    if recebidos or apagados:
                        self.total_synced += recebidos
                        self.update_status_icon(
                            'syncing',
                            f"LAN {self.par_cfg['nome']}: +{recebidos} ↑ "
                            f"{apagados} ↓")
            except Exception as e:
                sincronizar_local_supabase.print_log(
                    f"[LAN] loop: {e}", sincronizar_local_supabase.Colors.YELLOW)
            finally:
                if conn is not None:
                    try:
                        conn.close()
                    except Exception:
                        pass
            # Pausa em fatias para respeitar a parada do tray rapidamente
            dormiu = 0.0
            while self.running and dormiu < INTERVALO:
                time.sleep(0.25)
                dormiu += 0.25

    def produtos_loop(self):
        """Loop DEDICADO do catálogo (nuvem -> banco local).

        O ciclo completo baixa ~40 tabelas a cada 30 s; para preço/estoque de
        produto isso é lento demais. Aqui só o delta de `produtos` é baixado, a
        cada `PRODUTOS_INTERVALO` segundos. Usa o MESMO `gravar_registros_locais`
        do ciclo completo, então a regra "a nuvem só sobrescreve se for mais
        nova" e a proteção de conflito/empresa valem igual — e gravar já avisa
        o app pelo canal `exodo_ui_event`, que recarrega a tela.
        """
        INTERVALO = self.produtos_intervalo
        if INTERVALO <= 0:
            sincronizar_local_supabase.print_log(
                '[RAPIDO] Loop do catálogo desligado (PRODUTOS_INTERVALO=0).',
                sincronizar_local_supabase.Colors.CYAN)
            return
        while self.running:
            conn = None
            try:
                # Ciclo completo em andamento: as duas rotinas dividem cursor e
                # conexão lógica de escrita. Espera a vez (não bloqueia o ciclo).
                if self._em_ciclo_completo:
                    time.sleep(0.5)
                    continue
                conn = psycopg2.connect(
                    host=self.db_host, port=self.db_port, dbname=self.db_name,
                    user=self.db_user, password=self.db_password, connect_timeout=5
                )
                try:
                    _provedor, nuvem_url, api_key = \
                        sincronizar_local_supabase.resolver_nuvem()
                except Exception:
                    nuvem_url, api_key = self.supabase_url, self.api_key
                if not (nuvem_url and api_key):
                    time.sleep(1.0)
                    continue
                recebidos = sincronizar_local_supabase.sincronizar_produtos_rapido(
                    conn, nuvem_url, api_key,
                    sincronizar_local_supabase.obter_empresa_ativa(conn),
                )
                if recebidos:
                    self.total_synced += recebidos
                    self.last_sync = time.strftime('%H:%M:%S')
                    self.status = f"Catalogo {self.last_sync} | {recebidos} ↓"
                    self.update_icon_tooltip()
            except Exception as e:
                sincronizar_local_supabase.print_log(
                    f'[RAPIDO] loop do catalogo: {e}',
                    sincronizar_local_supabase.Colors.YELLOW)
            finally:
                if conn is not None:
                    try:
                        conn.close()
                    except Exception:
                        pass
            dormiu = 0.0
            while self.running and dormiu < INTERVALO:
                time.sleep(0.25)
                dormiu += 0.25

    def background_loop(self):
        # Executa o setup local primeiro
        self.run_setup_transparently()

        # O ciclo completo faz downloads concorrentes de todas as tabelas e
        # pode levar bastante tempo quando há muitos conflitos. Upload local
        # não deve esperar esse ciclo terminar: a fila pendente é pequena e
        # pode ser escoada em um caminho rápido, separado do download pesado.
        INTERVALO = 3  # segundos entre verificações rápidas da fila local
        CICLO_COMPLETO = 30  # segundos entre downloads/varreduras completas
        last_sync_time = 0
        while self.running:
            agora = time.time()
            # Evita loops frenéticos de frações de segundos caso a rede esteja offline ou haja falha de socket (select.select)
            if agora - last_sync_time < 5.0:
                time.sleep(1.0)

            # Upload prioritário: uma alteração feita no app não fica presa
            # atrás do download completo ou da análise de conflitos antigos.
            self.sync_pending_uploads()

            agora = time.time()
            if agora - last_sync_time >= CICLO_COMPLETO:
                last_sync_time = agora
                self.sync_cycle()
            if not self.running:
                break
            # Aguarda eventos locais via LISTEN/NOTIFY ou timeout curto. O
            # próximo giro sempre reconsulta a fila, inclusive se o trigger
            # de NOTIFY não estiver ativo neste computador.
            sincronizar_local_supabase.aguardar_notificacao_ou_timeout(
                db_host=self.db_host, db_port=self.db_port, db_name=self.db_name,
                db_user=self.db_user, db_password=self.db_password,
                timeout=INTERVALO
            )

    def sync_pending_uploads(self):
        """Envia somente a fila local, sem iniciar o download completo.

        Este caminho existe para reduzir a latência do app Windows -> nuvem.
        O ciclo completo continua responsável por baixar alterações de outros
        computadores e atualizar cursores.
        """
        conn = None
        try:
            conn = psycopg2.connect(
                host=self.db_host, port=self.db_port, dbname=self.db_name,
                user=self.db_user, password=self.db_password, connect_timeout=5
            )
            sincronizar_local_supabase.garantir_tabela_controle(conn)
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT DISTINCT table_name
                    FROM _exodo_sync_log
                    ORDER BY table_name
                """)
                tabelas = [r[0] for r in cur.fetchall()]
            if not tabelas:
                return

            try:
                _provedor, nuvem_url, api_key = sincronizar_local_supabase.resolver_nuvem()
            except Exception as e_res:
                sincronizar_local_supabase.print_log(
                    f"[FAST-UPLOAD] Nuvem indisponivel ({e_res})",
                    sincronizar_local_supabase.Colors.YELLOW)
                return

            tabelas.sort(key=sincronizar_local_supabase.get_tabela_prioridade)
            with conn.cursor() as cur:
                cur.execute("SET exodo.sync_mode = 'on'")
            conn.commit()

            enviados = 0
            for tabela in tabelas:
                if not self.running:
                    break
                enviados += sincronizar_local_supabase.upload_tabela(
                    conn, tabela, nuvem_url, api_key,
                    sincronizar_local_supabase.obter_empresa_ativa(conn),
                )
            if enviados:
                self.total_synced += enviados
                self.last_sync = time.strftime("%H:%M:%S")
                self.status = f"Upload rapido {self.last_sync} | +{enviados}"
                self.update_icon_tooltip()
        except Exception as e:
            sincronizar_local_supabase.print_log(
                f"[FAST-UPLOAD] Erro ao escoar fila: {e}",
                sincronizar_local_supabase.Colors.YELLOW)
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass

    def on_open_logs(self, icon, item):
        # Abre o arquivo de logs no editor padrão do Windows
        log_path = os.path.join(self.base_dir, 'sincronizador.log')
        if not os.path.exists(log_path):
            with open(log_path, 'w', encoding='utf-8') as f:
                f.write("=== LOGS DE SINCRONIZAÇÃO EXODO ===\n")
        try:
            os.startfile(log_path)
        except Exception as e:
            print(f"Erro ao abrir logs: {e}")

    def on_limpar_logs(self, icon, item):
        """Aplica a retenção do log (7 dias / teto de tamanho) na hora."""
        try:
            tamanho = sincronizar_local_supabase.podar_log(forcar=True)
            if tamanho is None:
                self.status = "Logs: nada a limpar"
            else:
                self.status = f"Log limpo ({tamanho // 1024} KB)"
            sincronizar_local_supabase.print_log(
                "[LOG] Retenção aplicada em sincronizador.log: "
                f"{'nada a limpar' if tamanho is None else str(tamanho) + ' bytes'} "
                f"(dias={sincronizar_local_supabase.LOG_RETENCAO_DIAS}, "
                f"max={sincronizar_local_supabase.LOG_TAMANHO_MAX_MB} MB).",
                sincronizar_local_supabase.Colors.CYAN)
        except Exception as e:
            self.status = f"Erro ao limpar logs: {e}"
            sincronizar_local_supabase.print_log(
                f"[LOG] Erro ao podar o log: {e}",
                sincronizar_local_supabase.Colors.RED)
        self.update_icon_tooltip()

    def on_force_sync(self, icon, item):
        t = threading.Thread(target=self.sync_cycle, kwargs={'force': True})
        t.daemon = True
        t.start()

    def on_restart(self, icon, item):
        """Reinicia o processo completamente."""
        self.running = False
        icon.stop()
        # Relança o proprio executavel de forma independente para evitar travar a pasta temporaria no Windows
        import subprocess
        creationflags = 0
        if sys.platform == 'win32':
            # DETACHED_PROCESS (0x00000008) impede que o processo filho herde os handles do pai,
            # permitindo que a pasta temporaria do PyInstaller (_MEIxxxxx) seja apagada com sucesso.
            creationflags = 0x00000008
            
        try:
            subprocess.Popen(
                [sys.executable] + sys.argv,
                creationflags=creationflags,
                close_fds=True
            )
        except Exception as e:
            print(f"Erro ao reiniciar processo: {e}")

    def on_quit(self, icon, item):
        self.running = False
        icon.stop()

    def get_status_text(self):
        return f"Status: {self.status} | Enviados: {self.total_synced} regs | Sync: 10s"

    def update_icon_tooltip(self):
        if self.icon:
            self.icon.title = f"Exodo Sync\n{self.status}"

    def on_download_inicial(self, icon, item):
        t = threading.Thread(target=self.run_download_inicial)
        t.start()

    def run_download_inicial(self):
        try:
            conn = sincronizar_local_supabase.obter_conexao_local()
            try:
                empresa_ativa = sincronizar_local_supabase.obter_empresa_ativa(conn)
                nuvem_ativa = sincronizar_local_supabase.empresa_permite_sincronizacao_nuvem(
                    conn, empresa_ativa
                )
            finally:
                conn.close()
            if empresa_ativa and not nuvem_ativa:
                self.status = "Nuvem desativada para esta empresa"
                self.update_icon_tooltip()
                sincronizar_local_supabase.print_log(
                    f"Download inicial bloqueado: nuvem desativada para {empresa_ativa}.",
                    sincronizar_local_supabase.Colors.YELLOW,
                )
                return

            self.status = "Baixando da Nuvem..."
            self.update_icon_tooltip()

            if (self.nuvem_provedor or "").lower() == "neon":
                # Neon: a carga inicial usa o PROPRIO ciclo de sincronizacao. Basta
                # zerar os cursores para ele baixar tudo (mesmo caminho do dia a dia,
                # com o merge/renumeracao que ja protege os dados).
                sincronizar_local_supabase.print_log(
                    "Iniciando Carga Inicial da nuvem (Neon)...",
                    sincronizar_local_supabase.Colors.BLUE)
                try:
                    conn_cur = psycopg2.connect(
                        host=self.db_host, port=self.db_port, dbname=self.db_name,
                        user=self.db_user, password=self.db_password, connect_timeout=10)
                    with conn_cur.cursor() as cur:
                        cur.execute(
                            "DELETE FROM _sync_controle "
                            "WHERE chave LIKE 'sync_%' OR chave = 'ultima_sincronizacao'")
                    conn_cur.commit()
                    conn_cur.close()
                except Exception as e_zero:
                    sincronizar_local_supabase.print_log(
                        f"Nao consegui zerar os cursores ({e_zero}); seguindo com o "
                        "que ja existe.", sincronizar_local_supabase.Colors.YELLOW)

                _provedor, nuvem_url, api_key = sincronizar_local_supabase.resolver_nuvem()
                conn = psycopg2.connect(
                    host=self.db_host, port=self.db_port, dbname=self.db_name,
                    user=self.db_user, password=self.db_password, connect_timeout=10)
                try:
                    for _ in range(3):
                        sincronizar_local_supabase.executar_ciclo_sincronizacao(
                            conn, nuvem_url, api_key,
                            on_state_change=self.update_status_icon)
                finally:
                    conn.close()
            else:
                sincronizar_local_supabase.print_log(
                    "Iniciando Carga Inicial do Supabase (reserva)...",
                    sincronizar_local_supabase.Colors.BLUE)

                import sys
                import migrar_supabase_postgresql
                old_argv = sys.argv
                sys.argv = ['migrar_supabase_postgresql.py', '--mode', 'append']
                try:
                    migrar_supabase_postgresql.main()
                finally:
                    sys.argv = old_argv

            # Após baixar, rodamos o setup para garantir as triggers
            self.run_setup_transparently()

            # Marca todos os baixados como sincronizados localmente
            conn = psycopg2.connect(
                host=self.db_host, port=self.db_port, dbname=self.db_name, 
                user=self.db_user, password=self.db_password
            )
            cursor = conn.cursor()
            cursor.execute("SELECT table_name FROM information_schema.columns WHERE column_name='_sincronizado_nuvem' AND table_schema='public'")
            for r in cursor.fetchall():
                tabela = r[0]
                cursor.execute(f'UPDATE "{tabela}" SET _sincronizado_nuvem = TRUE WHERE _sincronizado_nuvem = FALSE')
            conn.commit()
            conn.close()

            sincronizar_local_supabase.print_log("Carga Inicial concluída e marcada como sincronizada.", sincronizar_local_supabase.Colors.GREEN)
            self.status = "Download Concluído!"
            self.update_icon_tooltip()
        except Exception as e:
            self.status = "Erro no Download"
            self.update_icon_tooltip()
            sincronizar_local_supabase.print_log(f"Erro no download inicial: {e}", sincronizar_local_supabase.Colors.RED)

    def on_limpar_conflitos(self, icon, item):
        try:
            conn = sincronizar_local_supabase.obter_conexao_local()
            with conn.cursor() as cur:
                cur.execute("UPDATE exodo_sync_conflitos SET resolvido = TRUE WHERE resolvido = FALSE")
                updated = cur.rowcount
            conn.commit()
            conn.close()
            self.status = f"Online | {updated} conflitos resolvidos"
            self.update_status_icon('online')
            sincronizar_local_supabase.print_log(f"Marcados como resolvidos: {updated} conflitos via menu do tray.", sincronizar_local_supabase.Colors.GREEN)
        except Exception as e:
            sincronizar_local_supabase.print_log(f"Erro ao resolver conflitos via tray: {e}", sincronizar_local_supabase.Colors.RED)

    def run(self):
        sincronizar_local_supabase.print_log(
            f"[TRAY] Iniciando Sincronizador Nuvem | base_dir: {self.base_dir} | "
            f".env presente: {os.path.exists(os.path.join(self.base_dir, '.env'))}",
            sincronizar_local_supabase.Colors.BLUE)

        menu = pystray.Menu(
            item(lambda text: self.get_status_text(), lambda: None, enabled=False),
            pystray.Menu.SEPARATOR,
            item('Baixar Dados da Nuvem', self.on_download_inicial),
            item('Forcar Sincronizacao Agora', self.on_force_sync),
            item('Corrigir Conflitos (Limpar)', self.on_limpar_conflitos),
            item('Ver Logs', self.on_open_logs),
            item('Limpar Logs Antigos (7 dias)', self.on_limpar_logs),
            pystray.Menu.SEPARATOR,
            item('Reiniciar', self.on_restart),
            item('Sair', self.on_quit)
        )
        
        self.icon = pystray.Icon("ExodoSync", self.create_image(), "Exodo Sync", menu)
        
        self.sync_thread = threading.Thread(target=self.background_loop, daemon=True)
        self.sync_thread.start()

        # Loop próprio do catálogo: produto alterado no site aparece no app
        # local em poucos segundos (não espera o ciclo completo de ~30 s).
        if self.produtos_intervalo > 0:
            self.produtos_thread = threading.Thread(
                target=self.produtos_loop, daemon=True)
            self.produtos_thread.start()

        # Loop próprio da LAN: é o que mantém os dois PCs em dia sem nuvem.
        if self.par_cfg:
            self.lan_thread = threading.Thread(target=self.lan_loop, daemon=True)
            self.lan_thread.start()
        
        self.icon.run()

if __name__ == "__main__":
    app = SyncTrayApp()
    app.run()
