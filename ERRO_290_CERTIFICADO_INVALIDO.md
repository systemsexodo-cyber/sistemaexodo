# 🔴 Erro 290: Certificado de Assinatura Inválido

## 📋 Descrição do Erro

O erro **290** é retornado pela SEFAZ quando o certificado digital usado para assinar a NFC-e é considerado inválido.

**Mensagem da SEFAZ:**
```
cStat: 290
xMotivo: Rejeição: Certificado Assinatura inválido
```

## 🔍 Possíveis Causas

### 1. **Certificado Expirado**
- O certificado digital pode ter expirado
- Verifique a data de validade do certificado

### 2. **Formato do Certificado Incorreto**
- Certificado não está em formato PKCS#12 (.pfx)
- Certificado não inclui a chave privada
- Certificado corrompido ou incompleto

### 3. **Senha Incorreta**
- A senha do certificado informada está errada
- Senha foi alterada após a configuração

### 4. **Ambiente Incorreto**
- Certificado de **homologação** sendo usado em **produção**
- Certificado de **produção** sendo usado em **homologação**
- Cada ambiente requer seu próprio certificado

### 5. **CNPJ Não Corresponde**
- O CNPJ do certificado não corresponde ao CNPJ da empresa
- Certificado pertence a outra empresa

### 6. **Problema na Assinatura**
- Erro na geração da assinatura digital
- Certificado não está sendo incluído corretamente no XML
- Algoritmo de assinatura incompatível

## ✅ Soluções

### Solução 1: Verificar Validade do Certificado

1. Acesse a configuração da empresa no sistema
2. Verifique a data de validade do certificado
3. Se expirado, renove o certificado na autoridade certificadora

### Solução 2: Re-exportar o Certificado

1. Abra o certificado no software original:
   - **e-CPF Manager** ou **e-CNPJ Manager**
   - Ou use `certmgr.msc` no Windows

2. Exporte novamente o certificado:
   - ✅ Marque a opção **"Incluir todas as extensões"**
   - ✅ Marque a opção **"Exportar a chave privada"**
   - ✅ Escolha o formato **PKCS#12 (.pfx)**
   - ✅ Defina uma senha forte

3. Importe o certificado no sistema novamente

### Solução 3: Verificar Senha

1. Acesse a configuração da empresa
2. Verifique se a senha está correta
3. Teste a senha abrindo o certificado diretamente
4. Se necessário, redefina a senha do certificado

### Solução 4: Verificar Ambiente

1. Verifique se está usando o ambiente correto:
   - **Homologação**: Para testes
   - **Produção**: Para uso real

2. Certifique-se de que o certificado corresponde ao ambiente:
   - Certificado de homologação → Ambiente de homologação
   - Certificado de produção → Ambiente de produção

### Solução 5: Verificar CNPJ

1. Verifique o CNPJ do certificado
2. Confirme que corresponde ao CNPJ da empresa
3. Se não corresponder, use o certificado correto

### Solução 6: Validar Assinatura

1. Verifique os logs do sistema para erros de assinatura
2. Confirme que o certificado está sendo carregado corretamente
3. Verifique se a chave privada está disponível

## 🔧 Como Verificar o Certificado no Sistema

### Passos para Verificação:

1. **Acesse a Configuração da Empresa**
   - Vá até a tela de configurações
   - Selecione a empresa

2. **Verifique os Dados do Certificado**
   - CNPJ do certificado
   - Data de validade
   - Formato (deve ser PKCS#12)

3. **Teste o Certificado**
   - Tente carregar o certificado
   - Verifique se a senha está correta
   - Confirme que a chave privada está disponível

## 📊 Exemplo de Retorno da SEFAZ

```xml
<retEnviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <tpAmb>2</tpAmb>
  <verAplic>SP_NFCE_PL_009_V400</verAplic>
  <cStat>104</cStat>
  <xMotivo>Lote processado</xMotivo>
  <cUF>35</cUF>
  <dhRecbto>2025-12-13T11:52:17-03:00</dhRecbto>
  <protNFe versao="4.00">
    <infProt>
      <tpAmb>2</tpAmb>
      <verAplic>SP_NFCE_PL_009_V400</verAplic>
      <chNFe>35251204829400000165650010000000011262338964</chNFe>
      <dhRecbto>2025-12-13T11:52:17-03:00</dhRecbto>
      <cStat>290</cStat>
      <xMotivo>Rejeição: Certificado Assinatura inválido</xMotivo>
    </infProt>
  </protNFe>
</retEnviNFe>
```

## 🚨 Importante

- O erro 290 é um erro **crítico** que impede a autorização da NFC-e
- É necessário corrigir o problema do certificado antes de tentar novamente
- Não é possível contornar este erro sem corrigir o certificado

## 📞 Suporte

Se o problema persistir após seguir todas as soluções:

1. Verifique os logs detalhados do sistema
2. Confirme todos os dados do certificado
3. Entre em contato com a autoridade certificadora se necessário

## 🔄 Próximos Passos Após Corrigir

1. Reconfigure o certificado no sistema
2. Verifique se o certificado foi carregado corretamente
3. Tente emitir uma nova NFC-e
4. Monitore os logs para confirmar que não há mais erros











