# 🔧 Backend Python Não Quer Rodar - Solução

## 📋 Passos para Diagnosticar

### **1. Execute o Diagnóstico Automático**

Abra um terminal PowerShell na pasta `backend_pynfe` e execute:

```powershell
.\diagnostico.bat
```

Isso vai verificar:
- ✅ Python instalado
- ✅ Flask instalado
- ✅ PyNFe instalado (opcional)
- ✅ Sintaxe do código
- ✅ Imports funcionando

---

### **2. Ou Teste Manualmente**

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

# Testar Python
.\venv\Scripts\python.exe --version

# Testar Flask
.\venv\Scripts\python.exe -c "import flask; print('OK')"

# Testar início
.\venv\Scripts\python.exe testar_inicio.py

# Tentar iniciar
.\venv\Scripts\python.exe app.py
```

---

## 🐛 Problemas Comuns e Soluções

### **Problema 1: "ModuleNotFoundError: No module named 'flask'"**

**Solução:**
```powershell
.\venv\Scripts\python.exe -m pip install flask flask-cors python-dotenv
```

---

### **Problema 2: "ModuleNotFoundError: No module named 'pynfe'"**

**Solução:**
```powershell
.\venv\Scripts\python.exe -m pip install git+https://github.com/TadaSoftware/PyNFe.git
```

**Nota:** O servidor pode rodar sem PyNFe, mas não vai emitir NFC-e.

---

### **Problema 3: "Port 5000 is already in use"**

**Solução:**
1. Encontre o processo usando a porta:
   ```powershell
   netstat -ano | findstr :5000
   ```
2. Mate o processo (substitua PID pelo número encontrado):
   ```powershell
   taskkill /PID <PID> /F
   ```
3. Ou mude a porta no `.env`:
   ```
   PORT=5001
   ```

---

### **Problema 4: "ImportError: cannot import name 'X' from 'services'"**

**Solução:**
Verifique se os arquivos existem:
- `services/nfce_service.py`
- `services/certificado_service.py`

Se não existirem, crie-os ou reinstale as dependências.

---

### **Problema 5: Erro de Sintaxe no Python**

**Solução:**
```powershell
.\venv\Scripts\python.exe -m py_compile app.py
```

Isso vai mostrar o erro de sintaxe.

---

## ✅ Verificação Rápida

Execute estes comandos para verificar tudo:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

# 1. Python OK?
.\venv\Scripts\python.exe --version

# 2. Flask OK?
.\venv\Scripts\python.exe -c "import flask; print('Flask OK')"

# 3. App pode iniciar?
.\venv\Scripts\python.exe testar_inicio.py

# 4. Iniciar servidor
.\venv\Scripts\python.exe app.py
```

---

## 🚀 Iniciar Servidor (Método Simples)

### **Opção 1: Script Batch**
```powershell
.\start_local.bat
```

### **Opção 2: Direto**
```powershell
.\venv\Scripts\python.exe app.py
```

### **Opção 3: Com Logs Detalhados**
```powershell
$env:FLASK_ENV="development"
$env:DEBUG="True"
.\venv\Scripts\python.exe app.py
```

---

## 📝 O Que Esperar Quando Funcionar

Quando o servidor iniciar corretamente, você verá:

```
==================================================
🚀 Backend NFC-e - Modo LOCAL
==================================================
📝 Porta: 5000
🐛 Debug: True
🌐 URL: http://localhost:5000
📡 Health: http://localhost:5000/health
==================================================

 * Running on http://0.0.0.0:5000
 * Debug mode: on
```

---

## 🔍 Se Ainda Não Funcionar

1. **Copie a mensagem de erro completa**
2. **Execute o diagnóstico:**
   ```powershell
   .\diagnostico.bat > erro.txt
   ```
3. **Envie o arquivo `erro.txt` para análise**

---

## 💡 Dica

Se o servidor não iniciar, tente:

1. **Reinstalar dependências:**
   ```powershell
   .\venv\Scripts\python.exe -m pip install --upgrade pip
   .\venv\Scripts\python.exe -m pip install -r requirements.txt
   ```

2. **Recriar ambiente virtual:**
   ```powershell
   Remove-Item -Recurse -Force venv
   python -m venv venv
   .\venv\Scripts\activate.bat
   pip install -r requirements.txt
   ```

---

**Boa sorte! 🎉**


