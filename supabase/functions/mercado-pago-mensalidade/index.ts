import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;

type Empresa = {
  id: string;
  razao_social: string | null;
  configuracoes: JsonObject | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-signature, x-request-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
const mercadoPagoAccessToken =
  Deno.env.get("MERCADO_PAGO_ACCESS_TOKEN") ?? "";
const mercadoPagoWebhookSecret =
  Deno.env.get("MERCADO_PAGO_WEBHOOK_SECRET") ?? "";
const supabasePublicUrl = Deno.env.get("SUPABASE_PUBLIC_URL") ??
  "https://servidorsupabase.tail9b4943.ts.net";

if (!supabaseUrl || !supabaseServiceRoleKey) {
  throw new Error("Faltam as credenciais do Supabase no Edge Runtime.");
}

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function jsonResponse(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function mesCompetencia(configuracoes: JsonObject): string {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const data = Object.fromEntries(
    partes.map((parte) => [parte.type, parte.value]),
  );
  const hoje = new Date(
    Number(data.year),
    Number(data.month) - 1,
    Number(data.day),
  );
  const cobranca = configuracoes.data_cobranca ??
    configuracoes.dataCobranca;
  let diaVencimento: number;
  if (cobranca != null && String(cobranca).trim()) {
    const texto = String(cobranca).trim();
    const dataCompleta = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto);
    diaVencimento = dataCompleta
      ? Number(dataCompleta[3])
      : Number.parseInt(texto, 10);
  } else {
    diaVencimento = Number.NaN;
  }
  if (
    !Number.isInteger(diaVencimento) || diaVencimento < 1 ||
    diaVencimento > 31
  ) {
    return `${data.year}-${data.month}`;
  }
  const competencia = hoje.getDate() < diaVencimento
    ? new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1)
    : hoje;
  return `${competencia.getFullYear()}-${
    String(competencia.getMonth() + 1).padStart(2, "0")
  }`;
}

function valorMensalidade(configuracoes: JsonObject): number | null {
  const valor = Number(
    String(
      configuracoes.valor_mensalidade ??
        configuracoes.valorMensalidade ??
        "",
    ).replace(",", "."),
  );
  return Number.isFinite(valor) && valor > 0
    ? Math.round(valor * 100) / 100
    : null;
}

async function buscarEmpresa(empresaId: string): Promise<Empresa | null> {
  const { data, error } = await supabase
    .from("empresas")
    .select("id, razao_social, configuracoes")
    .eq("id", empresaId)
    .maybeSingle();
  if (error) throw new Error("Não foi possível consultar a empresa.");
  return data as Empresa | null;
}

async function buscarPagamento(paymentId: string): Promise<JsonObject> {
  if (!mercadoPagoAccessToken) {
    throw new Error("A integração Mercado Pago ainda não foi configurada.");
  }
  const resposta = await fetch(
    `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
    {
      headers: { Authorization: `Bearer ${mercadoPagoAccessToken}` },
      signal: AbortSignal.timeout(20_000),
    },
  );
  if (!resposta.ok) {
    throw new Error("Não foi possível consultar o pagamento no Mercado Pago.");
  }
  return await resposta.json() as JsonObject;
}

async function liberarMensalidadeAprovada(
  pagamento: JsonObject,
): Promise<{ aprovado: boolean; liberado: boolean }> {
  if (
    pagamento.status !== "approved" || pagamento.payment_method_id !== "pix"
  ) {
    return { aprovado: false, liberado: false };
  }
  const match = /^exodo:(.+):(\d{4}-\d{2})$/.exec(
    String(pagamento.external_reference ?? ""),
  );
  const valorPago = Number(pagamento.transaction_amount);
  if (!match || !Number.isFinite(valorPago)) {
    throw new Error("Referência de pagamento inválida.");
  }
  const [, empresaId, mes] = match;
  const empresa = await buscarEmpresa(empresaId);
  if (!empresa) throw new Error("Empresa da cobrança não encontrada.");
  const configuracoes = empresa.configuracoes ?? {};
  const valorEsperado = valorMensalidade(configuracoes);
  if (
    valorEsperado == null || Math.abs(valorEsperado - valorPago) > 0.01
  ) {
    throw new Error("Valor do pagamento não confere com a mensalidade.");
  }
  if (String(configuracoes.ultimo_mes_pago ?? "") >= mes) {
    return { aprovado: true, liberado: true };
  }

  const { data: atualizado, error } = await supabase.rpc(
    "registrar_pagamento_mensalidade",
    {
      p_empresa_id: empresaId,
      p_dados: {
        status_pagamento: "pago",
        bloqueado: false,
        ultimo_mes_pago: mes,
        mercado_pago_payment_id: String(pagamento.id),
        mercado_pago_pago_em: pagamento.date_approved ??
          new Date().toISOString(),
      },
    },
  );
  if (error || atualizado !== true) {
    throw new Error("Não foi possível registrar a liberação da empresa.");
  }
  return { aprovado: true, liberado: true };
}

async function criarPix(body: JsonObject): Promise<Response> {
  if (!mercadoPagoAccessToken) {
    return jsonResponse({
      erro: "A integração Mercado Pago ainda não foi configurada.",
    }, 503);
  }
  const empresaId = String(body.empresa_id ?? "").trim();
  const email = String(body.email ?? "").trim();
  if (
    !empresaId || empresaId.length > 128 || email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    return jsonResponse({ erro: "Empresa ou e-mail inválido." }, 400);
  }
  const empresa = await buscarEmpresa(empresaId);
  if (!empresa) {
    return jsonResponse({ erro: "Empresa não encontrada." }, 404);
  }
  const configuracoes = empresa.configuracoes ?? {};
  const valor = valorMensalidade(configuracoes);
  if (valor == null) {
    return jsonResponse({
      erro: "A mensalidade ainda não foi configurada. Fale com o suporte.",
    }, 400);
  }
  const mes = mesCompetencia(configuracoes);
  if (
    String(configuracoes.ultimo_mes_pago ?? "") >= mes &&
    configuracoes.bloqueado !== true
  ) {
    return jsonResponse({
      erro: "A mensalidade deste mês já consta como paga.",
    }, 409);
  }

  const referencia = `exodo:${empresaId}:${mes}`;
  const webhookUrl = new URL(
    "/functions/v1/mercado-pago-mensalidade/webhook",
    supabasePublicUrl,
  );
  const resposta = await fetch("https://api.mercadopago.com/v1/payments", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${mercadoPagoAccessToken}`,
      "Content-Type": "application/json",
      "X-Idempotency-Key": await sha256(referencia),
    },
    body: JSON.stringify({
      transaction_amount: valor,
      description: `Mensalidade Sistema Êxodo ${mes}`,
      payment_method_id: "pix",
      external_reference: referencia,
      notification_url: webhookUrl.toString(),
      payer: { email },
    }),
    signal: AbortSignal.timeout(20_000),
  });
  const pagamento = await resposta.json() as JsonObject;
  if (!resposta.ok) {
    console.error("Mercado Pago recusou a criação da cobrança:", resposta.status);
    return jsonResponse({
      erro: "O Mercado Pago não conseguiu gerar o Pix. Tente novamente.",
    }, 502);
  }
  const interacao = pagamento.point_of_interaction as JsonObject | undefined;
  const dadosPix = interacao?.transaction_data as JsonObject | undefined;
  if (!pagamento.id || !dadosPix?.qr_code) {
    console.error("Resposta Pix sem os dados esperados.");
    return jsonResponse({
      erro: "O Mercado Pago não retornou os dados do Pix.",
    }, 502);
  }
  return jsonResponse({
    pagamento_id: String(pagamento.id),
    qr_code: dadosPix.qr_code,
    qr_code_base64: dadosPix.qr_code_base64 ?? null,
    ticket_url: dadosPix.ticket_url ?? null,
    mes_referencia: mes,
    valor,
  });
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function emTempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferenca = 0;
  for (let i = 0; i < a.length; i++) {
    diferenca |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diferenca === 0;
}

