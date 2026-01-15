# ✅ Correção do Erro 242 - "Mensagem SOAP inválida"

## 🔍 Problema Identificado

**Erro:** `cStat 242 - Rejeição: Mensagem SOAP inválida`

**Causa:** O envelope SOAP estava usando:
- ❌ Namespace SOAP 1.1 (`http://schemas.xmlsoap.org/soap/envelope/`)
- ❌ Content-Type `text/xml` (SOAP 1.1)
- ❌ Estrutura incorreta do envelope

## ✅ Correções Aplicadas

### 1. **Namespace SOAP 1.2** (Corrigido)

**Antes:**
```python
ns_soap = "http://schemas.xmlsoap.org/soap/envelope/"  # SOAP 1.1 ❌
```

**Depois:**
```python
ns_soap = "http://www.w3.org/2003/05/soap-envelope"  # SOAP 1.2 ✅
```

**Arquivo:** `nfce_manual_completo.py`  
**Linha:** ~400

### 2. **Content-Type Correto** (Corrigido)

**Antes:**
```python
headers = {
    "Content-Type": "text/xml; charset=utf-8",  # SOAP 1.1 ❌
}
```

**Depois:**
```python
headers = {
    "Content-Type": "application/soap+xml; charset=utf-8",  # SOAP 1.2 ✅
    "SOAPAction": "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote",
    "User-Agent": "Python-requests/2.31.0",
    "Accept": "application/soap+xml, text/xml, */*"
}
```

**Arquivo:** `nfce_manual_completo.py`  
**Linha:** ~441

### 3. **Estrutura do Envelope SOAP** (Melhorada)

**Correções:**
- ✅ Namespace correto para `nfeAutorizacaoLote` e `nfeDadosMsg`
- ✅ Melhor tratamento do XML (enviNFe vs NFe)
- ✅ Validação e fallback para diferentes formatos

**Arquivo:** `nfce_manual_completo.py`  
**Método:** `montar_envelope_soap()` (linhas ~389-450)

## 📋 Estrutura Correta do Envelope SOAP 1.2

```xml
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
               xmlns:nfe="http://www.portalfiscal.inf.br/nfe">
    <soap:Body>
        <nfe:nfeAutorizacaoLote xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
            <nfeDadosMsg>
                <enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
                    <idLote>123456789012345</idLote>
                    <indSinc>1</indSinc>
                    <NFe>
                        <!-- XML da NFC-e -->
                    </NFe>
                </enviNFe>
            </nfeDadosMsg>
        </nfe:nfeAutorizacaoLote>
    </soap:Body>
</soap:Envelope>
```

## 🔧 Mudanças Técnicas

### Namespace Correto
- **SOAP 1.2:** `http://www.w3.org/2003/05/soap-envelope`
- **NFe:** `http://www.portalfiscal.inf.br/nfe`
- **WSDL:** `http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4`

### Headers HTTP
- **Content-Type:** `application/soap+xml; charset=utf-8` (SOAP 1.2)
- **SOAPAction:** `http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote`
- **Accept:** `application/soap+xml, text/xml, */*`

## ✅ Teste

Após as correções, o erro 242 deve ser resolvido. O envelope SOAP agora está:
- ✅ Usando SOAP 1.2 (padrão SEFAZ)
- ✅ Com Content-Type correto
- ✅ Com estrutura XML válida
- ✅ Com namespaces corretos

## 📝 Arquivos Modificados

1. **nfce_manual_completo.py**
   - Método `montar_envelope_soap()` - Corrigido namespace e estrutura
   - Método `enviar_para_sefaz()` - Corrigido Content-Type e headers

## 🚀 Próximos Passos

1. Testar emissão novamente
2. Verificar se o erro 242 foi resolvido
3. Se ainda houver erro, verificar:
   - XML da NFC-e (validação XSD)
   - Certificado digital
   - Dados da empresa

---

**Correção aplicada!** Teste novamente a emissão. 🎉

















