# 🔧 Diagnóstico: App Fecha Sozinho

## ✅ Solução Criada

Criei uma versão **SEGURA** do app que:
- ✅ Mostra erros claramente
- ✅ Não fecha sozinho
- ✅ Verifica dependências antes de iniciar
- ✅ Pausa para você ver os erros

## 🚀 Como Usar

### **Opção 1: Usar o script de inicialização (RECOMENDADO)**

```bash
cd backend_pynfe
.\iniciar_app.bat
```

Este script:
1. Verifica se o ambiente virtual existe
2. Verifica se as dependências estão instaladas
3. Inicia o app de forma segura
4. Mostra erros se houver

### **Opção 2: Usar o app seguro diretamente**

```bash
cd backend_pynfe
.\venv\Scripts\activate
python app_nfce_completo_seguro.py
```

## 🔍 Possíveis Causas do Problema

### **1. Dependências não instaladas**

**Sintoma:** App fecha imediatamente sem mensagem

**Solução:**
```bash
.\instalar_completo.bat
```

### **2. Ambiente virtual não ativado**

**Sintoma:** Erro de importação

**Solução:**
```bash
.\venv\Scripts\activate
```

### **3. Porta 5000 já em uso**

**Sintoma:** Erro ao iniciar servidor

**Solução:**
- Feche outros apps usando a porta 5000
- Ou mude a porta no código (linha 128):
  ```python
  app.run(host='0.0.0.0', port=5001, debug=True)  # Mude para 5001
  ```

### **4. Erro de importação**

**Sintoma:** Mensagem de erro ao importar módulos

**Solução:**
```bash
pip install Flask Flask-CORS lxml cryptography zeep
```

## 📋 Checklist de Verificação

Antes de iniciar, verifique:

- [ ] Ambiente virtual criado (`venv` existe)
- [ ] Ambiente virtual ativado
- [ ] Dependências instaladas
- [ ] Porta 5000 livre
- [ ] Arquivo `nfce_completo.py` existe
- [ ] Python 3.7+ instalado

## 🛠️ Teste Rápido

Execute este comando para testar:

```bash
cd backend_pynfe
.\venv\Scripts\activate
python -c "from flask import Flask; from nfce_completo import NFCeCompleto; print('OK')"
```

Se der erro, você verá qual dependência está faltando.

## 📞 Se Ainda Não Funcionar

1. Execute `.\iniciar_app.bat`
2. Copie a mensagem de erro completa
3. Verifique qual erro aparece
4. Siga as instruções do erro

---

**O app seguro não fecha sozinho e mostra todos os erros!** 🔧




















