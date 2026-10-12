# Sincronização pela rede local (LAN)

Faz os **dois PCs da mesma loja** atualizarem os bancos locais **direto um com o
outro**, sem passar pela nuvem. Serve para quando a internet cai (ou fica
instável): a loja continua com os dois caixas enxergando as mesmas vendas.

> A nuvem (Supabase) continua sendo o **caminho principal**. A LAN é um atalho a
> mais: roda antes do ciclo da nuvem no mesmo sincronizador.

---

## Como funciona

```
  PC-1                          PC-2
  PostgreSQL local  <-------->  PostgreSQL local
        |                              |
        +------------ Supabase --------+
              (fonte de verdade)
```

- Cada PC **puxa** do outro o que mudou desde a última visita (pela coluna de
  data da tabela) e também os **apagados** (`_exodo_deletados`).
- Nada é *empurrado*: os dois rodando, os bancos convergem.
- As linhas que chegam pela LAN são **réplica**: não entram na fila da nuvem.
  Quem envia a linha original para o Supabase é o PC de origem.
- Valem as mesmas travas do download da nuvem:
  - **filtro de empresa** (não mistura dados de empresas diferentes);
  - **nunca sobrescrever** alteração local ainda não enviada nem conflito aberto
    (a versão que o usuário está vendo em casa vence);
  - tabelas privadas **nunca** são copiadas — `usuarios` (senhas), `cache_dados`,
    `exodo_sync_conflitos`, `sync_status`, `sync_logs`, `bridge_*`, `exodo_config`.

---

## Configuração pelo próprio sistema (jeito fácil)

No app, na tela inicial, botão **Rede LAN** (fica ao lado de "Conferir"):

1. **Procurar PCs** — o sistema varre a rede da loja e mostra os computadores
   que têm o banco do Êxodo (ele entra no banco do outro PC para confirmar, com
   as mesmas credenciais deste). Você só escolhe qual é o outro — não precisa
   saber o IP de ninguém. Se achar o computador mas o PostgreSQL dele ainda não
   estiver liberado, a tela avisa exatamente isso.
2. **Testar** — confirma a conexão e diz quantas tabelas e qual empresa estão
   abertas no outro PC.
3. **Liberar este PC na rede** — o Windows pede a senha de Administrador e o
   sistema ajusta o PostgreSQL (`listen_addresses`, `pg_hba.conf` liberando só
   o IP do outro PC, Firewall) e reinicia o serviço. Faça isso **nos dois**
   computadores (um apontando para o outro).
4. **Salvar e reiniciar** — grava no `.env` (as mesmas chaves da tabela abaixo)
   e reinicia o SincronizadorNuvem para valer na hora.

