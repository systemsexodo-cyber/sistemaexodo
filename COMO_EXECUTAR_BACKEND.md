# 🚀 Como Executar o Backend NFC-e Corretamente

## ✅ Passo a Passo Simples

---

## 📋 PASSO 1: Verificar se Python está Instalado

Abra o PowerShell ou CMD e digite:
```bash
python --version
```

**Se aparecer a versão (ex: Python 3.12.10):** ✅ OK, continue!
**Se der erro:** Instale Python de https://www.python.org/downloads/
  - **IMPORTANTE:** Marque "Add Python to PATH" durante a instalação!

---

## 📋 PASSO 2: Navegar até a Pasta do Backend

```bash
cd backend_pynfe
```

---

## 📋 PASSO 3: Instalar Dependências (Primeira Vez)

Execute:
```bash
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
```

**Isso pode levar alguns minutos na primeira vez.**

**Se der erro:** Tente:
```bash
python -m pip install --upgrade pip
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
```

---

## 📋 PASSO 4: Iniciar o Servidor

Execute:
```bash
python app.py
```

**Ou use o script automático:**
```bash
INICIAR_TUDO.bat
```

---

## 📋 PASSO 5: Verificar se Está Funcionando

Abra no navegador:
```
http://localhost:5000/health
```

**Deve aparecer:**
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando"
}
```

✅ **Se aparecer isso, o backend está funcionando!**

---

## 🎯 Método Rápido (Tudo em Um)

### Windows - Duplo Clique:
```
EXECUTAR_PRIMEIRO.bat
```

Ou:
```
INICIAR_TUDO.bat
```

**Este script faz tudo automaticamente!**

---

## 📝 Comandos Completos

### Primeira Vez (Instalação + Execução):
```bash
cd backend_pynfe
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
python app.py
```

### Próximas Vezes (Apenas Executar):
```bash
cd backend_pynfe
python app.py
```

---

## ✅ Verificações

### ✅ Backend está rodando se:
- Terminal mostra: `🚀 Backend NFC-e - Modo LOCAL`
- URL `http://localhost:5000/health` retorna `{"status": "ok"}`
- Não há erros no terminal

### ❌ Problemas comuns:

#### Erro: "Python não encontrado"
**Solução:**
1. Instale Python: https://www.python.org/downloads/
2. Marque "Add Python to PATH"
3. Reinicie o terminal

#### Erro: "ModuleNotFoundError: No module named 'flask'"
**Solução:**
```bash
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
```

#### Erro: "Port 5000 already in use"
**Solução:**
- Feche outro programa usando a porta 5000
- Ou altere a porta no `app.py` (linha 545)

#### Erro: "nfelib não está instalado"
**Solução (Opcional - apenas se quiser usar nfelib):**
```bash
python -m pip install nfelib
```

**Nota:** O backend funciona sem nfelib também (usa PyNFe como fallback).

---

## 🎯 Checklist Rápido

- [ ] Python instalado (`python --version` funciona)
- [ ] Navegou para pasta `backend_pynfe`
- [ ] Dependências instaladas (`pip install ...`)
- [ ] Servidor iniciado (`python app.py`)
- [ ] Health check OK (`http://localhost:5000/health`)

---

## 📚 Arquivos Úteis

- `INICIAR_TUDO.bat` - Script automático (Windows)
- `EXECUTAR_PRIMEIRO.bat` - Instalação completa (Windows)
- `COMECE_AQUI.md` - Guia rápido
- `GUIA_COMPLETO_NFCE.md` - Guia completo

---

## ✅ Pronto!

Depois que o backend estiver rodando:
1. Mantenha o terminal aberto
2. Configure a empresa no Flutter
3. Emita NFC-e pelo Flutter

**O backend precisa estar rodando enquanto você usa o sistema!**

---

## 🔍 Logs do Backend

O terminal mostrará:
- `[OK]` - Sucesso
- `[AVISO]` - Aviso (não impede funcionamento)
- `[ERRO]` - Erro (verificar)

**Exemplo de logs:**
```
>>> [nfelib] Iniciando emissão de NFC-e...
>>> [nfelib] XML gerado com sucesso
>>> [nfelib] Enviando para SEFAZ...
>>> [nfelib] ✅ NFC-e autorizada!
```

---

## ❓ Precisa de Ajuda?

1. Verifique se Python está instalado
2. Verifique se as dependências estão instaladas
3. Verifique se a porta 5000 está livre
4. Veja os logs no terminal
5. Consulte `GUIA_COMPLETO_NFCE.md` para mais detalhes

---

## ✅ Pronto para Usar!

Siga esses passos e o backend estará funcionando perfeitamente! 🎉











