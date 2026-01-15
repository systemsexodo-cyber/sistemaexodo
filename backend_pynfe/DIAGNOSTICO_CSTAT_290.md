# Diagnóstico do Erro cStat=290 - Certificado de Assinatura Inválido

## Visão Geral

O erro **cStat=290** indica que a SEFAZ rejeitou a NFC-e porque o certificado digital usado na assinatura é considerado inválido. Este documento ajuda a diagnosticar e resolver o problema.

## Causas Possíveis

### 1. Certificado Expirado ou Ainda Não Válido

**Sintomas:**
- Certificado passou da data de validade
- Certificado ainda não entrou em vigor

**Solução:**
- Verificar a validade do certificado (o sistema agora faz isso automaticamente)
- Se expirado, adquirir novo certificado junto a uma autoridade certificadora credenciada na ICP-Brasil
- Se ainda não válido, aguardar até a data de início da validade

**Como verificar:**
O sistema agora valida automaticamente e exibe:
```
[VALIDAÇÃO 1/5] Verificando validade do certificado...
   📋 Válido de: 01/01/2024 00:00:00
   📋 Válido até: 31/12/2025 23:59:59
   📋 Data atual: 15/06/2024 10:30:00
   ✅ Certificado válido por mais 564 dias
```

### 2. Certificado Não é ICP-Brasil

**Sintomas:**
- Certificado não foi emitido por autoridade certificadora credenciada na ICP-Brasil

**Solução:**
- Usar apenas certificados emitidos por autoridades credenciadas na ICP-Brasil
- Verificar o issuer do certificado

**Como verificar:**
O sistema agora verifica e exibe:
```
[VALIDAÇÃO 2/5] Verificando se é certificado ICP-Brasil...
   ✅ Certificado parece ser ICP-Brasil (issuer: AC Certisign...)
```

### 3. Inconsistência de CNPJ

**Sintomas:**
- CNPJ do certificado não corresponde ao CNPJ da empresa

**Solução:**
- Verificar se o certificado pertence à empresa correta
- Se houver troca do responsável legal, o certificado anterior pode ter sido invalidado
- Usar o certificado correto para a empresa

**Como verificar:**
O sistema agora compara automaticamente e exibe:
```
⚠️ AVISO: INCONSISTÊNCIA DE CNPJ
   📋 CNPJ do certificado: 12345678000190
   📋 CNPJ da empresa: 98765432000110
   ⚠️ Os CNPJs não coincidem!
```

### 4. Problemas na Cadeia de Certificação

**Sintomas:**
- Certificados intermediários não estão instalados
- Cadeia de certificação incompleta

**Solução:**
- Reinstalar o certificado seguindo as instruções da autoridade certificadora
- Verificar se os certificados das autoridades certificadoras raiz e intermediárias estão instalados
- No Windows, verificar o repositório de certificados (certmgr.msc)

### 5. Certificado Não Incluído na Assinatura

**Sintomas:**
- O elemento `X509Certificate` não está presente na assinatura XML
- O certificado está vazio ou corrompido na assinatura

**Solução:**
- Verificar se o certificado foi carregado corretamente
- Verificar se a assinatura contém o `X509Certificate` completo

**Como verificar:**
O sistema agora valida automaticamente após assinar:
```
🔍 Validando assinatura digital gerada...
   ✅ Signature encontrada
   ✅ KeyInfo encontrada
   ✅ X509Data encontrada
   ✅ X509Certificate encontrado: 1234 caracteres
   ✅ X509Certificate parece válido (começa com 'MII')
```

### 6. Problemas com a Chave Privada

**Sintomas:**
- Chave privada não foi extraída corretamente do certificado
- Senha do certificado incorreta

**Solução:**
- Verificar se a senha está correta
- Re-exportar o certificado incluindo a chave privada
- Certificar-se de que o certificado está em formato PKCS#12 padrão

**Como verificar:**
O sistema agora valida e exibe:
```
   ✅ Certificado e chave privada carregados com sucesso
   📋 Tamanho do certificado: 8192 bytes
```

### 7. Algoritmo de Assinatura Incompatível

**Sintomas:**
- Algoritmo de assinatura não é o esperado pela SEFAZ

**Solução:**
- NFC-e deve usar RSA-SHA1 (padrão)
- Verificar se o algoritmo está correto

**Como verificar:**
O sistema agora exibe:
```
   📋 Algoritmo de assinatura: RSA-SHA1 (padrão NFC-e)
   ✅ Algoritmo de assinatura correto (RSA-SHA1 ou RSA-SHA256)
```

## Diagnóstico Passo a Passo

### Passo 1: Verificar Validações Automáticas

O sistema agora executa validações automáticas. Verifique os logs:

1. **Validação de Validade:**
   ```
   [VALIDAÇÃO 1/5] Verificando validade do certificado...
   ```
   - Se mostrar erro, o certificado está expirado ou ainda não válido

2. **Validação ICP-Brasil:**
   ```
   [VALIDAÇÃO 2/5] Verificando se é certificado ICP-Brasil...
   ```
   - Se mostrar aviso, o certificado pode não ser ICP-Brasil

3. **Validação de CNPJ:**
   ```
   [VALIDAÇÃO 3/5] Extraindo CNPJ do certificado...
   ```
   - Verifique se o CNPJ foi extraído corretamente

4. **Validação de Consistência:**
   ```
   ⚠️ AVISO: INCONSISTÊNCIA DE CNPJ
   ```
   - Se aparecer, os CNPJs não coincidem

