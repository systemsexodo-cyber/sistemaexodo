# ✅ Correção do Erro: Município inválido

## 🔍 Problema Identificado

**Erro:** `ValueError: Município inválido SAO JOSE DOS CAMPOS/SP`

**Causa:** O PyNFe não encontra o município pelo nome porque:
1. O nome precisa estar exatamente como na base de dados do IBGE
2. O PyNFe normaliza o nome (remove acentos, converte para maiúsculas)
3. Se o nome não corresponder exatamente, lança erro

## ✅ Correção Aplicada

### Estratégia de Resolução

1. **Prioridade 1: Usar código IBGE** (se disponível)
   - Se temos `codigoIBGE`, usar `obter_municipio_por_codigo()` para obter o nome oficial
   - Isso garante que o nome está correto

2. **Prioridade 2: Normalizar nome** (se não temos código)
   - Normalizar o nome da cidade (remove acentos, maiúsculas)
   - Buscar código IBGE usando nome normalizado
   - Obter nome oficial do município usando o código encontrado

3. **Fallback: Usar nome original**
   - Se tudo falhar, usar o nome informado (pode gerar erro, mas tenta)

### Código Implementado

```python
# 1. Tentar usar código IBGE
if codigo_ibge:
    cidade = obter_municipio_por_codigo(codigo_ibge, uf)

# 2. Se não tem código, normalizar e buscar
else:
    cidade_normalizada = normalizar_municipio(cidade)
    codigo_encontrado = obter_codigo_por_municipio(cidade_normalizada, uf)
    cidade = obter_municipio_por_codigo(codigo_encontrado, uf)
```

## 📋 Arquivos Modificados

- ✅ `nfce_pynfe_completo.py` (método `_criar_emitente`)
  - Busca município usando código IBGE quando disponível
  - Normaliza nome quando código não está disponível
  - Logs detalhados para debug

## 🔍 Como Funciona

### Base de Dados do PyNFe
O PyNFe tem arquivos de municípios em `pynfe/data/Municipios/`:
- Formato: `MunIBGE-UF{numero}.txt`
- Cada linha: `{codigo_ibge}\t{nome_municipio}`

### Normalização
A função `normalizar_municipio()`:
- Remove acentos
- Converte para maiúsculas
- Remove caracteres especiais

Exemplo:
- "São José dos Campos" → "SAO JOSE DOS CAMPOS"
- "Sao Jose dos Campos" → "SAO JOSE DOS CAMPOS"

## ⚠️ Importante

**Sempre forneça o código IBGE do município!**

O Flutter já envia `codigo_municipio` (código IBGE), então o sistema deve funcionar automaticamente.

## ✅ Status

- ✅ Busca por código IBGE implementada
- ✅ Normalização de nome implementada
- ✅ Logs detalhados adicionados
- ✅ Fallback para nome original

---

**Correção aplicada!** Teste novamente a emissão. 🎉

















