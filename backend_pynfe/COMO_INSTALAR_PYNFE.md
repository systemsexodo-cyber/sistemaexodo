# 📦 Como Instalar PyNFe

## ⚠️ Erro: "PyNFe não está instalado"

Se você está vendo este erro, o PyNFe precisa ser instalado no ambiente virtual do backend Python.

---

## 🚀 Método 1: Script Automático (Recomendado)

### **Windows:**
```bash
cd sistema_exodo_01-12/backend_pynfe
.\instalar_pynfe.bat
```

### **Linux/Mac:**
```bash
cd sistema_exodo_01-12/backend_pynfe
chmod +x instalar_pynfe.sh
./instalar_pynfe.sh
```

---

## 🔧 Método 2: Instalação Manual

### **Passo 1: Ativar Ambiente Virtual**

**Windows:**
```bash
cd sistema_exodo_01-12/backend_pynfe
.\venv\Scripts\activate.bat
```

**Linux/Mac:**
```bash
cd sistema_exodo_01-12/backend_pynfe
source venv/bin/activate
```

### **Passo 2: Verificar se Git está Instalado**

**Windows:**
```bash
git --version
```

Se não estiver instalado, baixe de: https://git-scm.com/download/win

### **Passo 3: Instalar PyNFe**

```bash
pip install --upgrade pip
pip install git+https://github.com/TadaSoftware/PyNFe.git
```

### **Passo 4: Verificar Instalação**

```bash
python -c "import pynfe; print('✅ PyNFe instalado!')"
```

Se aparecer "✅ PyNFe instalado!", está tudo certo!

---

## 🐛 Troubleshooting

### **Problema: "Git não encontrado"**

**Solução:**
1. Instale o Git: https://git-scm.com/download/win
2. Reinicie o terminal
3. Tente novamente

### **Problema: "Erro de conexão"**

**Solução:**
1. Verifique sua conexão com a internet
2. Verifique se o GitHub está acessível
3. Tente novamente

### **Problema: "Erro ao compilar"**

**Solução:**
1. Instale o Visual C++ Build Tools: https://visualstudio.microsoft.com/visual-cpp-build-tools/
2. Reinicie o terminal
3. Tente novamente

### **Problema: "Módulo não encontrado após instalação"**

**Solução:**
1. Certifique-se de que está no ambiente virtual correto
2. Verifique se o Python está usando o venv:
   ```bash
   which python  # Linux/Mac
   where python  # Windows
   ```
3. Deve apontar para `venv/Scripts/python.exe` (Windows) ou `venv/bin/python` (Linux/Mac)

---

## ✅ Verificação Final

Após instalar, verifique se está tudo funcionando:

```bash
# 1. Verificar se PyNFe está instalado
python -c "import pynfe; print('✅ OK')"

# 2. Iniciar o servidor
python app.py

# 3. Em outro terminal, testar health check
curl http://localhost:5000/health
```

A resposta deve mostrar:
```json
{
  "status": "ok",
  "pynfe_disponivel": true
}
```

---

## 📝 Notas Importantes

1. **PyNFe precisa do Git** para ser instalado do GitHub
2. **A instalação pode levar alguns minutos** (baixa e compila dependências)
3. **Certifique-se de estar no ambiente virtual** antes de instalar
4. **Reinicie o servidor** após instalar o PyNFe

---

## 🎯 Próximo Passo

Após instalar o PyNFe:

1. **Reinicie o servidor backend:**
   ```bash
   python app.py
   ```

2. **Teste novamente a emissão de NFC-e** no app Flutter

3. **Verifique os logs** para confirmar que está funcionando

---

**Boa sorte! 🚀**


