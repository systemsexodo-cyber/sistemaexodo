// ============================================================================
// licenca-instalacao
// ============================================================================
// Emite a licença de instalação (30 dias), amarrada ao computador, e renova
// depois do pagamento da mensalidade.
//
// A assinatura usa a MESMA chave privada da licença emergencial (pasta
// protegida do dono do sistema). Aqui ela vive como segredo do Supabase:
//
//   supabase secrets set EXODO_LICENSE_PRIVATE_KEY="$(cat chave_privada_exodo.pem)"
//
// O app valida a licença OFFLINE com a chave pública embutida
// (lib/services/licenca_emergencia_service.dart), então a instalação continua
// abrindo sem internet enquanto a licença estiver no prazo.
//
// Ações (POST, JSON):
//   ativar    { machine_id, machine_name }
//   renovar   { machine_id }
//   vincular  { machine_id, empresa_id }
//   consultar { machine_id }
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sign } from "node:crypto";
// No Edge Runtime auto-hospedado o Buffer não é global.
import { Buffer } from "node:buffer";

type JsonObject = Record<string, unknown>;

type Empresa = {
  id: string;
  configuracoes: JsonObject | null;
};

const DIAS_LICENCA = 30;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-exodo-setup-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");

// No Supabase auto-hospedado a chave vem do docker-compose/.env, onde quebra de
// linha dá problema: aceita o PEM em base64 (uma linha só) como alternativa.
function lerChavePrivada(): string {
  const direta = (Deno.env.get("EXODO_LICENSE_PRIVATE_KEY") ?? "").trim();
  if (direta) return direta;
  const base64 = (Deno.env.get("EXODO_LICENSE_PRIVATE_KEY_B64") ?? "").trim();
  if (!base64) return "";
  try {
    return new TextDecoder().decode(
      Uint8Array.from(atob(base64), (caractere) => caractere.charCodeAt(0)),
    );
  } catch {
    console.error("[licenca-instalacao] EXODO_LICENSE_PRIVATE_KEY_B64 inválida.");
    return "";
  }
}

const chavePrivada = lerChavePrivada();
// Opcional: se configurado, a ativação só aceita setup com a chave combinada.
// Serve para parar distribuição do setup sem precisar republicar o app.
const chaveSetup = Deno.env.get("EXODO_LICENSE_SETUP_KEY") ?? "";

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

function agoraSp(): { ano: number; mes: number; dia: number } {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const data = Object.fromEntries(
    partes.map((parte) => [parte.type, parte.value]),
  );
  return {
    ano: Number(data.year),
    mes: Number(data.month),
    dia: Number(data.day),
  };
}

function competenciaNecessaria(configuracoes: JsonObject): string | null {
  const bruto = String(
    configuracoes.data_cobranca ?? configuracoes.dataCobranca ?? "",
  ).trim();
  if (!bruto) return null;

  let diaVencimento = Number.parseInt(bruto, 10);
  const data = new Date(bruto);
  if (!Number.isFinite(diaVencimento) && !Number.isNaN(data.getTime())) {
    diaVencimento = data.getUTCDate();
  }
  if (!Number.isFinite(diaVencimento) || diaVencimento <= 0) return null;
  if (diaVencimento > 28) diaVencimento = 28;

  const hoje = agoraSp();
  let ano = hoje.ano;
  let mes = hoje.mes;
  if (hoje.dia < diaVencimento) {
    mes -= 1;
    if (mes === 0) {
      mes = 12;
      ano -= 1;
    }
  }
  return `${ano}-${String(mes).padStart(2, "0")}`;
}

