# Migrações de schema — Sistema Êxodo

Esta pasta é a **fonte única** das mudanças de schema do banco do Êxodo.
Cada arquivo `.sql` é aplicado **uma vez** pelo próprio app, no banco **local**,
no primeiro boot após a atualização — e o mesmo arquivo pode ser colado no
**Supabase SQL Editor** para a nuvem (as migrações são portáveis; as que só
fazem sentido na nuvem se auto-pulam no banco local, e vice-versa).

## Como funciona

- `scripts/init_db.sql` é o **baseline** (versão 0): cria tudo o que existia
  até a última instalação limpa. Instalação nova nasce com ele.
- Os arquivos desta pasta são os **incrementos**, numerados. O app mantém a
  tabela `schema_migrations` com a versão de cada um já aplicado e roda só os
  que faltam, em ordem, cada um numa transação.
- Instalar uma versão nova do sistema **entrega os arquivos novos** (o
  instalador copia `scripts\migrations\`) e o app aplica o que ainda não rodou
  naquele computador. Não depende de o banco já existir nem da data da
  instalação.

## Os arquivos

| Arquivo | Onde vale | O que faz |
|---|---|---|
| `005_ajustes_estoque_lote.sql` | local + nuvem | Cria `ajustes_estoque_lote` (tela Ajuste Geral) |
| `006_politicas_storage_app.sql` | nuvem | Políticas de Storage (resolve 403 ao publicar/backup) |
| `007_politica_publicacao_bridge_config.sql` | nuvem | Libera escrita em `bridge_config` para `anon` |
| `008_realtime_tabelas_criticas.sql` | nuvem | Publica tabelas no Realtime (UPDATE/DELETE <100ms) |
| `009_sessao_exclusiva_usuario.sql` | nuvem | Sessão exclusiva por dispositivo (`auth.users`) |
| `010_remover_tabelas_fantasma.sql` | local | Remove tabelas que não existem na nuvem (HTTP 404) |
| `011_remover_foreign_keys.sql` | local | Remove FKs (a nuvem não tem; quebravam o download) |
| `012_converter_uuid_para_text.sql` | local | Converte colunas `uuid` -> `text` (ids da nuvem são text) |
| `013_bloquear_troca_de_empresa.sql` | local + nuvem | Trava no banco: um registro **nunca** troca de empresa (anti-mistura) |

> A numeração 005–009 é a mesma das migrações originais do Supabase, para não
> embaralhar o histórico. O baseline (`init_db.sql`) equivale à
> `004_produto_historico`. As de 010 em diante são limpezas locais que antes
> viviam no `migrar_schema.ps1`.

## Regra para novas mudanças

1. **Tabela/coluna/índice** → crie `NNN_descricao.sql` nesta pasta (portável,
   idempotente). Se valer para a nuvem também, o mesmo arquivo serve.
2. **Política/RLS/storage/realtime** (só nuvem) → mesmo aqui, mas o arquivo
   **precisa se auto-pular** quando `auth`/`storage`/`authenticated` não
   existirem (veja o 009 como modelo).
3. A migração **tem que ser idempotente** e **só adicionar** — nunca apagar
   dado de produção. `DROP TABLE` só para tabelas que se sabe serem lixo.

## Adicionar uma migração (passo a passo)

1. Crie `scripts/migrations/010_minha_mudanca.sql`.
2. Use `CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` / `CREATE
   INDEX IF NOT EXISTS` e envolva blocos condicionais em `DO $$ ... $$`.
3. Teste no banco local: **Backup e Restauração → "Aplicar migrações de
   schema"**.
4. Se valer para a nuvem, cole o mesmo SQL no Supabase SQL Editor.

## Legado

`scripts/migrar_schema.ps1` foi o antecessor manual deste mecanismo (rodava
`init_db.sql` + limpezas soltas). Ele **não** é mais copiado pelo instalador
nem chamado pelo app: as migrações desta pasta cobrem os mesmos casos de forma
versionada. O arquivo continua no repositório só para suporte pontual.
