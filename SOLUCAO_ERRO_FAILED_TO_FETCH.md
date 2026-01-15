# 🔧 Solução: Erro "Failed to fetch" ao Emitir NFC-e

## ❌ Erro Encontrado

```
ClientException: Failed to fetch, uri=http://localhost:5000/api/nfce/emitir
```

## 🔍 Causa

O app Flutter não consegue se conectar ao backend Python. Possíveis causas:

1. **Servidor backend não está rodando**
2. **Dispositivo físico não consegue acessar localhost**
3. **Problema de CORS**
4. **Firewall bloqueando conexão**

---

## ✅ Solução Passo a Passo

### **1. Verificar se o Servidor está Rodando**

Abra um terminal PowerShell e execute:

```powershell
# Testar se o servidor responde
Invoke-WebRequest -Uri "http://localhost:5000/health" -UseBasicParsing
```

**Se funcionar:** Você verá uma resposta JSON com status "ok"

**Se não funcionar:** O servidor não está rodando

---

### **2. Iniciar o Servidor Backend**

Se o servidor não estiver rodando:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"
.\start_local.bat
```

**Aguarde até ver:**
```
Running on http://0.0.0.0:5000
```

---

### **3. Se Estiver Usando Dispositivo Físico**

Se você está testando em um **dispositivo físico** (celular/tablet), `localhost` não funciona!

**Solução:** Use o IP da sua máquina:

1. **Descubra o IP da sua máquina:**
   ```powershell
   ipconfig
   ```
   Procure por "IPv4 Address" (exemplo: 192.168.1.100)

2. **Configure o backend para aceitar conexões externas:**
   - O servidor já está configurado para `0.0.0.0:5000` (aceita todas as conexões)

3. **No código Flutter, altere a URL:**
   - Em `nfce_backend_service.dart`, linha 51
   - Mude de `http://localhost:5000` para `http://SEU_IP:5000`
   - Exemplo: `http://192.168.1.100:5000`

---

### **4. Verificar Firewall**

O Windows Firewall pode estar bloqueando a porta 5000.

**Solução:**
1. Abra "Firewall do Windows Defender"
2. Clique em "Permitir um aplicativo pelo Firewall"
3. Adicione Python ou permita a porta 5000

---

### **5. Verificar CORS**

O backend já está configurado com CORS habilitado. Se ainda houver problemas:

**No arquivo `backend_pynfe/app.py`:**
```python
CORS(app, resources={r"/api/*": {"origins": "*"}})
```

Isso já está configurado!

---

## 🧪 Teste Rápido

### **1. Testar Servidor:**
```powershell
curl http://localhost:5000/health
```

### **2. Testar Endpoint de NFC-e:**
```powershell
$body = @{
    empresa = @{
        cnpj = "12345678000190"
        razao_social = "Teste"
    }
    produtos = @()
    pagamentos = @()
} | ConvertTo-Json

Invoke-WebRequest -Uri "http://localhost:5000/api/nfce/emitir" -Method POST -Body $body -ContentType "application/json"
```

---

## 📋 Checklist

- [ ] Servidor backend está rodando (`http://localhost:5000/health` responde)
- [ ] PyNFe está instalado (verificar logs do servidor)
- [ ] Se dispositivo físico: URL configurada com IP da máquina
- [ ] Firewall não está bloqueando porta 5000
- [ ] App Flutter e servidor na mesma rede

---

## 🚀 Próximos Passos

1. **Inicie o servidor backend**
2. **Verifique se está respondendo** (`/health`)
3. **Teste novamente a emissão de NFC-e**
4. **Se usar dispositivo físico, configure o IP correto**

---

## 💡 Dica

Para facilitar, você pode criar um script que:
1. Inicia o servidor automaticamente
2. Mostra o IP da máquina
3. Testa a conexão

---

**Boa sorte! 🎉**


