# 🔄 Reiniciar Servidor Após Instalar PyNFe

## ⚠️ Problema

Você instalou o PyNFe, mas o servidor ainda diz que não está instalado.

## ✅ Solução

**O servidor precisa ser REINICIADO para detectar o PyNFe recém-instalado!**

---

## 🔄 Como Reiniciar

### **1. Parar o Servidor Atual**

No terminal onde o servidor está rodando:
- Pressione **Ctrl+C** para parar o servidor

### **2. Verificar se PyNFe Está Instalado**

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"
.\venv\Scripts\python.exe verificar_pynfe_completo.py
```

Se aparecer "✅ PyNFe ESTÁ INSTALADO E FUNCIONANDO!", está tudo certo!

### **3. Reiniciar o Servidor**

```powershell
.\iniciar_simples.bat
```

ou

```powershell
.\start_local.bat
```

### **4. Verificar nos Logs**

Quando o servidor iniciar, você deve ver:

```
✅ PyNFe encontrado em: [caminho]
✅ Todos os módulos PyNFe importados com sucesso!
✅ NFCeService carregado (PyNFe disponível)
```

**NÃO deve aparecer:**
```
⚠️ PyNFe não está instalado
```

---

## 🧪 Teste Rápido

Após reiniciar, teste o health check:

```powershell
Invoke-WebRequest -Uri "http://localhost:5000/health" -UseBasicParsing
```

A resposta deve mostrar:
```json
{
  "status": "ok",
  "pynfe_disponivel": true
}
```

Se `pynfe_disponivel` for `true`, está funcionando!

---

## 📝 Resumo

1. ✅ PyNFe instalado
2. ⏳ **REINICIAR servidor** ← IMPORTANTE!
3. ✅ Verificar logs
4. ✅ Testar health check

---

**Depois de reiniciar, o PyNFe será detectado! 🚀**


