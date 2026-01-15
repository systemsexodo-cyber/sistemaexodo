# Melhorias no Tratamento de Erros HTTP 400

## 📋 Resumo das Melhorias

O sistema foi aprimorado para capturar e processar **mensagens detalhadas de rejeição** da SEFAZ, mesmo quando o status HTTP é 400.

## ✅ O que foi implementado:

### 1. **Processamento de Resposta HTTP 400**

A SEFAZ pode retornar HTTP 400 com XML válido contendo detalhes da rejeição. O sistema agora:

- ✅ Processa a resposta XML mesmo quando o status é 400
- ✅ Extrai mensagens detalhadas de rejeição (cStat, xMotivo)
- ✅ Salva XML de resposta para debug
- ✅ Fornece diagnóstico completo com sugestões

### 2. **Função de Extração de Erros Básicos**

Nova função `_extrair_erro_basico_resposta()` que:

- Tenta extrair informações mesmo se o XML estiver malformado
- Busca cStat e xMotivo em múltiplos locais:
  - Diretamente no XML
  - Dentro de `retEnviNFe`
  - Dentro de `protNFe/infProt`
  - Dentro de `Fault` (erro SOAP)

### 3. **Diagnóstico Completo**

O sistema agora retorna informações detalhadas:

```python
{
    'success': False,
    'error': 'Rejeição 225: Falha no Schema XML do lote de NFe',
    'error_type': 'HTTPError',
    'status_code': 400,
    'codigo_erro': '225',
    'diagnostico': {
        'sugestao': 'Verifique a mensagem de rejeição detalhada acima. Ajuste os dados da nota...',
        'url_sefaz': 'https://...',
        'erro_parse': '...'
    }
}
```

## 🔍 Como Funciona

### Fluxo de Processamento:

1. **Envio para SEFAZ**
   - Envia envelope SOAP
   - Recebe resposta (pode ser HTTP 200 ou 400)

2. **Validação de Resposta**
   - Se HTTP 400 e resposta vazia → Retorna erro de conexão
   - Se HTTP 400 com conteúdo → Tenta processar XML

3. **Processamento de XML**
   - Tenta parse completo usando `processar_resposta_sefaz()`
   - Se falhar, usa `_extrair_erro_basico_resposta()` como fallback

4. **Extração de Informações**
   - Busca cStat e xMotivo em múltiplos locais
   - Monta mensagem de erro detalhada
   - Adiciona sugestões de correção

## 📝 Exemplos de Uso

### Erro HTTP 400 com XML Válido:

```python
# A SEFAZ retorna HTTP 400, mas o XML contém:
# <retEnviNFe>
#   <cStat>225</cStat>
#   <xMotivo>Rejeição: Falha no Schema XML do lote de NFe</xMotivo>
# </retEnviNFe>

# O sistema processa e retorna:
{
    'success': False,
    'error': 'Rejeição 225: Falha no Schema XML do lote de NFe',
    'codigo_erro': '225',
    'status_code': 400,
    'diagnostico': {
        'sugestao': 'Ajuste os dados da nota conforme indicado...'
    }
}
```

### Erro HTTP 400 com Resposta Vazia:

```python
# Se a resposta estiver vazia:
{
    'success': False,
    'error': 'Erro HTTP 400: Resposta vazia da SEFAZ. Pode ser problema de conexão ou configuração.',
    'status_code': 400,
    'diagnostico': {
        'sugestao': 'Verifique a URL da SEFAZ e aguarde alguns minutos antes de tentar novamente.',
        'url_sefaz': 'https://...'
    }
}
```

## 🎯 Benefícios

1. **Mensagens Mais Claras**
   - Usuário vê exatamente qual campo está com problema
   - Código de rejeição (cStat) é sempre extraído quando disponível

2. **Melhor Debug**
   - XML de resposta é salvo para análise
   - Logs detalhados de cada etapa

3. **Sugestões de Correção**
   - Sistema fornece sugestões baseadas no tipo de erro
   - Indica URL da SEFAZ para verificação

4. **Robustez**
   - Funciona mesmo se o XML estiver parcialmente malformado
   - Múltiplas estratégias de extração de informações

## 🔧 Soluções Implementadas

### 1. Verificar Mensagem de Rejeição Detalhada
✅ **Implementado**: Sistema extrai automaticamente cStat e xMotivo da resposta

### 2. Ajustar Dados da Nota
✅ **Implementado**: Mensagens de erro indicam qual campo precisa ser corrigido

### 3. Aguardar e Tentar Novamente
✅ **Implementado**: Sugestões incluem aguardar antes de retentar

### 4. Verificar URL e Extensões
✅ **Implementado**: URL da SEFAZ é incluída no diagnóstico

### 5. Contato com Suporte Técnico
✅ **Implementado**: XMLs são salvos para análise técnica

## 📁 Arquivos Modificados

- `nfce_manual_completo.py`:
  - Função `emitir()`: Melhorado tratamento de HTTP 400
  - Nova função `_extrair_erro_basico_resposta()`: Extração robusta de erros

## 🚀 Próximos Passos

1. Testar com diferentes tipos de rejeição da SEFAZ
2. Adicionar mais códigos de erro específicos com sugestões personalizadas
3. Melhorar logs para facilitar diagnóstico remoto












