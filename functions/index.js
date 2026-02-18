const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const multer = require('multer');
const forge = require('node-forge');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const os = require('os');

admin.initializeApp();

const app = express();

// Ativar CORS
app.use(cors({ origin: true }));

// Configurar multer para usar o diretório /tmp (o único gravável no Firebase Functions)
const upload = multer({ dest: os.tmpdir() });

/**
 * Endpoint para processar certificado PFX
 * Retorna chave privada e certificado em formato PEM
 */
app.post('/processar-certificado', upload.single('certificado'), async (req, res) => {
    try {
        console.log('>>> [Functions] Recebido certificado para processar');

        if (!req.file) {
            return res.status(400).json({
                erro: 'Certificado não fornecido',
                sucesso: false
            });
        }

        const senha = req.body.senha || '';
        const caminhoArquivo = req.file.path;

        console.log('>>> [Functions] Processando:', caminhoArquivo);

        // Ler arquivo PFX
        const pfxBytes = fs.readFileSync(caminhoArquivo);
        console.log('>>> [Functions] Arquivo lido:', pfxBytes.length, 'bytes');

        // Converter para base64 para processar com node-forge
        const pfxBase64 = pfxBytes.toString('base64');

        // Processar PFX
        let p12;
        try {
            p12 = forge.pkcs12.decodeBase64(pfxBase64, false, senha);
        } catch (e) {
            // Limpar arquivo temporário
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

                // Chave privada
                if (bag.type === forge.pki.oids.keyBag || bag.type === forge.pki.oids.pkcs8ShroudedKeyBag) {
                    if (bag.key) chavePrivada = bag.key;
                }

                // Certificado
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
            if (fs.existsSync(caminhoArquivo)) fs.unlinkSync(caminhoArquivo);
            return res.status(400).json({
                erro: 'Chave privada ou certificado não encontrado no PFX',
                sucesso: false
            });
        }

        // Converter para PEM
        const chavePrivadaPEM = forge.pki.privateKeyToPem(chavePrivada);
        const certificadoPEM = forge.pki.certificateToPem(certificadoX509);

        // Extrair componentes RSA (úteis para algumas bibliotecas Dart)
        const n = chavePrivada.n.toString(16);
        const d = chavePrivada.d.toString(16);
        const p = chavePrivada.p.toString(16);
        const q = chavePrivada.q.toString(16);

        // Limpar arquivo temporário
        if (fs.existsSync(caminhoArquivo)) fs.unlinkSync(caminhoArquivo);

        console.log('>>> [Functions] ✓ Certificado processado para CNPJ:', cnpj);

        res.json({
            sucesso: true,
            chavePrivada: {
                pem: chavePrivadaPEM,
                n: n,
                d: d,
                p: p,
                q: q,
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
        console.error('>>> [Functions] ERRO:', e);
        if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        res.status(500).json({
            erro: 'Erro interno ao processar certificado',
            detalhes: e.message,
            sucesso: false
        });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', source: 'Firebase Functions' });
});

// Exportar a cloud function
exports.api = functions.https.onRequest(app);
