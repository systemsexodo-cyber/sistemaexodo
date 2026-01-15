# 🔧 Correção Final: cMunFG, CRT, Decimais e Caracteres Proibidos

## 📋 Problema Identificado

As correções de `cMunFG`, `CRT`, valores decimais e caracteres proibidos estavam sendo aplicadas ao `nfe_val` (elemento parseado do XML corrigido), mas o XML estava sendo regenerado a partir do `envi_nfe` original, que não tinha essas correções. Isso causava o erro `cStat 225` porque o XML enviado para a SEFAZ ainda continha os problemas.

## ✅ Solução Implementada

### **Correções Aplicadas Diretamente ao `nfe_elem`**

As correções agora são aplicadas **ANTES** de regenerar o XML, diretamente ao `inf_nfe` dentro do `nfe_elem` que está dentro do `envi_nfe`:

1. **cMunFG** (linhas 1635-1663):
   - Verifica se é nome em vez de código IBGE
   - Obtém código IBGE do emitente (`cMun`)
   - Se não encontrar, usa código padrão `3549904` (São José dos Campos)
   - Garante que seja um código de 7 dígitos

2. **CRT** (linhas 1665-1688):
   - Remove elementos `CRT` vazios
   - Cria ou corrige `CRT` para `'1'` (Simples Nacional) se estiver ausente ou vazio

3. **Valores Decimais** (linhas 1690-1697):
   - Aplica validação `_validar_valores_decimais_xml` diretamente ao `inf_nfe`
   - Garante formato `TDec_1302` (13 dígitos antes, 2 depois do ponto decimal)

4. **Caracteres Proibidos** (linhas 1699-1706):
   - Aplica validação `_validar_caracteres_proibidos` diretamente ao `inf_nfe`
   - Remove caracteres proibidos do XML

## 🔄 Fluxo de Correção

```
1. XML interceptado (com problemas)
   ↓
2. Parsear XML e encontrar `envi_nfe`
   ↓
3. Encontrar `nfe_elem` dentro de `envi_nfe`
   ↓
4. Encontrar `inf_nfe` dentro de `nfe_elem`
   ↓
5. Aplicar correções DIRETAMENTE ao `inf_nfe`:
   - cMunFG (nome → código IBGE)
   - CRT (vazio → "1")
   - Valores decimais (formato TDec_1302)
   - Caracteres proibidos (remover)
   ↓
6. Regenerar XML a partir do `envi_nfe` corrigido
   ↓
7. XML corrigido enviado para SEFAZ ✅
```

## 📝 Localização das Correções

- **Arquivo**: `services/nfce_service.py`
- **Função**: `post_interceptado` (dentro de `emitir_nfce`)
- **Linhas**: 1635-1706

## ✅ Resultado Esperado

Com essas correções, o XML enviado para a SEFAZ deve conter:
- ✅ `cMunFG` com código IBGE de 7 dígitos (ex: `3549904`)
- ✅ `CRT` com valor `'1'` (sem elementos vazios)
- ✅ Valores decimais no formato correto (`TDec_1302`)
- ✅ Sem caracteres proibidos
- ✅ `idLote` com 15 dígitos
- ✅ `indSinc` com valor `'1'`
- ✅ Ordem correta: `idLote`, `indSinc`, `NFe`

## 🧪 Teste

Ao emitir uma NFC-e, verifique nos logs:
- `>>> [PyNFe] ✅ cMunFG corrigido: "Sao Jose dos Campos" → "3549904"`
- `>>> [PyNFe] ✅ CRT corrigido/criado: "1"`
- `>>> [PyNFe] ✅ Valores decimais corrigidos na infNFe`
- `>>> [PyNFe] ✅ Caracteres proibidos removidos da infNFe`

O XML corrigido será salvo em:
- `logs/empresas/{CNPJ}/lote_enviNFe_corrigido_{timestamp}.xml`

## 📅 Data da Correção

2025-12-09


























