const functions = require('firebase-functions');
const admin = require('firebase-admin');
const forge = require('node-forge');

// Inicializar Firebase Admin (já deve estar inicializado no seu projeto)
// Se não estiver, descomente a linha abaixo:
// admin.initializeApp();

/**
 * Cloud Function para processar certificado PKCS12
 * 
 * Esta função processa certificados PKCS12 que não podem ser processados
 * pela biblioteca asn1lib no Flutter.
 * 
 * URL: https://[REGION]-[PROJECT-ID].cloudfunctions.net/processarCertificado
 */
exports.processarCertificado = functions.https.onCall(async (data, context) => {
  try {
    // Validar autenticação (opcional - descomente se quiser exigir autenticação)
    // if (!context.auth) {
    //   throw new functions.https.HttpsError(
    //     'unauthenticated',
    //     'A função deve ser chamada enquanto autenticado.'
    //   );
    // }

    const { certificadoBase64, senha } = data;

    // Validações
    if (!certificadoBase64) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Certificado não fornecido. É necessário fornecer o certificado em base64.'
      );
    }

    if (!senha) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Senha não fornecida. É necessário fornecer a senha do certificado.'
      );
    }

    console.log('>>> [Cloud Function] Processando certificado PKCS12...');
    console.log('>>> [Cloud Function] Tamanho (base64):', certificadoBase64.length, 'caracteres');

    // Decodificar base64 para buffer
    const certificadoBuffer = Buffer.from(certificadoBase64, 'base64');
    console.log('>>> [Cloud Function] Tamanho (bytes):', certificadoBuffer.length);

    // Converter para formato que o node-forge entende
    const p12Der = forge.util.createBuffer(certificadoBuffer.toString('binary'));

    // Processar PKCS12
    const p12Asn1 = forge.asn1.fromDer(p12Der);
    const p12 = forge.pkcs12.pkcs12FromAsn1(p12Asn1, false, senha);

    // Extrair chave privada
    const bags = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag });
    if (!bags[forge.pki.oids.pkcs8ShroudedKeyBag] || bags[forge.pki.oids.pkcs8ShroudedKeyBag].length === 0) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Chave privada não encontrada no certificado. Verifique se a senha está correta.'
      );
    }

    const privateKey = bags[forge.pki.oids.pkcs8ShroudedKeyBag][0].key;
    const privateKeyPem = forge.pki.privateKeyToPem(privateKey);

    // Extrair certificado
    const certBags = p12.getBags({ bagType: forge.pki.oids.certBag });
    if (!certBags[forge.pki.oids.certBag] || certBags[forge.pki.oids.certBag].length === 0) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Certificado X509 não encontrado no arquivo PKCS12.'
      );
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

    console.log('>>> [Cloud Function] Certificado processado com sucesso');
    console.log('>>> [Cloud Function] CNPJ:', cnpj || 'Não encontrado');
    console.log('>>> [Cloud Function] Válido de:', validFrom, 'até', validTo);

    // Retornar resultado
    return {
      sucesso: true,
      chavePrivadaPem: privateKeyPem,
      certificadoPem: certificatePem,
      informacoes: {
        cnpj: cnpj,
        validade: {
          de: validFrom.toISOString(),
          ate: validTo.toISOString()
        },
        subject: subject.getField('CN')?.value || null,
        issuer: issuer.getField('CN')?.value || null
      }
    };

  } catch (erro) {
    console.error('>>> [Cloud Function] ERRO ao processar certificado:', erro);

    // Se já for um HttpsError, re-lançar
    if (erro instanceof functions.https.HttpsError) {
      throw erro;
    }

    // Mensagens de erro mais amigáveis
    let mensagem = erro.message || 'Erro desconhecido ao processar certificado';
    let codigo = 'internal';

    if (erro.message.includes('Invalid password') || erro.message.includes('MAC')) {
      mensagem = 'Senha do certificado incorreta. Verifique se a senha está correta.';
      codigo = 'invalid-argument';
    } else if (erro.message.includes('not found')) {
      mensagem = 'Certificado inválido ou corrompido. Verifique se o arquivo está completo.';
      codigo = 'invalid-argument';
    }

    throw new functions.https.HttpsError(
      codigo,
      mensagem,
      { detalhes: erro.message }
    );
  }
});

