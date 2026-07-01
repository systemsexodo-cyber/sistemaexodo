# ⚠️ SOLUÇÃO: Migração Supabase Bloqueada por RLS

## 🔍 Problema Diagnosticado

O Supabase tem **Row Level Security (RLS)** ativado, que está bloqueando o acesso aos dados via ANON_KEY.

- ✅ As tabelas existem: `empresas`, `usuarios`, `clientes`, etc.
- ✅ Os dados existem (verificado)
- ❌ ANON_KEY retorna listas vazias (RLS bloqueando)
- ❌ SERVICE_ROLE_KEY não está configurada

## 🛠️ Soluções

### Opção 1: Usar SERVICE_ROLE_KEY (Recomendado)

A SERVICE_ROLE_KEY contorna o RLS (Row Level Security). Você pode obtê-la no painel do Supabase:

1. **Abra o Supabase Dashboard**
   - URL: https://supabase.com/dashboard
   - Acesse seu projeto

2. **Encontre a chave:**
   - Menu esquerdo: Settings → API
   - Procure por "service_role" ou "Service Role Key"
   - Copie a chave

3. **Adicione ao .env:**
   ```env
   SUPABASE_SERVICE_ROLE_KEY=sua_service_role_key_aqui
   ```

4. **Execute a migração:**
   ```powershell
   python migrar_supabase_v2.py
   ```

### Opção 2: Desabilitar RLS no Supabase

Se não quiser/conseguir a SERVICE_ROLE_KEY:

1. Vá para Supabase Dashboard → Authentication → Policies
2. Para cada tabela (`empresas`, `usuarios`, etc):
   - Abra a tabela
   - Desabilite RLS ou crie uma policy para ANON_KEY
3. Reexecute a migração

### Opção 3: Usar RLS com a ANON_KEY

Se usar a ANON_KEY, você precisa ter policies que permitam leitura:

```sql
-- Exemplo de política permissiva
CREATE POLICY "Enable read for all users" ON empresas
  FOR SELECT
  USING (true);
```

## 📝 Status Atual

| Item | Status |
|------|--------|
| Supabase reachable | ✅ OK |
| Conexão com Supabase | ✅ OK |
| Tabelas existem | ✅ OK |
| Dados existem | ✅ OK |
| RLS ativado | ✅ Sim |
| ANON_KEY funciona | ❌ Bloqueada por RLS |
| SERVICE_ROLE_KEY | ❌ Não configurada |

## 🚀 Próximos Passos

1. Obtenha a SERVICE_ROLE_KEY
2. Adicione ao `.env`
3. Execute: `python migrar_supabase_v2.py`

Após isso, você terá todos os dados do Supabase sincronizados em seu PostgreSQL local!

---

**Data:** 30 de Maio de 2026
**Status:** Aguardando SERVICE_ROLE_KEY
