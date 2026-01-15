# 🧪 Guia de Teste - Validação de Certificado via Backend Python

## ✅ Backend Python Status

- **Status:** ✅ FUNCIONANDO
- **URL:** http://localhost:5000
- **PyNFe:** ✅ Disponível
- **Health Check:** ✅ OK

---

## 📱 Como Testar no App Flutter

### **Passo 1: Abrir o App Flutter**
1. Execute o app Flutter no seu dispositivo/emulador
2. Faça login (se necessário)

### **Passo 2: Ir para Empresas**
1. No menu principal, clique em **"Empresas"**
2. Selecione uma empresa existente ou clique em **"Adicionar Empresa"**

### **Passo 3: Selecionar Certificado**
1. Na tela de cadastro/edição da empresa, role até a seção **"Configurações NFC-e"**
2. Clique no botão **"Selecionar Certificado"** ou **"Selecionar Certificado do Windows"**

### **Passo 4: Escolher Certificado**
- **Opção A - Arquivo PFX/PEM:**
  - Clique em "Selecionar Certificado"
  - Escolha um arquivo `.pfx`, `.p12` ou `.pem`
  - Digite a senha quando solicitado

- **Opção B - Certificado do Windows:**
  - Clique em "Selecionar Certificado do Windows"
  - Escolha um certificado da lista
  - Digite a senha quando solicitado

### **Passo 5: Verificar Validação**
Após selecionar o certificado, você deve ver uma mensagem como:

**✅ Se o backend estiver funcionando:**
```
✓ Certificado processado e validado com sucesso!
(Validado via backend Python)

CNPJ: 12.345.678/0001-90
Validade: 31/12/2025 (365 dias restantes)

Certificado armazenado em memória (base64)
```

**⚠️ Se o backend não estiver disponível (fallback):**
```
✓ Certificado processado e validado com sucesso!
(Validado via serviço local)

CNPJ: 12.345.678/0001-90
Validade: 31/12/2025 (365 dias restantes)

Certificado armazenado em memória (base64)
```

---

## 🔍 O Que Verificar

### **1. Mensagem de Sucesso**
- ✅ Deve aparecer "Validado via backend Python" se o backend estiver rodando
- ✅ Deve mostrar CNPJ extraído do certificado
- ✅ Deve mostrar data de validade e dias restantes

### **2. Logs no Console**
Abra o console do Flutter e verifique os logs:

```
>>> [Certificado] Tentando validar via backend Python...
>>> [Certificado] Backend disponível, validando...
>>> [Certificado] ✓✓✓ Certificado validado via backend Python!
>>> [Certificado] CNPJ: 12.345.678/0001-90
>>> [Certificado] Validade: 2025-12-31
>>> [Certificado] Válido: true, Dias restantes: 365
```

### **3. Logs do Backend Python**
No terminal onde o backend está rodando, você deve ver:

```
127.0.0.1 - - [DD/MM/YYYY HH:MM:SS] "POST /api/certificado/validar HTTP/1.1" 200 -
```

---

## 🐛 Troubleshooting

### **Problema: "Backend não disponível"**
**Solução:**
1. Verifique se o backend está rodando: `http://localhost:5000/health`
2. Se não estiver, inicie novamente: `.\start_local.bat`
3. Verifique se não há erros no terminal do backend

### **Problema: "Erro ao validar certificado"**
**Possíveis causas:**
1. Certificado corrompido ou inválido
2. Senha incorreta
3. Certificado sem chave privada

**Solução:**
- Re-exporte o certificado do Windows
- Use senha simples (apenas letras e números)
- Certifique-se de incluir a chave privada na exportação

### **Problema: "Timeout ao validar"**
**Solução:**
1. Verifique se o backend está respondendo: `http://localhost:5000/health`
2. Aumente o timeout no código se necessário
3. Verifique a conexão de rede

---

## ✅ Checklist de Teste

- [ ] Backend Python está rodando
- [ ] Health check responde OK
- [ ] App Flutter está aberto
- [ ] Empresa selecionada/editada
- [ ] Certificado selecionado
- [ ] Mensagem mostra "Validado via backend Python"
- [ ] CNPJ extraído corretamente
- [ ] Validade mostrada corretamente
- [ ] Logs no console do Flutter
- [ ] Logs no terminal do backend

---

## 📊 Resultado Esperado

Se tudo estiver funcionando corretamente:

1. ✅ Backend Python valida o certificado
2. ✅ Informações extraídas (CNPJ, validade)
3. ✅ Mensagem de sucesso exibida
4. ✅ Certificado salvo em base64
5. ✅ Pronto para emitir NFC-e

---

## 🚀 Próximo Passo

Após validar o certificado com sucesso, você pode:

1. **Salvar a empresa** com o certificado configurado
2. **Fazer uma venda** no PDV
3. **Emitir NFC-e** após finalizar a venda
4. **Verificar** se a emissão usa o backend Python

---

**Boa sorte com os testes! 🎉**


