# 📊 GUIA COMPLETO: Migração de Dados SQLite → PostgreSQL

## 🎯 Visão Geral

Este guia mostra como migrar **todas as tabelas e dados** do SQLite para PostgreSQL.

### Arquivo SQLite
- **Localização**: `C:\Users\[seu_usuário]\Documents\exodo_local.db`
- **Tamanho**: Pode variar (contém todas as tabelas locais)
- **Tabelas**: Produtos, Vendas, Clientes, Configurações, etc.

---

## ⚡ Passos Rápidos (Se já tem PostgreSQL instalado)

### 1. Analisar o SQLite (opcional, mas recomendado)
```bash
python analisar_sqlite.py
```

Isso mostrará:
- ✅ Quantas tabelas existem
- ✅ Quantos registros em cada tabela
- ✅ Estrutura das colunas
- ✅ Tamanho total

### 2. Executar Migração
```bash
python migrar_sqlite_postgresql.py
```

Isso fará automaticamente:
- ✅ Ler estrutura do SQLite
- ✅ Criar tabelas no PostgreSQL
- ✅ Importar todos os dados
- ✅ Mostrar resumo completo

### 3. Verificar Sucesso
```bash
python test_postgres_connection.py
```

Se vir `✅ TESTE PASSOU`, migração foi bem-sucedida!

---

## 📋 Pré-requisitos

### PostgreSQL
- [ ] PostgreSQL 14+ instalado
- [ ] Banco `exodo_db` criado
- [ ] Usuário `exodo_user` criado
- [ ] Arquivo `.env` configurado

**Se não tem tudo pronto:**
```bash
# Ler guia de instalação
INSTALACAO_MANUAL_POSTGRESQL.md
```

### Python
- [ ] Python 3.8+
- [ ] psycopg2 instalado

```bash
pip install psycopg2-binary
```

---

## 🔧 Configuração do .env

Criar arquivo `.env` na raiz do projeto:

```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=sua_senha_aqui

DATABASE_URL=postgresql://exodo_user:sua_senha_aqui@localhost:5432/exodo_db
```

---

## 📊 Passo 1: Analisar SQLite

Antes de migrar, é bom saber o que você tem:

```bash
python analisar_sqlite.py
```

**Output esperado:**
```
✅ Arquivo encontrado: C:\Users\...\Documents\exodo_local.db
✅ Tamanho: 5.23 MB

📊 TABELAS ENCONTRADAS:
  1. produtos_local
  2. vendas
  3. clientes
  4. itens_venda
  5. configuracoes
  ...

Total: 8 tabelas, 1.245 registros
```

---

## 🚀 Passo 2: Executar Migração

```bash
python migrar_sqlite_postgresql.py
```

**Output esperado:**

```
════════════════════════════════════════════════════════════════
              MIGRAÇÃO SQLITE → POSTGRESQL
════════════════════════════════════════════════════════════════

1️⃣  VERIFICAÇÃO DE AMBIENTE
✅ SQLite encontrado: C:\Users\...\Documents\exodo_local.db
✅ PostgreSQL configurado: exodo_user@localhost:5432/exodo_db

2️⃣  CONECTANDO AO POSTGRESQL
✅ Conectado ao PostgreSQL com sucesso!

3️⃣  TABELAS ENCONTRADAS NO SQLITE
Total de tabelas: 8

  1. produtos_local
  2. vendas
  3. clientes
  4. itens_venda
  ...

4️⃣  MIGRANDO TABELAS
ℹ️  Migrando tabela: produtos_local
✅ Tabela 'produtos_local' criada no PostgreSQL
✅ Tabela 'produtos_local': 245 registros migrados

ℹ️  Migrando tabela: vendas
✅ Tabela 'vendas' criada no PostgreSQL
✅ Tabela 'vendas': 89 registros migrados

...

📊 RESUMO DA MIGRAÇÃO
Tabelas criadas:    8
Tabelas falhadas:   0
Registros migrados: 2.345

✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!
```

---

## ✅ Passo 3: Verificar Dados

### Teste Rápido
```bash
python test_postgres_connection.py
```

### Verificar Tabelas (SQL)
```sql
-- Conectar no PostgreSQL
psql -U exodo_user -d exodo_db

-- Listar tabelas
\dt

-- Contar registros de uma tabela
SELECT COUNT(*) FROM produtos_local;

-- Sair
\q
```

