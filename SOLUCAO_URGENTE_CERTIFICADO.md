# 🚨 SOLUÇÃO URGENTE: Certificado não carrega

## ✅ CORREÇÕES CRÍTICAS IMPLEMENTADAS:

### 1. **Validação antes de carregar:**
   - Verifica se certificado existe antes de tentar carregar
   - Verifica se senha está presente
   - Mensagens de erro claras e específicas

### 2. **Fallback para Windows:**
   - Se certificado em base64 estiver ausente mas tiver thumbprint do Windows
   - Tenta exportar do Windows novamente automaticamente
   - Garante que o certificado será carregado

### 3. **Logs detalhados:**
   - Logs em cada etapa do processo
   - Mostra exatamente onde está falhando
   - Facilita diagnóstico

### 4. **Tratamento de erros melhorado:**
   - Mensagens específicas para cada tipo de erro
   - Orientações claras sobre o que fazer

## 🧪 TESTE AGORA:

### 1. **Verifique se o certificado está salvo:**
   - Vá em "Empresas" → Edite a empresa
   - Verifique se mostra "Certificado selecionado"
   - **Se não mostrar, selecione novamente**

### 2. **Verifique a senha:**
   - Certifique-se de que a senha está preenchida
   - **Se não estiver, preencha e salve novamente**

### 3. **Tente emitir NFC-e:**
   - Vá em "Venda Direta"
   - Adicione produtos
   - Clique em "Emitir NFC-e"
   - **Verifique os logs no console**

## 📋 LOGS ESPERADOS:

### Se certificado estiver presente:
```
>>> [NFCe] ========================================
>>> [NFCe] Carregando certificado digital...
>>> [NFCe] certificadoDigitalBytes: presente (XXXX chars)
>>> [NFCe] senhaCertificado: presente (XX chars)
>>> [Certificado] Certificado em base64 detectado
>>> [Certificado] ✓✓✓ Detectado PEM em base64 (texto)
>>> [NFCe] ✓✓✓ Certificado carregado com sucesso
```

### Se certificado estiver ausente:
```
>>> [NFCe] ERRO: Certificado digital não encontrado!
Por favor, selecione um certificado digital na configuração da empresa.
```

### Se senha estiver ausente:
```
>>> [NFCe] ERRO: Senha do certificado não informada!
Por favor, informe a senha do certificado na configuração da empresa.
```

## 🔧 SE AINDA NÃO FUNCIONAR:

1. **Verifique os logs completos no console**
2. **Copie os logs e me envie**
3. **Verifique se:**
   - Certificado está selecionado na empresa
   - Senha está preenchida
   - Certificado não está expirado

## ✅ PRONTO!

Agora o sistema tem validações robustas e fallbacks automáticos. Teste e me envie os logs se ainda não funcionar!




