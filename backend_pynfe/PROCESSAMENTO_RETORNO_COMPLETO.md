# Processamento Completo do Retorno da SEFAZ

## ✅ Status Atual

O código agora processa **CORRETAMENTE** o retorno da SEFAZ quando `cStat=104` (Lote processado):

1. ✅ Encontra o `retEnviNFe` na resposta
2. ✅ Identifica `cStat=104` (Lote processado)
3. ✅ Busca o `protNFe` usando 5 estratégias diferentes
4. ✅ Extrai o `infProt` do `protNFe`
5. ✅ Verifica o `cStat` da nota individual
6. ✅ Processa autorização (cStat=100 ou 150) ou rejeição (outros cStat)

## 📋 Estrutura do Retorno da SEFAZ

Quando `cStat=104`, a resposta tem esta estrutura:

```xml
<retEnviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <tpAmb>2</tpAmb>
  <verAplic>SP_NFCE_PL_009_V400</verAplic>
  <cStat>104</cStat>
  <xMotivo>Lote processado</xMotivo>
  <cUF>35</cUF>
  <dhRecbto>2025-12-13T08:58:33-03:00</dhRecbto>
  <protNFe versao="4.00">
    <infProt>
      <tpAmb>2</tpAmb>
      <verAplic>SP_NFCE_PL_009_V400</verAplic>
      <chNFe>35251204829400000165650010000000011193859123</chNFe>
      <dhRecbto>2025-12-13T08:58:33-03:00</dhRecbto>
      <cStat>290</cStat>  <!-- Status da nota individual -->
      <xMotivo>Rejeição: Certificado Assinatura inválido</xMotivo>
    </infProt>
  </protNFe>
</retEnviNFe>
```

## 🔍 Fluxo de Processamento

### 1. Quando `cStat=104` (Lote processado)

O código:
1. Salva a resposta XML completa em `logs/debug/resposta_sefaz_cstat104_{timestamp}.xml`
2. Mostra estrutura completa do `retEnviNFe`
3. Busca `protNFe` usando 5 estratégias:
   - Estratégia 1: Busca direta como filho
   - Estratégia 2: Busca recursiva
   - Estratégia 3: Iteração manual
   - Estratégia 4: Busca em todo o documento
   - Estratégia 5: Busca `infProt` diretamente (cria `protNFe` artificialmente)
4. Extrai `infProt` do `protNFe`
5. Verifica `cStat` da nota individual

### 2. Quando Nota Autorizada (`cStat=100` ou `150`)

O código:
1. Constrói `nfeProc` (NFe + protNFe)
2. Extrai QR Code do `infNFeSupl`
3. Salva XML autorizado em `logs/xmls_nfce/{CNPJ}/{ano}/{mes}/`
4. Retorna dados completos para DANFE NFC-e

### 3. Quando Nota Rejeitada (outros `cStat`)

O código:
1. Mostra logs detalhados da rejeição
2. Retorna erro descritivo com `cStat` e `xMotivo`
3. Para `cStat=290`, adiciona diagnóstico específico sobre certificado

## ⚠️ Problema Atual: cStat=290 (Certificado Inválido)

O XML de retorno mostra que a nota foi rejeitada com:
- **cStat:** 290
- **xMotivo:** "Rejeição: Certificado Assinatura inválido"

### Possíveis Causas:

1. **Certificado Expirado**
   - Verifique a validade do certificado
   - Certificados ICP-Brasil têm validade limitada

2. **Certificado Não é ICP-Brasil**
   - O certificado deve ser emitido por uma AC ICP-Brasil
   - Certificados de teste ou autoassinados não são aceitos

3. **Problema na Assinatura Digital**
   - A assinatura pode estar sendo gerada incorretamente
   - Verifique se o algoritmo está correto (RSA-SHA256)

4. **Certificado Sem Permissão**
   - O certificado pode não ter permissão para assinar documentos fiscais
   - Verifique se o certificado é A1 ou A3 válido

