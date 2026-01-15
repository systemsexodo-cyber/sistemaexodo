# Validação de Certificado Digital - NFC-e

## Visão Geral

O sistema agora realiza validações completas do certificado digital antes de assinar a NFC-e, ajudando a identificar problemas que podem causar rejeição pela SEFAZ (especialmente o erro **cStat=290 - Certificado de Assinatura inválido**).

## Validações Implementadas

### 1. Validade do Certificado

**O que verifica:**
- Se o certificado está dentro do prazo de validade
- Se ainda não entrou em vigor
- Se já expirou
- Quantos dias restam até a expiração

**Problemas detectados:**
- ❌ Certificado expirado
- ❌ Certificado ainda não válido (data futura)

**Soluções:**
- Se expirado: Adquirir novo certificado junto a uma autoridade certificadora credenciada na ICP-Brasil
- Se ainda não válido: Aguardar até a data de início da validade

### 2. Verificação ICP-Brasil

**O que verifica:**
- Se o certificado é emitido por uma autoridade certificadora credenciada na ICP-Brasil
- Verifica o campo "issuer" do certificado

**Problemas detectados:**
- ⚠️ Certificado pode não ser ICP-Brasil

**Soluções:**
- Certificados não ICP-Brasil podem ser rejeitados pela SEFAZ
- Use apenas certificados emitidos por autoridades credenciadas na ICP-Brasil

### 3. Extração de CNPJ

**O que verifica:**
- Extrai o CNPJ do certificado digital
- Busca em diferentes campos do certificado (subject, serialNumber)

**Problemas detectados:**
- ⚠️ CNPJ não encontrado no certificado

**Soluções:**
- Verificar se o certificado está completo e não corrompido
- Reinstalar o certificado se necessário

### 4. Consistência CNPJ (Certificado vs Empresa)

**O que verifica:**
- Compara o CNPJ do certificado com o CNPJ cadastrado da empresa
- Executado antes de assinar a NFC-e

**Problemas detectados:**
- ⚠️ CNPJs não coincidem

**Soluções:**
1. Verificar se o certificado pertence à empresa correta
2. Se houver troca do responsável legal, o certificado anterior pode ter sido invalidado
3. Use o certificado correto para a empresa

### 5. Algoritmo e Tamanho da Chave

**O que verifica:**
- Tamanho da chave criptográfica (deve ser >= 2048 bits)
- Algoritmo utilizado

**Problemas detectados:**
- ⚠️ Chave com menos de 2048 bits (pode ser considerada fraca)

**Soluções:**
- Certificados modernos devem ter chaves de pelo menos 2048 bits
- Se o certificado for antigo, considere renovar

### 6. Extensões e Permissões

**O que verifica:**
- Se o certificado tem permissão para assinatura digital (keyUsage)

**Problemas detectados:**
- ⚠️ Certificado pode não ter permissão para assinatura digital

**Soluções:**
- Verificar com a autoridade certificadora se o certificado tem as permissões corretas

## Causas Comuns do Erro cStat=290

### 1. Certificado Expirado

**Sintoma:** Certificado passou da data de validade

**Solução:**
- Verificar a validade do certificado
- Se expirado, adquirir novo certificado junto a uma autoridade certificadora credenciada na ICP-Brasil

### 2. Problemas na Instalação ou Configuração

**Sintoma:** Certificado não está instalado corretamente ou foi corrompido

**Solução:**
- Reinstalar o certificado digital seguindo as instruções da sua autoridade certificadora
- Certificar-se de que o software está configurado para usar o certificado válido
- Verificar se a senha está correta

### 3. Inconsistência de Dados

**Sintoma:** CNPJ do certificado não corresponde ao CNPJ da empresa

**Solução:**
- Verificar se o CNPJ no certificado corresponde exatamente ao CNPJ do emitente
- Se houver troca do responsável legal, o certificado anterior pode ter sido invalidado
- Usar o certificado correto para a empresa

### 4. Problemas na Cadeia de Confiança

**Sintoma:** Sistema não reconhece a cadeia de certificação como confiável

