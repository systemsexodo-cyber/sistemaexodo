# 🔍 Análise do XML do Lote

## 📋 Arquivo Analisado

**Arquivo:** `lote_enviNFe_20251209_102913.xml`

## ❌ Status: NÃO AUTORIZADO

**Resposta da SEFAZ:** `resposta_sefaz_cstat225_20251209_102914.xml`
**Código:** `cStat 225` - Rejeição: Falha no Schema XML do lote de NFe

## 🔍 Problemas Identificados no XML

### 1. **❌ idLote com apenas 1 dígito**

**Encontrado:**
```xml
<idLote>1</idLote>
```

**Esperado (Schema TRec):**
```xml
<idLote>000000000000001</idLote>
```

**Problema:** O schema exige exatamente 15 dígitos (`[0-9]{15}`), mas o XML tem apenas 1 dígito.

### 2. **✅ indSinc presente**

**Encontrado:**
```xml
<indSinc>1</indSinc>
```

**Status:** ✅ Correto (valor 1 para síncrono)

### 3. **⚠️ Valores decimais com muitas casas**

**Encontrado:**
```xml
<vUnCom>2.0000000000</vUnCom>
<vUnTrib>2.0000000000</vUnTrib>
```

**Esperado (Schema TDec_1302):**
```xml
<vUnCom>2.00</vUnCom>
<vUnTrib>2.00</vUnTrib>
```

**Problema:** Valores com 10 casas decimais, mas o schema exige máximo 2 casas decimais.

### 4. **⚠️ Valores inteiros sem casas decimais**

**Encontrado:**
```xml
<vBC>4</vBC>
<qCom>2</qCom>
```

**Esperado (Schema TDec_1302):**
```xml
<vBC>4.00</vBC>
```

**Nota:** Valores inteiros são aceitos pelo schema, mas é melhor usar `4.00` para consistência.

### 5. **⚠️ Campo cMunFG com valor incorreto**

**Encontrado:**
```xml
<cMunFG>Sao Jose dos Campos</cMunFG>
```

**Esperado:**
```xml
<cMunFG>3549904</cMunFG>
```

**Problema:** `cMunFG` deve ser o código IBGE do município (7 dígitos), não o nome da cidade.

### 6. **⚠️ Campo CRT vazio**

**Encontrado:**
```xml
<ns0:CRT/>
```

**Esperado:**
```xml
<ns0:CRT>1</ns0:CRT>
```

**Problema:** CRT (Código de Regime Tributário) é obrigatório e não pode estar vazio.

### 7. **⚠️ Duplicação de infNFe**

**Problema:** O XML contém duas tags `infNFe` dentro da mesma `NFe`:
- `NFe35251204829400000165650017652869541474046790`
- `NFe35251204829400000165650017652869541474046790_1200`

Isso é inválido - cada `NFe` deve conter apenas uma `infNFe`.

## 📊 Resumo dos Problemas

| Problema | Severidade | Status |
|----------|-----------|--------|
| idLote com 1 dígito (deve ter 15) | 🔴 CRÍTICO | ❌ |
| cMunFG com nome em vez de código IBGE | 🔴 CRÍTICO | ❌ |
| CRT vazio | 🔴 CRÍTICO | ❌ |
| Duplicação de infNFe | 🔴 CRÍTICO | ❌ |
| Valores decimais com muitas casas | 🟡 MÉDIO | ⚠️ |
| indSinc presente | ✅ OK | ✅ |

## 🔧 Correções Necessárias

### **1. Corrigir idLote**
```xml
<!-- ANTES -->
<idLote>1</idLote>

<!-- DEPOIS -->
<idLote>000000000000001</idLote>
```

### **2. Corrigir cMunFG**
```xml
<!-- ANTES -->
<cMunFG>Sao Jose dos Campos</cMunFG>

<!-- DEPOIS -->
<cMunFG>3549904</cMunFG>
```

### **3. Corrigir CRT**
```xml
<!-- ANTES -->
<ns0:CRT/>

<!-- DEPOIS -->
<ns0:CRT>1</ns0:CRT>
<!-- ou 2 ou 3, dependendo do regime tributário -->
```

### **4. Remover duplicação de infNFe**
Cada `NFe` deve conter apenas uma `infNFe`.

### **5. Corrigir valores decimais**
```xml
<!-- ANTES -->
<vUnCom>2.0000000000</vUnCom>

<!-- DEPOIS -->
<vUnCom>2.00</vUnCom>
```

## ✅ Conclusão

**Status:** ❌ **NÃO AUTORIZADO**

**Motivo:** Múltiplos problemas no schema XML:
1. `idLote` com apenas 1 dígito (deve ter 15)
2. `cMunFG` com nome em vez de código IBGE
3. `CRT` vazio (obrigatório)
4. Duplicação de `infNFe` na mesma `NFe`
5. Valores decimais com formato incorreto

**Ação:** Corrigir todos os problemas acima antes de reenviar.


























