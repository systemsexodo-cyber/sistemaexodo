# ✅ GUIA RÁPIDO: Migração SQLite → PostgreSQL

## 🎯 Resumo Executivo

Você quer usar **PostgreSQL** em vez de SQLite. Este documento facilita a transição com passos práticos e testados.

---

## ⚡ Começo Rápido (5 minutos)

### 1. Instalar PostgreSQL (Windows)

**Opção A - Automática (recomendado):**
```powershell
# Execute como Administrador
.\INSTALAR_POSTGRESQL_WINDOWS.ps1
```

**Opção B - Manual:**
- Vá para https://www.postgresql.org/download/windows/
- Baixe PostgreSQL 15 ou superior
- Execute o instalador
- Anote a senha do usuário `postgres`

---

### 2. Criar banco de dados

```bash
# Abrir terminal como Administrador e execute:
psql -U postgres

# No prompt psql, executar estes comandos:
CREATE USER exodo_user WITH PASSWORD 'senha123';
CREATE DATABASE exodo_db OWNER exodo_user;
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
\q
```

---

### 3. Configurar backend Python

#### Passo 3a: Instalar driver PostgreSQL
```bash
cd backend_pynfe
pip install psycopg2-binary
```

#### Passo 3b: Criar arquivo `.env`
Na raiz do `backend_pynfe`, criar arquivo `.env`:
```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=senha123
```

#### Passo 3c: Testar conexão
```bash
python ../test_postgres_connection.py
```

Se vir `✅ TESTE PASSOU`, tudo está OK!

---

## 📂 Arquivos Criados para Você

| Arquivo | Propósito |
|---------|-----------|
| `MIGRACAO_SQLITE_POSTGRESQL.md` | Guia completo e detalhado |
| `INSTALAR_POSTGRESQL_WINDOWS.ps1` | Script de instalação automática |
| `test_postgres_connection.py` | Script para testar conexão |
| `backend_pynfe/database_config_example.py` | Exemplo de configuração com SQLAlchemy |
| `GUIA_RAPIDO_POSTGRESQL.md` | Este arquivo |

---

## 🔄 Estrutura do Projeto

```
sistema_exodo_15-04-2026/
├── backend_pynfe/              # Backend Flask para NFC-e
│   ├── app.py                  # Aplicação principal
│   ├── requirements.txt         # Dependências (adicione psycopg2-binary)
│   ├── .env                     # Credenciais (criar)
│   └── database_config_example.py  # Exemplo SQLAlchemy + PostgreSQL
│
├── backend_nfce/               # Backend alternativo
│
├── evolution-api/              # API WhatsApp (já configurada para PG)
│
├── MIGRACAO_SQLITE_POSTGRESQL.md
├── INSTALAR_POSTGRESQL_WINDOWS.ps1
├── test_postgres_connection.py
└── GUIA_RAPIDO_POSTGRESQL.md   # Este arquivo
```

---

## 📊 Comparação: SQLite vs PostgreSQL

| Aspecto | SQLite | PostgreSQL |
|--------|--------|-----------|
| **Arquivo local?** | ✅ Sim (.db) | ❌ Não (servidor) |
| **Produção** | ❌ Não recomendado | ✅ Excelente |
| **Concorrência** | ❌ Limitada | ✅ Forte |
| **Escalabilidade** | ❌ Pequenos projetos | ✅ Qualquer tamanho |
| **Backup** | 📋 Cópia de arquivo | 🔧 Ferramentas robustas |
| **Performance** | ⚡ Simples operações | ⚡⚡ Queries complexas |

---

## 🔗 Migrar Código Existente

### Antes (SQLite):
```python
import sqlite3

conn = sqlite3.connect('local.db')
cursor = conn.cursor()
cursor.execute("SELECT * FROM vendas")
results = cursor.fetchall()
cursor.close()
conn.close()
```

### Depois (PostgreSQL com psycopg2):
```python
import psycopg2
import os
from dotenv import load_dotenv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv('DB_HOST'),
    port=os.getenv('DB_PORT'),
    database=os.getenv('DB_NAME'),
    user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASSWORD')
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM vendas")
results = cursor.fetchall()
cursor.close()
conn.close()
```

