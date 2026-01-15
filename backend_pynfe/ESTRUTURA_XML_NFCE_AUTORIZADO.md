# Estrutura do XML de NFC-e Autorizado (nfeProc)

## Visão Geral

O XML autorizado de uma NFC-e segue uma estrutura específica definida pela SEFAZ. Este documento descreve a estrutura correta baseada em um exemplo real de NFC-e autorizada.

## Estrutura Hierárquica

```
nfeProc (raiz)
├── xmlns="http://www.portalfiscal.inf.br/nfe"
├── versao="4.00"
├── NFe
│   ├── xmlns="http://www.portalfiscal.inf.br/nfe"
│   ├── infNFe
│   │   ├── Id="NFe{chave_acesso}"
│   │   ├── versao="4.00"
│   │   ├── ide
│   │   ├── emit
│   │   ├── det (produtos)
│   │   ├── total
│   │   ├── transp
│   │   ├── pag
│   │   ├── infAdic
│   │   └── infRespTec
│   ├── infNFeSupl (QR Code)
│   │   ├── qrCode
│   │   └── urlChave
│   └── Signature (assinatura digital)
│       ├── SignedInfo
│       ├── SignatureValue
│       └── KeyInfo
│           └── X509Data
│               └── X509Certificate
└── protNFe (protocolo de autorização)
    ├── xmlns="http://www.portalfiscal.inf.br/nfe"
    ├── versao="4.00"
    └── infProt
        ├── tpAmb
        ├── verAplic
        ├── chNFe
        ├── dhRecbto
        ├── nProt
        ├── digVal
        ├── cStat
        └── xMotivo
```

## Elementos Principais

### 1. nfeProc (Elemento Raiz)

**Atributos obrigatórios:**
- `xmlns="http://www.portalfiscal.inf.br/nfe"`
- `versao="4.00"`

**Descrição:** Elemento raiz que contém a NFC-e assinada e o protocolo de autorização.

**Exemplo:**
```xml
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
```

### 2. NFe (Nota Fiscal Eletrônica)

**Atributos obrigatórios:**
- `xmlns="http://www.portalfiscal.inf.br/nfe"`

**Descrição:** Contém todos os dados da NFC-e, incluindo a assinatura digital.

**Elementos filhos obrigatórios:**
- `infNFe`: Informações da nota fiscal
- `Signature`: Assinatura digital (XML Signature)

**Elementos filhos opcionais:**
- `infNFeSupl`: Informações suplementares (QR Code)

**Exemplo:**
```xml
<NFe xmlns="http://www.portalfiscal.inf.br/nfe">
  <infNFe Id="NFe35250924163237000151650100000000011909396053" versao="4.00">
    <!-- Dados da nota -->
  </infNFe>
  <infNFeSupl>
    <qrCode>https://www.nfce.fazenda.sp.gov.br/qrcode?p=...</qrCode>
    <urlChave>https://www.nfce.fazenda.sp.gov.br/consulta</urlChave>
  </infNFeSupl>
  <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
    <!-- Assinatura digital -->
  </Signature>
</NFe>
```

### 3. infNFe (Informações da Nota Fiscal)

**Atributos obrigatórios:**
- `Id="NFe{chave_acesso}"`: ID único da nota (chave de acesso)
- `versao="4.00"`

**Elementos principais:**
- `ide`: Identificação da nota
- `emit`: Dados do emitente
- `det`: Detalhes dos produtos/serviços
- `total`: Totais da nota
- `transp`: Dados de transporte
- `pag`: Dados de pagamento
- `infAdic`: Informações adicionais
- `infRespTec`: Informações do responsável técnico

### 4. infNFeSupl (Informações Suplementares - QR Code)

**Elementos obrigatórios:**
- `qrCode`: URL completa do QR Code para consulta
- `urlChave`: URL base para consulta da chave de acesso

**Exemplo:**
```xml
<infNFeSupl>
  <qrCode>https://www.nfce.fazenda.sp.gov.br/qrcode?p=35250924163237000151650100000000011909396053|2|1|1|8e8e9156fd5a7e0c08e42df9929689bc4b602f16</qrCode>
  <urlChave>https://www.nfce.fazenda.sp.gov.br/consulta</urlChave>
</infNFeSupl>
```

**Importante:** O `infNFeSupl` deve ser adicionado **antes** da assinatura digital, para que o QR Code faça parte do documento assinado.

### 5. Signature (Assinatura Digital)

**Namespace:** `http://www.w3.org/2000/09/xmldsig#`

**Elementos obrigatórios:**
- `SignedInfo`: Informações sobre a assinatura
  - `CanonicalizationMethod`: Método de canonização
  - `SignatureMethod`: Algoritmo de assinatura (RSA-SHA1)
  - `Reference`: Referência ao elemento assinado (infNFe)
- `SignatureValue`: Valor da assinatura (Base64)
- `KeyInfo`: Informações da chave
  - `X509Data`: Dados do certificado X.509
    - `X509Certificate`: Certificado em Base64

