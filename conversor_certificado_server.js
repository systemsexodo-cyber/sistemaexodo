/**
 * Serviço Node.js para processar certificados PFX
 * 
 * Este serviço processa certificados PFX usando bibliotecas nativas do Node.js
 * e retorna os dados prontos para uso no Flutter.
 * 
 * Uso:
 *   1. Instalar dependências: npm install
 *   2. Iniciar servidor: node conversor_certificado_server.js
 *   3. Flutter chama: http://localhost:3000/processar-certificado
 */

const express = require('express');
const multer = require('multer');
const forge = require('node-forge');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const upload = multer({ dest: 'temp/' });

// Criar diretório temp se não existir
if (!fs.existsSync('temp')) {
  fs.mkdirSync('temp');
}

/**
 * Processa certificado PFX e retorna dados prontos
 */
app.post('/processar-certificado', upload.single('certificado'), async (req, res) => {
  try {
    console.log('>>> [Servidor] Recebido certificado para processar');
    
    if (!req.file) {
      return res.status(400).json({ 
        erro: 'Certificado não fornecido',
        sucesso: false 
      });
    }
    
    const senha = req.body.senha || '';
    const caminhoArquivo = req.file.path;
    
    console.log('>>> [Servidor] Processando:', caminhoArquivo);
    
    // Ler arquivo PFX
    const pfxBytes = fs.readFileSync(caminhoArquivo);
    console.log('>>> [Servidor] Arquivo lido:', pfxBytes.length, 'bytes');
    
    // Converter para base64 para processar com node-forge
    const pfxBase64 = pfxBytes.toString('base64');
    
    // Processar PFX
    let p12;
    try {
      p12 = forge.pkcs12.decodeBase64(pfxBase64, false, senha);
    } catch (e) {
      // Limpar arquivo temporário
      fs.unlinkSync(caminhoArquivo);
      
      return res.status(400).json({
        erro: 'Erro ao processar certificado PFX. Verifique se a senha está correta.',
        detalhes: e.message,
        sucesso: false
      });
    }
    
    // Extrair chave privada
    let chavePrivada = null;
    let certificadoX509 = null;
    let cnpj = null;
    let validade = null;
    
    // Procurar chave privada e certificado
    for (let i = 0; i < p12.safeContents.length; i++) {
      const safeContents = p12.safeContents[i];
      
      for (let j = 0; j < safeContents.safeBags.length; j++) {
        const bag = safeContents.safeBags[j];
        
        // Chave privada
        if (bag.type === forge.pki.oids.keyBag || 
            bag.type === forge.pki.oids.pkcs8ShroudedKeyBag) {
          if (bag.key) {
            chavePrivada = bag.key;
            console.log('>>> [Servidor] Chave privada encontrada');
          }
        }
        
        // Certificado
        if (bag.type === forge.pki.oids.certBag) {
          if (bag.cert) {
            certificadoX509 = bag.cert;
            console.log('>>> [Servidor] Certificado encontrado');
            
            // Extrair CNPJ do subject
            const subject = certificadoX509.subject;
            const cnpjMatch = subject.getField('CN')?.value?.match(/\d{14}/);
            if (cnpjMatch) {
              cnpj = cnpjMatch[0];
            }
            
            // Extrair validade
            validade = certificadoX509.validity.notAfter;
          }
        }
      }
    }
    
    if (!chavePrivada) {
      fs.unlinkSync(caminhoArquivo);
      return res.status(400).json({
        erro: 'Chave privada não encontrada no certificado PFX',
        sucesso: false
      });
    }
    
    if (!certificadoX509) {
      fs.unlinkSync(caminhoArquivo);
      return res.status(400).json({
        erro: 'Certificado X509 não encontrado no PFX',
        sucesso: false
      });
    }
    
    // Converter chave privada para formato PEM
    const chavePrivadaPEM = forge.pki.privateKeyToPem(chavePrivada);
    
    // Converter certificado para formato PEM
    const certificadoPEM = forge.pki.certificateToPem(certificadoX509);
    
    // Extrair componentes da chave RSA
    const n = chavePrivada.n.toString(16);
    const d = chavePrivada.d.toString(16);
    const p = chavePrivada.p.toString(16);
    const q = chavePrivada.q.toString(16);
    
    // Limpar arquivo temporário
    fs.unlinkSync(caminhoArquivo);
    
    console.log('>>> [Servidor] ✓ Certificado processado com sucesso');
    console.log('>>> [Servidor] CNPJ:', cnpj || 'Não encontrado');
    console.log('>>> [Servidor] Validade:', validade ? validade.toISOString() : 'Não encontrada');
    
    // Retornar dados prontos
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
    console.error('>>> [Servidor] ERRO:', e);
    
    // Limpar arquivo temporário se existir
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({
      erro: 'Erro ao processar certificado',
      detalhes: e.message,
      sucesso: false
    });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', servico: 'Conversor de Certificado' });
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log('========================================');
  console.log('  SERVIDOR DE CONVERSÃO DE CERTIFICADO');
  console.log('========================================');
  console.log(`Servidor rodando em: http://localhost:${PORT}`);
  console.log('Endpoints disponíveis:');
  console.log('  POST /processar-certificado');
  console.log('  GET  /health');
  console.log('========================================');
});




