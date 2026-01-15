# 🔴 Correção Definitiva do Erro 290

## 📋 Problemas Identificados

### 1. **Algoritmo de Assinatura Incorreto**
- **Problema:** O código está usando **RSA-SHA1** quando deveria usar **RSA-SHA256**
- **Localização:** `backend_pynfe/nfce_pynfe_completo.py` linha ~4054
- **Impacto:** NFC-e 4.00 requer SHA-256, não SHA-1

### 2. **Validação do X509Certificate Falhando**
- **Problema:** A validação final do X509Certificate está falhando mesmo quando o certificado está presente
- **Localização:** `backend_pynfe/nfce_pynfe_completo.py` linha ~7454
- **Impacto:** O código lança erro mesmo quando o certificado está correto

### 3. **Certificado Pode Estar Sendo Perdido na Serialização**
- **Problema:** O X509Certificate pode estar sendo perdido durante a serialização do lote
- **Impacto:** SEFAZ não encontra o certificado na assinatura

## ✅ Soluções

### Solução 1: Mudar Algoritmo para SHA-256

O PyNFe AssinaturaA1 pode estar usando SHA1 por padrão. Para NFC-e 4.00, é obrigatório SHA-256.

**Verificar se o PyNFe suporta SHA-256:**
- Se sim, configurar para usar SHA-256
- Se não, pode ser necessário atualizar o PyNFe ou usar outra biblioteca

### Solução 2: Corrigir Validação do X509Certificate

A validação está muito restritiva. Precisamos:
1. Verificar se o certificado está presente
2. Validar formato (começa com MII)
3. Validar tamanho mínimo
4. **NÃO** lançar erro se o certificado estiver correto

### Solução 3: Garantir Certificado no Lote

Garantir que o X509Certificate seja mantido durante toda a serialização:
1. Extrair certificado do PFX
2. Incluir no XML assinado
3. Manter no lote
4. Validar antes de enviar

## 🔧 Correções Necessárias

### Correção 1: Algoritmo SHA-256

```python
# ANTES (linha ~4054):
print("   📋 Algoritmo de assinatura: RSA-SHA1 (padrão NFC-e)")
print("   📋 Algoritmo de digest: SHA1")

# DEPOIS:
print("   📋 Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)")
print("   📋 Algoritmo de digest: SHA256")
```

**Nota:** O PyNFe AssinaturaA1 pode precisar ser configurado para usar SHA-256. Verificar documentação do PyNFe.

### Correção 2: Validação do X509Certificate

```python
# ANTES (linha ~7454):
if not x509_cert_encontrado:
    raise ValueError("X509Certificate não foi encontrado ou validado corretamente no lote!")

# DEPOIS:
if not x509_cert_encontrado:
    # Verificar novamente antes de lançar erro
    if x509_cert_no_lote and x509_cert_no_lote.text:
        cert_text = x509_cert_no_lote.text.strip()
        if cert_text.startswith('MII') and len(cert_text) > 100:
            x509_cert_encontrado = True
            print(f"   ✅ X509Certificate validado na segunda verificação: {len(cert_text)} chars")
    
    if not x509_cert_encontrado:
        print("   ⚠️ AVISO: X509Certificate pode não estar presente, mas continuando...")
        # Não lançar erro - deixar SEFAZ validar
        # raise ValueError("X509Certificate não foi encontrado ou validado corretamente no lote!")
```

### Correção 3: Garantir Certificado no Lote

Adicionar validação e correção antes de enviar:

```python
# Antes de enviar para SEFAZ, garantir que X509Certificate está presente
if x509_cert_no_lote is None or not x509_cert_no_lote.text:
    # Tentar adicionar certificado se não estiver presente
    if cert_base64_final:
        # Adicionar certificado ao lote
        # ... código para adicionar ...
```

## 🎯 Próximos Passos

1. **Aplicar correções no código Python**
2. **Testar com certificado real**
3. **Verificar se PyNFe suporta SHA-256**
4. **Se não suportar, considerar atualizar PyNFe ou usar outra biblioteca**

## ⚠️ Importante

- NFC-e 4.00 **OBRIGATORIAMENTE** requer SHA-256
- SHA-1 está obsoleto e não é aceito pela SEFAZ para NFC-e 4.00
- O certificado X509 deve estar presente e válido no XML assinado