### Verificar via Python
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

# Listar todas as tabelas
cursor.execute("""
    SELECT table_name FROM information_schema.tables 
    WHERE table_schema = 'public'
    ORDER BY table_name
""")

for table in cursor.fetchall():
    table_name = table[0]
    cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
    count = cursor.fetchone()[0]
    print(f"{table_name}: {count} registros")

cursor.close()
conn.close()
```

---

## 🔄 Rollback (Se algo der errado)

### Limpar PostgreSQL e Tentar Novamente

```bash
# Conectar como superuser
psql -U postgres

# Dentro do psql:
DROP DATABASE exodo_db;
CREATE DATABASE exodo_db OWNER exodo_user;
\q

# Executar migração novamente
python migrar_sqlite_postgresql.py
```

### Restaurar SQLite
Se havia backup:
```bash
cp exodo_local.db.backup exodo_local.db
```

---

## 🆘 Problemas Comuns

### ❌ "psycopg2.OperationalError: could not connect to server"
**Causa:** PostgreSQL não está rodando
**Solução:**
```bash
# No Windows, iniciar PostgreSQL service:
# 1. Abrir Services (services.msc)
# 2. Procurar por "postgresql"
# 3. Clicar em "Start" ou "Restart"

# Ou via Terminal (como Admin):
pg_ctl -D "C:\Program Files\PostgreSQL\15\data" start
```

### ❌ "database exodo_db does not exist"
**Causa:** Banco não foi criado
**Solução:**
```bash
psql -U postgres

# Dentro do psql:
CREATE DATABASE exodo_db OWNER exodo_user;
\q
```

### ❌ "permission denied for schema public"
**Causa:** Permissões incorretas
**Solução:**
```bash
psql -U postgres -d exodo_db

# Dentro do psql:
GRANT ALL PRIVILEGES ON SCHEMA public TO exodo_user;
\q
```

### ❌ "relation does not exist"
**Causa:** Tabela não foi criada corretamente
**Solução:**
1. Fazer backup do `.env`
2. Executar migração novamente
3. Ou limpar e reconectar

---

## 📈 Monitoramento Pós-Migração

### Verificar Performance
```sql
-- Conectar
psql -U exodo_user -d exodo_db

-- Ver tamanho das tabelas
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Ver índices
SELECT * FROM pg_indexes WHERE schemaname = 'public';
```

### Backup PostgreSQL
```bash
# Backup completo
pg_dump -U exodo_user -d exodo_db -F c -b -v -f backup.dump

# Restaurar se necessário
pg_restore -U exodo_user -d exodo_db -v backup.dump
```

---

## 🎓 Próximos Passos

### 1. Atualizar Código da Aplicação
Mudar todas as referências de SQLite para PostgreSQL:

**Antes (Flutter/Dart):**
```dart
final db = await DatabaseService().database;
final vendas = await db.query('vendas');
```

**Depois (Backend Python):**
```python
from app import db
vendas = db.session.query(Venda).all()
```

### 2. Testar Aplicação
```bash
# Backend
cd backend_pynfe
python app.py

# Testar endpoints
curl http://localhost:5000/health
curl http://localhost:5000/api/vendas
```

### 3. Sincronizar Evolution API
Evolution API já está configurada para PostgreSQL:
```bash
cd evolution-api
npm start
```

### 4. Fazer Backup Regular
```bash
# Backup automático (agendado)
pg_dump -U exodo_user exodo_db | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

---

## ✨ Checklist Final

- [ ] SQLite analisado (`analisar_sqlite.py`)
- [ ] PostgreSQL rodando
- [ ] Banco `exodo_db` criado
- [ ] Arquivo `.env` configurado
- [ ] Migração executada (`migrar_sqlite_postgresql.py`)
- [ ] Todos os registros importados
- [ ] Dados verificados no PostgreSQL
- [ ] Backend testado
- [ ] Aplicação funcionando
- [ ] Backup PostgreSQL feito

---

## 📞 Referências

- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [Psycopg2 Guide](https://www.psycopg.org/)
- [Migration Best Practices](https://wiki.postgresql.org/wiki/Migration_from_SQLite)

---

*Última atualização: 26 de Maio de 2026*
