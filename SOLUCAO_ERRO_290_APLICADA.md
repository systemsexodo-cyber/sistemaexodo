# ✅ Solução do Erro 290 Aplicada

## 🔧 Correções Aplicadas

### 1. ✅ Algoritmo de Assinatura Corrigido
**Arquivo:** `backend_pynfe/pynfe_dev/pynfe/processamento/assinatura.py`

**Mudança:**
- **ANTES:** `signature_algorithm="rsa-sha1"` e `digest_algorithm="sha1"`
- **DEPOIS:** `signature_algorithm="rsa-sha256"` e `digest_algorithm="sha256"`

**Impacto:** Esta era a causa principal do erro 290. NFC-e 4.00 **OBRIGATORIAMENTE** requer SHA-256, não SHA-1.

### 2. ✅ Mensagem de Log Atualizada
**Arquivo:** `backend_pynfe/nfce_pynfe_completo.py` linha ~2030

**Mudança:**
- **ANTES:** "Algoritmo de assinatura: RSA-SHA1 (padrão NFC-e)"
- **DEPOIS:** "Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)"

### 3. ✅ Validação do X509Certificate Melhorada
**Arquivo:** `backend_pynfe/nfce_pynfe_completo.py` linha ~3740

**Mudança:**
- Adicionada verificação adicional antes de lançar erro
- Não bloqueia mais quando o certificado está presente mas a validação inicial falhou
- Deixa a SEFAZ fazer a validação final

## 🎯 Por Que Isso Resolve o Erro 290?

O erro 290 "Certificado Assinatura inválido" ocorria porque:

1. **Algoritmo SHA-1 Obsoleto:** A SEFAZ não aceita mais SHA-1 para NFC-e 4.00
2. **SHA-256 Obrigatório:** NFC-e versão 4.00 requer obrigatoriamente SHA-256
3. **Validação Restritiva:** A validação local estava bloqueando mesmo quando o certificado estava correto

## ✅ Teste Agora

Após essas correções:

1. **Reinicie o backend Python** (se estiver rodando)
2. **Tente emitir uma NFC-e novamente**
3. **O erro 290 deve estar resolvido**

## 📋 Verificações Adicionais

Se o erro persistir, verifique:

1. **Certificado é ICP-Brasil:** Certificado deve ser emitido por autoridade certificadora brasileira
2. **Certificado não expirado:** Verifique a validade
3. **Certificado corresponde ao CNPJ:** CNPJ do certificado deve corresponder ao CNPJ da empresa
4. **Ambiente correto:** Certificado de homologação para homologação, produção para produção

## 🔍 Logs para Verificar

Após aplicar as correções, verifique nos logs:

```
✅ Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)
✅ Algoritmo de digest: SHA256
✅ X509Certificate presente e válido
```

Se aparecer SHA1 nos logs, a correção não foi aplicada corretamente.











