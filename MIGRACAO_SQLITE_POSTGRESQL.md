# Migração de SQLite para PostgreSQL

## 📋 Sumário Executivo

Este documento guia a migração completa do sistema de SQLite para PostgreSQL. O projeto usa:
- **Backend Python** (FastAPI/Flask) - sem banco de dados local
- **Firebase/Firestore** - banco de dados em nuvem
- **Evolution API** (Node.js) - já configurado para PostgreSQL
- **SQLite local** - apenas em scripts auxiliares (read_db.py)

---

## 🎯 Etapas de Migração

### 1. Instalar PostgreSQL

#### Windows:
```powershell
# Opção 1: Instalar via Chocolatey (recomendado)
choco install postgresql

# Opção 2: Download direto
# Ir em https://www.postgresql.org/download/windows/
# Selecionar versão 14+ e executar o instalador
```

#### Variáveis de Ambiente (Windows):
```powershell
# Adicionar à PATH do sistema:
C:\Program Files\PostgreSQL\15\bin

# Verificar instalação:
psql --version
```

---

### 2. Instalar Driver PostgreSQL em Python

#### Backend PyNFe:
```bash
cd backend_pynfe
pip install psycopg2-binary
pip install sqlalchemy
pip install alembic  # Para migrations
```

#### Backend NFCe:
```bash
cd backend_nfce
pip install psycopg2-binary
pip install sqlalchemy
```

#### Adicionar ao requirements.txt:
```
psycopg2-binary>=2.9.0
sqlalchemy>=2.0.0
alembic>=1.12.0
```

---

### 3. Configurar PostgreSQL

#### Criar banco de dados:
```sql
-- Conectar ao PostgreSQL como superuser
psql -U postgres

-- Criar usuário dedicado
CREATE USER exodo_user WITH PASSWORD 'sua_senha_segura';

-- Criar banco de dados
CREATE DATABASE exodo_db OWNER exodo_user;

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;

-- Conectar ao novo banco
\c exodo_db

-- Verificar conexão
SELECT 1;
```

#### Arquivo .env para backend:
```bash
# Backend PyNFe
DATABASE_URL=postgresql://exodo_user:sua_senha_segura@localhost:5432/exodo_db
DATABASE_ECHO=false  # true para debug
DATABASE_POOL_SIZE=10

# Backend NFCe
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=sua_senha_segura
```

---

### 4. Atualizar Código Python

#### Exemplo - Substituir SQLite por PostgreSQL em app.py:

**Antes (SQLite):**
```python
import sqlite3

conn = sqlite3.connect('local.db')
cursor = conn.cursor()
cursor.execute("SELECT * FROM tabela")
```

**Depois (PostgreSQL):**
```python
import psycopg2
from psycopg2.extras import RealDictCursor
import os

def get_db_connection():
    conn = psycopg2.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        port=os.getenv('DB_PORT', 5432),
        database=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD')
    )
    return conn

# Usar em rotas
@app.route('/api/dados')
def get_dados():
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT * FROM tabela")
    resultado = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify(resultado)
```

---

### 5. Usar SQLAlchemy (Recomendado)

#### Instalar:
```bash
pip install flask-sqlalchemy
pip install flask-migrate
```

#### Estrutura (app.py):
```python
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
import os

app = Flask(__name__)

# Configuração do banco de dados
database_url = os.getenv(
    'DATABASE_URL',
    'postgresql://exodo_user:senha@localhost:5432/exodo_db'
)
# Substituir sqlite:// por postgresql:// se necessário
app.config['SQLALCHEMY_DATABASE_URI'] = database_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
migrate = Migrate(app, db)

# Definir modelos
class Venda(db.Model):
    __tablename__ = 'vendas'
    
    id = db.Column(db.Integer, primary_key=True)
    numero_nfe = db.Column(db.String(50), unique=True)
    valor_total = db.Column(db.Float)
    data_criacao = db.Column(db.DateTime, default=datetime.utcnow)
    
    def to_dict(self):
        return {
            'id': self.id,
            'numero_nfe': self.numero_nfe,
            'valor_total': self.valor_total,
            'data_criacao': self.data_criacao.isoformat()
        }

# Usar em rotas
@app.route('/api/vendas')
def list_vendas():
    vendas = Venda.query.all()
    return jsonify([v.to_dict() for v in vendas])

@app.route('/api/vendas', methods=['POST'])
def create_venda():
    data = request.json
    venda = Venda(
        numero_nfe=data['numero_nfe'],
        valor_total=data['valor_total']
    )
    db.session.add(venda)
    db.session.commit()
    return jsonify(venda.to_dict()), 201
```

