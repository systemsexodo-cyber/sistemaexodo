const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const multer = require('multer');
const forge = require('node-forge');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const os = require('os');
const crypto = require('crypto');
const { Pool } = require('pg');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');

admin.initializeApp();

const app = express();

// Ativar CORS
app.use(cors({ origin: true }));

// Configurar multer para usar o diretório /tmp (o único gravável no Firebase Functions)
const upload = multer({ dest: os.tmpdir() });

// Middleware para logar todas as requisições (ajuda no diagnóstico)
app.use((req, res, next) => {
    console.log(`>>> [Functions] ${req.method} ${req.url}`);
    next();
});

/**
 * Endpoint para processar certificado PFX
 * Retorna chave privada e certificado em formato PEM
 * Suporta tanto o caminho direto quanto o prefixo /api
 */
const processarHandler = async (req, res) => {
    try {
        console.log('>>> [Functions] Iniciando processamento de certificado');

        if (!req.file) {
            console.log('>>> [Functions] ❌ Arquivo não encontrado na requisição');
            return res.status(400).json({
                erro: 'Certificado não fornecido. Certifique-se de enviar o arquivo no campo "certificado".',
                sucesso: false
            });
        }

        const senha = req.body.senha || '';
        const caminhoArquivo = req.file.path;

        console.log(`>>> [Functions] Arquivo temporário: ${caminhoArquivo} (${req.file.size} bytes)`);

        // Ler arquivo PFX
        const pfxBytes = fs.readFileSync(caminhoArquivo);

        // Converter para base64 para processar com node-forge
        const pfxBase64 = pfxBytes.toString('base64');

        // Processar PFX
        let p12;
        try {
            p12 = forge.pkcs12.decodeBase64(pfxBase64, false, senha);
        } catch (e) {
            console.error('>>> [Functions] ❌ Erro ao decodificar P12:', e.message);
            if (fs.existsSync(caminhoArquivo)) fs.unlinkSync(caminhoArquivo);

            return res.status(400).json({
                erro: 'Erro ao processar certificado PFX. Verifique se a senha está correta.',
                detalhes: e.message,
                sucesso: false
            });
        }

        // Extrair chave privada e certificado
        let chavePrivada = null;
        let certificadoX509 = null;
        let cnpj = null;
        let validade = null;

        for (let i = 0; i < p12.safeContents.length; i++) {
            const safeContents = p12.safeContents[i];
            for (let j = 0; j < safeContents.safeBags.length; j++) {
                const bag = safeContents.safeBags[j];

                if (bag.type === forge.pki.oids.keyBag || bag.type === forge.pki.oids.pkcs8ShroudedKeyBag) {
                    if (bag.key) chavePrivada = bag.key;
                }

                if (bag.type === forge.pki.oids.certBag) {
                    if (bag.cert) {
                        certificadoX509 = bag.cert;
                        const subject = certificadoX509.subject;
                        const cnpjMatch = subject.getField('CN')?.value?.match(/\d{14}/);
                        if (cnpjMatch) cnpj = cnpjMatch[0];
                        validade = certificadoX509.validity.notAfter;
                    }
                }
            }
        }

        if (!chavePrivada || !certificadoX509) {
            console.error('>>> [Functions] ❌ Componentes essenciais não encontrados no PFX');
            if (fs.existsSync(caminhoArquivo)) fs.unlinkSync(caminhoArquivo);
            return res.status(400).json({
                erro: 'Chave privada ou certificado não encontrado no arquivo PFX fornecido.',
                sucesso: false
            });
        }

        const chavePrivadaPEM = forge.pki.privateKeyToPem(chavePrivada);
        const certificadoPEM = forge.pki.certificateToPem(certificadoX509);

        // Componentes RSA
        const n = chavePrivada.n.toString(16);
        const d = chavePrivada.d.toString(16);

        if (fs.existsSync(caminhoArquivo)) fs.unlinkSync(caminhoArquivo);

        console.log(`>>> [Functions] ✅ Sucesso! CNPJ: ${cnpj || 'N/A'}`);

        res.json({
            sucesso: true,
            chavePrivada: {
                pem: chavePrivadaPEM,
                n: n,
                d: d,
            },
            certificado: {
                pem: certificadoPEM,
                bytes: Buffer.from(certificadoPEM).toString('base64'),
            },
            informacoes: {
                cnpj: cnpj,
                validade: validade ? validade.toISOString() : null,
            }
        });

    } catch (e) {
        console.error('>>> [Functions] ❌ ERRO INTERNO:', e);
        if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        res.status(500).json({
            erro: 'Erro interno ao processar certificado',
            detalhes: e.message,
            sucesso: false
        });
    }
};