/// Mesma regra da tela de bloqueio (lib/models/empresa.dart): a renovação só
/// acontece quando a mensalidade da competência corrente está quitada.
function mensalidadeEmDia(configuracoes: JsonObject | null): {
  ok: boolean;
  motivo: string;
} {
  const configs = configuracoes ?? {};
  if (configs.bloqueado === true || configs.bloqueado === "true") {
    return { ok: false, motivo: "A empresa está bloqueada no portal." };
  }
  if (configs.status_pagamento === "inadimplente") {
    return { ok: false, motivo: "A empresa está marcada como inadimplente." };
  }

  const ultimoMesPago = String(configs.ultimo_mes_pago ?? "").trim();
  const competencia = competenciaNecessaria(configs);
  if (competencia) {
    if (!ultimoMesPago || ultimoMesPago < competencia) {
      return {
        ok: false,
        motivo: `Mensalidade de ${competencia} não confirmada.`,
      };
    }
    return { ok: true, motivo: "" };
  }

  if (configs.status_pagamento === "pago" && ultimoMesPago) {
    return { ok: true, motivo: "" };
  }
  return {
    ok: false,
    motivo: "Mensalidade não confirmada no portal.",
  };
}

function assinar(payload: JsonObject): string {
  // A ordem das chaves e o JSON compacto fazem parte do documento assinado.
  // O app remonta o MESMO objeto antes de verificar a assinatura.
  return sign(
    "RSA-SHA256",
    Buffer.from(JSON.stringify(payload), "utf8"),
    chavePrivada,
  ).toString("base64");
}

type LicencaRow = {
  machine_id: string;
  machine_name: string | null;
  empresa_id: string | null;
  license_id: string;
  emitida_em: string;
  expira_em: string;
  renovacoes: number | null;
  bloqueada: boolean | null;
};

async function buscarLicenca(machineId: string): Promise<LicencaRow | null> {
  const { data, error } = await supabase
    .from("licencas_instalacao")
    .select(
      "machine_id, machine_name, empresa_id, license_id, emitida_em, expira_em, renovacoes, bloqueada",
    )
    .eq("machine_id", machineId)
    .maybeSingle();
  if (error) throw new Error("Não foi possível consultar a licença.");
  return data as LicencaRow | null;
}

function documento(row: LicencaRow, machineName: string): JsonObject {
  const payload: JsonObject = {
    version: 1,
    type: "instalacao",
    company_id: "",
    machine_id: row.machine_id,
    machine_name: machineName || row.machine_name || "",
    issued_at: row.emitida_em,
    expires_at: row.expira_em,
    license_id: row.license_id,
  };
  return { payload, assinatura: assinar(payload) };
}

function isoEmDias(dias: number): string {
  return new Date(Date.now() + dias * 86_400_000).toISOString();
}