**Exemplo:**
```xml
<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
  <SignedInfo>
    <CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
    <SignatureMethod Algorithm="http://www.w3.org/2000/09/xmldsig#rsa-sha1"/>
    <Reference URI="#NFe35250924163237000151650100000000011909396053">
      <Transforms>
        <Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
        <Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
      </Transforms>
      <DigestMethod Algorithm="http://www.w3.org/2000/09/xmldsig#sha1"/>
      <DigestValue>b5h56zGU1BkM9VR4CPewkQpliuc=</DigestValue>
    </Reference>
  </SignedInfo>
  <SignatureValue>XlP1cLmKL3AuBOFjP4kjHl4pf93qHbUSxLwkotCQGcHkhacGIvTdDWn9K1+eiI9qpDDtra52OJQLJ0OQ56wDIqCUjIjTzHReO/NAbW2ILmJTakLguXvQyVGhoCFUfh1oNtCe4XhnPqpxyC4wHm2KjBEjQe2vs/N0mjwDjSaRiub4zcDG2SnyT3cbxKPFSbwsvOCBtFTB86Uupe9ZDy291r8QMgy+QTSg7v/ldsDyyMnBZx7dEkUzg3uspNbJfUZIpSIyQe8NurDF1mwN1ci0xwd79IjXHilU3mr7YuYdUTkajjjJZHAJ4OtNDpDt2J2TeT/xoe2G0lfkmzbvIFDalg==</SignatureValue>
  <KeyInfo>
    <X509Data>
      <X509Certificate>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</X509Certificate>
    </X509Data>
  </KeyInfo>
</Signature>
```

**Importante:** 
- O `KeyInfo` não pode conter texto, apenas elementos filhos
- O `X509Data` deve conter o certificado completo em Base64

### 6. protNFe (Protocolo de Autorização)

**Atributos obrigatórios:**
- `xmlns="http://www.portalfiscal.inf.br/nfe"`
- `versao="4.00"`

**Elemento filho obrigatório:**
- `infProt`: Informações do protocolo

**Exemplo:**
```xml
<protNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <infProt>
    <tpAmb>1</tpAmb>
    <verAplic>SP_NFCE_PL_009_V400</verAplic>
    <chNFe>35250924163237000151650100000000011909396053</chNFe>
    <dhRecbto>2025-09-10T10:31:52-03:00</dhRecbto>
    <nProt>135252045063241</nProt>
    <digVal>b5h56zGU1BkM9VR4CPewkQpliuc=</digVal>
    <cStat>100</cStat>
    <xMotivo>Autorizado o uso da NF-e</xMotivo>
  </infProt>
</protNFe>
```

**Campos importantes do infProt:**
- `cStat`: Código de status
  - `100`: Autorizado o uso da NF-e
  - `150`: Autorizado fora de prazo
  - Outros: Rejeição (verificar `xMotivo`)
- `nProt`: Número do protocolo de autorização
- `chNFe`: Chave de acesso da NFC-e
- `digVal`: Digest Value (deve corresponder ao DigestValue da assinatura)

## Ordem dos Elementos

A ordem correta dentro do `NFe` é:
1. `infNFe` (primeiro)
2. `infNFeSupl` (opcional, mas recomendado - QR Code)
3. `Signature` (último, assina tudo acima)

## Validações Implementadas

O sistema agora valida automaticamente:

1. ✅ `nfeProc` tem `xmlns` e `versao`
2. ✅ `NFe` tem `xmlns` próprio
3. ✅ `infNFe` está presente dentro do `NFe`
4. ✅ `Signature` está presente dentro do `NFe`
5. ✅ `infNFeSupl` está presente (se QR Code foi gerado)
6. ✅ `protNFe` tem `xmlns` e `versao`
7. ✅ `infProt` está presente dentro do `protNFe`
8. ✅ `cStat` no `infProt` indica autorização (100 ou 150)

## Exemplo Completo (Resumido)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <NFe xmlns="http://www.portalfiscal.inf.br/nfe">
    <infNFe Id="NFe35250924163237000151650100000000011909396053" versao="4.00">
      <!-- Dados da nota -->
    </infNFe>
    <infNFeSupl>
      <qrCode>https://www.nfce.fazenda.sp.gov.br/qrcode?p=...</qrCode>
      <urlChave>https://www.nfce.fazenda.sp.gov.br/consulta</urlChave>
    </infNFeSupl>
    <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
      <!-- Assinatura digital -->
    </Signature>
  </NFe>
  <protNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
    <infProt>
      <cStat>100</cStat>
      <xMotivo>Autorizado o uso da NF-e</xMotivo>
      <!-- Outros campos -->
    </infProt>
  </protNFe>
</nfeProc>
```

## Observações Importantes

1. **Namespaces:** Todos os elementos devem usar o namespace correto, sem prefixos desnecessários
2. **Ordem:** A ordem dos elementos é importante e deve ser respeitada
3. **Assinatura:** A assinatura deve incluir o `infNFeSupl` (QR Code) se presente
4. **Protocolo:** O `protNFe` só é adicionado após autorização pela SEFAZ
5. **Validação:** O `digVal` no `infProt` deve corresponder ao `DigestValue` na `Signature`

## Referências

- Manual de Integração do Contribuinte - NFC-e (versão 4.00)
- Especificação Técnica de Assinatura Digital XML (XML Signature)
- Padrão ICP-Brasil para Certificados Digitais












