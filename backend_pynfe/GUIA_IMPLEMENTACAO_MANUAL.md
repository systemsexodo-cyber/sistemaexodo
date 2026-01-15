# 📘 Guia Completo - Implementação Manual NFC-e

## 🎯 Visão Geral

Este guia explica como usar a implementação **100% manual em Python** para emitir NFC-e, sem depender de PyNFe, ACBr ou outros wrappers.

## ✅ O que está implementado

1. ✅ **Geração de XML completo** conforme leiaute 4.00
2. ✅ **Assinatura digital** com certificado A1 (.pfx) usando XML-DSig
3. ✅ **Montagem de envelope SOAP** para serviços SEFAZ
4. ✅ **Envio HTTPS** para SEFAZ SP (homologação e produção)
5. ✅ **Processamento de resposta** (autorização, rejeição, protocolo)
6. ✅ **Geração de QR Code** URL

## 📦 Instalação

### 1. Instalar dependências

```bash
pip install -r requirements_manual.txt
```

Ou manualmente:

```bash
pip install lxml signxml requests pyOpenSSL cryptography urllib3
```

### 2. Verificar instalação

```python
from nfce_manual_completo import NFCeManualCompleto
print("✅ Módulo carregado com sucesso")
```

## 🚀 Uso Básico

### Exemplo Mínimo

```python
from nfce_manual_completo import NFCeManualCompleto

# 1. Criar instância
nfce = NFCeManualCompleto()

# 2. Carregar certificado
nfce.carregar_certificado(
    certificado_base64="BASE64_DO_CERTIFICADO",
    senha="senha123"
)

# 3. Dados da empresa
empresa_data = {
    'cnpj': '12345678000190',
    'razao_social': 'Minha Empresa LTDA',
    'uf': 'SP',
    # ... outros dados
}

# 4. Produtos
produtos = [
    {
        'codigo': '001',
        'descricao': 'Produto 1',
        'quantidade': 1.0,
        'valor_unitario': 10.00,
        # ... outros dados
    }
]

# 5. Pagamentos
pagamentos = [
    {'tipo': '01', 'valor': 10.00}  # 01 = Dinheiro
]

# 6. Emitir
resultado = nfce.emitir(
    empresa_data=empresa_data,
    produtos=produtos,
    pagamentos=pagamentos,
    numero_nfce=1
)

# 7. Verificar resultado
if resultado['success']:
    print(f"✅ Autorizada: {resultado['chave_acesso']}")
else:
    print(f"❌ Erro: {resultado['error']}")
```

## 📋 Campos Obrigatórios

### Empresa (empresa_data)

- ✅ `cnpj` - CNPJ (14 dígitos)
- ✅ `razao_social` - Razão social
- ✅ `uf` - Estado (ex: 'SP')
- ✅ `inscricao_estadual` - Inscrição estadual
- ✅ `codigo_municipio_ibge` - Código IBGE (7 dígitos)
- ✅ `endereco`, `numero`, `bairro`, `cidade`, `cep`
- ✅ `certificado_base64` - Certificado em base64 (ou usar `carregar_certificado()`)
- ✅ `senhaCertificado` - Senha do certificado
- ✅ `ambienteHomologacao` - True/False

### Produto

- ✅ `codigo` - Código do produto
- ✅ `descricao` - Descrição
- ✅ `ncm` - NCM (8 dígitos)
- ✅ `cfop` - CFOP (4 dígitos)
- ✅ `unidade` - Unidade (ex: 'UN')
- ✅ `quantidade` - Quantidade
- ✅ `valor_unitario` - Valor unitário
- ✅ `valor_total` - Valor total
- ✅ `icms` - Dados ICMS (origem, cst, aliquota)

### Pagamento

- ✅ `tipo` - Tipo de pagamento (01=Dinheiro, 03=Cartão, etc.)
- ✅ `valor` - Valor do pagamento

## 🔐 Certificado Digital

### Opção 1: Base64

```python
nfce.carregar_certificado(
    certificado_base64="BASE64_DO_CERTIFICADO_PFX",
    senha="senha123"
)
```

### Opção 2: Arquivo

