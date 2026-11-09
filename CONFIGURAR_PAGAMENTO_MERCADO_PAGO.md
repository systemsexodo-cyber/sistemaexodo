# Ativar pagamento de mensalidade com Mercado Pago

Este guia descreve a ativação da cobrança Pix no Supabase local publicado pelo
Tailscale Funnel. A Edge Function e a migration estão no projeto; a migration
`010_liberar_mensalidade_mercado_pago.sql` já foi aplicada ao banco local.
As credenciais do Mercado Pago ainda precisam ser configuradas no servidor, e
a função ainda precisa ser copiada para a VM.

## 1. Configure os segredos na VM

Conecte-se à VM por SSH e edite `/home/charles/supabase/.env`. Acrescente as
variáveis abaixo sem aspas e sem espaços antes ou depois do `=`:

```dotenv
MERCADO_PAGO_ACCESS_TOKEN=COLE_O_TOKEN_DA_CONTA
MERCADO_PAGO_WEBHOOK_SECRET=COLE_O_SEGREDO_DO_WEBHOOK
```

Use o token da conta Mercado Pago que deve receber os pagamentos. Obtenha o
segredo do webhook no painel do Mercado Pago. **Não coloque esses valores no
Git, no app Flutter, neste arquivo ou em mensagens.**

O Compose da VM já injeta `SUPABASE_URL`, `SUPABASE_PUBLIC_URL` e
`SUPABASE_SERVICE_ROLE_KEY` no Edge Runtime. Confirme que `SUPABASE_PUBLIC_URL`
é `https://servidorsupabase.tail9b4943.ts.net`.

## 2. Passe as novas variáveis ao Edge Runtime

No serviço `functions` do arquivo
`/home/charles/supabase/docker-compose.yml`, dentro de `environment:`, inclua:

```yaml
      MERCADO_PAGO_ACCESS_TOKEN: ${MERCADO_PAGO_ACCESS_TOKEN}
      MERCADO_PAGO_WEBHOOK_SECRET: ${MERCADO_PAGO_WEBHOOK_SECRET}
```

Salve o arquivo sem alterar as outras variáveis do serviço.

## 3. Copie a função e reinicie o serviço

No PowerShell, na raiz deste repositório, copie a pasta da função para o volume
que já está montado no Edge Runtime:

```powershell
$key = "$env:USERPROFILE\.ssh\id_ed25519_vm"
ssh -i $key -p 2222 charles@127.0.0.1 "mkdir -p /home/charles/supabase/volumes/functions/mercado-pago-mensalidade"
scp -i $key -P 2222 -r .\supabase\functions\mercado-pago-mensalidade\* `
  charles@127.0.0.1:/home/charles/supabase/volumes/functions/mercado-pago-mensalidade/
```

Recrie somente o serviço Edge Functions para carregar os segredos e a função:

```powershell
ssh -i $key -p 2222 charles@127.0.0.1 `
  "cd /home/charles/supabase && docker compose up -d --force-recreate functions"
```

Confira os logs do serviço, sem imprimir ou compartilhar o conteúdo do arquivo
`.env`:

```powershell
ssh -i $key -p 2222 charles@127.0.0.1 `
  "docker logs --tail 100 supabase-edge-functions"
```

## 4. Cadastre o webhook no Mercado Pago

Configure notificações de pagamentos para:

```text
https://servidorsupabase.tail9b4943.ts.net/functions/v1/mercado-pago-mensalidade/webhook
```

Use o mesmo segredo de assinatura colocado em
`MERCADO_PAGO_WEBHOOK_SECRET` na VM.

## 5. Confira o app e faça um teste

O app usa por padrão:

```text
https://servidorsupabase.tail9b4943.ts.net/functions/v1/mercado-pago-mensalidade
```

Se o endereço público mudar, configure `SUPABASE_FUNCTIONS_URL` no ambiente
empacotado do app com a URL base acima, incluindo o caminho
`/functions/v1/mercado-pago-mensalidade`, e gere uma nova versão do app.

Faça um pagamento de teste e confirme que:

1. A função retorna o QR Pix e o código copia e cola.
2. Após o pagamento aprovado, o webhook registra a aprovação na configuração da
   empresa e a licença é liberada.
3. O app também detecta a aprovação consultando o status do pagamento.

## Observação de acesso

No Supabase local, `FUNCTIONS_VERIFY_JWT` está atualmente como `false` para o
Edge Runtime. Assim, os endpoints de criação e consulta de pagamento aceitam
chamadas públicas; somente o webhook valida a assinatura HMAC do Mercado Pago.
Antes de disponibilizar o domínio publicamente em produção, restrinja os
endpoints de criação e consulta a clientes autorizados e adicione proteção
contra abuso.
