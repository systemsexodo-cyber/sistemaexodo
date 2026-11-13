# Mercado Pago mensalidade (Supabase local)

Esta função precisa estar disponível no Edge Runtime do Supabase local e ser
roteada pelo Kong em `/functions/v1/mercado-pago-mensalidade`. O proxy público
do Tailscale precisa encaminhar esse caminho ao Kong. A autenticação JWT da
função fica desativada para aceitar o webhook do Mercado Pago; a assinatura
HMAC do webhook é validada pela própria função.

Configure no ambiente do Edge Runtime:

- `SUPABASE_URL`: URL interna do Kong/Supabase.
- `SUPABASE_PUBLIC_URL`: domínio HTTPS público do Funnel, sem caminho de API.
- `SUPABASE_SERVICE_ROLE_KEY` (ou `SERVICE_ROLE_KEY`): chave de serviço do
  Supabase; mantenha somente no servidor.
- `MERCADO_PAGO_ACCESS_TOKEN`: token da conta Mercado Pago que receberá os Pix.
- `MERCADO_PAGO_WEBHOOK_SECRET`: segredo de assinatura configurado no Mercado
  Pago.

Antes de habilitar a função, aplique
`supabase/migrations/010_liberar_mensalidade_mercado_pago.sql` no banco local.
O app chama `https://exodosystems.tail9b4943.ts.net/functions/v1/mercado-pago-mensalidade`;
se o domínio público mudar, configure `SUPABASE_FUNCTIONS_URL` no ambiente
empacotado do app. Cadastre no Mercado Pago o webhook de pagamentos em
`https://exodosystems.tail9b4943.ts.net/functions/v1/mercado-pago-mensalidade/webhook`.
