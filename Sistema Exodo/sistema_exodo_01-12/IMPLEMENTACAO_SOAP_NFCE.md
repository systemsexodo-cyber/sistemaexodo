# 🔧 Implementação Manual NFC-e via SOAP SEFAZ

## 📚 Bibliotecas Necessárias

Adicionar ao `pubspec.yaml`:

```yaml
dependencies:
  # Já temos:
  xml: ^6.4.2              # Geração de XML
  http: ^1.1.0             # Comunicação SOAP
  
  # Adicionar:
  pointycastle: ^3.7.3     # Criptografia e assinatura digital
  asn1lib: ^1.5.0         # Manipulação de certificados
  qr_flutter: ^4.1.0      # Geração de QR Code
  pdf: ^3.10.7             # Geração do DANFE-NFC-e
  printing: ^5.12.0       # Impressão do DANFE
  crypto: ^3.0.3           # Funções criptográficas
  path_provider: ^2.1.1    # Acesso a diretórios do sistema
```

## 🏗️ Estrutura do Projeto

```
lib/
  services/
    nfce_service.dart          # Serviço principal
    sefaz_service.dart          # Comunicação SOAP com SEFAZ
    certificado_service.dart    # Manipulação de certificado
    assinatura_service.dart     # Assinatura digital XML
  models/
    nfce.dart                   # Modelo da NFC-e
    nfce_item.dart              # Item da NFC-e
    nfce_pagamento.dart         # Forma de pagamento
  utils/
    xml_builder.dart            # Construtor de XML
    qr_code_generator.dart      # Gerador de QR Code
    danfe_generator.dart        # Gerador do DANFE
```

## 📋 Fluxo de Emissão

1. **Montar XML da NFC-e** (conforme layout oficial)
2. **Assinar XML** com certificado digital
3. **Enviar para SEFAZ** via WebService SOAP
4. **Receber retorno** (autorizada, rejeitada, denegada)
5. **Gerar QR Code** (se autorizada)
6. **Armazenar XML** (obrigatório por 5 anos)
7. **Imprimir DANFE-NFC-e** (opcional)

## 🔐 Assinatura Digital

A assinatura digital usa **XML Signature (XMLDSig)**:
- Algoritmo: RSA-SHA256
- Formato: PKCS#7
- Certificado: ICP-Brasil (A1 ou A3)

## 🌐 WebServices SEFAZ

### URLs por Estado (Homologação):

- **SP:** https://homologacao.nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx
- **RJ:** https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx
- **MG:** https://hnfce.fazenda.mg.gov.br/nfce/services/NFeAutorizacao4
- **RS:** https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx

### URLs por Estado (Produção):

- **SP:** https://nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx
- **RJ:** https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx
- **MG:** https://nfce.fazenda.mg.gov.br/nfce/services/NFeAutorizacao4
- **RS:** https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx

## 📝 Layout XML NFC-e

