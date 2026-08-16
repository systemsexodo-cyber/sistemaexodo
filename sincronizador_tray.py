import os
import sys
import threading
import time
import psycopg2
from PIL import Image, ImageDraw
import pystray
from pystray import MenuItem as item
from dotenv import load_dotenv

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

# Diretorio base: quando congelado (exe), a pasta do executavel; senao, a pasta do script.
# IMPORTANTE: no PyInstaller onefile, load_dotenv() sem caminho procura a partir da pasta
# temporaria _MEIxxxx e NUNCA acha o .env da pasta do sistema (C:\SistemaExodo).
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
        self.status = "Iniciando..."
        self.last_sync = "Nunca"
        self.total_synced = 0
        self.base_dir = BASE_DIR

        # Carregar o .env SEMPRE a partir da pasta do executavel
        env_path = os.path.join(self.base_dir, '.env')
        env_existe = os.path.exists(env_path)
        load_dotenv(env_path, override=False)

        self.supabase_url = os.getenv('SUPABASE_URL')
        self.api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
        self.db_host = os.getenv('DB_HOST', 'localhost')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')

        # Log de inicializacao para facilitar diagnostico (agora vai para sincronizador.log)
        faltando = [v for v in ('SUPABASE_URL', 'DB_NAME', 'DB_USER', 'DB_PASSWORD') if not os.getenv(v)]
        if not self.api_key:
            faltando.append('SUPABASE_ANON_KEY/SERVICE_ROLE_KEY')
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
                f"[INIT] .env carregado de {env_path} | Supabase: {self.supabase_url} | "
                f"Banco local: {self.db_user}@{self.db_host}:{self.db_port}/{self.db_name}",
                sincronizar_local_supabase.Colors.GREEN)

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
            'conflict': (241, 196, 15)   # Amarelo
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
        data_dir = os.path.join(self.base_dir, 'data')
        if not os.path.exists(pg_ctl) or not os.path.exists(data_dir):
            sincronizar_local_supabase.print_log(
                f"[PG] pg_ctl nao encontrado ({pg_ctl}) ou data dir ausente ({data_dir})",
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

            # Executa o ciclo otimizado de sincronização com o callback de mudança de estado
            enviados, recebidos = sincronizar_local_supabase.executar_ciclo_sincronizacao(
                conn, self.supabase_url, self.api_key, on_state_change=self.update_status_icon
            )

            self.total_synced += enviados
            self.last_sync = time.strftime("%H:%M:%S")
            if enviados > 0 or recebidos > 0:
                self.status = f"Sync {self.last_sync} | +{enviados} ↑ {recebidos} ↓"
            else:
                qtd_conflitos = sincronizar_local_supabase.obter_qtd_conflitos_pendentes(conn)
                if qtd_conflitos > 0:
                    self.status = f"Online ({qtd_conflitos} Conflitos) | Ultima: {self.last_sync}"
                else:
                    self.status = f"Online | Ultima: {self.last_sync}"
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

    def background_loop(self):
        # Executa o setup local primeiro
        self.run_setup_transparently()

        INTERVALO = 10  # segundos
        last_sync_time = 0
        while self.running:
            agora = time.time()
            # Evita loops frenéticos de frações de segundos caso a rede esteja offline ou haja falha de socket (select.select)
            if agora - last_sync_time < 5.0:
                time.sleep(5.0 - (agora - last_sync_time))
            
            last_sync_time = time.time()
            self.sync_cycle()
            if not self.running:
                break
            # Aguarda eventos locais via LISTEN/NOTIFY ou timeout de 10 segundos
            sincronizar_local_supabase.aguardar_notificacao_ou_timeout(
                db_host=self.db_host, db_port=self.db_port, db_name=self.db_name,
                db_user=self.db_user, db_password=self.db_password,
                timeout=INTERVALO
            )

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
            self.status = "Baixando da Nuvem..."
            self.update_icon_tooltip()
            sincronizar_local_supabase.print_log("Iniciando Carga Inicial do Supabase...", sincronizar_local_supabase.Colors.BLUE)
            
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
            pystray.Menu.SEPARATOR,
            item('Reiniciar', self.on_restart),
            item('Sair', self.on_quit)
        )
        
        self.icon = pystray.Icon("ExodoSync", self.create_image(), "Exodo Sync", menu)
        
        self.sync_thread = threading.Thread(target=self.background_loop, daemon=True)
        self.sync_thread.start()
        
        self.icon.run()

if __name__ == "__main__":
    app = SyncTrayApp()
    app.run()