### Melhor Ainda (usando SQLAlchemy):
```python
from flask_sqlalchemy import SQLAlchemy
from flask import Flask

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
db = SQLAlchemy(app)

# Em vez de SQL puro:
vendas = Venda.query.all()
```

---

## 🐳 Alternativa: PostgreSQL com Docker

Se não quer instalar PostgreSQL no PC, pode usar Docker:

```bash
docker pull postgres:15-alpine

docker run --name exodo_postgres \
  -e POSTGRES_USER=exodo_user \
  -e POSTGRES_PASSWORD=senha123 \
  -e POSTGRES_DB=exodo_db \
  -p 5432:5432 \
  -d postgres:15-alpine
```

Depois configure `.env` normalmente (localhost:5432).

---

## ✅ Checklist de Migração

- [ ] PostgreSQL instalado e rodando
- [ ] Banco de dados `exodo_db` criado
- [ ] Usuário `exodo_user` criado
- [ ] Arquivo `.env` configurado
- [ ] `pip install psycopg2-binary` executado
- [ ] `python test_postgres_connection.py` passou ✅
- [ ] Backend testado com nova conexão
- [ ] Dados migrados (se havia SQLite com dados)
- [ ] Evolution API funcionando (já usa PostgreSQL)
- [ ] Produção pronta

---

## 🚨 Troubleshooting

### Erro: `psycopg2.OperationalError: could not connect to server`

**Solução:**
1. Verificar se PostgreSQL está rodando
2. Verificar host/porta no `.env`
3. Verificar credenciais (user/password)

```bash
# Testar conexão manualmente
psql -h localhost -U exodo_user -d exodo_db

# Se pedir senha, a conexão está funcionando!
```

---

### Erro: `database exodo_db does not exist`

**Solução:**
```bash
# Conectar como postgres e recriar
psql -U postgres

# Dentro do psql:
CREATE DATABASE exodo_db OWNER exodo_user;
```

---

### Erro: `psycopg2: No module named 'psycopg2'`

**Solução:**
```bash
pip install psycopg2-binary
```

---

## 🎓 Próximos Passos (Intermediário)

### 1. Usar SQLAlchemy (ORM)
```bash
pip install flask-sqlalchemy flask-migrate
```

Ver arquivo `backend_pynfe/database_config_example.py` para exemplo completo.

### 2. Criar Migrations com Alembic
```bash
flask db init
flask db migrate -m "Inicial"
flask db upgrade
```

### 3. Backup Automático
```bash
# Backup manual
pg_dump -U exodo_user exodo_db > backup.sql

# Restaurar
psql -U exodo_user exodo_db < backup.sql
```

---

## 📞 Referências Rápidas

| Recurso | Link |
|---------|------|
| PostgreSQL Docs | https://www.postgresql.org/docs/ |
| Psycopg2 | https://www.psycopg.org/ |
| SQLAlchemy | https://www.sqlalchemy.org/ |
| Flask-SQLAlchemy | https://flask-sqlalchemy.palletsprojects.com/ |
| Docker PostgreSQL | https://hub.docker.com/_/postgres |

---

## ❓ Dúvidas Frequentes

**P: Preciso migrar dados do SQLite?**
R: Somente se tinha dados importantes lá. Projeto novo = comece com PostgreSQL vazio.

**P: Qual versão do PostgreSQL usar?**
R: Recomendo 15 ou 14. Qualquer versão recente funciona.

**P: Posso usar PostgreSQL local (sem Docker)?**
R: Sim! Instale via PostgreSQL.org ou Chocolatey (recomendado no Windows).

**P: E para produção?**
R: PostgreSQL é excelente para produção. Use em cloud (AWS RDS, Google Cloud SQL, DigitalOcean, etc).

**P: Como fazer backup?**
R: Use `pg_dump` para exportar, `psql` para restaurar.

---

## 🎉 Sucesso!

Se chegou até aqui e o teste passou ✅, você tem PostgreSQL funcionando!

**Próximo passo:** Verificar o arquivo `MIGRACAO_SQLITE_POSTGRESQL.md` para detalhes avançados.

---

*Última atualização: Maio de 2026*
