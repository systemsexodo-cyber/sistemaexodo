# 🧪 Guia de Testes - Backend PyNFe

Este guia explica como testar a validação de certificados e a emissão de NFC-e em homologação.

---

## 📋 Pré-requisitos

1. ✅ Backend Python rodando (`.\iniciar_simples.bat`)
2. ✅ PyNFe instalado e funcionando
3. ✅ Certificado digital (.pfx ou .p12)
4. ✅ Dados da empresa (CNPJ, CSC, etc.)

---

## 🧪 Teste 1: Validação de Certificado

### **Objetivo**
Verificar se o certificado digital pode ser lido e validado pelo backend.

### **Como testar**

#### **Opção 1: Via script Python**
```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

# Com certificado em base64
.\venv\Scripts\python.exe testar_certificado.py MIIKpAIBAz... 123456

# Ou com arquivo .pfx
.\venv\Scripts\python.exe testar_certificado.py certificado.pfx
# (vai pedir a senha)
```

#### **Opção 2: Via app Flutter**
1. Abra o app Flutter
2. Vá em **Empresas** → **Adicionar/Editar**
3. Selecione um certificado
4. Verifique se aparece **"Validado via backend Python"**

#### **Opção 3: Via curl/Postman**
```bash
curl -X POST http://localhost:5000/api/certificado/validar \
  -H "Content-Type: application/json" \
  -d '{
    "certificado_base64": "MIIKpAIBAz...",
    "senha": "123456"
  }'
```

### **Resultado esperado**
```
✅ CERTIFICADO VÁLIDO!

Detalhes:
- Válido até: 2025-12-31
- Emitido para: NOME DA EMPRESA
- Emitido por: AUTORIDADE CERTIFICADORA
```

---

## 🧪 Teste 2: Emissão Completa de NFC-e em Homologação

### **Objetivo**
Emitir uma NFC-e completa em ambiente de homologação da SEFAZ.

### **Preparação**

1. **Criar arquivo de configuração:**
   ```powershell
   # Copie o exemplo
   copy config_exemplo.json config.json
   
   # Edite com seus dados reais
   notepad config.json
   ```

2. **Preencher `config.json`:**
   ```json
   {
     "cnpj": "SEU_CNPJ",
     "razao_social": "SUA_RAZAO_SOCIAL",
     "inscricao_estadual": "SUA_IE",
     "csc": "SEU_CSC",  // Código de Segurança do Contribuinte
     "csc_id_token": "1",
     "serie": "1",
     "uf": "SP",
     "certificado_arquivo": "caminho/para/certificado.pfx",
     "senha_certificado": "sua_senha"
   }
   ```

### **Como testar**

#### **Opção 1: Via script Python**
```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

.\venv\Scripts\python.exe testar_emissao_nfce.py config.json
```

#### **Opção 2: Via app Flutter**
1. Abra o app Flutter
2. Vá em **Vendas** → **Venda Direta**
3. Adicione produtos ao carrinho
4. Clique em **Emitir NFC-e**
5. Aguarde o processamento

### **Resultado esperado**

#### **✅ Sucesso (NFC-e Autorizada):**
```
✅ NFC-e PROCESSADA!

Detalhes:
- Status: autorizada
- Chave de acesso: 3521...
- Número: 123
- Série: 1
- Protocolo: 123456789012345
- QR Code: http://www.nfce.fazenda...

✅ NFC-e AUTORIZADA PELA SEFAZ!
```

#### **⚠️ Rejeitada:**
```
⚠️ NFC-e REJEITADA PELA SEFAZ
- Motivo: [código] - [descrição]
```

#### **❌ Erro:**
```
❌ ERRO NA EMISSÃO
Tipo: [tipo do erro]
Erro: [mensagem]
Detalhes técnicos: [traceback]
```

---

## 🔍 Verificações Importantes

### **1. Backend está rodando?**
```powershell
# Verificar health
curl http://localhost:5000/health

# Deve retornar: {"status": "ok", "pynfe_disponivel": true}
```

### **2. PyNFe está instalado?**
```powershell
.\venv\Scripts\python.exe -c "import pynfe; print('OK')"
```

### **3. Certificado é válido?**
- ✅ Não está expirado
- ✅ Formato correto (.pfx ou .p12)
- ✅ Senha correta
- ✅ Não está corrompido

### **4. Dados da empresa estão corretos?**
- ✅ CNPJ válido
- ✅ CSC correto (obtido na SEFAZ)
- ✅ Inscrição Estadual válida
- ✅ UF correta

---

## 🐛 Troubleshooting

### **Erro: "Backend não está rodando"**
```powershell
# Iniciar backend
cd backend_pynfe
.\iniciar_simples.bat
```

### **Erro: "Certificado inválido"**
- Verifique se a senha está correta
- Re-exporte o certificado em formato .pfx
- Verifique se não está expirado

### **Erro: "NFC-e rejeitada"**
- Verifique se está em **homologação** (não produção)
- Verifique se o CSC está correto
- Verifique se os dados da empresa estão corretos
- Consulte o motivo da rejeição na resposta

### **Erro: "Timeout"**
- A emissão pode levar até 2 minutos
- Verifique sua conexão com a internet
- Verifique se a SEFAZ está acessível

---

## 📝 Logs

Os logs detalhados aparecem no terminal onde o backend está rodando.

Para ver logs mais detalhados, adicione no `app.py`:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

---

## ✅ Checklist de Testes

- [ ] Backend está rodando
- [ ] PyNFe está instalado
- [ ] Certificado foi validado com sucesso
- [ ] NFC-e foi emitida em homologação
- [ ] NFC-e foi autorizada pela SEFAZ
- [ ] QR Code foi gerado corretamente
- [ ] XML foi retornado

---

**Boa sorte com os testes! 🚀**

