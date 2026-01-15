# 📦 Instalação do Backend Python

## ⚠️ Importante sobre PyNFe

A biblioteca PyNFe pode não estar disponível no PyPI oficial. Siga as instruções abaixo para instalar.

## 🚀 Instalação Passo a Passo

### 1. Criar Ambiente Virtual

```bash
# Windows
python -m venv venv
venv\Scripts\activate

# Linux/Mac
python3 -m venv venv
source venv/bin/activate
```

### 2. Instalar Dependências Básicas

```bash
pip install Flask==3.0.0 Flask-CORS==4.0.0
pip install lxml==4.9.3 requests==2.31.0
pip install python-dotenv==1.0.0
pip install cryptography==41.0.7 pyOpenSSL==23.3.0
pip install zeep==4.2.1
```

### 3. Instalar PyNFe

**Opção A: Do GitHub (Recomendado)**
```bash
pip install git+https://github.com/TadaSoftware/PyNFe.git
```

**Opção B: Manual**
```bash
git clone https://github.com/TadaSoftware/PyNFe.git
cd PyNFe
pip install -e .
```

**Opção C: Se PyNFe não funcionar, usar alternativa**

Se o PyNFe não estiver funcionando, você pode:
1. Usar outra biblioteca como `nfselib`
2. Implementar manualmente usando `zeep` para SOAP
3. Usar `suds-py3` para comunicação SOAP

### 4. Verificar Instalação

```bash
python -c "import flask; print('Flask OK')"
python -c "import pynfe; print('PyNFe OK')"  # Se instalado
```

### 5. Configurar Variáveis de Ambiente

```bash
cp .env.example .env
# Editar .env com suas configurações
```

### 6. Testar Servidor

```bash
python app.py
```

Você deve ver:
```
🚀 Iniciando servidor NFC-e na porta 5000
📝 Modo debug: True
 * Running on http://0.0.0.0:5000
```

## 🔧 Troubleshooting

### Erro: "No module named 'pynfe'"

**Solução:** Instale o PyNFe do GitHub:
```bash
pip install git+https://github.com/TadaSoftware/PyNFe.git
```

### Erro: "git não encontrado"

**Solução:** Instale o Git ou baixe o PyNFe manualmente:
1. Baixe o ZIP do GitHub: https://github.com/TadaSoftware/PyNFe
2. Extraia em uma pasta
3. Execute: `pip install -e /caminho/para/PyNFe`

### Erro: "lxml não instala"

**Solução Windows:**
```bash
# Instalar Visual C++ Build Tools primeiro
# Ou usar wheel pré-compilado:
pip install lxml --only-binary :all:
```

**Solução Linux:**
```bash
sudo apt-get install python3-dev libxml2-dev libxslt1-dev
pip install lxml
```

### Erro: "cryptography não instala"

**Solução:**
```bash
# Windows: Instalar Visual C++ Build Tools
# Linux: 
sudo apt-get install build-essential libssl-dev libffi-dev python3-dev
pip install cryptography
```

## 📝 Nota sobre PyNFe

O PyNFe pode não estar 100% atualizado ou pode ter problemas de compatibilidade. Se encontrar problemas:

1. **Verifique a versão do Python:** PyNFe pode precisar Python 3.8-3.10
2. **Use uma versão específica do PyNFe:** Tente versões diferentes
3. **Considere alternativas:** Use `zeep` diretamente para SOAP ou outra biblioteca

## ✅ Próximos Passos

Após instalar com sucesso:
1. Configure o arquivo `.env`
2. Inicie o servidor: `python app.py`
3. Teste a conexão do Flutter


