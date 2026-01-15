# ✅ Verificação do Schema do Lote - Checklist

## 📋 Checklist de Validação

Após emitir uma NFC-e, verifique os seguintes pontos:

### 1. **Verificar Arquivos Gerados**

Os arquivos são salvos em:
```
backend_pynfe/logs/empresas/{CNPJ}/lote_enviNFe_corrigido_{timestamp}.xml
```

### 2. **Estrutura Obrigatória do enviNFe**

Abra o arquivo `lote_enviNFe_corrigido_{timestamp}.xml` e verifique:

#### ✅ **A. Elemento raiz enviNFe**
```xml
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
```
- ✅ Namespace: `http://www.portalfiscal.inf.br/nfe`
- ✅ Versão: `4.00`

#### ✅ **B. idLote (PRIMEIRO elemento)**
```xml
<idLote>000000000000001</idLote>
```
- ✅ Deve ser o **primeiro elemento**
- ✅ Deve ter **exatamente 15 dígitos**
- ✅ Apenas números (0-9)
- ❌ **ERRADO:** `<idLote>1</idLote>` (1 dígito)
- ✅ **CORRETO:** `<idLote>000000000000001</idLote>` (15 dígitos)

#### ✅ **C. indSinc (SEGUNDO elemento)**
```xml
<indSinc>1</indSinc>
```
- ✅ Deve ser o **segundo elemento**
- ✅ Deve ter valor `1` (síncrono)
- ✅ Obrigatório para NFC-e
- ❌ **ERRADO:** Ausente
- ✅ **CORRETO:** `<indSinc>1</indSinc>`

#### ✅ **D. NFe (TERCEIRO elemento)**
```xml
<NFe xmlns="http://www.portalfiscal.inf.br/nfe">
    <infNFe Id="NFe..." versao="4.00">
        <!-- Conteúdo da NFC-e -->
    </infNFe>
</NFe>
```
- ✅ Deve ser o **terceiro elemento**
- ✅ Deve conter `infNFe` dentro
- ✅ Namespace correto

### 3. **Ordem dos Elementos (CRÍTICO)**

A ordem **DEVE** ser exatamente:
1. `idLote`
2. `indSinc`
3. `NFe`

❌ **ERRADO:**
```xml
<enviNFe>
    <NFe>...</NFe>
    <idLote>1</idLote>
    <indSinc>1</indSinc>
</enviNFe>
```

✅ **CORRETO:**
```xml
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
    <idLote>000000000000001</idLote>
    <indSinc>1</indSinc>
    <NFe xmlns="http://www.portalfiscal.inf.br/nfe">
        <infNFe Id="NFe..." versao="4.00">
            <!-- Conteúdo -->
        </infNFe>
    </NFe>
</enviNFe>
```

### 4. **Verificar Logs do Console**

Procure por estas mensagens nos logs:

```
>>> [PyNFe] ✅ idLote adicionado: 000000000000001 (15 dígitos)
>>> [PyNFe] ✅ indSinc adicionado: 1 (síncrono)
>>> [PyNFe] ✅ idLote com 15 dígitos confirmado no XML final
>>> [PyNFe] ✅ indSinc confirmado no XML final
```

Se aparecer:
```
>>> [PyNFe] ❌ ERRO: indSinc NÃO encontrado no XML final!
```
**PROBLEMA:** O XML não está sendo corrigido corretamente.

### 5. **Validar XML Manualmente**

1. **Copie o conteúdo** do arquivo `lote_enviNFe_corrigido_{timestamp}.xml`
2. **Remova o envelope SOAP** (se houver), deixando apenas o `enviNFe`
3. **Valide no validador da SEFAZ:**
   - https://www.sefaz.rs.gov.br/NFE/NFE-VAL.aspx
   - Cole o XML do `enviNFe`
   - Clique em "Validar"
   - Verifique os erros reportados

### 6. **Problemas Comuns e Soluções**

#### **Problema 1: idLote com menos de 15 dígitos**
**Sintoma:** `<idLote>1</idLote>`
**Solução:** Sistema corrige automaticamente para `000000000000001`

#### **Problema 2: indSinc ausente**
**Sintoma:** Não há elemento `<indSinc>`
**Solução:** Sistema adiciona automaticamente `<indSinc>1</indSinc>`

#### **Problema 3: Ordem incorreta**
**Sintoma:** `NFe` aparece antes de `idLote` ou `indSinc`
**Solução:** Sistema reordena automaticamente

#### **Problema 4: Namespace incorreto**
**Sintoma:** Namespace diferente de `http://www.portalfiscal.inf.br/nfe`
**Solução:** Sistema corrige automaticamente

### 7. **Se o Problema Persistir**

1. **Copie o XML completo** do arquivo `lote_enviNFe_corrigido_{timestamp}.xml`
2. **Copie os logs** do console (últimas 100 linhas)
3. **Verifique:**
   - Se o `idLote` tem 15 dígitos
   - Se o `indSinc` está presente
   - Se a ordem está correta
   - Se o namespace está correto

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

- O sistema tenta corrigir automaticamente, mas **sempre verifique** o XML gerado
- Os logs mostram exatamente o que está sendo enviado
- Se o erro 225 persistir, o problema pode estar em outro lugar (ex: dentro da NFe)

## 📝 Próximos Passos

1. Teste a emissão novamente
2. Verifique o arquivo `lote_enviNFe_corrigido_{timestamp}.xml`
3. Compare com o exemplo acima
4. Se ainda houver erro, envie o XML completo para análise


























