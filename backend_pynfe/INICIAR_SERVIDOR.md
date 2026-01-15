# Como Executar o Servidor Backend NFC-e

## 🚀 Formas de Executar

### Opção 1: Execução Direta (Mais Simples)
```bash
cd backend_pynfe
python app.py
```

### Opção 2: Usando Script Batch (Windows)
Duplo clique em:
- `start_local.bat` - Configura tudo automaticamente
- `iniciar_simples.bat` - Versão simplificada

### Opção 3: Com Ambiente Virtual
```bash
cd backend_pynfe

# Criar ambiente virtual (se não existir)
python -m venv venv

# Ativar ambiente virtual
# Windows:
venv\Scripts\activate
# Linux/Mac:
source venv/bin/activate

# Instalar dependências (se necessário)
pip install -r requirements.txt

# Executar servidor
python app.py
```

## 📋 Informações do Servidor

- **URL Local**: http://localhost:5000
- **Health Check**: http://localhost:5000/health
- **Endpoint NFC-e**: http://localhost:5000/api/nfce/emitir
- **Porta Padrão**: 5000 (pode ser alterada via variável de ambiente PORT)

## 🔧 Variáveis de Ambiente

Crie um arquivo `.env` na pasta `backend_pynfe` com:
```
PORT=5000
DEBUG=True
CORS_ORIGINS=*
MAX_CONTENT_LENGTH=10485760
```

## ✅ Verificar se Está Funcionando

Abra no navegador ou use curl:
```bash
curl http://localhost:5000/health
```

Deve retornar:
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando"
}
```

## 🛑 Parar o Servidor

Pressione `Ctrl+C` no terminal onde o servidor está rodando.

## 📝 Notas

- O servidor usa o **PyNFe novo** (`nfce_pynfe_novo.py`) por padrão
- Se o PyNFe novo não estiver disponível, tenta usar a versão antiga
- Certifique-se de que o PyNFe está instalado: `pip install pynfe`