Estrutura básica conforme Manual de Integração:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<NFe xmlns="http://www.portalfiscal.inf.br/nfe">
  <infNFe Id="NFe..." versao="4.00">
    <ide>
      <cUF>35</cUF>
      <cNF>...</cNF>
      <mod>65</mod>
      <serie>1</serie>
      <nNF>...</nNF>
      <dhEmi>...</dhEmi>
      <tpNF>1</tpNF>
      <idDest>1</idDest>
      <cMunFG>...</cMunFG>
      <tpImp>4</tpImp>
      <tpEmis>1</tpEmis>
      <cDV>...</cDV>
      <tpAmb>2</tpAmb>
      <finNFe>1</finNFe>
      <indFinal>1</indFinal>
      <indPres>1</indPres>
      <procEmi>0</procEmi>
      <verProc>...</verProc>
    </ide>
    <emit>
      <CNPJ>...</CNPJ>
      <xNome>...</xNome>
      <xFant>...</xFant>
      <enderEmit>
        <xLgr>...</xLgr>
        <nro>...</nro>
        <xBairro>...</xBairro>
        <cMun>...</cMun>
        <xMun>...</xMun>
        <UF>...</UF>
        <CEP>...</CEP>
      </enderEmit>
      <IE>...</IE>
      <CRT>1</CRT>
    </emit>
    <dest>
      <CPF>...</CPF>
      <xNome>...</xNome>
    </dest>
    <det>
      <!-- Itens da venda -->
    </det>
    <total>
      <ICMSTot>
        <vBC>0.00</vBC>
        <vICMS>0.00</vICMS>
        <vICMSDeson>0.00</vICMSDeson>
        <vFCP>0.00</vFCP>
        <vBCST>0.00</vBCST>
        <vST>0.00</vST>
        <vFCPST>0.00</vFCPST>
        <vFCPSTRet>0.00</vFCPSTRet>
        <vProd>...</vProd>
        <vFrete>0.00</vFrete>
        <vSeg>0.00</vSeg>
        <vDesc>0.00</vDesc>
        <vII>0.00</vII>
        <vIPI>0.00</vIPI>
        <vIPIDevol>0.00</vIPIDevol>
        <vPIS>0.00</vPIS>
        <vCOFINS>0.00</vCOFINS>
        <vOutro>0.00</vOutro>
        <vNF>...</vNF>
        <vTotTrib>0.00</vTotTrib>
      </ICMSTot>
    </total>
    <pag>
      <!-- Formas de pagamento -->
    </pag>
    <infAdic>
      <infCpl>...</infCpl>
    </infAdic>
  </infNFe>
  <Signature xmlns="http://www.w3.org/2000/09/xmldsig#">
    <!-- Assinatura digital -->
  </Signature>
</NFe>
```

## 🔑 Campos Obrigatórios

### Identificação (ide):
- cUF (Código do Estado)
- cNF (Código numérico)
- mod (Modelo = 65 para NFC-e)
- serie (Série)
- nNF (Número da NFC-e)
- dhEmi (Data/hora de emissão)
- tpNF (Tipo = 1 para saída)
- idDest (Destino = 1 para interna)
- cMunFG (Código do município)
- tpImp (Tipo de impressão = 4 para NFC-e)
- tpEmis (Tipo de emissão = 1 normal)
- cDV (Dígito verificador)
- tpAmb (Ambiente = 1 produção, 2 homologação)
- finNFe (Finalidade = 1 normal)
- indFinal (Consumidor final = 1 sim, 0 não)
- indPres (Presença = 1 presencial)
- procEmi (Processo de emissão = 0 próprio)
- verProc (Versão do processo)

### Emitente (emit):
- CNPJ
- xNome (Razão Social)
- xFant (Nome Fantasia)
- enderEmit (Endereço completo)
- IE (Inscrição Estadual)
- CRT (Código de Regime Tributário)

### Destinatário (dest):
- CPF ou CNPJ (opcional para NFC-e)
- xNome (opcional)

### Itens (det):
- prod (Produto)
  - cProd (Código)
  - cEAN (GTIN/EAN)
  - xProd (Descrição)
  - NCM
  - CFOP
  - uCom (Unidade comercial)
  - qCom (Quantidade)
  - vUnCom (Valor unitário)
  - vProd (Valor total)
  - cEANTrib (GTIN tributável)
  - uTrib (Unidade tributável)
  - qTrib (Quantidade tributável)
  - vUnTrib (Valor unitário tributável)
  - vFrete (Frete)
  - vSeg (Seguro)
  - vDesc (Desconto)
  - vOutro (Outros)
  - indTot (Indicador de totalização)
- imposto (Impostos)
  - ICMS
  - IPI
  - PIS
  - COFINS

### Total (total):
- ICMSTot (Totais de impostos)
  - vProd (Valor dos produtos)
  - vNF (Valor total da NFC-e)

### Pagamento (pag):
- detPag (Detalhe do pagamento)
  - tPag (Tipo de pagamento)
  - vPag (Valor pago)

## 🚀 Próximos Passos

1. Adicionar bibliotecas ao pubspec.yaml
2. Criar estrutura de pastas
3. Implementar leitura de certificado
4. Implementar assinatura digital
5. Implementar geração de XML
6. Implementar comunicação SOAP
7. Implementar tratamento de retorno
8. Implementar geração de QR Code
9. Implementar geração de DANFE

