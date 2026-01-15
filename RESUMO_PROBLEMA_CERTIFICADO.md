# 🔐 Resumo: Problema ao Carregar Certificado para NFC-e

## 🎯 Principais Causas

### 1. **Certificado não está salvo** (Mais Comum)
- O certificado foi selecionado mas não foi salvo corretamente
- O certificado foi perdido ao salvar no Firebase

**Solução:**
1. Edite a empresa
2. Selecione o certificado novamente
3. Preencha a senha
4. Salve a empresa
5. Verifique no console: `>>> [AdicionarEmpresa] Certificado salvo em base64`

---

### 2. **Senha não preenchida**
- A senha do certificado não foi informada na configuração da empresa

**Solução:**
1. Edite a empresa
2. Preencha o campo "Senha do Certificado"
3. Salve a empresa

---

### 3. **Certificado em formato não compatível**
- O certificado PFX foi exportado com opções avançadas
- O certificado está corrompido

**Solução:**
1. **Re-exporte o certificado:**
   - Abra no software original (e-CPF Manager, e-CNPJ Manager, etc)
   - Exporte como **PKCS#12 (.pfx)**
   - Use senha simples (apenas letras e números)
   - Não marque opções avançadas
2. Selecione o novo arquivo no sistema

---

### 4. **Certificado expirado**
- O certificado digital expirou

**Solução:**
1. Renove o certificado digital
2. Exporte o novo certificado
3. Selecione no sistema

---

## 🚀 Solução Rápida (Passo a Passo)

1. **Abra a tela de empresas**
2. **Edite a empresa com problema**
3. **Verifique se o certificado está selecionado:**
   - Se não estiver → Selecione novamente
   - Se estiver → Remova e selecione novamente
4. **Preencha a senha do certificado** (obrigatório)
5. **Salve a empresa**
6. **Verifique no console do Flutter:**
   - Procure por: `>>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres`
   - Se não aparecer, o certificado não foi salvo
7. **Tente emitir NFC-e novamente**

---

## 🔍 Como Diagnosticar

### Verificar se o certificado está salvo:
```
Console do Flutter → Procure por:
>>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres
```

### Verificar se o certificado está sendo carregado:
```
Console do Flutter → Procure por:
>>> [AdicionarEmpresa] Carregando certificado da empresa:
>>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (XXXX chars)
```

### Verificar ao emitir NFC-e:
```
Console do Flutter → Procure por:
>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...
>>> [NFCe]   • Base64: ✓ presente
```

---

## ⚠️ Erros Comuns e Soluções

### "Certificado digital não encontrado!"
**Causa:** Certificado não está salvo ou foi perdido  
**Solução:** Selecione o certificado novamente e salve

### "Senha do certificado não fornecida!"
**Causa:** Senha não foi preenchida  
**Solução:** Preencha a senha na configuração da empresa

### "Não foi possível processar o certificado PFX"
**Causa:** Certificado em formato não compatível  
**Solução:** Re-exporte o certificado em formato PKCS#12 padrão

### "Senha do certificado incorreta"
**Causa:** Senha digitada está incorreta  
**Solução:** Teste a senha em outro software e verifique se não há espaços

---

## 📝 Checklist de Verificação

- [ ] Certificado está selecionado na empresa
- [ ] Senha do certificado está preenchida
- [ ] Certificado foi salvo (verificar no console)
- [ ] Certificado está sendo carregado (verificar no console)
- [ ] Certificado não está expirado
- [ ] Senha está correta (testar em outro software)

---

## 🔐 Dicas Importantes

1. **Sempre re-exporte o certificado** se estiver com problemas
2. **Use senha simples** (sem caracteres especiais) ao exportar
3. **Mantenha o certificado atualizado** (renove antes de expirar)
4. **Teste a senha** em outro software antes de usar
5. **Verifique os logs** sempre que houver problema

---

## 📞 Se Nada Funcionar

1. Capture os logs completos do console do Flutter
2. Anote a mensagem de erro exata
3. Verifique:
   - Tamanho do certificado em base64 (deve ter pelo menos alguns milhares de caracteres)
   - Se a senha está correta (teste em outro software)
   - Se o certificado não está expirado
   - Se o certificado foi re-exportado recentemente

---

**Para mais detalhes, consulte:** `GUIA_DIAGNOSTICO_CERTIFICADO.md`



