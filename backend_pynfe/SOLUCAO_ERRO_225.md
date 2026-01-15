# 🔧 Solução para Erro cStat 225 - Falha no Schema XML do lote de NFe

## 📋 Descrição do Problema

O erro **cStat 225** indica que o XML do lote (enviNFe) gerado pelo PyNFe não está de acordo com o schema XSD esperado pela SEFAZ.

### Mensagem de Erro
```
Rejeição: Falha no Schema XML do lote de NFe
```

## 🔍 Possíveis Causas

1. **Namespace incorreto** no elemento `enviNFe`
2. **Versão do schema incorreta** (deve ser 4.00)
3. **Elementos obrigatórios faltando** ou na ordem errada
4. **Problema na montagem do lote** pelo PyNFe

## ✅ Soluções Implementadas

### 1. Validação Robusta do XML Antes de Enviar

Adicionada validação completa do XML da nota antes de enviar para a SEFAZ:

- ✅ Verificação da versão (deve ser 4.00)
- ✅ Verificação do Id (chave de acesso)
- ✅ Verificação de elementos obrigatórios:
  - `ide` (identificação)
  - `emit` (emitente)
  - `det` (produtos)
  - `total` (totalização)
  - `pag` (pagamento - obrigatório para NFC-e)

### 2. Tratamento Melhorado de Erros

Melhorado o tratamento de erros para identificar especificamente o erro 225:

- ✅ Detecção específica do código 225
- ✅ Mensagens de erro mais detalhadas
- ✅ Logs informativos sobre possíveis causas
- ✅ Extração correta do motivo da rejeição da SEFAZ

### 3. Logs Detalhados

Adicionados logs mais detalhados para facilitar o diagnóstico:

- ✅ Logs antes de enviar para SEFAZ
- ✅ Logs da estrutura do XML
- ✅ Logs da resposta da SEFAZ
- ✅ Logs específicos para erro 225

## 🔧 Próximos Passos (Se o Problema Persistir)

Se o erro 225 continuar ocorrendo após essas melhorias, pode ser necessário:

### 1. Verificar Versão do PyNFe

O PyNFe pode ter um bug conhecido na montagem do lote. Verificar se há atualizações:

```bash
pip install --upgrade git+https://github.com/TadaSoftware/PyNFe.git
```

### 2. Verificar Estrutura do Lote Gerado

Adicionar logs para ver o XML do lote que está sendo enviado:

```python
# No método autorizacao() do PyNFe, adicionar log do XML do lote
# Isso requer modificar o código do PyNFe ou fazer monkey patch
```

### 3. Validar XML do Lote com Schema XSD

Validar o XML do lote gerado pelo PyNFe contra o schema XSD oficial:

```python
from lxml import etree
from lxml.etree import XMLSchema

# Carregar schema XSD
schema = XMLSchema(file='schema/enviNFe_v4.00.xsd')

# Validar XML do lote
schema.validate(xml_lote)
```

### 4. Usar Versão Alternativa do PyNFe

Se o problema persistir, considerar usar uma versão alternativa ou fazer fork do PyNFe com correções.

## 📝 Logs de Debug

Os logs agora incluem informações detalhadas:

```
>>> [PyNFe] ========================================
>>> [PyNFe] PREPARAÇÃO PARA AUTORIZAÇÃO
>>> [PyNFe] ========================================
>>> [PyNFe] Modelo: nfce (65)
>>> [PyNFe] ID Lote: 1
>>> [PyNFe] Ind Sinc: 1 (síncrono)
>>> [PyNFe] Ambiente: Homologação
>>> [PyNFe] UF: SP
>>> [PyNFe] ========================================
```

E quando o erro 225 ocorrer:

```
>>> [PyNFe] ❌ ERRO 225: Falha no Schema XML do lote
>>> [PyNFe] Isso geralmente indica que o XML do lote (enviNFe) está com estrutura incorreta
>>> [PyNFe] Possíveis causas:
>>> [PyNFe]   1. Namespace incorreto no elemento enviNFe
>>> [PyNFe]   2. Versão do schema incorreta
>>> [PyNFe]   3. Elementos obrigatórios faltando ou na ordem errada
>>> [PyNFe]   4. Problema na montagem do lote pelo PyNFe
```

## 🎯 Como Testar

1. Tentar emitir uma NFC-e novamente
2. Verificar os logs detalhados no console
3. Se o erro 225 persistir, verificar:
   - Versão do PyNFe instalada
   - Estrutura do XML do lote gerado
   - Schema XSD oficial da SEFAZ

## 📚 Referências

- [Manual de Integração NFC-e](http://www.nfce.sefaz.ce.gov.br/integracoes-homologacao/)
- [Schema XSD NFe 4.00](http://www.nfe.fazenda.gov.br/portal/listaConteudo.aspx?tipoConteudo=/9qk5qOqZkE=)
- [PyNFe GitHub](https://github.com/TadaSoftware/PyNFe)

---

**Última atualização:** 2025-12-09
**Status:** ✅ Melhorias implementadas - Aguardando testes




























