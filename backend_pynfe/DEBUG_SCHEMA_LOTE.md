# 🔍 Debug do Schema do Lote - Erro 225

## 📋 Como Verificar o XML que Está Sendo Enviado

### 1. **Localização dos Arquivos XML**

O sistema salva automaticamente os XMLs em:
```
backend_pynfe/logs/empresas/{CNPJ}/lote_enviNFe_{timestamp}.xml
backend_pynfe/logs/empresas/{CNPJ}/lote_enviNFe_corrigido_{timestamp}.xml
```

### 2. **Verificar o XML Corrigido**

Abra o arquivo `lote_enviNFe_corrigido_{timestamp}.xml` e verifique:

#### **A. Estrutura do enviNFe**
```xml
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
    <idLote>000000000000001</idLote>  <!-- Deve ter 15 dígitos -->
    <indSinc>1</indSinc>               <!-- Deve existir e ter valor 1 -->
    <NFe>
        <!-- Conteúdo da NFC-e -->
    </NFe>
</enviNFe>
```

#### **B. Verificações Obrigatórias**

1. **idLote:**
   - ✅ Deve existir
   - ✅ Deve ser o primeiro elemento
   - ✅ Deve ter exatamente 15 dígitos
   - ❌ Se tiver menos de 15 dígitos, está ERRADO

2. **indSinc:**
   - ✅ Deve existir
   - ✅ Deve ser o segundo elemento
   - ✅ Deve ter valor `'1'`
   - ❌ Se não existir, está ERRADO

3. **NFe:**
   - ✅ Deve existir
   - ✅ Deve ser o terceiro elemento
   - ✅ Deve ter namespace correto

4. **Versão:**
   - ✅ Deve ser `"4.00"`

5. **Namespace:**
   - ✅ Deve ser `"http://www.portalfiscal.inf.br/nfe"`

### 3. **Verificar o Envelope SOAP**

Se o XML estiver dentro de um envelope SOAP, verifique:

```xml
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
    <soap:Body>
        <nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
            <!-- Aqui deve estar o enviNFe completo -->
            <enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
                <idLote>000000000000001</idLote>
                <indSinc>1</indSinc>
                <NFe>...</NFe>
            </enviNFe>
        </nfeDadosMsg>
    </soap:Body>
</soap:Envelope>
```

### 4. **Problemas Comuns**

#### **Problema 1: idLote com menos de 15 dígitos**
```xml
<!-- ERRADO -->
<idLote>1</idLote>

<!-- CORRETO -->
<idLote>000000000000001</idLote>
```

#### **Problema 2: indSinc ausente**
```xml
<!-- ERRADO -->
<enviNFe>
    <idLote>000000000000001</idLote>
    <NFe>...</NFe>
</enviNFe>

<!-- CORRETO -->
<enviNFe>
    <idLote>000000000000001</idLote>
    <indSinc>1</indSinc>
    <NFe>...</NFe>
</enviNFe>
```

#### **Problema 3: Ordem incorreta dos elementos**
```xml
<!-- ERRADO -->
<enviNFe>
    <NFe>...</NFe>
    <idLote>000000000000001</idLote>
    <indSinc>1</indSinc>
</enviNFe>

<!-- CORRETO -->
<enviNFe>
    <idLote>000000000000001</idLote>
    <indSinc>1</indSinc>
    <NFe>...</NFe>
</enviNFe>
```

### 5. **Validar XML com Ferramenta Externa**

1. **Validador da SEFAZ RS:**
   - Acesse: https://www.sefaz.rs.gov.br/NFE/NFE-VAL.aspx
   - Cole o XML do `enviNFe` (sem o envelope SOAP)
   - Clique em "Validar"
   - Verifique os erros reportados

2. **Validador Online:**
   - Use ferramentas online de validação XML
   - Verifique contra o schema XSD oficial

### 6. **Logs do Sistema**

O sistema gera logs detalhados no console. Procure por:

```
>>> [PyNFe] XML DO LOTE INTERCEPTADO E SALVO
>>> [PyNFe] XML DO LOTE CORRIGIDO
>>> [PyNFe] ENVIANDO REQUISIÇÃO PARA SEFAZ
```

Verifique se:
- ✅ `idLote` tem 15 dígitos
- ✅ `indSinc` está presente
- ✅ Ordem dos elementos está correta

### 7. **Se o Problema Persistir**

1. **Copie o XML completo** do arquivo `lote_enviNFe_corrigido_{timestamp}.xml`
2. **Valide manualmente** com o validador da SEFAZ
3. **Verifique os logs** para ver se as correções foram aplicadas
4. **Compare** com um exemplo de lote correto

### 8. **Exemplo de Lote Correto Completo**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
    <idLote>000000000000001</idLote>
    <indSinc>1</indSinc>
    <NFe xmlns="http://www.portalfiscal.inf.br/nfe">
        <infNFe Id="NFe35170123456789000123550010000000011000000001" versao="4.00">
            <ide>
                <cUF>35</cUF>
                <cNF>00000001</cNF>
                <natOp>VENDA</natOp>
                <mod>65</mod>
                <serie>1</serie>
                <nNF>1</nNF>
                <!-- ... outros campos ... -->
            </ide>
            <!-- ... resto da NFC-e ... -->
        </infNFe>
    </NFe>
</enviNFe>
```

## ⚠️ Importante

- O sistema tenta corrigir automaticamente, mas se o problema persistir, verifique manualmente o XML gerado
- Sempre valide o XML antes de reenviar
- Os logs mostram exatamente o que está sendo enviado


























