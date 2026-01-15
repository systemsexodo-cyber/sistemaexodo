# 📁 Organização de XMLs por Empresa

## 📋 Estrutura Implementada

Os XMLs das NFC-e agora são salvos organizados por empresa, facilitando a consulta e gestão dos arquivos.

### Estrutura de Diretórios

```
backend_pynfe/
└── logs/
    └── empresas/
        ├── {CNPJ_EMPRESA_1}/
        │   ├── lote_enviNFe_YYYYMMDD_HHMMSS.xml
        │   ├── lote_enviNFe_corrigido_YYYYMMDD_HHMMSS.xml
        │   ├── lote_enviNFe_corrigido_YYYYMMDD_HHMMSS_AVISOS.txt
        │   ├── resposta_sefaz_cstatXXX_YYYYMMDD_HHMMSS.xml
        │   └── resposta_sefaz_erro_parse_YYYYMMDD_HHMMSS.xml
        │
        ├── {CNPJ_EMPRESA_2}/
        │   ├── lote_enviNFe_YYYYMMDD_HHMMSS.xml
        │   ├── lote_enviNFe_corrigido_YYYYMMDD_HHMMSS.xml
        │   └── ...
        │
        └── sem_empresa/
            └── (XMLs quando não há dados da empresa)
```

## 🔍 Identificação da Empresa

O sistema identifica a empresa usando a seguinte ordem de prioridade:

1. **CNPJ** (preferencial)
   - Extrai o CNPJ dos dados da empresa
   - Remove caracteres não numéricos
   - Usa o CNPJ limpo como nome da pasta

2. **Razão Social** (se CNPJ não disponível)
   - Usa a razão social da empresa
   - Remove caracteres especiais
   - Limita a 50 caracteres
   - Substitui espaços por underscores

3. **ID da Empresa** (se disponível)
   - Usa o campo `id` ou `_id` dos dados da empresa

4. **Diretório Padrão** (fallback)
   - Se nenhuma informação estiver disponível, usa `sem_empresa`

## 📝 Arquivos Salvos por Empresa

### 1. XML do Lote Original
- **Nome**: `lote_enviNFe_YYYYMMDD_HHMMSS.xml`
- **Conteúdo**: XML do lote antes das correções
- **Quando**: Sempre que um lote é interceptado antes de enviar

### 2. XML do Lote Corrigido
- **Nome**: `lote_enviNFe_corrigido_YYYYMMDD_HHMMSS.xml`
- **Conteúdo**: XML do lote após correções automáticas
- **Quando**: Quando o sistema corrige problemas no XML

### 3. Arquivo de Avisos
- **Nome**: `lote_enviNFe_corrigido_YYYYMMDD_HHMMSS_AVISOS.txt`
- **Conteúdo**: Lista de problemas que não puderam ser corrigidos automaticamente
- **Quando**: Apenas se houver problemas não corrigidos

### 4. Resposta da SEFAZ
- **Nome**: `resposta_sefaz_cstatXXX_YYYYMMDD_HHMMSS.xml`
- **Conteúdo**: Resposta completa da SEFAZ
- **Quando**: Sempre que há uma resposta da SEFAZ

### 5. Resposta de Erro de Parse
- **Nome**: `resposta_sefaz_erro_parse_YYYYMMDD_HHMMSS.xml`
- **Conteúdo**: Resposta da SEFAZ quando há erro ao processar
- **Quando**: Quando há erro ao parsear a resposta XML

## 🎯 Benefícios

1. **Organização**: Cada empresa tem seus próprios XMLs organizados
2. **Facilidade de Consulta**: Fácil encontrar XMLs de uma empresa específica
3. **Histórico**: Mantém histórico completo de todas as emissões por empresa
4. **Debugging**: Facilita identificar problemas específicos de cada empresa
5. **Backup**: Pode fazer backup por empresa facilmente

## 📂 Exemplo de Uso

### Consultar XMLs de uma Empresa

```python
# Os XMLs são salvos automaticamente em:
# logs/empresas/{CNPJ}/lote_enviNFe_*.xml

# Exemplo para CNPJ 12345678000190:
# logs/empresas/12345678000190/lote_enviNFe_20251209_143022.xml
```

### Estrutura de Pastas por Empresa

Cada empresa terá uma pasta com:
- Todos os lotes enviados
- Todas as respostas da SEFAZ
- Todos os arquivos de correção e avisos

## 🔧 Implementação Técnica

### Função `_obter_diretorio_empresa()`

```python
def _obter_diretorio_empresa(self, empresa_data=None):
    """
    Obtém o diretório para salvar XMLs da empresa
    
    Args:
        empresa_data: Dicionário com dados da empresa
        
    Returns:
        Caminho do diretório da empresa
    """
    # Extrai CNPJ, razão social ou ID
    # Cria diretório: logs/empresas/{identificador}/
    # Retorna caminho completo
```

### Armazenamento de Dados da Empresa

O serviço armazena os dados da empresa atual em `self._empresa_data` para uso em todas as funções que precisam salvar arquivos.

## 📊 Estatísticas

Com essa organização, você pode:
- Contar quantas NFC-e cada empresa emitiu
- Verificar histórico completo de uma empresa
- Identificar padrões de erros por empresa
- Fazer análises específicas por empresa

## 🚀 Próximos Passos

1. **Consulta de XMLs**: Implementar função para listar XMLs de uma empresa
2. **Busca por Data**: Filtrar XMLs por data de emissão
3. **Estatísticas**: Gerar relatórios por empresa
4. **Backup Automático**: Implementar backup automático por empresa

---

**Última atualização:** 2025-12-09
**Status:** ✅ Implementado e funcionando



























