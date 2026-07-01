#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
🗄️ GESTOR VISUAL DE BANCO DE DADOS
==================================
Interface gráfica para gerenciar PostgreSQL do Exodo NFC-e
Veja tabelas, dados, e a localização do banco
"""

import os
import sys
import json
import psycopg2
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
from dotenv import load_dotenv
from datetime import datetime
import threading

# Carregar variáveis de ambiente
load_dotenv()

class GestorBancoVisual:
    def __init__(self, root):
        self.root = root
        self.root.title("🗄️ Gestor Visual - Banco de Dados Exodo NFC-e")
        self.root.geometry("1200x700")
        self.root.configure(bg="#f0f0f0")
        
        # Dados de conexão
        self.db_host = os.getenv('DB_HOST', 'localhost')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME', 'exodo_db')
        self.db_user = os.getenv('DB_USER', 'exodo_user')
        self.db_password = os.getenv('DB_PASSWORD', '')
        self.conn = None
        
        # Estilo
        self.style = ttk.Style()
        self.style.theme_use('clam')
        
        # Cores personalizadas
        self.primary_color = "#2c3e50"
        self.accent_color = "#27ae60"
        self.warning_color = "#e74c3c"
        
        self.setup_ui()
        self.conectar_banco()
        
    def setup_ui(self):
        """Configurar interface do usuário"""
        
        # Barra de título
        title_frame = tk.Frame(self.root, bg=self.primary_color, height=60)
        title_frame.pack(fill=tk.X)
        title_frame.pack_propagate(False)
        
        title_label = tk.Label(
            title_frame,
            text="🗄️  GESTOR VISUAL - BANCO DE DADOS EXODO NFC-E",
            font=("Arial", 18, "bold"),
            bg=self.primary_color,
            fg="white"
        )
        title_label.pack(pady=10)
        
        # Notebook (abas)
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # Aba 1: Conexão
        self.frame_conexao = ttk.Frame(self.notebook)
        self.notebook.add(self.frame_conexao, text="📡 Conexão")
        self.setup_tab_conexao()
        
        # Aba 2: Tabelas
        self.frame_tabelas = ttk.Frame(self.notebook)
        self.notebook.add(self.frame_tabelas, text="📋 Tabelas")
        self.setup_tab_tabelas()
        
        # Aba 3: Dados
        self.frame_dados = ttk.Frame(self.notebook)
        self.notebook.add(self.frame_dados, text="📊 Dados")
        self.setup_tab_dados()
        
        # Aba 4: Informações
        self.frame_info = ttk.Frame(self.notebook)
        self.notebook.add(self.frame_info, text="ℹ️ Informações")
        self.setup_tab_info()
        
        # Rodapé
        footer_frame = tk.Frame(self.root, bg="#ecf0f1", height=30)
        footer_frame.pack(fill=tk.X, side=tk.BOTTOM)
        footer_frame.pack_propagate(False)
        
        self.status_label = tk.Label(
            footer_frame,
            text="Desconectado",
            font=("Arial", 10),
            bg="#ecf0f1",
            fg=self.warning_color
        )
        self.status_label.pack(pady=5)
    
    def setup_tab_conexao(self):
        """Aba de Conexão"""
        main_frame = ttk.Frame(self.frame_conexao, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Título
        title = tk.Label(
            main_frame,
            text="📡 Configuração de Conexão",
            font=("Arial", 14, "bold"),
            bg="#f0f0f0"
        )
        title.pack(pady=10)
        
        # Frame de informações
        info_frame = ttk.LabelFrame(main_frame, text="Detalhes da Conexão", padding=15)
        info_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        
        # Campos
        fields = [
            ("Host", self.db_host),
            ("Porta", self.db_port),
            ("Banco", self.db_name),
            ("Usuário", self.db_user),
            ("Arquivo .env", self.get_env_path()),
            ("Python", sys.version.split()[0]),
            ("Sistema", sys.platform),
        ]
        
        for label, value in fields:
            row = ttk.Frame(info_frame)
            row.pack(fill=tk.X, pady=8)
            
            lbl = ttk.Label(row, text=f"{label}:", font=("Arial", 11, "bold"), width=15)
            lbl.pack(side=tk.LEFT, padx=5)
            
            val = tk.Label(row, text=str(value), font=("Arial", 11), fg="#2c3e50")
            val.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        
        # Botões
        button_frame = ttk.Frame(main_frame)
        button_frame.pack(fill=tk.X, pady=20)
        
        btn_conectar = ttk.Button(
            button_frame,
            text="🔄 Reconectar",
            command=self.reconectar
        )
        btn_conectar.pack(side=tk.LEFT, padx=5)
        
        btn_testar = ttk.Button(
            button_frame,
            text="✅ Testar Conexão",
            command=self.testar_conexao
        )
        btn_testar.pack(side=tk.LEFT, padx=5)
        
        # Texto de status
        self.status_text = scrolledtext.ScrolledText(main_frame, height=10, width=80)
        self.status_text.pack(fill=tk.BOTH, expand=True, pady=10)
        self.status_text.config(state=tk.DISABLED)
    
    def setup_tab_tabelas(self):
        """Aba de Tabelas"""
        main_frame = ttk.Frame(self.frame_tabelas, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Título
        title = tk.Label(
            main_frame,
            text="📋 Tabelas do Banco de Dados",
            font=("Arial", 14, "bold"),
            bg="#f0f0f0"
        )
        title.pack(pady=10)
        
        # Listbox com tabelas
        list_frame = ttk.LabelFrame(main_frame, text="Tabelas Disponíveis", padding=10)
        list_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        
        # Scrollbar
        scrollbar = ttk.Scrollbar(list_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.listbox_tabelas = tk.Listbox(
            list_frame,
            yscrollcommand=scrollbar.set,
            font=("Courier", 11),
            height=15
        )
        self.listbox_tabelas.pack(fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.listbox_tabelas.yview)
        self.listbox_tabelas.bind('<<ListboxSelect>>', self.selecionar_tabela)
        
        # Info da tabela selecionada
        info_frame = ttk.LabelFrame(main_frame, text="Informações da Tabela", padding=10)
        info_frame.pack(fill=tk.X, pady=10)
        
        self.info_tabela_text = scrolledtext.ScrolledText(info_frame, height=6, width=80)
        self.info_tabela_text.pack(fill=tk.BOTH, expand=True)
        self.info_tabela_text.config(state=tk.DISABLED)
        
        # Botões
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=10)
        
        btn_refresh = ttk.Button(btn_frame, text="🔄 Atualizar", command=self.carregar_tabelas)
        btn_refresh.pack(side=tk.LEFT, padx=5)
        
        btn_ver_dados = ttk.Button(btn_frame, text="📊 Ver Dados", command=self.ver_dados_tabela)
        btn_ver_dados.pack(side=tk.LEFT, padx=5)
        
        self.carregar_tabelas()
    
    def setup_tab_dados(self):
        """Aba de Dados"""
        main_frame = ttk.Frame(self.frame_dados, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Título
        title = tk.Label(
            main_frame,
            text="📊 Visualizador de Dados",
            font=("Arial", 14, "bold"),
            bg="#f0f0f0"
        )
        title.pack(pady=10)
        
        # Seletor de tabela
        selector_frame = ttk.Frame(main_frame)
        selector_frame.pack(fill=tk.X, pady=10)
        
        ttk.Label(selector_frame, text="Tabela:").pack(side=tk.LEFT, padx=5)
        self.combo_tabelas = ttk.Combobox(selector_frame, width=30, state="readonly")
        self.combo_tabelas.pack(side=tk.LEFT, padx=5)
        
        ttk.Label(selector_frame, text="Limite:").pack(side=tk.LEFT, padx=5)
        self.spin_limite = ttk.Spinbox(selector_frame, from_=1, to=1000, width=5)
        self.spin_limite.set(50)
        self.spin_limite.pack(side=tk.LEFT, padx=5)
        
        btn_carregar = ttk.Button(selector_frame, text="📥 Carregar Dados", command=self.carregar_dados)
        btn_carregar.pack(side=tk.LEFT, padx=5)
        
        # Treeview para dados
        tree_frame = ttk.LabelFrame(main_frame, text="Dados da Tabela", padding=10)
        tree_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        
        # Criar treeview com scrollbars
        tree_scroll_y = ttk.Scrollbar(tree_frame)
        tree_scroll_y.pack(side=tk.RIGHT, fill=tk.Y)
        
        tree_scroll_x = ttk.Scrollbar(tree_frame, orient=tk.HORIZONTAL)
        tree_scroll_x.pack(side=tk.BOTTOM, fill=tk.X)
        
        self.tree_dados = ttk.Treeview(
            tree_frame,
            yscrollcommand=tree_scroll_y.set,
            xscrollcommand=tree_scroll_x.set
        )
        self.tree_dados.pack(fill=tk.BOTH, expand=True)
        tree_scroll_y.config(command=self.tree_dados.yview)
        tree_scroll_x.config(command=self.tree_dados.xview)
        
        self.atualizar_combo_tabelas()
    
    def setup_tab_info(self):
        """Aba de Informações"""
        main_frame = ttk.Frame(self.frame_info, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Título
        title = tk.Label(
            main_frame,
            text="ℹ️ Informações do Sistema",
            font=("Arial", 14, "bold"),
            bg="#f0f0f0"
        )
        title.pack(pady=10)
        
        # Frame de informações
        info_frame = ttk.LabelFrame(main_frame, text="Localização e Configuração", padding=15)
        info_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        
        self.info_text = scrolledtext.ScrolledText(info_frame, height=20, width=100)
        self.info_text.pack(fill=tk.BOTH, expand=True)
        self.info_text.config(state=tk.DISABLED)
        
        # Botões
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=10)
        
        btn_refresh = ttk.Button(btn_frame, text="🔄 Atualizar", command=self.atualizar_info)
        btn_refresh.pack(side=tk.LEFT, padx=5)
        
        self.atualizar_info()
    
    def conectar_banco(self):
        """Conectar ao banco de dados"""
        try:
            self.conn = psycopg2.connect(
                host=self.db_host,
                port=int(self.db_port),
                database=self.db_name,
                user=self.db_user,
                password=self.db_password
            )
            self.atualizar_status("✅ Conectado ao banco de dados", True)
        except Exception as e:
            self.atualizar_status(f"❌ Erro de conexão: {e}", False)
    
    def reconectar(self):
        """Reconectar ao banco"""
        if self.conn:
            self.conn.close()
        self.conectar_banco()
    
    def testar_conexao(self):
        """Testar conexão"""
        self.status_text.config(state=tk.NORMAL)
        self.status_text.delete(1.0, tk.END)
        
        try:
            conn = psycopg2.connect(
                host=self.db_host,
                port=int(self.db_port),
                database=self.db_name,
                user=self.db_user,
                password=self.db_password,
                connect_timeout=5
            )
            
            cursor = conn.cursor()
            cursor.execute("SELECT version();")
            version = cursor.fetchone()[0]
            
            cursor.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
            table_count = cursor.fetchone()[0]
            
            cursor.execute("""
                SELECT table_name FROM information_schema.tables 
                WHERE table_schema = 'public' 
                LIMIT 5
            """)
            tabelas = cursor.fetchall()
            
            self.status_text.insert(tk.END, "✅ TESTE DE CONEXÃO BEM-SUCEDIDO\n\n")
            self.status_text.insert(tk.END, f"PostgreSQL: {version[:70]}...\n\n")
            self.status_text.insert(tk.END, f"Tabelas na base: {table_count}\n\n")
            self.status_text.insert(tk.END, "Primeiras tabelas:\n")
            for tabela in tabelas:
                self.status_text.insert(tk.END, f"  • {tabela[0]}\n")
            
            cursor.close()
            conn.close()
            
        except Exception as e:
            self.status_text.insert(tk.END, f"❌ ERRO NA CONEXÃO:\n\n{str(e)}\n\n")
            self.status_text.insert(tk.END, "Verifique:\n")
            self.status_text.insert(tk.END, "  • PostgreSQL está rodando?\n")
            self.status_text.insert(tk.END, "  • Credenciais corretas no .env?\n")
            self.status_text.insert(tk.END, "  • Banco de dados existe?\n")
        
        self.status_text.config(state=tk.DISABLED)
    
    def carregar_tabelas(self):
        """Carregar lista de tabelas"""
        self.listbox_tabelas.delete(0, tk.END)
        
        if not self.conn:
            return
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name
            """)
            
            tabelas = cursor.fetchall()
            for tabela in tabelas:
                self.listbox_tabelas.insert(tk.END, tabela[0])
            
            cursor.close()
            self.atualizar_combo_tabelas()
            
        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao carregar tabelas: {e}")
    
    def atualizar_combo_tabelas(self):
        """Atualizar combo de tabelas"""
        if not self.conn:
            return
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name
            """)
            
            tabelas = [t[0] for t in cursor.fetchall()]
            self.combo_tabelas['values'] = tabelas
            if tabelas:
                self.combo_tabelas.current(0)
            
            cursor.close()
        except:
            pass
    
    def selecionar_tabela(self, event=None):
        """Quando seleciona uma tabela na listbox"""
        selection = self.listbox_tabelas.curselection()
        if not selection or not self.conn:
            return
        
        tabela = self.listbox_tabelas.get(selection[0])
        self.info_tabela_text.config(state=tk.NORMAL)
        self.info_tabela_text.delete(1.0, tk.END)
        
        try:
            cursor = self.conn.cursor()
            
            # Contar registros
            cursor.execute(f"SELECT COUNT(*) FROM \"{tabela}\"")
            count = cursor.fetchone()[0]
            
            # Listar colunas
            cursor.execute(f"""
                SELECT column_name, data_type, is_nullable
                FROM information_schema.columns
                WHERE table_name = %s
                ORDER BY ordinal_position
            """, (tabela,))
            
            self.info_tabela_text.insert(tk.END, f"📊 Tabela: {tabela}\n")
            self.info_tabela_text.insert(tk.END, f"Registros: {count}\n\n")
            self.info_tabela_text.insert(tk.END, "Colunas:\n")
            
            for col_name, data_type, is_nullable in cursor.fetchall():
                nullable = "NULL" if is_nullable == "YES" else "NOT NULL"
                self.info_tabela_text.insert(tk.END, f"  • {col_name} ({data_type}) - {nullable}\n")
            
            cursor.close()
        except Exception as e:
            self.info_tabela_text.insert(tk.END, f"Erro: {e}")
        
        self.info_tabela_text.config(state=tk.DISABLED)
    
    def ver_dados_tabela(self):
        """Ver dados da tabela selecionada"""
        selection = self.listbox_tabelas.curselection()
        if not selection:
            messagebox.showwarning("Aviso", "Selecione uma tabela")
            return
        
        tabela = self.listbox_tabelas.get(selection[0])
        self.combo_tabelas.set(tabela)
        self.notebook.select(1)  # Ir para aba de dados
        self.carregar_dados()
    
    def carregar_dados(self):
        """Carregar dados da tabela"""
        tabela = self.combo_tabelas.get()
        if not tabela or not self.conn:
            messagebox.showwarning("Aviso", "Selecione uma tabela")
            return
        
        try:
            limite = int(self.spin_limite.get())
        except:
            limite = 50
        
        # Limpar treeview
        for item in self.tree_dados.get_children():
            self.tree_dados.delete(item)
        self.tree_dados["columns"] = []
        
        try:
            cursor = self.conn.cursor()
            
            # Buscar dados
            cursor.execute(f'SELECT * FROM "{tabela}" LIMIT %s', (limite,))
            rows = cursor.fetchall()
            
            # Configurar colunas
            cursor.execute(f"""
                SELECT column_name
                FROM information_schema.columns
                WHERE table_name = %s
                ORDER BY ordinal_position
            """, (tabela,))
            
            columns = [col[0] for col in cursor.fetchall()]
            self.tree_dados["columns"] = columns
            self.tree_dados.column("#0", width=0, stretch=False)
            self.tree_dados.heading("#0", text="")
            
            for col in columns:
                self.tree_dados.column(col, anchor=tk.W, width=100)
                self.tree_dados.heading(col, text=col)
            
            # Inserir dados
            for i, row in enumerate(rows):
                values = [str(v)[:100] if v else "NULL" for v in row]
                self.tree_dados.insert("", "end", text="", values=values)
            
            cursor.close()
            messagebox.showinfo("Sucesso", f"Carregados {len(rows)} registros")
            
        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao carregar dados: {e}")
    
    def atualizar_info(self):
        """Atualizar informações do sistema"""
        self.info_text.config(state=tk.NORMAL)
        self.info_text.delete(1.0, tk.END)
        
        info = f"""
