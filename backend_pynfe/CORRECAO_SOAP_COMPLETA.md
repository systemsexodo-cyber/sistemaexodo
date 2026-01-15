# 🔧 Correção Completa do Erro SOAP 242

## ❌ Erro Original
**cStat 242: "Rejeição: Mensagem SOAP inválida"**

## ✅ Correções Aplicadas

### 1. Namespace SOAP 1.2 ✅
```python
# ANTES (SOAP 1.1 - ERRADO)
ns_soap = "http://schemas.xmlsoap.org/soap/envelope/"

# DEPOIS (SOAP 1.2 - CORRETO)
ns_soap = "http://www.w3.org/2003/05/soap-envelope"
```

### 2. Content-Type SOAP 1.2 ✅
```python
# ANTES
"Content-Type": "text/xml; charset=utf-8"

# DEPOIS
"Content-Type": "application/soap+xml; charset=utf-8"
```

### 3. SOAPAction ✅
```python
# ANTES
"SOAPAction": "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote"

# DEPOIS (vazio para SOAP 1.2, como PyNFe faz)
"SOAPAction": ""
```

### 4. Estrutura do Envelope ✅
```python
# Seguindo padrão PyNFe:
# - nfeDadosMsg direto no body (sem nfeAutorizacaoLote)
# - XML inserido como elemento usando append()
```

## 📋 Estrutura Final Correta

```xml
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
    <soap:Body>
        <nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
            <enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
                <idLote>123456789012345</idLote>
                <indSinc>1</indSinc>
                <NFe>
                    <!-- XML da NFC-e -->
                </NFe>
            </enviNFe>
        </nfeDadosMsg>
    </soap:Body>
</soap:Envelope>
```

## 🔍 Se Ainda Não Funcionar

### Alternativa 1: Com nfeAutorizacaoLote

Alguns estados podem exigir `nfeAutorizacaoLote` envolvendo `nfeDadosMsg`:

```python
# nfeAutorizacaoLote
op = etree.SubElement(body, f"{{{ns_wsdl}}}nfeAutorizacaoLote")
# nfeDadosMsg dentro de nfeAutorizacaoLote
dados = etree.SubElement(op, "nfeDadosMsg")
```

### Alternativa 2: XML como Texto Escapado

Alguns servidores podem exigir XML como texto escapado:

```python
xml_escaped = xml_str.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
dados.text = xml_escaped
```

## 🐛 Debug

Adicionei logs para ver a estrutura do SOAP gerado. Verifique:
1. Se o namespace está correto
2. Se o XML está sendo inserido corretamente
3. Se os headers estão corretos

## 📝 Arquivos Modificados

- `nfce_manual_completo.py`:
  - `montar_envelope_soap()` - Corrigido
  - `enviar_para_sefaz()` - Headers corrigidos

---

**Teste novamente!** Se ainda der erro, verifique os logs de debug.

