// Registrar as rotas
app.post('/processar-certificado', upload.single('certificado'), processarHandler);
app.post('/api/processar-certificado', upload.single('certificado'), processarHandler); // Suporte a prefixo se houver

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        service: 'Conversor Certificado',
        env: process.env.NODE_ENV
    });
});

// Exportar a cloud function
exports.api = functions.region('us-central1').https.onRequest(app);

const mercadoPagoAccessToken = defineSecret('MERCADO_PAGO_ACCESS_TOKEN');
const mercadoPagoWebhookSecret = defineSecret('MERCADO_PAGO_WEBHOOK_SECRET');
const neonDatabaseUrl = defineSecret('NEON_DATABASE_URL');
const pagamentosApp = express();
pagamentosApp.use(express.json({ limit: '32kb' }));
pagamentosApp.use(cors({ origin: true }));

let mensalidadePool;
function obterPoolMensalidade() {
    if (!mensalidadePool) {
        mensalidadePool = new Pool({
            connectionString: neonDatabaseUrl.value(),
            max: 3,
            ssl: { rejectUnauthorized: true },
        });
    }
    return mensalidadePool;
}

function mesCompetencia(configuracoes) {
        const partes = new Intl.DateTimeFormat('en-CA', {
            timeZone: 'America/Sao_Paulo',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        }).formatToParts(new Date());
        const data = Object.fromEntries(partes.map((parte) => [parte.type, parte.value]));
        const hoje = new Date(Number(data.year), Number(data.month) - 1, Number(data.day));
        const cobranca = configuracoes?.data_cobranca ?? configuracoes?.dataCobranca;
        let diaVencimento;
        if (cobranca != null && String(cobranca).trim()) {
            const texto = String(cobranca).trim();
            const dataCompleta = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto);
            diaVencimento = dataCompleta
                ? Number(dataCompleta[3])
                : Number.parseInt(texto, 10);
        }
        if (!Number.isInteger(diaVencimento) || diaVencimento < 1 || diaVencimento > 31) {
            return `${data.year}-${data.month}`;
        }
        const competencia = hoje.getDate() < diaVencimento
            ? new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1)
            : hoje;
        return `${competencia.getFullYear()}-${String(competencia.getMonth() + 1).padStart(2, '0')}`;
}

function valorMensalidade(configuracoes) {
    const valor = Number(String(
        configuracoes?.valor_mensalidade ?? configuracoes?.valorMensalidade ?? ''
    ).replace(',', '.'));
    return Number.isFinite(valor) && valor > 0 ? Math.round(valor * 100) / 100 : null;
}

function verificarAssinaturaWebhook(req) {
    const signatureHeader = req.get('x-signature') || '';
    const requestId = req.get('x-request-id') || '';
    const paymentId = String(req.query['data.id'] || req.body?.data?.id || '').toLowerCase();
    const campos = Object.fromEntries(
        signatureHeader.split(',').map((campo) => {
            const [chave, ...valor] = campo.trim().split('=');
            return [chave, valor.join('=')];
        })
    );
    if (!campos.ts || !campos.v1 || !requestId || !paymentId) return false;
    const manifest = `id:${paymentId};request-id:${requestId};ts:${campos.ts};`;
    const esperado = crypto
        .createHmac('sha256', mercadoPagoWebhookSecret.value())
        .update(manifest)
        .digest();
    let recebido;
    try {
        recebido = Buffer.from(campos.v1, 'hex');
    } catch (_) {
        return false;
    }
    return recebido.length === esperado.length &&
        crypto.timingSafeEqual(recebido, esperado);
}

