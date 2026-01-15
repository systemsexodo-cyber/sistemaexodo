# 🔍 O Que É o Erro SOAP e Como Foi Corrigido

## ❓ O Que É o Erro SOAP?

**Erro 242: "Mensagem SOAP inválida"**

Este erro acontece quando a SEFAZ recebe um **envelope SOAP malformado**. O SOAP (Simple Object Access Protocol) é o protocolo usado para comunicação com os web services da SEFAZ.

## 🔴 Problemas Identificados

### 1. **Namespace SOAP Incorreto**
- ❌ **Estava usando:** SOAP 1.1 (`http://schemas.xmlsoap.org/soap/envelope/`)
- ✅ **Corrigido para:** SOAP 1.2 (`http://www.w3.org/2003/05/soap-envelope`)
- **Por quê?** A SEFAZ usa SOAP 1.2, não 1.1

### 2. **Content-Type Incorreto**
- ❌ **Estava usando:** `text/xml; charset=utf-8` (SOAP 1.1)
- ✅ **Corrigido para:** `application/soap+xml; charset=utf-8` (SOAP 1.2)
- **Por quê?** SOAP 1.2 exige `application/soap+xml`

### 3. **Estrutura do Envelope**
- ❌ Namespaces incorretos para `nfeAutorizacaoLote` e `nfeDadosMsg`
- ✅ Corrigido para usar namespace correto do WSDL

## ✅ Correções Aplicadas

### Arquivo: `nfce_manual_completo.py`

#### 1. Método `montar_envelope_soap()` (linhas 389-468)

**ANTES:**
```python
ns_soap = "http://schemas.xmlsoap.org/soap/envelope/"  # SOAP 1.1 ❌
```

**DEPOIS:**
```python
ns_soap = "http://www.w3.org/2003/05/soap-envelope"  # SOAP 1.2 ✅
ns_wsdl = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4"
```

#### 2. Método `enviar_para_sefaz()` (linhas 487-491)

**ANTES:**
```python
headers = {
    "Content-Type": "text/xml; charset=utf-8",  # SOAP 1.1 ❌
    "SOAPAction": "..."
}
```

**DEPOIS:**
```python
headers = {
    "Content-Type": "application/soap+xml; charset=utf-8",  # SOAP 1.2 ✅
    "SOAPAction": "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote",
    "User-Agent": "Python-requests/2.31.0",
    "Accept": "application/soap+xml, text/xml, */*"
}
```

## 📋 Estrutura Correta do Envelope SOAP 1.2

```xml
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
               xmlns:nfe="http://www.portalfiscal.inf.br/nfe">
    <soap:Body>
        <nfeAutorizacaoLote xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
            <nfeDadosMsg>
                <enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
                    <idLote>123456789012345</idLote>
                    <indSinc>1</indSinc>
                    <NFe>
                        <!-- XML da NFC-e assinado -->
                    </NFe>
                </enviNFe>
            </nfeDadosMsg>
        </nfeAutorizacaoLote>
    </soap:Body>
</soap:Envelope>
```

## 🔧 Diferenças Entre SOAP 1.1 e 1.2

| Item | SOAP 1.1 ❌ | SOAP 1.2 ✅ |
|------|-------------|-------------|
| **Namespace** | `http://schemas.xmlsoap.org/soap/envelope/` | `http://www.w3.org/2003/05/soap-envelope` |
| **Content-Type** | `text/xml` | `application/soap+xml` |
| **Padrão** | Antigo | Atual (SEFAZ usa este) |

## ✅ Status das Correções

- ✅ Namespace SOAP corrigido (1.1 → 1.2)
- ✅ Content-Type corrigido
- ✅ Headers HTTP melhorados
- ✅ Estrutura do envelope corrigida
- ✅ Namespaces do WSDL corrigidos

## 🚀 Próximo Passo

**Teste novamente a emissão!** O erro 242 deve estar resolvido.

Se ainda houver erro, pode ser:
- XML da NFC-e com problemas (validação XSD)
- Certificado digital inválido
- Dados da empresa incorretos

---

**Todas as correções foram aplicadas!** 🎉

















