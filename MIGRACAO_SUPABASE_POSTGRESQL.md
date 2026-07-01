# Migração Supabase → PostgreSQL local

O script `migrar_supabase_postgresql.py` sincroniza as tabelas do Supabase para o PostgreSQL local definido em `.env`.

## Pré-requisitos

1. PostgreSQL local rodando e acessível.
2. Acesso ao Supabase com `SUPABASE_URL`.
3. Pelo menos uma chave válida (`SUPABASE_SERVICE_ROLE_KEY` recomendado).

## Variáveis de ambiente

Copie o arquivo `.env.supabase.example` para `.env.supabase` e configure as chaves.

Exemplo:

```env
SUPABASE_URL=https://SEU_PROJETO.supabase.co
SUPABASE_ANON_KEY=sua_anon_key
SUPABASE_SERVICE_ROLE_KEY=sua_service_role_key
```

O PostgreSQL continua vindo do `.env` principal:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db
DB_USER=exodo_user
DB_PASSWORD=sua_senha
```

## Uso

### Sincronização incremental (recomendado)

```powershell
python migrar_supabase_postgresql.py --mode append
```

### Recriar o banco local a partir do Supabase

```powershell
python migrar_supabase_postgresql.py --mode replace
```

### Migrar apenas uma tabela

```powershell
python migrar_supabase_postgresql.py --table empresas --table clientes
```

### Verificar o que seria executado

```powershell
python migrar_supabase_postgresql.py --dry-run
```

## Observações sobre "um banco local compartilhado"

O script popula o PostgreSQL local apontado por `DB_HOST`.

- Se `DB_HOST=localhost`, cada máquina mantém seu próprio banco local.
- Se `DB_HOST` apontar para um PostgreSQL compartilhado (servidor em rede), a mesma execução sincroniza esse banco único a partir do Supabase.

Para a arquitetura desejada, configure `DB_HOST` para o servidor compartilhado quando quiser um único banco para várias máquinas.
