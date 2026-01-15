# 🚀 Backend NFC-e - Modo Local

## 📋 Guia Rápido

### Windows

1. **Executar script de inicialização:**
   ```bash
   start_local.bat
   ```

2. **Ou manualmente:**
   ```bash
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   pip install git+https://github.com/TadaSoftware/PyNFe.git
   python app.py
   ```

### Linux/Mac

1. **Dar permissão de execução:**
   ```bash
   chmod +x start_local.sh
   ```

2. **Executar script:**
   ```bash
   ./start_local.sh
   ```

3. **Ou manualmente:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   pip install git+https://github.com/TadaSoftware/PyNFe.git
   python app.py
   ```

## ✅ Verificar se está funcionando

Abra no navegador: http://localhost:5000/health

Você deve ver:
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando",
  "local": true,
  "pynfe_disponivel": true
}
```

## 🔧 Configuração

1. **Criar arquivo `.env`:**
   ```bash
   cp .env.example .env
   ```

2. **Editar `.env`:**
   ```env
   PORT=5000
   DEBUG=True
   ```

## 📡 Endpoints Disponíveis

- `GET /health` - Verificar se está funcionando
- `POST /api/nfce/emitir` - Emitir NFC-e
- `POST /api/nfce/consultar` - Consultar NFC-e
- `POST /api/certificado/validar` - Validar certificado

## 🔗 Conectar Flutter

No Flutter, use:
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://localhost:5000',
);
```

**Para testar em dispositivo físico ou emulador Android:**
- Use `http://10.0.2.2:5000` (Android Emulator)
- Use o IP da sua máquina (ex: `http://192.168.1.100:5000`)

## 🐛 Troubleshooting

### Porta já em uso
```bash
# Alterar porta no .env
PORT=5001
```

### PyNFe não instala
```bash
# Tentar versão específica
pip install git+https://github.com/TadaSoftware/PyNFe.git@master
```

### Erro de certificado
- Verifique se o certificado está em base64 válido
- Verifique se a senha está correta

## 📝 Próximos Passos

Após testar localmente, você pode migrar para Firebase Cloud Run seguindo o guia de deploy.


