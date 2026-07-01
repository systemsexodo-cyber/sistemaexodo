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

class SyncTrayApp:
    def __init__(self):
        self.icon = None
        self.running = True
        self.sync_thread = None
        self.status = "Iniciando..."
        self.last_sync = "Nunca"
        self.total_synced = 0
        
        load_dotenv()
        self.supabase_url = os.getenv('SUPABASE_URL')
        self.api_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('SUPABASE_ANON_KEY')
        self.db_host = os.getenv('DB_HOST', 'localhost')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')

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

    def update_status_icon(self, state_type):
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
        
        if state_type == 'offline':
            self.status = "Sem Conexao com Supabase"
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
            print(f"Erro no setup: {e}")

    def sync_cycle(self, force=False):
        if not all([self.supabase_url, self.api_key, self.db_name, self.db_user, self.db_password]):
            self.status = "Erro: .env incompleto!"
            self.update_icon_tooltip()
            return

        conn = None
        try:
            conn = psycopg2.connect(
                host=self.db_host, port=self.db_port, dbname=self.db_name,
                user=self.db_user, password=self.db_password
            )

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
            self.status = "Erro na sincronizacao (Off)"
            self.update_status_icon('offline')
            print(f"Erro no ciclo: {e}")
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
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))
        log_path = os.path.join(base_dir, 'sincronizador.log')
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