async function assinaturaWebhookValida(
  req: Request,
  body: JsonObject,
): Promise<boolean> {
  const assinatura = req.headers.get("x-signature") ?? "";
  const requestId = req.headers.get("x-request-id") ?? "";
  const url = new URL(req.url);
  const id = String(
    url.searchParams.get("data.id") ??
      (body.data as JsonObject | undefined)?.id ??
      "",
  ).toLowerCase();
  const campos = Object.fromEntries(
    assinatura.split(",").map((campo) => {
      const [chave, ...valor] = campo.trim().split("=");
      return [chave, valor.join("=")];
    }),
  );
  if (!campos.ts || !campos.v1 || !requestId || !id) return false;

  const manifest = `id:${id};request-id:${requestId};ts:${campos.ts};`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(mercadoPagoWebhookSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(manifest),
  );
  const expected = Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return emTempoConstante(expected, campos.v1.toLowerCase());
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ erro: "Método não permitido." }, 405);
  }

  const caminho = new URL(req.url).pathname.split("/").filter(Boolean);
  const acao = caminho[caminho.length - 1];
  let body: JsonObject;
  try {
    body = await req.json() as JsonObject;
  } catch {
    return jsonResponse({ erro: "Corpo da requisição inválido." }, 400);
  }

  try {
    if (acao === "create-pix") {
      return await criarPix(body);
    }
    if (acao === "payment-status") {
      if (!mercadoPagoAccessToken) {
        return jsonResponse({
          erro: "A integração Mercado Pago ainda não foi configurada.",
        }, 503);
      }
      const paymentId = String(body.pagamento_id ?? "").trim();
      const empresaId = String(body.empresa_id ?? "").trim();
      if (!/^\d+$/.test(paymentId) || !empresaId) {
        return jsonResponse({
          erro: "Identificação do pagamento inválida.",
        }, 400);
      }
      const pagamento = await buscarPagamento(paymentId);
      if (
        !String(pagamento.external_reference ?? "")
          .startsWith(`exodo:${empresaId}:`)
      ) {
        return jsonResponse({
          erro: "Pagamento não pertence a esta empresa.",
        }, 404);
      }
      const resultado = await liberarMensalidadeAprovada(pagamento);
      return jsonResponse({
        status: pagamento.status,
        pago_em: pagamento.date_approved ?? null,
        ...resultado,
      });
    }
    if (acao === "webhook") {
      if (!mercadoPagoAccessToken || !mercadoPagoWebhookSecret) {
        return jsonResponse({
          erro: "A integração Mercado Pago ainda não foi configurada.",
        }, 503);
      }
      if (!await assinaturaWebhookValida(req, body)) {
        return jsonResponse({ erro: "Assinatura do webhook inválida." }, 401);
      }
      const url = new URL(req.url);
      const paymentId = String(
        url.searchParams.get("data.id") ??
          (body.data as JsonObject | undefined)?.id ??
          "",
      );
      const pagamento = await buscarPagamento(paymentId);
      const resultado = await liberarMensalidadeAprovada(pagamento);
      return jsonResponse({ recebido: true, ...resultado });
    }
    return jsonResponse({ erro: "Endpoint não encontrado." }, 404);
  } catch (error) {
    console.error("Falha na função de mensalidade:", error);
    return jsonResponse({
      erro: error instanceof Error
        ? error.message
        : "Não foi possível processar a solicitação.",
    }, 500);
  }
});
