# Próximos Passos para Emitir NFC-e Após Lote Processado

## Situação Atual

O lote da NFC-e foi enviado e processado pela SEFAZ. Agora é necessário obter o protocolo de autorização para finalizar a emissão.

## Fluxo de Emissão NFC-e

### 1. Envio do Lote (já realizado)
- ✅ XML da NFC-e foi gerado
- ✅ XML foi assinado digitalmente
- ✅ Lote foi enviado para a SEFAZ
- ✅ Lote foi processado (cStat=104)

### 2. Resposta da SEFAZ

A SEFAZ pode retornar dois tipos de resposta:

#### **Cenário A: Resposta Síncrona (indSinc=1)**
Quando `cStat=104` (Lote processado), a SEFAZ retorna:
- `retEnviNFe` com `cStat=104`
- `protNFe` dentro do `retEnviNFe` com o protocolo de autorização
- `infProt` dentro do `protNFe` com:
  - `cStat` da nota (100=Autorizada, 150=Autorizada fora do prazo)
  - `chNFe` (chave de acesso)
  - `nProt` (número do protocolo)

**Próximo passo:** O código já processa automaticamente este caso e finaliza a emissão.

#### **Cenário B: Resposta Assíncrona (indSinc=0) ou Lote Recebido (cStat=103)**
Quando `cStat=103` (Lote recebido com sucesso), a SEFAZ retorna:
- `retEnviNFe` com `cStat=103`
- `infRec` com `nRec` (número do recibo)

**Próximo passo:** É necessário consultar o recibo para obter o protocolo.

## Como Consultar o Recibo

### Passo 1: Aguardar Processamento
- Aguardar **mínimo de 15 segundos** após o envio do lote (conforme manual SEFAZ)
- Isso evita o erro 105 "Lote em Processamento"

### Passo 2: Consultar o Recibo
Usar o método `consulta_recibo` do PyNFe:

```python
from pynfe.processamento.comunicacao import ComunicacaoSefaz

# Criar comunicação
comunicacao = ComunicacaoSefaz(uf, cert_path, senha, ambiente)

# Consultar recibo (nRec é o número do recibo retornado)
resultado = comunicacao.consulta_recibo(
    modelo="nfce",
    numero=nRec,  # Número do recibo
    contingencia=False
)
```

### Passo 3: Processar Resposta do Recibo
A resposta do recibo contém:
- `retConsReciNFe` com `cStat=104` (Lote processado)
- `protNFe` dentro do `retConsReciNFe` com o protocolo de autorização

## Implementação no Código

O código já está preparado para:

1. ✅ Detectar quando `cStat=104` (Lote processado)
2. ✅ Buscar `protNFe` na resposta usando múltiplas estratégias
3. ✅ Processar o protocolo de autorização quando encontrado
4. ✅ Construir o `nfeProc` completo (NFe + protNFe)
5. ✅ Salvar o XML autorizado
6. ✅ Retornar dados para impressão

### Melhorias Implementadas

1. **Busca Robusta do protNFe:**
   - Busca direta como filho
   - Busca recursiva
   - Busca por iteração manual (ignora namespaces)

2. **Logs Detalhados:**
   - Mostra estrutura do XML quando não encontra
   - Salva XML de resposta para debug
   - Indica onde está o problema

3. **Tratamento de Erros:**
   - Mensagens descritivas
   - Sugestões de solução
   - Salvamento de XMLs para análise

## Próximos Passos Manuais (se necessário)

Se o código não conseguir processar automaticamente:

### 1. Verificar XMLs Salvos
Verifique os XMLs salvos em:
- `logs/debug/xml_lote_*.xml` - XML do lote enviado
- `logs/debug/resposta_sefaz_*.xml` - Resposta da SEFAZ
- `logs/xmls_empresas/[CNPJ]/` - XMLs por empresa

### 2. Consultar Recibo Manualmente
Se você tem o número do recibo (`nRec`), pode consultar manualmente:

```python
# No código Python
from pynfe.processamento.comunicacao import ComunicacaoSefaz

comunicacao = ComunicacaoSefaz(uf, cert_path, senha, ambiente)
resultado = comunicacao.consulta_recibo("nfce", nRec, False)
```

### 3. Verificar Status da Nota
Se você tem a chave de acesso, pode consultar o status:

```python
comunicacao.consulta_nota("nfce", chave_acesso, False)
```

## Estrutura do XML Autorizado (nfeProc)

Após obter o protocolo, o XML final deve ter esta estrutura:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
  <NFe>
    <!-- XML da NFC-e assinado -->
  </NFe>
  <protNFe versao="4.00">
    <infProt>
      <tpAmb>2</tpAmb>
      <verAplic>...</verAplic>
      <chNFe>...</chNFe>
      <dhRecbto>...</dhRecbto>
      <nProt>...</nProt>
      <digVal>...</digVal>
      <cStat>100</cStat>
      <xMotivo>Autorizado o uso da NFC-e</xMotivo>
    </infProt>
  </protNFe>
</nfeProc>
```

## Status da Nota (cStat)

- **100**: Autorizado o uso da NFC-e
- **150**: Autorizado fora do prazo
- **110**: Denegada
- **301**: Uso Denegado: Irregularidade fiscal do emitente
- Outros: Rejeição (ver motivo em xMotivo)

## Checklist de Emissão

- [ ] XML da NFC-e gerado
- [ ] XML assinado digitalmente
- [ ] Lote enviado para SEFAZ
- [ ] Lote processado (cStat=104) ou recebido (cStat=103)
- [ ] Protocolo de autorização obtido (protNFe)
- [ ] Nota autorizada (cStat=100 ou 150)
- [ ] nfeProc construído (NFe + protNFe)
- [ ] XML autorizado salvo
- [ ] Chave de acesso extraída
- [ ] Protocolo extraído
- [ ] QR Code gerado (se necessário)
- [ ] Dados retornados para impressão

## Solução de Problemas

### Problema: protNFe não encontrado
**Solução:**
1. Verifique o XML de resposta em `logs/debug/`
2. Verifique se o namespace está correto
3. Tente consultar o recibo se tiver o nRec

### Problema: Nota rejeitada
**Solução:**
1. Verifique o `cStat` e `xMotivo` na resposta
2. Corrija o problema indicado
3. Reenvie a nota

### Problema: Lote em processamento
**Solução:**
1. Aguarde mais tempo (mínimo 15 segundos)
2. Consulte o recibo novamente
3. Verifique se o lote foi realmente processado

## Referências

- Manual do Validador SEFAZ
- Documentação PyNFe
- Esquemas XSD da NFe 4.00












