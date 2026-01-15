# 🔍 Diagnóstico: Certificado Não Carrega

## Problema
O certificado não está carregando de forma nenhuma.

## Possíveis Causas

### 1. Certificado não está sendo salvo no Firebase
**Sintoma:** `certificadoDigitalBytes` é `null` quando tenta carregar

**Verificação:**
- Abra o console do Flutter
- Procure por `>>> [AdicionarEmpresa] Certificado salvo em base64`
- Verifique se aparece `>>> [Firebase] Empresa salva`

**Solução:**
- Verifique se o certificado foi selecionado antes de salvar
- Verifique se a empresa foi salva com sucesso
- Verifique se `_certificadoDigitalBytes` não é `null` antes de salvar

### 2. Certificado não está sendo carregado do Firebase
**Sintoma:** `certificadoDigitalBytes` é `null` quando tenta usar

**Verificação:**
- Abra o console do Flutter
- Procure por `>>> [AdicionarEmpresa] Carregando certificado da empresa:`
- Verifique se `certificadoDigitalBytes` aparece como `presente`

**Solução:**
- Verifique se o Firebase está salvando o `configuracoes` corretamente
- Verifique se o `fromMap` está carregando o `configuracoes` corretamente

### 3. Validação está bloqueando antes de tentar carregar
**Sintoma:** Erro antes de tentar carregar o certificado

**Verificação:**
- Abra o console do Flutter
- Procure por `>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...`
- Verifique qual fonte está ausente

**Solução:**
- Se Base64 ausente: Selecione o certificado novamente
- Se URL ausente: Não é problema se Base64 estiver presente
- Se Windows ausente: Não é problema se Base64 estiver presente

### 4. Certificado está sendo salvo mas não está sendo encontrado
**Sintoma:** Certificado salvo mas não encontrado na hora de usar

**Verificação:**
- Abra o console do Flutter
- Procure por `>>> [NFCe] Estado inicial:`
- Verifique se `certificadoBytes` aparece como `presente`

**Solução:**
- Verifique se o certificado está sendo salvo no `configuracoes` corretamente
- Verifique se o certificado está sendo carregado do `configuracoes` corretamente

## Logs para Verificar

### Ao Salvar Empresa:
```
>>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres
>>> [Firebase] Empresa salva: Nome da Empresa (ID: xxx)
```

### Ao Carregar Empresa:
```
>>> [AdicionarEmpresa] Carregando certificado da empresa:
>>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (XXXX chars)
```

### Ao Emitir NFC-e:
```
>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...
>>> [NFCe]   • Base64: ✓ presente
>>> [NFCe] Estado inicial:
>>> [NFCe]   certificadoBytes: presente (XXXX chars)
>>> [Certificado] INÍCIO: carregarCertificado
>>> [Certificado] certificadoDigitalBytes: presente (XXXX chars)
```

## Solução Rápida

1. **Verifique se o certificado está salvo:**
   - Vá em "Empresas" → Edite a empresa
   - Verifique se aparece o nome do certificado
   - Se não aparecer, selecione o certificado novamente

2. **Verifique os logs:**
   - Abra o console do Flutter
   - Procure por `>>> [NFCe] DIAGNÓSTICO`
   - Veja qual fonte está ausente

3. **Se Base64 estiver ausente:**
   - Selecione o certificado novamente
   - Salve a empresa
   - Tente emitir NFC-e novamente

4. **Se ainda não funcionar:**
   - Verifique se o Firebase está salvando o `configuracoes`
   - Verifique se o `fromMap` está carregando o `configuracoes`
   - Verifique se não há erro ao salvar no Firebase

## Correções Implementadas

1. ✅ Logs detalhados em cada etapa
2. ✅ Validação melhorada antes de carregar
3. ✅ Diagnóstico claro de qual fonte está ausente
4. ✅ Mensagens de erro mais informativas