╔══════════════════════════════════════════════════════════════╗
║         INFORMAÇÕES DO BANCO DE DADOS EXODO NFC-E            ║
╚══════════════════════════════════════════════════════════════╝

📌 CONFIGURAÇÃO DE CONEXÃO
═══════════════════════════════════════════════════════════════
  Host               : {self.db_host}
  Porta              : {self.db_port}
  Banco de Dados     : {self.db_name}
  Usuário            : {self.db_user}
  
📁 LOCALIZAÇÃO DOS ARQUIVOS
═══════════════════════════════════════════════════════════════
  Arquivo .env       : {self.get_env_path()}
  Diretório Projeto  : {os.getcwd()}
  
💾 INFORMAÇÕES DO POSTGRESQL
═══════════════════════════════════════════════════════════════
"""
        
        if self.conn:
            try:
                cursor = self.conn.cursor()
                
                # Versão
                cursor.execute("SELECT version();")
                version = cursor.fetchone()[0]
                info += f"  Versão            : {version[:60]}...\n"
                
                # Tabelas
                cursor.execute("""
                    SELECT COUNT(*) FROM information_schema.tables
                    WHERE table_schema = 'public'
                """)
                table_count = cursor.fetchone()[0]
                info += f"  Total de Tabelas  : {table_count}\n"
                
                # Tamanho do banco
                cursor.execute(f"SELECT pg_size_pretty(pg_database_size('{self.db_name}'));")
                db_size = cursor.fetchone()[0]
                info += f"  Tamanho do Banco  : {db_size}\n"
                
                # Conexões ativas
                cursor.execute(f"""
                    SELECT COUNT(*) FROM pg_stat_activity 
                    WHERE datname = '{self.db_name}'
                """)
                connections = cursor.fetchone()[0]
                info += f"  Conexões Ativas   : {connections}\n"
                
                info += f"\n📊 TABELAS PRINCIPAIS\n"
                info += f"═══════════════════════════════════════════════════════════════\n"
                
                cursor.execute("""
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public'
                    ORDER BY table_name
                """)
                
                tabelas = cursor.fetchall()
                for tabela in tabelas:
                    table_name = tabela[0]
                    cursor.execute(f"""
                        SELECT COUNT(*) FROM information_schema.columns 
                        WHERE table_name = %s
                    """, (table_name,))
                    col_count = cursor.fetchone()[0]
                    
                    cursor.execute(f"SELECT COUNT(*) FROM \"{table_name}\"")
                    row_count = cursor.fetchone()[0]
                    
                    cursor.execute(f"SELECT pg_size_pretty(pg_total_relation_size('\"{table_name}\"'))")
                    table_size = cursor.fetchone()[0]
                    
                    info += f"  • {table_name:30} | Colunas: {col_count:3} | Registros: {row_count:8} | Tamanho: {table_size}\n"
                
                cursor.close()
                
            except Exception as e:
                info += f"\n❌ Erro ao buscar informações: {e}\n"
        else:
            info += "  ❌ Não conectado ao banco de dados\n"
        
        info += f"""

