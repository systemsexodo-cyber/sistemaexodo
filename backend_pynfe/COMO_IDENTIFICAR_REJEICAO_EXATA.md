# 🔍 Como Identificar a Rejeição Exata da SEFAZ

## 📋 Problema

O erro 225 "Falha no Schema XML do lote de NFe" é genérico. Para corrigir o problema, precisamos saber **exatamente** o que está errado no XML do lote.

## ✅ Solução Implementada

Implementei um sistema completo de logs e salvamento de arquivos para análise:

### 1. XML do Lote Salvo Automaticamente

Quando você tentar emitir uma NFC-e, o sistema agora:

- ✅ **Salva o XML completo do lote** em `backend_pynfe/logs/lote_enviNFe_YYYYMMDD_HHMMSS.xml`
- ✅ **Mostra o XML completo** nos logs do console
- ✅ **Analisa a estrutura** do lote automaticamente

### 2. Análise Detalhada do Lote

O sistema analisa automaticamente:

- ✅ Versão do lote (deve ser 4.00)
- ✅ Namespace do lote
- ✅ Presença de `idLote`
- ✅ Presença de `NFe` dentro do lote
- ✅ Estrutura da NFe (ide, emit, det, total, pag)
- ✅ Lista todos os elementos filhos do `enviNFe`

### 3. Resposta da SEFAZ Salva

Quando há erro 225, o sistema também:

- ✅ **Salva a resposta completa da SEFAZ** em `backend_pynfe/logs/resposta_sefaz_erro225_YYYYMMDD_HHMMSS.xml`
- ✅ **Extrai todos os campos** da resposta (cStat, xMotivo, verAplic, cUF, dhRecbto, etc.)
- ✅ **Mostra informações detalhadas** nos logs

## 🔍 Como Usar

### Passo 1: Tentar Emitir NFC-e

Tente emitir uma NFC-e normalmente. O sistema automaticamente:

1. Intercepta o XML do lote antes de enviar
2. Salva o XML em arquivo
3. Mostra análise detalhada nos logs
4. Salva a resposta da SEFAZ se houver erro

### Passo 2: Verificar os Logs

No console, você verá:

```
>>> [PyNFe] ========================================
>>> [PyNFe] XML DO LOTE INTERCEPTADO E SALVO
>>> [PyNFe] ========================================
>>> [PyNFe] Arquivo salvo em: .../logs/lote_enviNFe_20251209_120000.xml
>>> [PyNFe] Tamanho: 12345 caracteres
>>> [PyNFe] ========================================
>>> [PyNFe] XML COMPLETO DO LOTE:
>>> [PyNFe] ========================================
<?xml version="1.0" encoding="UTF-8"?>
<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <idLote>1</idLote>
  <NFe>
    ...
  </NFe>
</enviNFe>
>>> [PyNFe] ========================================
>>> [PyNFe] ANÁLISE DETALHADA DO LOTE
>>> [PyNFe] ========================================
>>> [PyNFe] Versão do lote: 4.00
>>> [PyNFe] ✅ Versão correta: 4.00
>>> [PyNFe] Namespace do lote: http://www.portalfiscal.inf.br/nfe
>>> [PyNFe] ✅ ID do lote: 1
>>> [PyNFe] ✅ NFe encontrada dentro do lote
>>> [PyNFe] Elementos da NFe:
>>> [PyNFe]   - ide: ✅
>>> [PyNFe]   - emit: ✅
>>> [PyNFe]   - det (produtos): ✅ (2 itens)
>>> [PyNFe]   - total: ✅
>>> [PyNFe]   - pag: ✅
>>> [PyNFe] Elementos filhos do enviNFe:
>>> [PyNFe]   - idLote: 1
>>> [PyNFe]   - NFe: ...
```

### Passo 3: Verificar Arquivos Salvos

Os arquivos são salvos em:
- `backend_pynfe/logs/lote_enviNFe_YYYYMMDD_HHMMSS.xml` - XML do lote enviado
- `backend_pynfe/logs/resposta_sefaz_erro225_YYYYMMDD_HHMMSS.xml` - Resposta da SEFAZ (se houver erro)

### Passo 4: Analisar o XML do Lote

Abra o arquivo `lote_enviNFe_*.xml` e verifique:

1. **Estrutura básica**:
   ```xml
   <enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
     <idLote>1</idLote>
     <NFe>
       ...
     </NFe>
   </enviNFe>
   ```

2. **Verificar**:
   - ✅ Namespace correto: `http://www.portalfiscal.inf.br/nfe`
   - ✅ Versão correta: `4.00`
   - ✅ `idLote` presente e válido
   - ✅ `NFe` presente dentro do `enviNFe`
   - ✅ Estrutura da NFe completa

3. **Problemas comuns**:
   - ❌ Namespace incorreto ou ausente
   - ❌ Versão diferente de 4.00
   - ❌ `idLote` ausente ou inválido
   - ❌ `NFe` ausente ou malformada
   - ❌ Elementos na ordem errada
   - ❌ Elementos obrigatórios faltando

### Passo 5: Validar contra Schema XSD

Para validação completa, você pode validar o XML contra o schema XSD oficial:

1. **Baixar schema XSD**:
   - Schema do lote: `enviNFe_v4.00.xsd`
   - Disponível em: http://www.nfe.fazenda.gov.br/portal/listaConteudo.aspx?tipoConteudo=/9qk5qOqZkE=

2. **Validar XML**:
   ```python
   from lxml import etree
   
   # Carregar schema
   schema = etree.XMLSchema(file='enviNFe_v4.00.xsd')
   
   # Validar XML do lote
   xml_lote = etree.parse('logs/lote_enviNFe_*.xml')
   schema.assertValid(xml_lote)  # Levanta exceção se inválido
   ```

## 📝 Exemplo de Logs de Erro 225

Quando ocorre erro 225, você verá:

```
>>> [PyNFe] ========================================
>>> [PyNFe] RESPOSTA DA SEFAZ - DETALHES COMPLETOS
>>> [PyNFe] ========================================
>>> [PyNFe] Código de status (cStat): 225
>>> [PyNFe] tpAmb: 2
>>> [PyNFe] verAplic: SP_NFCE_PL_009_V400
>>> [PyNFe] xMotivo: Rejeição: Falha no Schema XML do lote de NFe
>>> [PyNFe] cUF: 35
>>> [PyNFe] dhRecbto: 2025-12-09T12:00:00-03:00
>>> [PyNFe] ========================================
>>> [PyNFe] ❌ ERRO 225: Falha no Schema XML do lote
>>> [PyNFe] ========================================
>>> [PyNFe] Resposta completa salva em: .../logs/resposta_sefaz_erro225_20251209_120000.xml
>>> [PyNFe] Motivo detalhado: Rejeição: Falha no Schema XML do lote de NFe
```

## 🎯 Próximos Passos

Com os arquivos XML salvos, você pode:

1. **Comparar com exemplos oficiais** da SEFAZ
2. **Validar contra schema XSD** para identificar problemas específicos
3. **Analisar estrutura** para encontrar elementos faltando ou incorretos
4. **Corrigir o PyNFe** ou fazer patch no XML antes de enviar

## 🔧 Correção do Problema

Uma vez identificado o problema exato:

1. **Se for problema do PyNFe**: Fazer patch ou atualizar o PyNFe
2. **Se for problema de estrutura**: Corrigir antes de enviar
3. **Se for problema de namespace**: Ajustar namespace do lote
4. **Se for problema de versão**: Garantir versão 4.00

---

**Última atualização:** 2025-12-09
**Status:** ✅ Sistema de logs e salvamento implementado




