**Solução:**
- Verificar se os certificados das autoridades certificadoras raiz e intermediárias estão instalados
- Reinstalar o certificado corretamente
- No Windows, verificar o repositório de certificados

## Próximos Passos ao Identificar Problemas

### 1. Verificar a Validade
O primeiro passo é confirmar se o certificado digital está dentro do prazo de validade. O sistema agora faz isso automaticamente e exibe mensagens claras.

### 2. Verificar CNPJ
O sistema compara automaticamente o CNPJ do certificado com o CNPJ da empresa e alerta se houver inconsistência.

### 3. Verificar ICP-Brasil
O sistema verifica se o certificado parece ser ICP-Brasil e alerta se não for.

### 4. Contatar Suporte
Se o certificado estiver válido e os CNPJs coincidirem, mas ainda houver problemas:
- Entre em contato com o suporte técnico do seu software emissor
- Entre em contato com a empresa que emitiu seu certificado digital (autoridade certificadora)

## Logs e Diagnóstico

O sistema agora exibe logs detalhados durante a validação do certificado:

```
======================================================================
PREPARAÇÃO DE CERTIFICADO DIGITAL - VALIDAÇÃO COMPLETA
======================================================================

[PASSO 1/6] Validando entrada...
   ✅ Certificado base64: 12345 caracteres
   ✅ Senha: 8 caracteres

[PASSO 2/6] Limpando base64...
   ✅ Base64 limpo: 12345 caracteres

[PASSO 3/6] Decodificando base64...
   ✅ Base64 decodificado: 8192 bytes

[PASSO 4/6] Validando formato PFX/P12...
   ✅ Formato DER/PKCS#12 detectado (0x30 0x82)

[PASSO 5/6] Criando arquivo temporário...
   ✅ Arquivo criado: /tmp/cert_nfce_xxxxx.pfx
   ✅ Tamanho: 8192 bytes

[PASSO 6/6] Validando certificado com PyNFe...
   🔧 Tentando carregar certificado...
   ✅ Certificado carregado com sucesso!
   ✅ Chave privada extraída
   ✅ Certificado X509 extraído

======================================================================
VALIDAÇÕES ADICIONAIS DO CERTIFICADO
======================================================================

[VALIDAÇÃO 1/5] Verificando validade do certificado...
   📋 Válido de: 01/01/2024 00:00:00
   📋 Válido até: 31/12/2025 23:59:59
   📋 Data atual: 15/06/2024 10:30:00
   ✅ Certificado válido por mais 564 dias

[VALIDAÇÃO 2/5] Verificando se é certificado ICP-Brasil...
   ✅ Certificado parece ser ICP-Brasil (issuer: AC Certisign...)

[VALIDAÇÃO 3/5] Extraindo CNPJ do certificado...
   ✅ CNPJ encontrado no certificado: 12345678000190

[VALIDAÇÃO 4/5] Verificando algoritmo e chave...
   📋 Tamanho da chave: 2048 bits
   ✅ Tamanho da chave adequado (2048 bits)

[VALIDAÇÃO 5/5] Verificando extensões do certificado...
   ✅ Certificado tem permissão para assinatura digital

======================================================================
✅ VALIDAÇÕES DO CERTIFICADO CONCLUÍDAS
======================================================================
```

## Dependências

Para as validações avançadas funcionarem, é necessário ter a biblioteca `cryptography` instalada:

```bash
pip install cryptography
```

Se a biblioteca não estiver instalada, o sistema continuará funcionando, mas sem as validações avançadas (validade, ICP-Brasil, CNPJ, etc.).

## Conclusão

Com essas validações, o sistema agora identifica problemas com o certificado digital **antes** de tentar assinar a NFC-e, economizando tempo e ajudando a resolver problemas rapidamente.

Se todas as validações passarem, mas ainda houver erro cStat=290, pode ser necessário:
1. Verificar a cadeia de certificação no sistema operacional
2. Contatar a autoridade certificadora
3. Verificar se há atualizações pendentes do certificado ou do sistema