---

### 6. Migrations com Alembic

#### Inicializar migrations:
```bash
flask db init
```

#### Gerar migration automática:
```bash
flask db migrate -m "Criar tabelas iniciais"
```

#### Aplicar migrations:
```bash
flask db upgrade
```

#### Ver status:
```bash
flask db current
flask db history
```

---

### 7. Testar Conexão

#### Script de teste:
```python
# test_db_connection.py
import os
from dotenv import load_dotenv
import psycopg2

load_dotenv()

try:
    conn = psycopg2.connect(
        host=os.getenv('DB_HOST'),
        port=os.getenv('DB_PORT'),
        database=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD')
    )
    
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    resultado = cursor.fetchone()
    
    print("✅ Conexão com PostgreSQL bem-sucedida!")
    print(f"Resultado: {resultado}")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Erro ao conectar: {e}")
```

#### Executar:
```bash
python test_db_connection.py
```

---

### 8. Evolution API (Node.js) - Já Configurado

O Evolution API já está configurado para PostgreSQL em `src/config/env.config.ts`:

```typescript
DATABASE: {
  CONNECTION: {
    URI: process.env.DATABASE_CONNECTION_URI || '',
    CLIENT_NAME: process.env.DATABASE_CONNECTION_CLIENT_NAME || 'evolution',
  },
  PROVIDER: process.env.DATABASE_PROVIDER || 'postgresql',
  // ... resto da configuração
}
```

#### Variáveis de ambiente (.env):
```bash
DATABASE_CONNECTION_URI=postgresql://exodo_user:senha@localhost:5432/exodo_db
DATABASE_CONNECTION_CLIENT_NAME=evolution
DATABASE_PROVIDER=postgresql
```

---

### 9. Backup e Migração de Dados

#### Exportar dados do SQLite:
```bash
# Se houver dados em SQLite, exportar como CSV
sqlite3 local.db ".mode csv" ".headers on" ".output dados.csv" "SELECT * FROM tabela;"
```

#### Importar para PostgreSQL:
```sql
-- Conectar ao PostgreSQL
\c exodo_db

-- Criar tabela correspondente
CREATE TABLE tabela (
    id SERIAL PRIMARY KEY,
    coluna1 VARCHAR(255),
    coluna2 DECIMAL(10,2),
    criado_em TIMESTAMP DEFAULT NOW()
);

-- Importar CSV
\copy tabela(coluna1, coluna2) FROM 'dados.csv' WITH (FORMAT csv, HEADER);
```

---

### 10. Docker com PostgreSQL (Opcional)

#### docker-compose.yml:
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: exodo_postgres
    environment:
      POSTGRES_USER: exodo_user
      POSTGRES_PASSWORD: sua_senha_segura
      POSTGRES_DB: exodo_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - exodo_network

  backend:
    build: ./backend_pynfe
    depends_on:
      - postgres
    environment:
      DATABASE_URL: postgresql://exodo_user:sua_senha_segura@postgres:5432/exodo_db
    ports:
      - "8000:8000"
    networks:
      - exodo_network

volumes:
  postgres_data:

networks:
  exodo_network:
```

#### Iniciar:
```bash
docker-compose up -d
```

---

## 📝 Checklist de Migração

- [ ] PostgreSQL instalado e em execução
- [ ] Driver psycopg2 instalado em todos os backends
- [ ] Banco de dados `exodo_db` criado
- [ ] Usuário `exodo_user` criado
- [ ] Arquivo `.env` configurado com credenciais PostgreSQL
- [ ] Testes de conexão passando
- [ ] Código Python migrado de SQLite para psycopg2/SQLAlchemy
- [ ] Migrations criadas com Alembic
- [ ] Dados exportados e importados (se aplicável)
- [ ] Backend local testado com PostgreSQL
- [ ] Evolution API configurada para PostgreSQL
- [ ] Testes end-to-end passando

---

## 🚀 Próximos Passos

1. **Produção**: Deploy do PostgreSQL em servidor de produção
2. **Backups**: Configurar backup automático do PostgreSQL
3. **Monitoring**: Configurar monitoramento de performance
4. **ORM**: Considerar usar SQLAlchemy em todos os modelos
5. **Transactions**: Implementar transações ACID onde necessário

---

## 📞 Referências

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Psycopg2 Documentation](https://www.psycopg.org/)
- [SQLAlchemy ORM](https://docs.sqlalchemy.org/)
- [Flask-SQLAlchemy](https://flask-sqlalchemy.palletsprojects.com/)
- [Alembic Migrations](https://alembic.sqlalchemy.org/)

