# ⚡ CHEAT SHEET: SQLite → PostgreSQL

## 🚀 Início Rápido (Copiar e Colar)

### 1. Verificar Pré-requisitos
```bash
# Python versão
python --version

# PostgreSQL versão
psql --version

# Psycopg2 instalado?
pip list | grep psycopg2
```

### 2. Configurar .env
```bash
# Criar arquivo na raiz do projeto
cat > .env << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=sua_senha_aqui
DATABASE_URL=postgresql://exodo_user:sua_senha_aqui@localhost:5432/exodo_db
SQLALCHEMY_ECHO=false
EOF
```

### 3. Criar Banco PostgreSQL
```bash
# Conectar como admin
psql -U postgres

# Dentro do psql, copiar e colar:
# ========================
CREATE USER exodo_user WITH PASSWORD 'sua_senha_aqui';
CREATE DATABASE exodo_db OWNER exodo_user;
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;
\q
# ========================
```

### 4. Instalar Dependências
```bash
pip install psycopg2-binary sqlalchemy alembic flask-sqlalchemy
```

### 5. Executar Migração (TUDO AUTOMÁTICO!)
```bash
python automatizar_migracao_completa.py
```

### 6. Verificar Sucesso
```bash
python test_postgres_connection.py
```

---

## 🔧 Comandos PostgreSQL (Essencial)

### Conectar ao PostgreSQL
```bash
# Como admin
psql -U postgres

# Como usuário específico
psql -U exodo_user -d exodo_db

# Com host específico
psql -h localhost -U exodo_user -d exodo_db
```

### Dentro do psql (Comandos)

```sql
-- Listar bancos de dados
\l

-- Conectar a um banco
\c exodo_db

-- Listar tabelas
\dt

-- Ver estrutura de uma tabela
\d produtos_local

-- Contar registros
SELECT COUNT(*) FROM produtos_local;

-- Ver primeiros 10 registros
SELECT * FROM produtos_local LIMIT 10;

-- Ver tamanho das tabelas
SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
FROM pg_tables WHERE schemaname='public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Deletar tudo e recomeçar
DROP DATABASE exodo_db;
CREATE DATABASE exodo_db OWNER exodo_user;

-- Sair
\q
```

---

## 🐍 Comandos Python (Scripts)

```bash
# 1. Análise (ver o que tem no SQLite)
python analisar_sqlite.py

# 2. Migração (copiar dados)
python migrar_sqlite_postgresql.py

# 3. Automático (fazer tudo em um!)
python automatizar_migracao_completa.py

# 4. Teste de conexão
python test_postgres_connection.py

# 5. Diagnóstico completo
python verificar_migracao_postgresql.py
```

---

## 📊 Queries PostgreSQL (Mais Usados)

### Listar Tudo
```sql
-- Tabelas
SELECT * FROM information_schema.tables WHERE table_schema='public';

-- Colunas de uma tabela
SELECT column_name, data_type FROM information_schema.columns 
WHERE table_name='produtos_local';

-- Índices
SELECT * FROM pg_indexes WHERE schemaname='public';

-- Usuários
\du
```

### Dados
```sql
-- Contar em todas as tabelas
SELECT tablename, COUNT(*) FROM pg_tables 
JOIN ... WHERE schemaname='public';

-- Buscar registros
SELECT * FROM vendas WHERE data > '2026-01-01';

-- Deletar registros
DELETE FROM vendas WHERE id = 123;

-- Atualizar registros
UPDATE vendas SET status = 'pago' WHERE id = 123;

-- Inserir registros
INSERT INTO vendas (numero, valor) VALUES ('001', 99.90);
```

### Backup
```bash
# Backup completo
pg_dump -U exodo_user -d exodo_db > backup.sql

# Backup comprimido
pg_dump -U exodo_user -d exodo_db | gzip > backup.sql.gz

# Backup de uma tabela
pg_dump -U exodo_user -d exodo_db -t produtos_local > produtos.sql

# Restaurar
psql -U exodo_user -d exodo_db < backup.sql

# Restaurar comprimido
gunzip < backup.sql.gz | psql -U exodo_user -d exodo_db
```

---

## 🐛 Troubleshooting Rápido

### Erro: "could not connect to server"
```bash
# Iniciar PostgreSQL (Windows)
net start postgresql-x64-15

# Ou via Services (services.msc)
# Procurar por "postgresql" e clicar Start
```