O IP que o outro PC precisa informar aparece na própria tela ("Este PC é o
192.168.0.11"). Durante o passo 3 o PostgreSQL reinicia: por alguns segundos o
sistema pode mostrar "sem conexão" e volta sozinho.

### Ou pela linha de comando (para o suporte)

O mesmo preparo do passo 3, em cada computador, como Administrador:

```powershell
# No PC-1 (IP 192.168.0.11) aponte para o PC-2:
powershell -ExecutionPolicy Bypass -File scripts\configurar_lan_postgres.ps1 -PeerHost 192.168.0.12

# No PC-2 (IP 192.168.0.12) aponte para o PC-1:
powershell -ExecutionPolicy Bypass -File scripts\configurar_lan_postgres.ps1 -PeerHost 192.168.0.11
```

O script faz o mesmo que o botão do app e ainda grava `PAR_HOST`/`PAR_PORT` no
`.env`. Depois disso, **reinicie o SincronizadorNuvem** nos dois PCs.

### Chaves no `.env`

| Chave | Obrigatória | Padrão | O que é |
|---|---|---|---|
| `PAR_HOST` | sim (para ligar a LAN) | vazio | IP do **outro** PC na rede local |
| `PAR_PORT` | não | `5432` | Porta do PostgreSQL do par |
| `PAR_DB_NAME` | não | `DB_NAME` | Banco no par |
| `PAR_DB_USER` | não | `DB_USER` | Usuário no par |
| `PAR_DB_PASSWORD` | não | `DB_PASSWORD` | Senha no par |
| `PAR_NOME` | não | o próprio `PAR_HOST` | Rótulo do par no log/status |
| `LAN_SYNC` | não | `true` | `false` desliga sem apagar o `PAR_HOST` |
| `LAN_DIAS_TOMBSTONE` | não | `30` | Retenção dos apagados |
| `LAN_INICIAL_COMPLETO` | não | `false` | `true` = no 1º contato puxa o histórico inteiro |
| `LAN_INTERVALO` | não | `2` | Segundos entre as buscas do loop da LAN (mínimo 1) |

Sem `PAR_HOST` nada muda: o sincronizador da nuvem segue igual.

---

## Como conferir

Na tela **Rede LAN** do app, o painel "O que o sincronizador está fazendo"
mostra as últimas linhas `[LAN]`. Ou, nos dois PCs:

```bash
.venv\Scripts\python.exe sincronizador_lan.py
```

Saída esperada: `[LAN] Par PC-2 (192.168.0.12:5432/exodo_db)` e depois
`nada novo (bancos em dia)` ou quantos registros vieram.

No log do sincronizador (`sincronizador.log`) aparecem as linhas `[LAN] ...`.
O status na bandeja mostra `| LAN PC-2` quando a LAN está ativa.

Se aparecer `sem conexão com o par ...`, cheque: IP correto, os dois PCs na
mesma rede, firewall liberado e o PostgreSQL do outro PC ligado.

---

## Como a LAN fica rápida e confiável

A LAN agora tem um **loop próprio**, separado do ciclo da nuvem. Antes ela
rodava só dentro do ciclo da nuvem (a cada ~10s): uma venda no PC-A podia
levar até 10s para aparecer no PC-B, e quem não tinha LAN configurada ficava
100% dependente da nuvem. Agora:

- **Loop dedicado (`lan_loop`)** roda a cada `LAN_INTERVALO` (padrão **2s**),
  independente do ciclo da nuvem. É o caminho principal entre os PCs da loja.
- **Trigger `set_updated_at`** — carimba `updated_at` em toda alteração do
  usuário. A LAN descobre o que mudou pela coluna de data; vários models
  gravavam sem mexer nessa coluna, então a mudança **nunca era vista** pelo
  outro PC (só chegava pela nuvem). O carimbo resolve isso para todas as
  tabelas. Ele **não** carimba quando o sincronizador aplica réplica
  (`exodo.sync_mode='on'`), senão as máquinas puxariam a mesma linha para
  sempre.
- **Leitura determinística** — a busca no par ordena por (data, id), para as
  linhas que compartilham o mesmo carimbo (o app grava em blocos de 100) não
  ficarem em ordem indefinida.

## Acelerador na nuvem (Realtime)

Quando há internet, o **Supabase Realtime** entrega a mudança aos outros PCs em
<100ms — bem antes do ciclo de sincronização. Para isso funcionar de verdade é
preciso rodar uma vez, no Supabase SQL Editor:

```
scripts/migrations/008_realtime_tabelas_criticas.sql
```

Ele publica as tabelas críticas na publicação `supabase_realtime` e define
`REPLICA IDENTITY FULL`. **Sem esse SQL só INSERT chega na hora** — UPDATE e
DELETE ficam no pipeline lento (ciclo de ~10s), que era a causa de “algumas
mudanças demorarem”.

## Detalhes que importam

- **Primeiro contato começa de agora.** O histórico já é alinhado pela nuvem;
  puxar tudo de uma vez seria um download gigante de graça. Use
  `LAN_INICIAL_COMPLETO=true` (nos dois PCs) se quiser forçar o histórico.
- **Apagados (`_exodo_deletados`).** O trigger `log_sync_event` grava todo
  DELETE feito pelo usuário. Isso também corrige um furo antigo da própria
  nuvem: antes o DELETE não tinha detecção de conflito e um registro apagado
  podia "ressuscitar". Apagados mais velhos que `LAN_DIAS_TOMBSTONE` são
  limpos automaticamente.
- **Apagado x alteração local**: se o par apagou e aqui a linha tem alteração
  pendente/conflito, **a local vence** (o apagado é ignorado e registrado no
  log). É a mesma regra do download da nuvem.
- **Um PC desligado** por menos de `LAN_DIAS_TOMBSTONE` dias não perde nada:
  ele puxa tudo o que mudou no outro quando voltar.
- **A LAN não substitui a nuvem.** Se os dois PCs ficarem sem internet e sem
  rede entre si, cada um segue vendendo no seu banco; ao reconectar, a fila
  sobe para o Supabase como sempre.

---

## Arquivos envolvidos

| Arquivo | Papel |
|---|---|
| `sincronizador_lan.py` | O ciclo LAN (puxa do par, aplica aqui) |
| `sincronizador_tray.py` | Loop dedicado da LAN (`lan_loop`, a cada `LAN_INTERVALO`) + ciclo da nuvem |
| `setup_sync_local.py` | Cria `_exodo_deletados`, os triggers de log e o `set_updated_at` |
| `scripts/migrations/008_realtime_tabelas_criticas.sql` | Publica as tabelas no Realtime (UPDATE/DELETE rápidos) |
| `setup_sync_local.py` | Cria `_exodo_deletados` e o trigger que grava os apagados |
| `scripts/init_db.sql` | Mesma tabela/trigger para instalações novas |
| `lib/services/database_service.dart` | Cria `_exodo_deletados` no banco do app |
| `lib/pages/configuracao_lan_page.dart` | Tela **Rede LAN** (toda a configuração pelo app) |
| `lib/services/lan_config_service.dart` | Lê/grava o `.env`, procura o par na rede, testa e prepara o PC |
| `scripts/configurar_lan_postgres.ps1` | Prepara o PostgreSQL para a LAN (o app chama este script) |
| `test/configuracao_lan_test.dart` | Testes da tela e da gravação no `.env` |
| `test_sincronizador_lan.py` | Testes (rodam sem banco e sem rede) |
| `test_lan_integracao.py` | Integração real: sobe dois PostgreSQL temporários e valida INSERT/UPDATE/DELETE propagando |

## Como rodar os testes

```bash
# Rápido, sem banco e sem rede:
.venv\Scripts\python.exe test_sincronizador_lan.py

# Integração de verdade (sobe DOIS clusters PostgreSQL temporários,
# aplica scripts/init_db.sql e confere a propagação pela LAN):
.venv\Scripts\python.exe test_lan_integracao.py
```

O teste de integração acha o PostgreSQL em `C:\SistemaExodo\postgresql\bin`
(ou em `Program Files\PostgreSQL\*`). Se não encontrar, ele **pula** (não falha).
Para apontar outra pasta, use a variável `EXODO_PG_BIN`. Ele cria os clusters em
pasta temporária e os remove no fim — nada do banco de produção é tocado.