⏰ TIMESTAMP
═══════════════════════════════════════════════════════════════
  Gerado em          : {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}
  Timezone           : {datetime.now().astimezone().tzname()}

💡 DICAS
═══════════════════════════════════════════════════════════════
  ✓ Use a aba "Tabelas" para ver a estrutura das tabelas
  ✓ Use a aba "Dados" para visualizar os registros
  ✓ Use a aba "Conexão" para testar a conexão
  ✓ Todos os dados são somente leitura nesta interface
"""
        
        self.info_text.insert(tk.END, info)
        self.info_text.config(state=tk.DISABLED)
    
    def atualizar_status(self, mensagem, sucesso=True):
        """Atualizar label de status"""
        cor = self.accent_color if sucesso else self.warning_color
        self.status_label.config(text=mensagem, fg=cor)
    
    def get_env_path(self):
        """Obter caminho do arquivo .env"""
        if os.path.exists(".env"):
            return os.path.abspath(".env")
        elif os.path.exists(".env.postgresql.example"):
            return os.path.abspath(".env.postgresql.example")
        else:
            return "Não encontrado"
    
    def __del__(self):
        """Fechar conexão ao sair"""
        if self.conn:
            self.conn.close()


def main():
    root = tk.Tk()
    app = GestorBancoVisual(root)
    root.mainloop()


if __name__ == "__main__":
    main()