5. **Certificado Corrompido**
   - O certificado pode estar corrompido ou em formato incorreto
   - Tente exportar novamente do e-CPF/e-CNPJ

### Soluções:

1. **Verificar Validade do Certificado:**
   ```python
   # O PyNFe já valida o certificado ao carregar
   # Se o certificado estiver expirado, o PyNFe deve mostrar erro
   ```

2. **Verificar Formato do Certificado:**
   - Deve ser PFX/P12 válido
   - Deve conter chave privada e certificado X509
   - Deve estar em base64 válido

3. **Verificar Assinatura Digital:**
   - O PyNFe usa `AssinaturaA1` que deve gerar assinatura correta
   - Verifique se a assinatura está sendo adicionada corretamente ao XML

4. **Testar com Certificado Diferente:**
   - Tente com outro certificado válido
   - Verifique se o problema é específico deste certificado

## 📊 Logs Implementados

O código agora mostra logs detalhados:

```
======================================================================
   ✅ Lote processado (cStat=104), verificando status da nota individual...
======================================================================
   📁 Resposta XML salva para debug: logs/debug/resposta_sefaz_cstat104_*.xml

   📋 Estrutura completa do retEnviNFe:
      Tag raiz: {http://www.portalfiscal.inf.br/nfe}retEnviNFe
      Número de filhos diretos: X
      [0] tpAmb (tag completa: ...)
      [1] verAplic (tag completa: ...)
      [2] cStat (tag completa: ...)
      [3] xMotivo (tag completa: ...)
      [4] protNFe (tag completa: ...)

   🔍 Estratégia 1: Buscando protNFe como filho direto...
   ✅ protNFe encontrado como filho direto! Tag: ...

   ✅ protNFe encontrado! Tag: ...
   📋 cStat da nota: 290
   📋 xMotivo da nota: Rejeição: Certificado Assinatura inválido

======================================================================
   ❌ NOTA REJEITADA PELA SEFAZ
======================================================================
   📋 cStat: 290
   📋 xMotivo: Rejeição: Certificado Assinatura inválido

   ⚠️ ERRO: Certificado de Assinatura inválido (cStat=290)
   📋 Possíveis causas:
      1. Certificado expirado
      2. Certificado não é ICP-Brasil
      ...
```

## ✅ O Que Está Funcionando

1. ✅ Processamento do `cStat=104`
2. ✅ Busca do `protNFe` (5 estratégias)
3. ✅ Extração do `infProt`
4. ✅ Verificação do `cStat` da nota individual
5. ✅ Retorno de rejeição com detalhes
6. ✅ Logs detalhados em cada etapa
7. ✅ Salvamento de XML de debug

## 🔧 O Que Precisa Ser Corrigido

### Problema: Certificado de Assinatura Inválido (cStat=290)

**Ação necessária:**
1. Verificar se o certificado está válido e não expirado
2. Verificar se o certificado é ICP-Brasil (A1 ou A3)
3. Verificar se a assinatura está sendo gerada corretamente
4. Testar com certificado diferente se possível

**Verificações:**
- ✅ Certificado carregado com sucesso pelo PyNFe
- ✅ XML assinado com sucesso
- ❌ SEFAZ rejeita a assinatura (cStat=290)

**Próximos passos:**
1. Verificar validade do certificado
2. Verificar se o certificado é ICP-Brasil válido
3. Verificar se a assinatura está no formato correto
4. Consultar documentação do PyNFe sobre assinatura

## 📁 Arquivos de Debug

Os seguintes arquivos são salvos automaticamente:

1. **Resposta da SEFAZ:** `logs/debug/resposta_sefaz_cstat104_{timestamp}.xml`
2. **XML Assinado:** `logs/debug/xml_assinado_{timestamp}.xml`
3. **XML do Lote:** `logs/debug/xml_lote_{timestamp}.xml`
4. **XML Corrigido:** `logs/debug/xml_corrigido_final_{timestamp}.xml`

Use esses arquivos para análise e depuração.












