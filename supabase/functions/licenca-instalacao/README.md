# Licença de instalação (30 dias por computador)

Primeira liberação do sistema instalado. O setup ativa o computador na nuvem,
recebe uma licença assinada e vale **30 dias**. Vencida, o app só abre depois
de renovar — e a renovação só é emitida com a **mensalidade da competência
paga** (a própria função confere a empresa vinculada).

Proteções:

- a licença é presa ao `MachineGuid` do Windows; copiar o setup ou a pasta
  `C:\SistemaExodo` para outro PC **não** libera o sistema;
- reinstalar no mesmo computador não gera outros 30 dias: a função devolve a
  licença existente e, se estiver vencida, exige renovação;
- o app valida a assinatura **offline** (chave pública embutida), então a
  licença funciona sem internet até o prazo.

## Publicar

1. Aplique a migração no banco da nuvem:

   ```bash
   supabase db push          # ou rode scripts/migrations/020_licencas_instalacao.sql
   ```

2. Configure a chave privada como segredo (a MESMA da licença emergencial,
   `%USERPROFILE%\Documents\ExodoLicencasPrivadas\chave_privada_exodo.pem`):

   ```bash
   supabase secrets set EXODO_LICENSE_PRIVATE_KEY="$(cat chave_privada_exodo.pem)"
   ```

   Opcional — exige um cabeçalho `x-exodo-setup-key` na ativação (dificulta
   distribuir o setup sem a chave combinada):

   ```bash
   supabase secrets set EXODO_LICENSE_SETUP_KEY="uma-chave-combinada"
   ```

   Se usar essa opção, coloque `EXODO_LICENSE_SETUP_KEY=` no `.env` do cliente.

3. Publique a função:

   ```bash
   supabase functions deploy licenca-instalacao --no-verify-jwt
   ```

## Ações (POST JSON)

| Ação        | Corpo                                          | Resultado |
|-------------|------------------------------------------------|-----------|
| `ativar`    | `machine_id`, `machine_name`, `codigo_ativacao` | `{ documento }` (30 dias) |
| `renovar`   | `machine_id`                                    | `{ documento }` (só com mensalidade paga) |
| `vincular`  | `machine_id`, `empresa_id`                      | liga o computador à empresa |
| `consultar` | `machine_id`                                    | status, vencimento e empresa |

### Código de ativação (por venda)

`ativar` de um computador **sem licença** exige um código de venda, guardado
na tabela `licencas_ativacao` (migração `021`). O código:

- só pode ser usado **uma vez**, em **um** computador (`usada_por`);
- é consumido antes de a licença ser emitida (duas máquinas com o mesmo código
  não passam as duas);
- pode estar preso a uma empresa (`empresa_id`) — a licença já nasce vinculada,
  e a renovação confere a mensalidade dessa empresa;
- pode ser revogado (`revogado`) ou ter prazo (`expira_em`).

Gere os códigos com `tools/licencas/gerar_codigos_ativacao.js`
(`--quantidade`, `--empresa`, `--dias`, `--sql`).

Reinstalar/atualizar no computador já ativado **não** pede código: a função
reconhece a licença existente daquele `machine_id`. Se ela estiver vencida,
responde `402 licenca_expirada` — renovação é só com pagamento.

O `documento` é `{ payload, assinatura }`, no mesmo formato da licença
emergencial (`type: "instalacao"`), verificado por
`lib/services/licenca_instalacao_service.dart`.

## Nuvem auto-hospedada (Supabase local na VM)

Na stack de `/home/charles/supabase` não existe `supabase secrets`: a chave vai
pelo `.env` do compose, em base64 (uma linha só), porque o arquivo `.env` não
lida bem com o PEM multilinha.

1. Aplique as migrações `020` e `021` no banco da VM:

   ```bash
   docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 < 020_licencas_instalacao.sql
   docker exec -i supabase-db psql -U postgres -v ON_ERROR_STOP=1 < 021_codigos_ativacao.sql
   ```

2. Copie a função para o volume servido pelo Edge Runtime:

   ```bash
   mkdir -p volumes/functions/licenca-instalacao
   scp .../supabase/functions/licenca-instalacao/index.ts \
       volumes/functions/licenca-instalacao/index.ts
   ```

3. Gere a chave em base64 e grave no `.env` da stack:

   ```bash
   base64 -w0 chave_privada_exodo.pem
   # .env: EXODO_LICENSE_PRIVATE_KEY_B64=<valor>
   ```

   E passe a variável ao serviço `functions` no `docker-compose.yml`:

   ```yaml
   EXODO_LICENSE_PRIVATE_KEY_B64: ${EXODO_LICENSE_PRIVATE_KEY_B64}
   ```

   A função aceita `EXODO_LICENSE_PRIVATE_KEY` (PEM direto, como no Supabase
   hospedado) e, se ele não existir, decodifica `..._B64`.

4. Recarregue o serviço e confira:

   ```bash
   docker compose up -d --force-recreate functions
   docker logs --tail 20 supabase-edge-functions
   ```

   Um `POST /functions/v1/licenca-instalacao` com `action: "consultar"` deve
   responder `404` (computador não ativado) e não `503` (chave ausente).

## Onde a licença fica no cliente

- Instalação: `C:\SistemaExodo\licenca_instalacao.json` (gravado pelo
  `scripts/ativar_instalacao.ps1` no fim do setup).
- Renovação pelo app: mesma pasta + pasta de suporte do aplicativo.

## Limitação conhecida

A primeira ativação exige um código por venda, mas ainda não existe controle
de **quantidade de computadores por empresa** no Portal Êxodo: quem tiver um
código válido ativa um computador, e o suporte revoga código perdido pelo SQL
(`update licencas_ativacao set revogado = true where codigo = '...'`). Boa
prática: um código por venda, sempre com `--empresa`.
