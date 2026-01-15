# ✅ Configuração Completa - Backend Python para NFC-e

## 🎯 O Que Foi Configurado

### 1. ✅ Backend Python (PyNFe)
- **Localização:** `backend_pynfe/`
- **Status:** Configurado para rodar localmente
- **Ambiente:** Homologação (padrão)
- **Porta:** 5000 (configurável)

### 2. ✅ Código Flutter Atualizado
- **Arquivo:** `lib/pages/venda_direta_page.dart`
- **Mudança:** Agora usa `NFCeBackendService` por padrão
- **Fallback:** Se backend não estiver disponível, mostra erro claro

### 3. ✅ Serviços Criados
- `lib/services/nfce_backend_service.dart` - Comunicação com backend Python
- `lib/services/nfce_service_factory.dart` - Factory para escolher serviço
- `backend_pynfe/services/nfce_service.py` - Serviço Python de emissão
- `backend_pynfe/services/certificado_service.py` - Serviço Python de certificados

## 🚀 Como Usar

### Passo 1: Iniciar Backend Python

```bash
cd backend_pynfe
start_local.bat  # Windows
# ou
./start_local.sh  # Linux/Mac
```

O servidor iniciará em: **http://localhost:5000**

### Passo 2: Verificar se Está Funcionando

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

### Passo 3: Emitir NFC-e no Flutter

1. **Finalize uma venda** na tela de Venda Direta
2. **Clique em "Emitir NFC-e"** no popup de sucesso
3. **O sistema irá:**
   - Verificar se backend está disponível
   - Enviar dados para o backend Python
   - Backend Python emite NFC-e na SEFAZ (homologação)
   - Retorna resultado para Flutter
   - Exibe QR Code se autorizada

## 🔧 Configuração de Homologação

### Backend Python
O backend está configurado para **homologação por padrão**:

```python
# Em nfce_service.py
ambiente_homologacao = empresa_data.get('ambiente_homologacao', True)  # Padrão: True
```

### Flutter
O Flutter usa a configuração da empresa:

```dart
final ambienteHomologacao = empresa.ambienteHomologacao ?? true;  // Padrão: Homologação
```

## 📋 Fluxo Completo

```
Flutter App
    ↓ HTTP POST
Backend Python (Flask)
    ↓ PyNFe
SEFAZ Homologação
    ↓ Resposta
Backend Python
    ↓ JSON
Flutter App
    ↓ Exibe QR Code
Usuário
```

## 🔍 Logs e Debug

### Backend Python
Os logs aparecem no terminal onde o servidor está rodando:
```
>>> [PyNFe] Emitindo NFC-e em modo HOMOLOGAÇÃO
>>> [PyNFe] Enviando NFC-e para SEFAZ...
>>> [PyNFe] Status: autorizada
```

### Flutter
Os logs aparecem no console do Flutter:
```
>>> [NFCeBackend] Iniciando emissão via backend Python...
>>> [NFCeBackend] Status: 200
>>> [NFCeBackend] ✓✓✓ NFC-e emitida com sucesso!
```

## ⚙️ Configurações Importantes

### URL do Backend

**Modo Local (Padrão):**
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://localhost:5000',
);
```

**Android Emulator:**
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://10.0.2.2:5000',
);
```

**Dispositivo Físico:**
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://192.168.1.100:5000', // IP da sua máquina
);
```

### Ambiente (Homologação/Produção)

**Configurar na Empresa:**
- Vá em "Empresas" → Edite a empresa
- Campo "Ambiente Homologação": ✅ Marcado = Homologação, ❌ Desmarcado = Produção

**Padrão:** Homologação (✅ marcado)

## 🐛 Troubleshooting

### Backend não responde

**Sintoma:** Erro "Backend Python não está disponível"

**Solução:**
1. Verifique se o servidor está rodando: http://localhost:5000/health
2. Se não estiver, inicie: `cd backend_pynfe && start_local.bat`
3. Verifique firewall/antivírus

### PyNFe não instalado

**Sintoma:** Health check mostra `pynfe_disponivel: false`

**Solução:**
```bash
cd backend_pynfe
.\venv\Scripts\Activate.ps1
pip install git+https://github.com/TadaSoftware/PyNFe.git
```

### Erro de certificado

**Sintoma:** "Certificado digital não fornecido"

**Solução:**
1. Vá em "Empresas" → Edite a empresa
2. Selecione o certificado novamente
3. Preencha a senha
4. Salve a empresa

### NFC-e rejeitada

**Sintoma:** Status "rejeitada" na resposta

**Possíveis causas:**
- Dados da empresa incompletos (CNPJ, IE, endereço)
- Produtos sem NCM, CFOP ou Origem
- Certificado inválido ou expirado
- Ambiente incorreto (tentando produção com certificado de homologação)

## ✅ Checklist de Configuração

- [ ] Python instalado (3.12.10)
- [ ] Ambiente virtual criado
- [ ] Dependências instaladas (Flask, etc)
- [ ] PyNFe instalado (opcional, mas recomendado)
- [ ] Servidor rodando (http://localhost:5000/health)
- [ ] Certificado digital configurado na empresa
- [ ] Senha do certificado preenchida
- [ ] CSC configurado (para produção)
- [ ] Ambiente configurado (homologação/produção)
- [ ] Flutter configurado para usar backend

## 📝 Próximos Passos

1. **Testar emissão em homologação**
2. **Verificar logs do backend e Flutter**
3. **Ajustar conforme necessário**
4. **Quando estiver pronto, fazer deploy no Firebase**

## 🔗 Arquivos Modificados

### Flutter:
- `lib/pages/venda_direta_page.dart` - Usa backend Python
- `lib/services/nfce_backend_service.dart` - Serviço de comunicação
- `lib/services/nfce_service_factory.dart` - Factory (criado)

### Python:
- `backend_pynfe/app.py` - Servidor Flask
- `backend_pynfe/services/nfce_service.py` - Emissão NFC-e
- `backend_pynfe/services/certificado_service.py` - Certificados

## 🎉 Status Final

✅ **Backend Python configurado**
✅ **Código Flutter atualizado**
✅ **Integração completa**
✅ **Configurado para homologação**

**Pronto para testar a emissão de NFC-e!**