### Erro: "permission denied"
```sql
-- Dentro do psql como admin
GRANT ALL PRIVILEGES ON SCHEMA public TO exodo_user;
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
```

### Erro: "database does not exist"
```bash
psql -U postgres
CREATE DATABASE exodo_db OWNER exodo_user;
\q
```

### Erro: "password authentication failed"
```bash
# Resetar senha do usuário
psql -U postgres
ALTER USER exodo_user WITH PASSWORD 'nova_senha';
\q

# Depois atualizar .env
```

### Erro: "table already exists"
```sql
-- Deletar tudo e recomeçar
DROP TABLE products CASCADE;
DROP TABLE vendas CASCADE;

-- Ou
DROP DATABASE exodo_db;
CREATE DATABASE exodo_db OWNER exodo_user;
```

---

## 📝 Código Python (Exemplos)

### Conectar Manualmente
```python
import psycopg2
from dotenv import load_dotenv
import os

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST'),
    port=os.getenv('DB_PORT'),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM produtos_local")
results = cursor.fetchall()

for row in results:
    print(row)

cursor.close()
conn.close()
```

### Com SQLAlchemy (Recomendado)
```python
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
import os

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
db = SQLAlchemy(app)

class Produto(db.Model):
    __tablename__ = 'produtos_local'
    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(255))
    preco = db.Column(db.Float)

# Usar
with app.app_context():
    produtos = Produto.query.all()
    for p in produtos:
        print(f"{p.nome}: R${p.preco}")
```

---

## 🎯 Workflow Típico

```bash
# 1. Setup
python -m venv venv
source venv/Scripts/activate  # Windows: .\venv\Scripts\activate
pip install -r requirements.txt

# 2. Configurar
# Editar .env com credenciais

# 3. Migrar
python analisar_sqlite.py          # Ver o que tem
python automatizar_migracao_completa.py  # Migrar tudo
python test_postgres_connection.py  # Verificar

# 4. Testar
cd backend_pynfe
python app.py

# 5. Acessar
# http://localhost:5000/health
```

---

## 📱 Variáveis de Ambiente (.env)

```ini
# Banco de Dados
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=senha123

# URLs
DATABASE_URL=postgresql://exodo_user:senha123@localhost:5432/exodo_db

# Aplicação
FLASK_ENV=development
FLASK_DEBUG=false

# SQLAlchemy
SQLALCHEMY_ECHO=false
SQLALCHEMY_TRACK_MODIFICATIONS=false
```

---

## ✅ Checklist Final

```
Pre-Migração:
- [ ] PostgreSQL instalado
- [ ] Banco criado
- [ ] .env configurado
- [ ] Python 3.8+
- [ ] psycopg2 instalado

Migração:
- [ ] analisar_sqlite.py executado
- [ ] automatizar_migracao_completa.py OK
- [ ] test_postgres_connection.py ✅

Pós-Migração:
- [ ] Dados verificados
- [ ] Backend testado
- [ ] Backup feito
- [ ] Código atualizado
```

---

## 🔗 Links Rápidos

| O que fazer | Comando |
|------------|---------|
| Começar | `cat RESUMO_MIGRACAO_DADOS.md` |
| Migrar | `python automatizar_migracao_completa.py` |
| Testar | `python test_postgres_connection.py` |
| Conectar psql | `psql -U exodo_user -d exodo_db` |
| Ver tabelas | `\dt` (dentro do psql) |
| Fazer backup | `pg_dump -U exodo_user -d exodo_db > backup.sql` |
| Referência | `cat MIGRACAO_SQLITE_POSTGRESQL.md` |

---

## 💡 Tips & Tricks

```bash
# Encontrar erro no psql
psql -U exodo_user -d exodo_db < script.sql 2>&1 | grep -i error

# Executar script SQL
psql -U exodo_user -d exodo_db -f migration.sql

# Contar todas as tabelas
psql -U exodo_user -d exodo_db -c "
  SELECT tablename, COUNT(*) FROM pg_tables t 
  WHERE schemaname='public' GROUP BY tablename;
"

# Exportar para CSV
psql -U exodo_user -d exodo_db -c "
  COPY (SELECT * FROM produtos_local) TO STDOUT WITH CSV HEADER;
" > produtos.csv

# Importar de CSV
psql -U exodo_user -d exodo_db -c "
  COPY produtos_local(id,nome,preco) FROM STDIN WITH CSV HEADER;
" < produtos.csv
```

---

*Quick Reference - SQLite → PostgreSQL Migração*
*Última atualização: 26 de Maio de 2026*