```python
nfce.carregar_certificado_arquivo(
    caminho_arquivo="certificado.pfx",
    senha="senha123"
)
```

### Requisitos do Certificado

- ✅ Tipo: A1 (arquivo .pfx) ou A3 (token/cartão)
- ✅ Válido e não expirado
- ✅ CNPJ deve corresponder ao CNPJ da empresa
- ✅ ICP-Brasil

## 🌐 URLs SEFAZ SP

### Homologação

- Autorização: `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx`
- Retorno: `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx`
- Consulta: `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx`
- Status: `https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx`
- QR Code: `https://homologacao.nfce.fazenda.sp.gov.br/qrcode`

### Produção

- Autorização: `https://nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx`
- Retorno: `https://nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx`
- Consulta: `https://nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx`
- Status: `https://nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx`
- QR Code: `https://nfce.fazenda.sp.gov.br/qrcode`

## 📊 Estrutura do XML

O sistema gera XML no formato `enviNFe` conforme leiaute 4.00:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <idLote>...</idLote>
  <NFe versao="4.00">
    <infNFe Id="NFe..." versao="4.00">
      <ide>...</ide>
      <emit>...</emit>
      <dest>...</dest>
      <det>...</det>
      <total>...</total>
      <pag>...</pag>
    </infNFe>
    <Signature>...</Signature>
  </NFe>
</enviNFe>
```

## 🔍 Processamento de Resposta

A resposta da SEFAZ é processada automaticamente:

### Autorizada (cStat = 100)

```python
{
    'success': True,
    'autorizada': True,
    'status': 'autorizada',
    'chave_acesso': '...',
    'protocolo': '...',
    'mensagem': 'Autorizada',
    'qrcode_url': '...',
    'xml': '...'
}
```

### Rejeitada

```python
{
    'success': False,
    'autorizada': False,
    'status': 'rejeitada',
    'error': 'Motivo da rejeição',
    'codigo_erro': '225',
    'xml_resposta': '...'
}
```

## 🎨 QR Code

O QR Code é gerado automaticamente após autorização:

```python
if resultado['success']:
    qrcode_url = resultado['qrcode_url']
    # URL format: https://homologacao.nfce.fazenda.sp.gov.br/qrcode?p=CHAVE_ACESSO
```

## ⚠️ Validações Importantes

### XML

- ✅ Todos os campos obrigatórios devem estar preenchidos
- ✅ Valores devem estar no formato correto (2 casas decimais)
- ✅ Datas no formato ISO 8601
- ✅ CNPJ/CPF sem formatação (apenas números)

### Certificado

- ✅ Deve estar válido
- ✅ CNPJ deve corresponder
- ✅ Senha correta

### SEFAZ

- ✅ Ambiente correto (homologação/produção)
- ✅ Certificado configurado na requisição
- ✅ XML bem formado

## 🐛 Troubleshooting

### Erro: "Certificado não foi carregado"

**Solução:** Carregue o certificado antes de emitir:
```python
nfce.carregar_certificado(certificado_base64, senha)
```

### Erro: "infNFe não encontrado no XML"

**Solução:** Verifique se o XML está no formato correto (enviNFe > NFe > infNFe)

### Erro HTTP 403/404

**Solução:** 
- Verifique se a URL está correta
- Verifique se o certificado está configurado
- Verifique ambiente (homologação/produção)

### Erro: "Rejeição 225"

**Solução:** Verifique estrutura do XML e campos obrigatórios

## 📚 Referências

- Manual de Integração NFC-e: https://portal.fazenda.sp.gov.br/servicos/nfce
- Schemas XSD: https://www.nfe.fazenda.gov.br/portal/listaConteudo.aspx?tipoConteudo=/WsNFe/listaConteudo
- Portal SVRS: https://www.nfce.fazenda.sp.gov.br

## ✅ Status

- ✅ Geração XML completa
- ✅ Assinatura digital
- ✅ Envio SOAP
- ✅ Processamento resposta
- ✅ QR Code
- ⚠️ Cancelamento (a implementar)
- ⚠️ Inutilização (a implementar)
- ⚠️ Eventos (a implementar)

---

**Pronto para uso em homologação!** 🚀



