5. **Validação da Assinatura:**
   ```
   🔍 Validando assinatura digital gerada...
   ```
   - Verifique se todos os elementos estão presentes

### Passo 2: Verificar Logs de Erro

Procure por mensagens de erro nos logs:

- `❌ ERRO CRÍTICO:` - Problemas críticos que impedem a assinatura
- `⚠️ AVISO:` - Avisos que podem causar problemas
- `✅` - Elementos que foram validados com sucesso

### Passo 3: Verificar o XML Assinado

Se possível, verifique o XML assinado:

1. Abra o XML assinado
2. Procure pelo elemento `<Signature>`
3. Verifique se contém:
   - `<KeyInfo>`
   - `<X509Data>`
   - `<X509Certificate>` (deve conter o certificado completo em Base64)

### Passo 4: Verificar Certificado no Sistema Operacional

**Windows:**
1. Abra `certmgr.msc`
2. Navegue até "Pessoal" > "Certificados"
3. Verifique se o certificado está presente e válido
4. Verifique a cadeia de certificação (duplo clique no certificado > "Caminho de Certificação")

**Linux/Mac:**
- Use ferramentas de linha de comando para verificar o certificado

## Soluções por Causa

### Certificado Expirado

1. Adquirir novo certificado junto a uma autoridade certificadora credenciada na ICP-Brasil
2. Instalar o novo certificado no sistema
3. Atualizar o certificado no sistema

### Certificado Não ICP-Brasil

1. Verificar se o certificado foi emitido por autoridade credenciada
2. Se não for ICP-Brasil, adquirir certificado ICP-Brasil
3. Reinstalar o certificado

### Inconsistência de CNPJ

1. Verificar se o certificado pertence à empresa correta
2. Se houver troca do responsável legal, usar o certificado correto
3. Atualizar o certificado no sistema

### Cadeia de Certificação Incompleta

1. Reinstalar o certificado seguindo as instruções da autoridade certificadora
2. Verificar se os certificados intermediários estão instalados
3. No Windows, executar `certmgr.msc` e verificar a cadeia

### Certificado Não Incluído na Assinatura

1. Verificar se o certificado foi carregado corretamente
2. Verificar se a senha está correta
3. Re-exportar o certificado incluindo a chave privada

## Prevenção

Para evitar o erro cStat=290:

1. ✅ **Use certificados ICP-Brasil válidos**
2. ✅ **Mantenha os certificados atualizados** (renove antes de expirar)
3. ✅ **Verifique a consistência do CNPJ** (certificado vs empresa)
4. ✅ **Mantenha a cadeia de certificação completa**
5. ✅ **Use senhas corretas** para os certificados
6. ✅ **Verifique os logs** após cada tentativa de assinatura

## Logs de Exemplo

### Log de Sucesso

```
======================================================================
VALIDAÇÕES ADICIONAIS DO CERTIFICADO
======================================================================

[VALIDAÇÃO 1/5] Verificando validade do certificado...
   ✅ Certificado válido por mais 564 dias

[VALIDAÇÃO 2/5] Verificando se é certificado ICP-Brasil...
   ✅ Certificado parece ser ICP-Brasil

[VALIDAÇÃO 3/5] Extraindo CNPJ do certificado...
   ✅ CNPJ do certificado: 12345678000190

[7/8] Assinando XML...
   ✅ Certificado e chave privada carregados com sucesso
   ✅ XML assinado

🔍 Validando assinatura digital gerada...
   ✅ Signature encontrada
   ✅ KeyInfo encontrada
   ✅ X509Data encontrada
   ✅ X509Certificate encontrado: 1234 caracteres
   ✅ X509Certificate parece válido (começa com 'MII')
   ✅ Validação da assinatura concluída
```

### Log com Problemas

```
[VALIDAÇÃO 1/5] Verificando validade do certificado...
   ❌ CERTIFICADO EXPIRADO!
   O certificado expirou em: 31/12/2023 23:59:59
   Data atual: 15/06/2024 10:30:00

⚠️ AVISO: INCONSISTÊNCIA DE CNPJ
   📋 CNPJ do certificado: 12345678000190
   📋 CNPJ da empresa: 98765432000110
   ⚠️ Os CNPJs não coincidem!

🔍 Validando assinatura digital gerada...
   ❌ ERRO CRÍTICO: X509Certificate não encontrado ou vazio!
   ⚠️ Isso pode causar cStat=290 (Certificado inválido)
```

## Contato com Suporte

Se todas as validações passarem, mas ainda houver erro cStat=290:

1. **Contatar a Autoridade Certificadora:**
   - Verificar se o certificado está válido no sistema deles
   - Verificar se há problemas conhecidos com o certificado

2. **Contatar o Suporte da SEFAZ:**
   - Fornecer a chave de acesso da NFC-e
   - Fornecer o número do protocolo (se houver)
   - Fornecer os logs de validação

3. **Verificar Atualizações:**
   - Verificar se há atualizações do sistema
   - Verificar se há mudanças nas regras da SEFAZ

## Conclusão

O sistema agora realiza validações automáticas completas do certificado antes de assinar. Se todas as validações passarem, mas ainda houver erro cStat=290, pode ser necessário:

1. Verificar a cadeia de certificação no sistema operacional
2. Contatar a autoridade certificadora
3. Verificar se há atualizações pendentes do certificado ou do sistema












