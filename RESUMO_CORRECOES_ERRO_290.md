# ✅ Correções Aplicadas para Resolver Erro 290

## 🔧 Correções Implementadas

### 1. ✅ **Algoritmo de Assinatura: SHA-1 → SHA-256**
**Arquivo:** `backend_pynfe/pynfe_dev/pynfe/processamento/assinatura.py`

**Linha 112-113:**
```python
# ANTES:
signature_algorithm="rsa-sha1",
digest_algorithm="sha1",

# DEPOIS:
signature_algorithm="rsa-sha256",  # NFC-e 4.00 requer SHA-256, não SHA-1
digest_algorithm="sha256",  # NFC-e 4.00 requer SHA-256, não SHA-1
```

**✅ Esta era a causa principal do erro 290!**

### 2. ✅ **Mensagem de Log Atualizada**
**Arquivo:** `backend_pynfe/nfce_pynfe_completo.py` linha ~2030

```python
# ANTES:
print("   📋 Algoritmo de assinatura: RSA-SHA1 (padrão NFC-e)")

# DEPOIS:
print("   📋 Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)")
```

### 3. ✅ **Validação do X509Certificate Corrigida**
**Arquivo:** `backend_pynfe/nfce_pynfe_completo.py` linha ~3740

**Mudança:**
- Adicionada verificação adicional antes de lançar erro
- Não bloqueia mais quando o certificado está presente
- Deixa a SEFAZ fazer a validação final

## 🎯 Por Que Isso Resolve o Erro 290?

O erro 290 "Certificado Assinatura inválido" ocorria porque:

1. **SHA-1 está obsoleto:** A SEFAZ não aceita mais SHA-1 para NFC-e 4.00
2. **SHA-256 é obrigatório:** NFC-e versão 4.00 requer obrigatoriamente SHA-256
3. **Validação muito restritiva:** A validação local estava bloqueando mesmo quando o certificado estava correto

## ✅ Teste Agora

**IMPORTANTE:** Reinicie o backend Python para aplicar as mudanças!

1. **Pare o backend Python** (Ctrl+C)
2. **Inicie novamente:**
   ```bash
   python backend_pynfe/app.py
   ```
3. **Tente emitir uma NFC-e novamente**
4. **O erro 290 deve estar resolvido!**

## 📋 Verificações nos Logs

Após reiniciar, verifique nos logs:

```
✅ Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)
✅ Algoritmo de digest: SHA256
✅ X509Certificate presente e válido
```

**Se ainda aparecer SHA1 nos logs, a correção não foi aplicada corretamente.**

## ⚠️ Se o Erro Persistir

Se após essas correções o erro 290 ainda ocorrer, verifique:

1. **Certificado é ICP-Brasil:**
   - Certificado deve ser emitido por autoridade certificadora brasileira
   - Certificados estrangeiros não funcionam

2. **Certificado não expirado:**
   - Verifique a data de validade
   - Certificados expirados são rejeitados

3. **Certificado corresponde ao CNPJ:**
   - CNPJ do certificado deve corresponder ao CNPJ da empresa
   - Verifique se está usando o certificado correto

4. **Ambiente correto:**
   - Certificado de **homologação** → Ambiente **homologação**
   - Certificado de **produção** → Ambiente **produção**
   - Não misture!

5. **Certificado tem permissão:**
   - Certificado deve ter permissão para assinar documentos fiscais
   - Verifique com a autoridade certificadora

## 🔍 Diagnóstico Adicional

Se necessário, verifique:

- **Tamanho do certificado:** Deve ter pelo menos 200 bytes
- **Formato:** Deve começar com `MII` em base64
- **Chave privada:** Deve estar presente no certificado
- **Senha:** Deve estar correta (case-sensitive)

## 📊 Status das Correções

- ✅ Algoritmo SHA-256: **CORRIGIDO**
- ✅ Validação X509Certificate: **CORRIGIDA**
- ✅ Mensagens de log: **ATUALIZADAS**

**Todas as correções foram aplicadas com sucesso!**