// O código é guardado sem hífens e em maiúsculas; o cliente pode digitar de
// qualquer jeito (ex.: "exo-7f2k-9m4q-8pxr" ou "7f2k 9m4q 8pxr"). O prefixo
// EXO é só de exibição e precisa sair: o alfabeto gerado não tem a letra O,
// então nenhum código real começa com "EXO".
function normalizarCodigo(valor: unknown): string {
  const limpo = String(valor ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return limpo.startsWith("EXO") ? limpo.slice(3) : limpo;
}

type CodigoAtivacao = {
  codigo: string;
  empresa_id: string | null;
  revogado: boolean | null;
  expira_em: string | null;
  usada_por: string | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ erro: "Método não permitido." }, 405);
  }
  if (!chavePrivada) {
    console.error("[licenca-instalacao] EXODO_LICENSE_PRIVATE_KEY ausente.");
    return jsonResponse(
      { erro: "Licenciamento indisponível: chave de assinatura não configurada." },
      503,
    );
  }
  if (chaveSetup && req.headers.get("x-exodo-setup-key") !== chaveSetup) {
    return jsonResponse({ erro: "Setup não autorizado." }, 403);
  }

  let corpo: JsonObject;
  try {
    corpo = await req.json();
  } catch {
    return jsonResponse({ erro: "Corpo inválido." }, 400);
  }

  const acao = String(corpo.action ?? "").trim().toLowerCase();
  const machineId = String(corpo.machine_id ?? "").trim().toLowerCase();
  const machineName = String(corpo.machine_name ?? "").trim().slice(0, 100);
  const empresaId = String(corpo.empresa_id ?? "").trim();
  const codigoAtivacao = normalizarCodigo(corpo.codigo_ativacao);

  if (!/^[a-f0-9]{64}$/.test(machineId)) {
    return jsonResponse({ erro: "ID do computador inválido." }, 400);
  }

  try {
    const existente = await buscarLicenca(machineId);

    if (acao === "consultar") {
      if (!existente) {
        return jsonResponse({ erro: "Este computador ainda não foi ativado." }, 404);
      }
      return jsonResponse({
        status: new Date(existente.expira_em) > new Date() ? "valida" : "expirada",
        expira_em: existente.expira_em,
        empresa_id: existente.empresa_id,
        renovacoes: existente.renovacoes ?? 0,
        bloqueada: existente.bloqueada ?? false,
      });
    }

    if (acao === "vincular") {
      if (!existente) {
        return jsonResponse({ erro: "Ative o computador primeiro." }, 404);
      }
      // O código de venda já pode ter prendido o computador à empresa certa.
      // Nesse caso o login em outra empresa NÃO troca o vínculo: só preenche
      // quando a licença ainda está sem empresa.
      if (empresaId && !existente.empresa_id) {
        const { error } = await supabase
          .from("licencas_instalacao")
          .update({ empresa_id: empresaId, atualizada_em: new Date().toISOString() })
          .eq("machine_id", machineId);
        if (error) throw new Error("Não foi possível vincular a empresa.");
      }
      return jsonResponse({ ok: true, empresa_id: empresaId });
    }

    if (acao === "ativar") {
      if (existente?.bloqueada) {
        return jsonResponse({ erro: "Licença bloqueada pelo suporte." }, 403);
      }
      if (existente) {
        const expirada = new Date(existente.expira_em).getTime() <= Date.now();
        if (expirada) {
          // Reinstalar no MESMO computador não renova: precisa do pagamento.
          return jsonResponse(
            {
              erro: "A licença deste computador está vencida. Renove a mensalidade para liberar.",
              codigo: "licenca_expirada",
              expira_em: existente.expira_em,
              machine_id: machineId,
            },
            402,
          );
        }
        return jsonResponse({ ok: true, renovada: false, documento: documento(existente, machineName) });
      }

      // ---- CÓDIGO DE ATIVAÇÃO (por venda, uso único) ----
      if (codigoAtivacao.length < 8) {
        return jsonResponse(
          {
            erro: "Informe o código de ativação que acompanha a compra.",
            codigo: "codigo_obrigatorio",
          },
          400,
        );
      }

      const { data: codigoBruto, error: erroCodigo } = await supabase
        .from("licencas_ativacao")
        .select("codigo, empresa_id, revogado, expira_em, usada_por")
        .eq("codigo", codigoAtivacao)
        .maybeSingle();
      if (erroCodigo) throw new Error("Não foi possível conferir o código.");
      const codigoRow = codigoBruto as CodigoAtivacao | null;

      if (!codigoRow) {
        return jsonResponse(
          {
            erro: "Código de ativação inválido. Confira com o suporte.",
            codigo: "codigo_invalido",
          },
          403,
        );
      }
      if (codigoRow.revogado) {
        return jsonResponse(
          { erro: "Este código de ativação foi revogado.", codigo: "codigo_revogado" },
          403,
        );
      }
      if (codigoRow.expira_em && new Date(codigoRow.expira_em).getTime() <= Date.now()) {
        return jsonResponse(
          { erro: "Este código de ativação venceu.", codigo: "codigo_vencido" },
          403,
        );
      }
      if (codigoRow.usada_por && codigoRow.usada_por !== machineId) {
        return jsonResponse(
          {
            erro: "Este código já foi usado em outro computador.",
            codigo: "codigo_ja_usado",
          },
          403,
        );
      }

      const emitida = new Date().toISOString();
      const expira = isoEmDias(DIAS_LICENCA);
      const licenseId = crypto.randomUUID();
      const empresaDaVenda = codigoRow.empresa_id || empresaId || null;

      // Consome o código ANTES de emitir a licença, de forma atômica: duas
      // máquinas com o mesmo código não passam as duas.
      if (!codigoRow.usada_por) {
        const { data: consumido, error: erroConsumo } = await supabase
          .from("licencas_ativacao")
          .update({ usada_por: machineId, usada_em: emitida })
          .eq("codigo", codigoAtivacao)
          .is("usada_por", null)
          .select("codigo");
        if (erroConsumo) throw new Error("Não foi possível consumir o código.");
        if (!consumido || consumido.length === 0) {
          return jsonResponse(
            {
              erro: "Este código já foi usado em outro computador.",
              codigo: "codigo_ja_usado",
            },
            403,
          );
        }
      }

      const { error } = await supabase.from("licencas_instalacao").insert({
        machine_id: machineId,
        machine_name: machineName,
        empresa_id: empresaDaVenda,
        license_id: licenseId,
        emitida_em: emitida,
        expira_em: expira,
      });
      if (error) throw new Error("Não foi possível registrar a licença.");

      await supabase.from("licencas_instalacao_historico").insert({
        machine_id: machineId,
        empresa_id: empresaDaVenda,
        acao: "ativacao",
        license_id: licenseId,
        emitida_em: emitida,
        expira_em: expira,
      });

      const row: LicencaRow = {
        machine_id: machineId,
        machine_name: machineName,
        empresa_id: empresaDaVenda,
        license_id: licenseId,
        emitida_em: emitida,
        expira_em: expira,
        renovacoes: 0,
        bloqueada: false,
      };
      return jsonResponse({ ok: true, renovada: false, documento: documento(row, machineName) });
    }

    if (acao === "renovar") {
      if (!existente) {
        return jsonResponse(
          { erro: "Computador sem licença. Ative a instalação primeiro.", codigo: "sem_licenca" },
          404,
        );
      }
      if (existente.bloqueada) {
        return jsonResponse({ erro: "Licença bloqueada pelo suporte." }, 403);
      }
      if (!existente.empresa_id) {
        return jsonResponse(
          {
            erro: "Entre no sistema uma vez para vincular este computador à empresa.",
            codigo: "empresa_nao_vinculada",
          },
          409,
        );
      }

      const { data: empresaBruta, error } = await supabase
        .from("empresas")
        .select("id, configuracoes")
        .eq("id", existente.empresa_id)
        .maybeSingle();
      if (error) throw new Error("Não foi possível consultar a empresa.");
      const empresa = empresaBruta as Empresa | null;
      if (!empresa) {
        return jsonResponse({ erro: "Empresa não encontrada na nuvem." }, 404);
      }

      const pagamento = mensalidadeEmDia(empresa.configuracoes);
      if (!pagamento.ok) {
        return jsonResponse(
          {
            erro: pagamento.motivo,
            codigo: "pagamento_pendente",
            empresa_id: empresa.id,
          },
          402,
        );
      }

      const emitida = new Date().toISOString();
      const expira = isoEmDias(DIAS_LICENCA);
      const licenseId = crypto.randomUUID();
      const renovacoes = (existente.renovacoes ?? 0) + 1;

      const { error: erroUpdate } = await supabase
        .from("licencas_instalacao")
        .update({
          license_id: licenseId,
          emitida_em: emitida,
          expira_em: expira,
          renovacoes,
          machine_name: machineName || existente.machine_name || "",
          atualizada_em: emitida,
        })
        .eq("machine_id", machineId);
      if (erroUpdate) throw new Error("Não foi possível renovar a licença.");

      await supabase.from("licencas_instalacao_historico").insert({
        machine_id: machineId,
        empresa_id: existente.empresa_id,
        acao: "renovacao",
        license_id: licenseId,
        emitida_em: emitida,
        expira_em: expira,
      });

      return jsonResponse({
        ok: true,
        renovada: true,
        documento: documento(
          {
            ...existente,
            license_id: licenseId,
            emitida_em: emitida,
            expira_em: expira,
            renovacoes,
            machine_name: machineName || existente.machine_name,
          },
          machineName,
        ),
      });
    }

    return jsonResponse({ erro: "Ação desconhecida." }, 400);
  } catch (erro) {
    console.error("[licenca-instalacao]", erro);
    return jsonResponse(
      {
        erro: erro instanceof Error
          ? erro.message
          : "Falha ao processar a licença.",
      },
      500,
    );
  }
});
