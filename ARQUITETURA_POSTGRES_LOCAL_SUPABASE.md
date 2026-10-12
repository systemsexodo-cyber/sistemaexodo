# Arquitetura validada: PostgreSQL local + Supabase em nuvem

## Situação validada

A base local do sistema está ativa e aceita conexões em `localhost:5432`.

Validação executada:

```bash
pg_isready -h localhost -p 5432
```

Resultado:

```text
localhost:5432 - accepting connections
```

Isso confirma que o PostgreSQL local está operacional e é a base principal do sistema no momento.

## Estrutura correta recomendada

### 1) Banco local (fonte principal)
- PostgreSQL local
- Usado pelo app em produção local
- Configuração lida em:
  - [.env](.env)
  - [lib/services/database_service.dart](lib/services/database_service.dart)
  - [lib/services/postgres_local_starter.dart](lib/services/postgres_local_starter.dart)

### 2) Nuvem (espelho/sincronização)
- Supabase
- Usado para backup, sincronização, réplica e acesso via nuvem
- Configuração lida em:
  - [.env](.env)
  - [lib/services/supabase_service.dart](lib/services/supabase_service.dart)

### 3) Firebase
- Ainda existe como integração complementar
- Não é a base principal do sistema
- Funciona mais como camada extra de armazenamento/integracão, não como banco principal do app

## Regra de ouro para o projeto

- PostgreSQL local = fonte de verdade para o uso diário
- Supabase = espelho da nuvem e sincronização
- SQLite = legado/migração, não deve ser a base principal em produção

## Evidências no código

- Conexão do PostgreSQL local em [lib/services/database_service.dart](lib/services/database_service.dart)
- Auto-start do PostgreSQL em [lib/services/postgres_local_starter.dart](lib/services/postgres_local_starter.dart)
- Inicialização do Supabase em [lib/services/supabase_service.dart](lib/services/supabase_service.dart)
- Variáveis de ambiente em [.env](.env)

## Próximos passos recomendados

1. Manter o PostgreSQL local como banco principal do sistema.
2. Garantir que o app só use a conexão local como padrão de escrita/consulta.
3. Continuar a sincronização para Supabase como camada cloud.
4. Manter scripts antigos de SQLite apenas como compatibilidade histórica, sem ativá-los no fluxo principal.
5. Validar o fluxo de sincronização com uma empresa real e uma operação de venda simples.

## Checklist operacional

- [ ] PostgreSQL local iniciado
- [ ] .env com DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD corretos
- [ ] Supabase configurado no .env
- [ ] App conectando ao PostgreSQL local
- [ ] Sincronização para Supabase funcionando em ciclo
- [ ] SQLite não ativo no fluxo principal

## Conclusão

A estrutura atual do projeto já está alinhada com a arquitetura desejada:

PostgreSQL local + Supabase em nuvem

Esse é o modelo que deve ser mantido para o sistema funcionar estável e em paralelo com a nuvem.
