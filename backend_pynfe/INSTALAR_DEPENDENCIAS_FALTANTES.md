# 📦 Instalar Dependências Faltantes do PyNFe

## ❌ Problema

O PyNFe está instalado, mas faltam módulos:
- `signxml` (principal)
- Outras dependências

## ✅ Solução

### **Método 1: Script Automático (Recomendado)**

Execute:
```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"
.\instalar_dependencias_pynfe.bat
```

### **Método 2: Instalação Manual**

Execute estes comandos **um por vez**:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

# 1. Instalar signxml (principal)
.\venv\Scripts\python.exe -m pip install signxml

# 2. Instalar outras dependências
.\venv\Scripts\python.exe -m pip install defusedxml

# 3. Atualizar requirements
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

### **Método 3: Reinstalar PyNFe com Dependências**

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"

# Reinstalar PyNFe (pode instalar dependências automaticamente)
.\venv\Scripts\python.exe -m pip install --force-reinstall --no-cache-dir git+https://github.com/TadaSoftware/PyNFe.git
```

---

## 🧪 Verificar se Funcionou

Após instalar, execute:

```powershell
.\venv\Scripts\python.exe verificar_pynfe_completo.py
```

**Deve aparecer:**
```
✅ PyNFe ESTÁ INSTALADO E FUNCIONANDO!
✅ Todos os módulos OK
```

**NÃO deve aparecer:**
```
❌ No module named 'signxml'
```

---

## 🔄 Depois de Instalar

**IMPORTANTE:** Reinicie o servidor!

1. **Pare o servidor atual** (Ctrl+C)
2. **Reinicie:**
   ```powershell
   .\iniciar_simples.bat
   ```

---

## 📋 Dependências do PyNFe

O PyNFe precisa de:
- ✅ `signxml` - **CRÍTICO** (assinatura XML)
- ✅ `lxml` - Processamento XML
- ✅ `requests` - Requisições HTTP
- ✅ `zeep` - SOAP client
- ✅ `cryptography` - Criptografia
- ✅ `defusedxml` - Segurança XML

---

## 🚀 Comando Rápido

Execute tudo de uma vez:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"
.\venv\Scripts\python.exe -m pip install signxml defusedxml
.\venv\Scripts\python.exe verificar_pynfe_completo.py
```

Se tudo estiver OK, reinicie o servidor!

---

**Boa sorte! 🎉**


