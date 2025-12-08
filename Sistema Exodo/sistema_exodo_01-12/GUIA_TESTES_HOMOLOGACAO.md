# 🧪 Guia de Testes em Homologação - NFC-e

## 📋 Pré-requisitos

### 1. Credenciamento na SEFAZ
- Acesse o portal da SEFAZ do seu estado
- Faça o credenciamento para emissão de NFC-e
- Obtenha as credenciais de acesso

### 2. Certificado Digital
- Certificado digital A1 (arquivo .pfx) ou A3 (token/cartão)
- Senha do certificado
- Certificado deve estar válido e não expirado
- CNPJ do certificado deve corresponder ao CNPJ da empresa

### 3. Configurações na Empresa
- **CNPJ:** Obrigatório
- **Inscrição Estadual:** Obrigatória
- **CRT:** Código de Regime Tributário (1, 2 ou 3)
- **Código IBGE:** Código do município (7 dígitos)
- **Certificado Digital:** Upload do arquivo .pfx
- **Senha do Certificado:** Senha do arquivo .pfx
- **CSC:** Código de Segurança do Contribuinte (fornecido pela SEFAZ)
- **ID Token CSC:** ID do token CSC (fornecido pela SEFAZ)

## 🔧 Configuração do Ambiente

### Ambiente de Homologação
- Por padrão, o sistema usa ambiente de homologação (`ambienteHomologacao: true`)
- URLs da SEFAZ são automaticamente ajustadas para homologação
- Certificados de teste podem ser usados

### URLs de Homologação (Exemplo - São Paulo)
- **NFeAutorizacao4:** `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx`
- **NFeRetAutorizacao4:** `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx`
- **NFeConsultaProtocolo4:** `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx`
- **NFeStatusServico4:** `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx`

## 🧪 Como Testar

### 1. Validar Configuração
```dart
final testeService = TesteHomologacaoService(nfceService: nfceService);
final validacao = await testeService.validarConfiguracao(empresa);

if (!validacao['valido']) {
  print('Erros encontrados:');
  for (final erro in validacao['erros']) {
    print('  - $erro');
  }
}
```

### 2. Executar Teste de Emissão
```dart
final resultado = await testeService.executarTesteBasico(
  empresa: empresa,
  produtos: produtos,
  valorTotal: 100.00,
);

if (resultado['sucesso']) {
  print('NFC-e autorizada!');
  print('Chave de acesso: ${resultado['chaveAcesso']}');
  print('Protocolo: ${resultado['protocolo']}');
} else {
  print('Erro: ${resultado['erro']}');
}
```

### 3. Testar via Interface
1. Realize uma venda no PDV
2. Após finalizar a venda, clique em "Emitir NFC-e"
3. Aguarde o processamento
4. Verifique o resultado (autorizada/rejeitada)

## ⚠️ Problemas Comuns

### Certificado Digital
- **Erro:** "Não foi possível extrair a chave privada"
  - **Solução:** Verifique se a senha está correta
  - **Solução:** Verifique se o certificado está válido
  - **Solução:** Tente usar outro certificado de teste

### Assinatura Digital
- **Erro:** "Erro ao converter RSASignature para bytes"
  - **Solução:** Certificado pode estar em formato incompatível
  - **Solução:** Verifique se o PointyCastle está na versão correta

### Parsing PKCS12
- **Erro:** "Estrutura PKCS12 inválida"
  - **Solução:** Certificado pode estar corrompido
  - **Solução:** Tente exportar o certificado novamente

### SEFAZ
- **Erro:** "Erro ao comunicar com SEFAZ"
  - **Solução:** Verifique conexão com internet
  - **Solução:** Verifique se está usando URL correta do estado
  - **Solução:** Verifique se o certificado está credenciado

## 📝 Checklist de Testes

- [ ] Certificado digital carregado com sucesso
- [ ] Chave privada extraída corretamente
- [ ] Certificado X509 extraído corretamente
- [ ] XML gerado corretamente
- [ ] XML assinado corretamente
- [ ] Comunicação com SEFAZ estabelecida
- [ ] NFC-e autorizada pela SEFAZ
- [ ] QR Code gerado corretamente
- [ ] DANFE gerado corretamente
- [ ] NFC-e salva no DataService

## 🔍 Validações Importantes

### Antes de Emitir
1. ✅ Empresa configurada
2. ✅ Certificado digital válido
3. ✅ CSC e ID Token configurados
4. ✅ Produtos com dados fiscais (NCM, CFOP, etc)
5. ✅ Código IBGE do município configurado

### Após Emissão
1. ✅ NFC-e autorizada (status = 'autorizada')
2. ✅ Chave de acesso gerada
3. ✅ Protocolo recebido
4. ✅ QR Code gerado
5. ✅ NFC-e salva no sistema

## 📚 Recursos

- **Portal Nacional da NF-e:** https://www.nfe.fazenda.gov.br
- **Portal da SEFAZ do seu estado:** Consulte o portal específico
- **Manual de Integração:** Disponível no portal da SEFAZ
- **Ambiente de Homologação:** Use para testes sem impacto fiscal

## ✅ Pronto para Testes!

Após configurar todos os itens acima, o sistema está pronto para testes em homologação.

