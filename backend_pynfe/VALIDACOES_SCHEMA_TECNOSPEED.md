# ✅ Validações de Schema XML - Baseado em Tecnospeed

## 📚 Referência

Baseado no artigo: [Como identificar e corrigir falha no Schema XML da NF-e e NFC-e](https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/)

## 🔍 Validações Implementadas

### 1. **Validação de Valores Decimais**

**Problema:** Valores decimais devem ter exatamente 2 casas decimais conforme schema XSD.

**Exemplo do artigo:**
- ❌ **ERRADO:** `<vCOFINS>0.000</vCOFINS>` (3 casas decimais)
- ✅ **CORRETO:** `<vCOFINS>0.00</vCOFINS>` (2 casas decimais)

**Padrão:** TDec_1302 (13 dígitos antes da vírgula e 2 após)

**Campos validados:**
- `vProd`, `vUnCom`, `vUnTrib`
- `vFrete`, `vSeg`, `vDesc`, `vOutro`
- `vBC`, `vICMS`, `vICMSDeson`, `vFCP`
- `vBCST`, `vST`, `vFCPST`
- `vIPI`, `vPIS`, `vCOFINS`
- `vNF`, `vTotTrib`
- `vPag`, `vTroco`, `vLiq`
- E outros campos monetários

**Função:** `_validar_valores_decimais_xml()`

### 2. **Validação de Caracteres Proibidos**

**Problema:** Caracteres especiais como `*`, `/`, `?`, `!` não são permitidos em campos de texto.

**Campos validados:**
- `xNome`, `xFant`, `xProd`
- `xLgr`, `xBairro`, `xMun`, `xPais`
- `infCpl`, `infAdProd`, `xObs`

**Ações:**
- Remove caracteres proibidos automaticamente
- Remove quebras de linha e espaços extras
- Normaliza espaços em branco

**Função:** `_validar_caracteres_proibidos()`

### 3. **Validação de Estrutura XML**

**Validações realizadas:**

#### **A. Tamanho do Arquivo**
- Verifica se o XML não excede 500 KB (recomendado)
- Gera aviso se exceder

#### **B. Formatação XML**
- Valida que é XML válido (parse bem-sucedido)
- Verifica tags sem espaços indevidos
- Valida fechamento de tags

#### **C. Namespace e Versão**
- Verifica namespace correto: `http://www.portalfiscal.inf.br/nfe`
- Verifica versão: `4.00`

**Função:** `_validar_estrutura_xml_completa()`

## 📋 Motivos de Falha no Schema XML

Conforme o artigo da Tecnospeed, os principais motivos são:

### 1. **Valor informado inválido**
- ✅ **Corrigido:** Validação e correção automática de valores decimais

### 2. **Campo obrigatório ausente**
- ⚠️ **Parcial:** Validação básica implementada, pode precisar expansão

### 3. **Campo informado no bloco incorreto**
- ⚠️ **Parcial:** Validação de estrutura básica implementada

### 4. **Uso de caracteres proibidos ou formatação incorreta**
- ✅ **Corrigido:** Remoção automática de caracteres proibidos

### 5. **Erros no fechamento de tags XML**
- ✅ **Corrigido:** Validação de estrutura XML

### 6. **Tamanho do arquivo XML excedendo o limite**
- ✅ **Corrigido:** Verificação de tamanho com aviso

## 🔧 Como Funciona

### **Fluxo de Validação:**

1. **XML é interceptado** antes de enviar para SEFAZ
2. **Correções básicas aplicadas:**
   - `idLote` com 15 dígitos
   - `indSinc` adicionado
   - Ordem dos elementos corrigida
3. **Validações adicionais (Tecnospeed):**
   - Valores decimais corrigidos (2 casas)
   - Caracteres proibidos removidos
   - Estrutura XML validada
4. **XML corrigido é enviado** para SEFAZ

### **Logs Gerados:**

```
>>> [PyNFe] ✅ Valor decimal corrigido: vCOFINS de "0.000" para "0.00"
>>> [PyNFe] ✅ Texto corrigido: xProd
>>> [PyNFe] ✅ XML corrigido está estruturalmente correto!
```

## 📝 Exemplo de Correção

### **Antes (ERRADO):**
```xml
<vCOFINS>0.000</vCOFINS>
<xProd>Produto * Especial / Teste?</xProd>
```

### **Depois (CORRETO):**
```xml
<vCOFINS>0.00</vCOFINS>
<xProd>Produto Especial Teste</xProd>
```

## ⚠️ Importante

- As validações são aplicadas **automaticamente** antes de enviar
- Logs detalhados mostram todas as correções aplicadas
- Se ainda houver erro 225, verifique:
  1. Campos obrigatórios ausentes
  2. Campos no bloco incorreto
  3. Outros problemas não cobertos pelas validações automáticas

## 🔗 Referências

- [Artigo Tecnospeed - Falha no Schema XML](https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/)
- Schema XSD oficial da SEFAZ
- Manual de Orientação ao Contribuinte (MOC)

## ✅ Benefícios

1. **Correção automática** de valores decimais
2. **Remoção automática** de caracteres proibidos
3. **Validação completa** da estrutura XML
4. **Logs detalhados** para debug
5. **Redução de erros** 225 por schema inválido


