pagamentosApp.post('/create-pix', async (req, res) => {
    try {
        const empresaId = String(req.body?.empresa_id || '').trim();
        const email = String(req.body?.email || '').trim();
        if (!empresaId || empresaId.length > 128 || email.length > 254 ||
            !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            return res.status(400).json({ erro: 'Empresa ou e-mail inválido.' });
        }

        const db = obterPoolMensalidade();
        const resultado = await db.query(
            'SELECT id, razao_social, configuracoes FROM empresas WHERE id = $1 LIMIT 1',
            [empresaId]
        );
        if (resultado.rowCount !== 1) {
            return res.status(404).json({ erro: 'Empresa não encontrada.' });
        }
        const empresa = resultado.rows[0];
        const config = empresa.configuracoes || {};
        const valor = valorMensalidade(config);
        if (valor == null) {
            return res.status(400).json({
                erro: 'A mensalidade ainda não foi configurada. Fale com o suporte.',
            });
        }
        const mes = mesCompetencia(config);
        const ultimoMesPago = String(config.ultimo_mes_pago || '');
        if (ultimoMesPago >= mes && config.bloqueado !== true) {
            return res.status(409).json({
                erro: 'A mensalidade deste mês já consta como paga.',
            });
        }

        const referencia = `exodo:${empresaId}:${mes}`;
        const resposta = await fetch('https://api.mercadopago.com/v1/payments', {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${mercadoPagoAccessToken.value()}`,
                'Content-Type': 'application/json',
                'X-Idempotency-Key': crypto
                    .createHash('sha256')
                    .update(referencia)
                    .digest('hex'),
            },
            body: JSON.stringify({
                transaction_amount: valor,
                description: `Mensalidade Sistema Êxodo ${mes}`,
                payment_method_id: 'pix',
                external_reference: referencia,
                notification_url:
                    'https://us-central1-exodosystems-1541d.cloudfunctions.net/mercadoPagoApi/webhook',
                payer: { email },
            }),
            signal: AbortSignal.timeout(20000),
        });
        const pagamento = await resposta.json();
        if (!resposta.ok) {
            console.error('Mercado Pago recusou a criação da cobrança:', resposta.status);
            return res.status(502).json({
                erro: 'O Mercado Pago não conseguiu gerar o Pix. Tente novamente.',
            });
        }
        const dadosPix = pagamento.point_of_interaction?.transaction_data;
        if (!pagamento.id || !dadosPix?.qr_code) {
            console.error('Resposta Pix sem dados esperados do Mercado Pago.');
            return res.status(502).json({
                erro: 'O Mercado Pago não retornou os dados do Pix.',
            });
        }
        return res.status(200).json({
            pagamento_id: String(pagamento.id),
            qr_code: dadosPix.qr_code,
            qr_code_base64: dadosPix.qr_code_base64 || null,
            ticket_url: dadosPix.ticket_url || null,
            mes_referencia: mes,
            valor,
        });
    } catch (error) {
        console.error('Falha ao criar cobrança de mensalidade:', error.message);
        return res.status(500).json({
            erro: 'Não foi possível gerar a cobrança agora. Tente novamente.',
        });
    }
});

async function liberarMensalidadeAprovada(pagamento) {
    if (pagamento.status !== 'approved' || pagamento.payment_method_id !== 'pix') {
        return { aprovado: false, liberado: false };
    }
    const match = /^exodo:(.+):(\d{4}-\d{2})$/.exec(
        String(pagamento.external_reference || '')
    );
    if (!match || !Number.isFinite(Number(pagamento.transaction_amount))) {
        throw new Error('Referência de pagamento inválida.');
    }
    const [, empresaId, mes] = match;
    const db = obterPoolMensalidade();
    const empresaResultado = await db.query(
        'SELECT configuracoes FROM empresas WHERE id = $1 LIMIT 1',
        [empresaId]
    );
    if (empresaResultado.rowCount !== 1) {
        throw new Error('Empresa da cobrança não encontrada.');
    }
    const config = empresaResultado.rows[0].configuracoes || {};
    const valorEsperado = valorMensalidade(config);
    if (valorEsperado == null ||
        Math.abs(valorEsperado - Number(pagamento.transaction_amount)) > 0.01) {
        throw new Error('Valor do pagamento não confere com a mensalidade.');
    }
    if (String(config.ultimo_mes_pago || '') > mes) {
        return { aprovado: true, liberado: true };
    }

    const novosDados = {
        status_pagamento: 'pago',
        bloqueado: false,
        ultimo_mes_pago: mes,
        mercado_pago_payment_id: String(pagamento.id),
        mercado_pago_pago_em: pagamento.date_approved || new Date().toISOString(),
    };
    const atualizacao = await db.query(
        `UPDATE empresas
         SET configuracoes = COALESCE(configuracoes, '{}'::jsonb) || $1::jsonb
         WHERE id = $2`,
        [JSON.stringify(novosDados), empresaId]
    );
    if (atualizacao.rowCount !== 1) {
        throw new Error('Não foi possível registrar a liberação da empresa.');
    }
    return { aprovado: true, liberado: true };
}

pagamentosApp.post('/payment-status', async (req, res) => {
    try {
        const paymentId = String(req.body?.pagamento_id || '').trim();
        const empresaId = String(req.body?.empresa_id || '').trim();
        if (!/^\d+$/.test(paymentId) || !empresaId) {
            return res.status(400).json({ erro: 'Identificação do pagamento inválida.' });
        }
        const resposta = await fetch(
            `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
            {
                headers: { Authorization: `Bearer ${mercadoPagoAccessToken.value()}` },
                signal: AbortSignal.timeout(20000),
            }
        );
        if (!resposta.ok) {
            return res.status(502).json({ erro: 'Não foi possível consultar o pagamento.' });
        }
        const pagamento = await resposta.json();
        if (pagamento.external_reference?.startsWith(`exodo:${empresaId}:`) !== true) {
            return res.status(404).json({ erro: 'Pagamento não pertence a esta empresa.' });
        }
        const resultado = await liberarMensalidadeAprovada(pagamento);
        return res.status(200).json({
            status: pagamento.status,
            pago_em: pagamento.date_approved || null,
            ...resultado,
        });
    } catch (error) {
        console.error('Falha ao consultar pagamento de mensalidade:', error.message);
        return res.status(500).json({ erro: 'Erro ao consultar o pagamento.' });
    }
});

pagamentosApp.post('/webhook', async (req, res) => {
    try {
        if (!verificarAssinaturaWebhook(req)) {
            return res.status(401).json({ erro: 'Assinatura do webhook inválida.' });
        }
        const paymentId = String(req.query['data.id'] || req.body?.data?.id || '');
        const resposta = await fetch(
            `https://api.mercadopago.com/v1/payments/${encodeURIComponent(paymentId)}`,
            {
                headers: { Authorization: `Bearer ${mercadoPagoAccessToken.value()}` },
                signal: AbortSignal.timeout(20000),
            }
        );
        if (!resposta.ok) {
            console.error('Falha ao consultar pagamento no Mercado Pago:', resposta.status);
            return res.status(502).json({ erro: 'Não foi possível validar o pagamento.' });
        }
        const pagamento = await resposta.json();
        const resultado = await liberarMensalidadeAprovada(pagamento);
        return res.status(200).json({ recebido: true, ...resultado });
    } catch (error) {
        console.error('Falha ao processar webhook de mensalidade:', error.message);
        return res.status(500).json({ erro: 'Erro ao processar o pagamento.' });
    }
});
