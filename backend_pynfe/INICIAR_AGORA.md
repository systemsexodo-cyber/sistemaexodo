# 🚀 Como Iniciar o Backend Python (PyNFe)

## 📋 Pré-requisitos

- **Python 3.7+** instalado
- **Git** (para instalar PyNFe do GitHub)

## ⚡ Início Rápido

### 1. Abrir Terminal

Abra um **PowerShell** ou **Prompt de Comando** e navegue até a pasta:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend_pynfe"
```

### 2. Executar Script de Inicialização

```powershell
.\start_local.bat
```

O script irá:
- ✅ Criar ambiente virtual (se não existir)
- ✅ Instalar dependências automaticamente
- ✅ Instalar PyNFe do GitHub
- ✅ Iniciar o servidor na porta 5000

### 3. Verificar se Está Funcionando

Abra no navegador: **http://localhost:5000/health**

Você deve ver:
```json
{
    "status": "ok",
    "message": "Backend NFC-e está funcionando",
    "local": true,
    "pynfe_disponivel": true
}
```

## 🔧 Instalação Manual (Se o Script Não Funcionar)

### Passo 1: Criar Ambiente Virtual

```powershell
python -m venv venv
```

### Passo 2: Ativar Ambiente Virtual

```powershell
venv\Scripts\activate
```

### Passo 3: Instalar Dependências

```powershell
pip install -r requirements.txt
```

### Passo 4: Instalar PyNFe

```powershell
pip install git+https://github.com/TadaSoftware/PyNFe.git
```

Ou usando a versão do leotada (alternativa):

```powershell
pip install https://github.com/leotada/PyNFe/archive/master.zip
```

### Passo 5: Iniciar Servidor

```powershell
python app.py
```

## 📝 Dependências Necessárias

O PyNFe requer:

- **Java 8u51+** - Para geração da DANFE (opcional, apenas se quiser gerar DANFE)
- **lxml** - Biblioteca XML (já está no requirements.txt)
- **xmlsec1** e **openssl** - Para assinatura XML (já configurado no Python via bibliotecas)
- **requests** - Comunicação com webservices (já está no requirements.txt)

Todas as dependências Python já estão no `requirements.txt`!

## 🔍 Verificar Instalação

### Verificar Python:

```powershell
python --version
```

Deve mostrar: `Python 3.x.x`

### Verificar PyNFe:

```powershell
pip show pynfe
```

Deve mostrar informações sobre o PyNFe instalado.

### Verificar Ambiente Virtual:

```powershell
where python
```

Se estiver no ambiente virtual, deve mostrar caminho com `venv\Scripts\python.exe`

## 🐛 Problemas Comuns

### Erro: "python não é reconhecido"

**Solução:**
1. Instale Python: https://www.python.org/downloads/
2. Na instalação, marque **"Add Python to PATH"**
3. Reinicie o terminal

### Erro: "git não é reconhecido"

**Solução:**
1. Instale Git: https://git-scm.com/download/win
2. Reinicie o terminal

### Erro ao instalar PyNFe do GitHub

**Tente alternativa:**
```powershell
pip install https://github.com/leotada/PyNFe/archive/master.zip
```

### Porta 5000 já em uso

**Solução:**
1. Pare outros servidores rodando na porta 5000
2. Ou edite `app.py` e mude a porta:
   ```python
   app.run(host='0.0.0.0', port=5001, debug=True)
   ```

### Erro: "ModuleNotFoundError: No module named 'pynfe'"

**Solução:**
1. Certifique-se de que o ambiente virtual está ativado
2. Reinstale: `pip install git+https://github.com/TadaSoftware/PyNFe.git`

## ✅ Checklist de Verificação

- [ ] Python 3.7+ instalado
- [ ] Ambiente virtual criado (`venv` existe)
- [ ] Ambiente virtual ativado (aparece `(venv)` no prompt)
- [ ] Dependências instaladas (`pip install -r requirements.txt`)
- [ ] PyNFe instalado (`pip show pynfe`)
- [ ] Servidor iniciado (`start_local.bat`)
- [ ] Health check funcionando (http://localhost:5000/health)

## 🎯 Após Iniciar o Servidor

O servidor estará rodando em: **http://localhost:5000**

O Flutter já está configurado para usar esta URL automaticamente!

Para parar o servidor, pressione **Ctrl+C** no terminal.

---

**Dica:** Use `start_local.bat` - ele faz tudo automaticamente! 🚀
