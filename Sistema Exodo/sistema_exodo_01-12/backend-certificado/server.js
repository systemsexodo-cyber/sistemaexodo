const express = require('express');
const cors = require('cors');
const forge = require('node-forge');
const multer = require('multer');

const app = express();
const PORT = 3001;

// Configurar CORS para permitir requisições do Flutter
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Configurar multer para upload de arquivos
const upload = multer({ storage: multer.memoryStorage() });

/**
 * Endpoint para processar certificado PKCS12
 * Recebe o certificado em base64 e a senha
 * Retorna a chave privada e o certificado em formato PEM
 */
app.post('/api/certificado/processar', async (req, res) => {
  try {
    const { certificadoBase64, senha } = req.body;

    if (!certificadoBase64) {
      return res.status(400).json({ 
        erro: 'Certificado não fornecido',
        mensagem: 'É necessário fornecer o certificado em base64'
      });
    }

    if (!senha) {
      return res.status(400).json({ 
        erro: 'Senha não fornecida',
        mensagem: 'É necessário fornecer a senha do certificado'
      });
    }

    console.log('>>> Processando certificado PKCS12...');
    console.log('>>> Tamanho (base64):', certificadoBase64.length, 'caracteres');

    // Decodificar base64 para buffer
    const certificadoBuffer = Buffer.from(certificadoBase64, 'base64');
    console.log('>>> Tamanho (bytes):', certificadoBuffer.length);

    // Converter para formato que o node-forge entende
    const p12Der = forge.util.createBuffer(certificadoBuffer.toString('binary'));

    // Processar PKCS12
    const p12Asn1 = forge.asn1.fromDer(p12Der);
    const p12 = forge.pkcs12.pkcs12FromAsn1(p12Asn1, false, senha);

    // Extrair chave privada
    const bags = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag });
    if (!bags[forge.pki.oids.pkcs8ShroudedKeyBag] || bags[forge.pki.oids.pkcs8ShroudedKeyBag].length === 0) {
      throw new Error('Chave privada não encontrada no certificado. Verifique se a senha está correta.');
    }

    const privateKey = bags[forge.pki.oids.pkcs8ShroudedKeyBag][0].key;
    const privateKeyPem = forge.pki.privateKeyToPem(privateKey);

    // Extrair certificado
    const certBags = p12.getBags({ bagType: forge.pki.oids.certBag });
    if (!certBags[forge.pki.oids.certBag] || certBags[forge.pki.oids.certBag].length === 0) {
      throw new Error('Certificado X509 não encontrado no arquivo PKCS12');
    }

    const certificate = certBags[forge.pki.oids.certBag][0].cert;
    const certificatePem = forge.pki.certificateToPem(certificate);

    // Extrair informações do certificado
    const subject = certificate.subject;
    const issuer = certificate.issuer;
    const validFrom = certificate.validity.notBefore;
    const validTo = certificate.validity.notAfter;

    // Tentar extrair CNPJ do subject
    let cnpj = null;
    const cnpjAttr = subject.getField('2.16.76.1.3.1'); // OID do CNPJ
    if (cnpjAttr) {
      cnpj = cnpjAttr.value;
    }

    console.log('>>> Certificado processado com sucesso');
    console.log('>>> CNPJ:', cnpj || 'Não encontrado');
    console.log('>>> Válido de:', validFrom, 'até', validTo);

    // Retornar resultado
    res.json({
      sucesso: true,
      chavePrivadaPem: privateKeyPem,
      certificadoPem: certificatePem,
      informacoes: {
        cnpj: cnpj,
        validade: {
          de: validFrom,
          ate: validTo
        },
        subject: subject.getField('CN')?.value || null,
        issuer: issuer.getField('CN')?.value || null
      }
    });

  } catch (erro) {
    console.error('>>> ERRO ao processar certificado:', erro);
    
    // Mensagens de erro mais amigáveis
    let mensagem = erro.message || 'Erro desconhecido ao processar certificado';
    
    if (erro.message.includes('Invalid password') || erro.message.includes('MAC')) {
      mensagem = 'Senha do certificado incorreta. Verifique se a senha está correta.';
    } else if (erro.message.includes('not found')) {
      mensagem = 'Certificado inválido ou corrompido. Verifique se o arquivo está completo.';
    }

    res.status(400).json({
      erro: 'Erro ao processar certificado',
      mensagem: mensagem,
      detalhes: erro.message
    });
  }
});

/**
 * Endpoint de health check
 */
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', servico: 'Backend de Certificados' });
});

// Iniciar servidor
app.listen(PORT, () => {
  console.log(`>>> Backend de Certificados rodando na porta ${PORT}`);
  console.log(`>>> Acesse http://localhost:${PORT}/api/health para verificar`);
});

