# 🚀 INSTALAÇÃO MANUAL DO POSTGRESQL - PASSO A PASSO

## ⚠️ Importante

O script de instalação automática requer **privilégios de Administrador**. 
Siga os passos abaixo para instalar manualmente:

---

## ✅ Passo 1: Baixar PostgreSQL

1. Vá para: https://www.postgresql.org/download/windows/
2. Clique em **"Download the installer"**
3. Escolha PostgreSQL **15.x** ou superior
4. Execute o instalador baixado

---

## ✅ Passo 2: Configurar PostgreSQL durante Instalação

Durante o instalador, você verá estas opções:

| Opção | Valor |
|-------|-------|
| **Diretório** | C:\Program Files\PostgreSQL\15 (padrão) |
| **Servidor** | postgresql-x64-15 |
| **Porta** | 5432 |
| **Usuário admin (postgres)** | Nota a senha! |
| **Locale** | Português (Brasil) ou English |

⚠️ **IMPORTANTE:** Anote a senha do usuário `postgres` que você digitar!

---

## ✅ Passo 3: Criar Banco de Dados e Usuário

Abra o **pgAdmin** (vem com PostgreSQL) ou use o terminal:

### Opção A: Usando pgAdmin (Recomendado para iniciantes)

1. Procure por "pgAdmin" no menu Iniciar
2. Abra no navegador (localhost:5050)
3. Clique em **Servers** → **PostgreSQL 15**
4. Use a senha do usuário `postgres` que você anotou
5. Clique direito em **Databases** → **Create** → **Database**
   - Nome: `exodo_db`
   - Owner: `postgres` (padrão)
6. Clique em **SQL** (ícone de terminal) e execute:

```sql
-- Criar usuário
CREATE USER exodo_user WITH PASSWORD 'senha123';

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;
```

### Opção B: Usando Terminal (Mais rápido)

1. Abra **Command Prompt** (cmd.exe) como **Administrador**
2. Execute:

```bash
psql -U postgres
```

3. Digite a senha do usuário `postgres`
4. Execute estes comandos:

```sql
CREATE USER exodo_user WITH PASSWORD 'senha123';
CREATE DATABASE exodo_db OWNER exodo_user;
GRANT ALL PRIVILEGES ON DATABASE exodo_db TO exodo_user;
ALTER ROLE exodo_user CREATEDB;
\q
```

---

## ✅ Passo 4: Verificar PATH (Windows)

PostgreSQL precisa estar no PATH. Verificar:

1. Abra **Prompt de Comando** como **Administrador**
2. Digite: `psql --version`
3. Se funcionar, PostgreSQL está no PATH ✅
4. Se não funcionar, adicione manualmente:
   - Variáveis de Ambiente
   - Path: `C:\Program Files\PostgreSQL\15\bin`

---

## ✅ Passo 5: Criar arquivo .env

Na pasta `sistema_exodo_15-04-2026`, crie arquivo `.env`:

```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=senha123

DATABASE_URL=postgresql://exodo_user:senha123@localhost:5432/exodo_db
SQLALCHEMY_ECHO=false
```

---

## ✅ Passo 6: Instalar Driver Python

Abra o terminal na pasta do projeto:

```bash
cd backend_pynfe
pip install psycopg2-binary
```

---

## ✅ Passo 7: Testar Conexão

Na raiz do projeto, execute:

```bash
python test_postgres_connection.py
```

Se vir `✅ TESTE PASSOU`, tudo está funcionando!

---

## 🔍 Verificação Completa

Execute para validar tudo:

```bash
python verificar_migracao_postgresql.py
```

---

## 🆘 Troubleshooting

### "psql: command not found"
- PostgreSQL não está no PATH
- Solução: Adicione `C:\Program Files\PostgreSQL\15\bin` às Variáveis de Ambiente

### "could not connect to server"
- PostgreSQL não está rodando
- Solução: Iniciar o serviço PostgreSQL no Services (services.msc)

### "password authentication failed"
- Senha incorreta
- Solução: Use a senha que você digitou na instalação

### "database does not exist"
- Banco de dados não foi criado
- Solução: Executar o Passo 3 novamente

---

## ✨ Sucesso!

Se chegou até aqui e os testes passaram, **PostgreSQL está pronto!**

Próximos passos:
1. Executar backend: `python app.py`
2. Testar endpoints em: `http://localhost:5000/health`
3. Consultar guia completo: `MIGRACAO_SQLITE_POSTGRESQL.md`

