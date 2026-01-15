# 🔍 Guia de Diagnóstico: Problema ao Carregar Certificado para NFC-e

## 📋 Checklist de Verificação Rápida

### 1. ✅ Certificado está salvo na empresa?
- [ ] Abra a tela de edição da empresa
- [ ] Verifique se aparece o nome do certificado selecionado
- [ ] Se não aparecer, selecione o certificado novamente e salve

### 2. ✅ Senha do certificado está preenchida?
- [ ] Verifique se a senha do certificado está preenchida na configuração da empresa
- [ ] Teste a senha abrindo o certificado em outro software

### 3. ✅ Certificado está sendo carregado do Firebase?
- [ ] Abra o console do Flutter (F5 ou `flutter run`)
- [ ] Procure por: `>>> [AdicionarEmpresa] Carregando certificado da empresa:`
- [ ] Verifique se aparece: `certificadoDigitalBytes: presente (XXXX chars)`

### 4. ✅ Erro específico ao emitir NFC-e?
- [ ] Abra o console do Flutter
- [ ] Procure por: `>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...`
- [ ] Veja qual mensagem de erro aparece

---

## 🔴 Problemas Comuns e Soluções

### Problema 1: "Certificado digital não encontrado!"

**Sintomas:**
- Mensagem: "Certificado digital não encontrado!"
- Log mostra: `Base64: ✗ ausente`

**Causa:**
O certificado não foi salvo corretamente no Firebase ou foi perdido.

**Solução:**
1. Vá em "Empresas" → Edite a empresa
2. Selecione o certificado novamente
3. **IMPORTANTE:** Digite a senha do certificado
4. Salve a empresa
5. Verifique no console: `>>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres`

---

### Problema 2: "Senha do certificado não fornecida!"

**Sintomas:**
- Mensagem: "Senha do certificado não fornecida!"
- Log mostra: `senha: AUSENTE`

**Causa:**
A senha do certificado não foi preenchida na configuração da empresa.

**Solução:**
1. Vá em "Empresas" → Edite a empresa
2. Preencha o campo "Senha do Certificado"
3. Salve a empresa

---

### Problema 3: "Não foi possível processar o certificado PFX"

**Sintomas:**
- Mensagem: "Não foi possível processar o certificado PFX"
- Log mostra tentativas de parsing falhando

**Causa:**
O certificado PFX pode estar em formato não padrão ou corrompido.

**Soluções (tente nesta ordem):**

#### Solução 3.1: Re-exportar o Certificado (RECOMENDADO)
1. Abra o certificado no software original (e-CPF Manager, e-CNPJ Manager, etc)
2. Exporte novamente como **PKCS#12 (.pfx)**
3. **IMPORTANTE:** Use senha simples (apenas letras e números, sem caracteres especiais)
4. Não marque opções avançadas como "Exportar chave privada estendida"
5. Selecione o novo arquivo no sistema

#### Solução 3.2: Converter para PEM
Se não conseguir re-exportar, converta manualmente:

```powershell
# Se tiver Git Bash instalado:
& "C:\Program Files\Git\usr\bin\openssl.exe" pkcs12 -in certificado.pfx -out certificado.pem -nodes -passin pass:SUA_SENHA

# Depois, selecione o arquivo .pem no sistema
```

#### Solução 3.3: Verificar se OpenSSL está disponível
O sistema tenta usar OpenSSL automaticamente. Verifique se está instalado:

```powershell
# Verificar se OpenSSL está disponível
openssl version

# Se não estiver, instale Git Bash (já vem com OpenSSL)
# OU execute: .\instalar_openssl.ps1
```

---

### Problema 4: "Senha do certificado incorreta"

**Sintomas:**
- Mensagem: "Senha do certificado incorreta"
- Log mostra: `mac verify failure` ou `invalid password`

**Causa:**
A senha digitada está incorreta ou o certificado está corrompido.

**Solução:**
1. Teste a senha abrindo o certificado em outro software
2. Se funcionar em outro software, verifique se não há espaços antes/depois da senha
3. Se não funcionar em nenhum software, o certificado pode estar corrompido - re-exporte

---

### Problema 5: Certificado expirado

**Sintomas:**
- Mensagem sobre validade do certificado
- Log mostra data de validade no passado

**Causa:**
O certificado digital expirou.

**Solução:**
1. Renove o certificado digital
2. Exporte o novo certificado
3. Selecione o novo certificado no sistema

---

## 🔧 Verificação Técnica Detalhada

### Passo 1: Verificar se o certificado está salvo

Abra o console do Flutter e procure por:

```
>>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres
>>> [Firebase] Empresa salva: Nome da Empresa (ID: xxx)
```

Se não aparecer, o certificado não foi salvo.

### Passo 2: Verificar se o certificado está sendo carregado

Ao editar a empresa, procure por:

```
>>> [AdicionarEmpresa] Carregando certificado da empresa:
>>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (XXXX chars)
```

Se aparecer "null" ou "ausente", o certificado não está sendo carregado do Firebase.

### Passo 3: Verificar ao emitir NFC-e

Ao tentar emitir NFC-e, procure por:

```
>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...
>>> [NFCe]   • Base64: ✓ presente
>>> [NFCe] Estado inicial:
>>> [NFCe]   certificadoBytes: presente (XXXX chars)
>>> [Certificado] INÍCIO: carregarCertificado
```

Se aparecer "✗ ausente", o certificado não está disponível.

---

## 🚀 Solução Rápida (Passo a Passo)

1. **Abra a tela de empresas**
2. **Edite a empresa que está com problema**
3. **Verifique se o certificado está selecionado:**
   - Se não estiver, selecione novamente
   - Se estiver, remova e selecione novamente
4. **Preencha a senha do certificado** (campo obrigatório)
5. **Salve a empresa**
6. **Verifique no console** se apareceu: `>>> [AdicionarEmpresa] Certificado salvo em base64`
7. **Tente emitir NFC-e novamente**

---

## 📞 Se Nada Funcionar

Se após seguir todos os passos o problema persistir:

1. **Capture os logs completos** do console do Flutter
2. **Anote a mensagem de erro exata**
3. **Verifique:**
   - Tamanho do certificado em base64 (deve ter pelo menos alguns milhares de caracteres)
   - Se a senha está correta (teste em outro software)
   - Se o certificado não está expirado
   - Se o certificado foi re-exportado recentemente

---

## 🔐 Dicas Importantes

1. **Sempre re-exporte o certificado** se estiver com problemas
2. **Use senha simples** (sem caracteres especiais) ao exportar
3. **Mantenha o certificado atualizado** (renove antes de expirar)
4. **Teste a senha** em outro software antes de usar no sistema
5. **Verifique os logs** sempre que houver problema

---

## 📝 Logs Esperados (Sucesso)

### Ao Salvar Empresa:
```
>>> [AdicionarEmpresa] Certificado salvo em base64: 12345 caracteres
>>> [Firebase] Empresa salva: Minha Empresa (ID: 1)
```

### Ao Carregar Empresa:
```
>>> [AdicionarEmpresa] Carregando certificado da empresa:
>>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (12345 chars)
```

### Ao Emitir NFC-e:
```
>>> [NFCe] DIAGNÓSTICO: Verificando fontes de certificado...
>>> [NFCe]   • Base64: ✓ presente
>>> [NFCe] Estado inicial:
>>> [NFCe]   certificadoBytes: presente (12345 chars)
>>> [Certificado] INÍCIO: carregarCertificado
>>> [Certificado] certificadoDigitalBytes: presente (12345 chars)
>>> [Certificado] ✓✓✓ Certificado criado com sucesso!
```



