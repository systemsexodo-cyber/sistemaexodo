# 🚀 Como Usar o Backend Local

## 📋 Passo a Passo Completo

### 1. Preparar Ambiente Python

#### Windows:
```bash
cd backend_pynfe
start_local.bat
```

#### Linux/Mac:
```bash
cd backend_pynfe
chmod +x start_local.sh
./start_local.sh
```

### 2. Verificar se Está Funcionando

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

### 3. Configurar Flutter

O Flutter já está configurado para usar `http://localhost:5000` por padrão.

**Para testar em dispositivo físico ou emulador:**

#### Android Emulator:
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://10.0.2.2:5000', // IP especial do Android Emulator
);
```

#### iOS Simulator:
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://localhost:5000', // Funciona no iOS Simulator
);
```

#### Dispositivo Físico:
1. Descubra o IP da sua máquina:
   - Windows: `ipconfig` (procure por IPv4)
   - Linux/Mac: `ifconfig` ou `ip addr`
   
2. Use o IP no Flutter:
```dart
final backendService = NFCeBackendService(
  baseUrl: 'http://192.168.1.100:5000', // Substitua pelo seu IP
);
```

3. **IMPORTANTE:** Certifique-se de que o dispositivo e o computador estão na mesma rede Wi-Fi.

### 4. Testar Emissão de NFC-e

```dart
import 'package:sistema_exodo/services/nfce_backend_service.dart';

// Verificar se backend está disponível
final backendService = NFCeBackendService();
final disponivel = await backendService.verificarConexao();

if (!disponivel) {
  print('❌ Backend não está disponível!');
  print('Verifique se o servidor Python está rodando.');
  return;
}

// Emitir NFC-e
try {
  final nfce = await backendService.emitir(
    empresa: empresa,
    produtos: produtos,
    quantidades: quantidades,
    pagamentos: pagamentos,
    valorTotal: valorTotal,
    cpfCnpjConsumidor: cpfCnpjConsumidor,
    nomeConsumidor: nomeConsumidor,
    observacoes: observacoes,
    ambienteHomologacao: true,
  );
  
  print('✅ NFC-e emitida: ${nfce.chaveAcesso}');
} catch (e) {
  print('❌ Erro: $e');
}
```

## 🔧 Troubleshooting

### Backend não responde

1. **Verifique se o servidor está rodando:**
   - Abra http://localhost:5000/health no navegador
   - Se não abrir, o servidor não está rodando

2. **Verifique a porta:**
   - Padrão: 5000
   - Se estiver em uso, altere no `.env`: `PORT=5001`

3. **Verifique firewall:**
   - Windows: Permitir Python no Firewall
   - Linux: `sudo ufw allow 5000`

### Erro de conexão no Flutter

1. **Android Emulator:**
   - Use `http://10.0.2.2:5000` (não localhost)

2. **Dispositivo físico:**
   - Use o IP da máquina (não localhost)
   - Certifique-se de que estão na mesma rede

3. **Verifique permissões:**
   - Android: Adicione no `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```

### PyNFe não instala

```bash
# Tentar instalar diretamente
pip install git+https://github.com/TadaSoftware/PyNFe.git

# Se não funcionar, tentar versão específica
pip install git+https://github.com/TadaSoftware/PyNFe.git@master

# Ou clonar e instalar manualmente
git clone https://github.com/TadaSoftware/PyNFe.git
cd PyNFe
pip install -e .
```

## 📝 Checklist

- [ ] Python 3.8+ instalado
- [ ] Ambiente virtual criado
- [ ] Dependências instaladas
- [ ] PyNFe instalado
- [ ] Arquivo `.env` configurado
- [ ] Servidor rodando (http://localhost:5000/health)
- [ ] Flutter configurado com URL correta
- [ ] Teste de conexão funcionando

## 🎯 Próximos Passos

1. **Testar localmente** - Certifique-se de que tudo funciona
2. **Fazer deploy no Firebase** - Quando estiver pronto
3. **Atualizar URL no Flutter** - Para usar Cloud Run

## 📚 Documentação Adicional

- `README_LOCAL.md` - Guia rápido local
- `DEPLOY_FIREBASE.md` - Guia de deploy para Firebase
- `INTEGRACAO_BACKEND_PYTHON.md` - Documentação completa


