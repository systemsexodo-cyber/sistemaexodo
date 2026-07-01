# 📦 Instalador Bridge NFC-e v347

## 🎯 Versão 347 - Emissão 100% Local

### ✅ Novidades desta versão:
- **Compatibilidade total** com nova arquitetura local
- **Endpoints atualizados**: `/api/nfce/emitir`, `/api/nfce/cancelar`, `/api/nfce/consultar`
- **Salvamento dual**: SQLite local + Supabase nuvem
- **Detecção automática** do bridge pelo app Flutter
- **Operação offline** garantida

---

## 📁 Arquivos do Pacote

### Executáveis:
- `ExodoNfceBridge_v347.exe` (36.5 MB) - Bridge principal
- `ExodoNfceBridgeWatchdog_v347.exe` (33.2 MB) - Monitoramento

### Configuração:
- `firebase-credentials.json` - Credenciais Firebase (se necessário)
- `bridge_identity.json` - Identidade da última empresa

### Logs:
- `bridge_log.txt` - Log de operações
- `watchdog_log.txt` - Log do monitoramento

---

## 🚀 Instalação Rápida

### 1️⃣ Criar pasta de instalação:
```
C:\ExodoNFCe\
```

### 2️⃣ Copiar arquivos:
```
✓ ExodoNfceBridge_v347.exe
✓ ExodoNfceBridgeWatchdog_v347.exe
✓ firebase-credentials.json (se existir)
```

### 3️⃣ Executar:
```
✓ Duplo clique em ExodoNfceBridge_v347.exe
✓ Mantenha o programa aberto durante o uso
```

---

## 🔧 Configuração de Firewall

### Windows Defender:
1. **Abrir Firewall do Windows**
2. **Configurações Avançadas**
3. **Regras de Entrada** → **Nova Regra**
4. **Programa**: `C:\ExodoNFCe\ExodoNfceBridge_v347.exe`
5. **Porta**: 8000
6. **Perfil**: Rede Privada
7. **Ação**: Permitir

### Antivírus:
- Adicionar exceção para `C:\ExodoNFCe\`
- Marcar como "Programa Confiável"

---

## 📡 Endpoints Disponíveis

### Status:
```
GET  http://localhost:8000/
GET  http://localhost:8000/health
```

### NFC-e:
```
POST http://localhost:8000/api/nfce/emitir
POST http://localhost:8000/api/nfce/cancelar
POST http://localhost:8000/api/nfce/consultar
```

### Certificado:
```
POST http://localhost:8000/api/certificado/validar
```

---

## 🧪 Teste de Funcionamento

### 1. Verificar Status:
```powershell
curl http://localhost:8000/
```
**Resposta esperada:**
```json
{
  "status": "online",
  "message": "Emissor NFC-e Exodo rodando!"
}
```

### 2. Testar Endpoint:
```powershell
curl -X POST http://localhost:8000/api/nfce/emitir `
  -H "Content-Type: application/json" `
  -d '{"test": true}'
```
**Resposta esperada:** Erro de validação (confirma que endpoint funciona)

---

## 📱 Integração com App Flutter

O app Flutter detectará automaticamente:
1. **Bridge rodando** em `localhost:8000`
2. **Endpoints disponíveis** com prefixo `/api/nfce/`
3. **Status online/offline** em tempo real

### Configuração no App:
```dart
// Auto-detecção (recomendado)
final service = await NFCeBackendService.createWithAutoDetection();

// URL manual (se necessário)
final service = NFCeBackendService(baseUrl: 'http://localhost:8000');
```

---

## 🛠️ Solução de Problemas

### Bridge não inicia:
- ✅ Verificar .NET Framework 4.8
- ✅ Verificar permissões de administrador
- ✅ Verificar antivírus/firewall

### Porta 8000 em uso:
- ✅ Fechar outros programas na porta 8000
- ✅ Reiniciar computador
- ✅ Mudar porta (requer recompilação)

### Erro de certificado:
- ✅ Verificar arquivo .pfx/.p12
- ✅ Verificar senha do certificado
- ✅ Verificar validade do certificado

---

## 📋 Checklist Final

- [ ] Bridge v347 instalado em `C:\ExodoNFCe\`
- [ ] Firewall configurado para porta 8000
- [ ] Antivírus com exceção para o bridge
- [ ] Bridge respondendo em `http://localhost:8000/`
- [ ] App Flutter detectando bridge automaticamente
- [ ] Teste de emissão funcionando

---

## 🎉 Suporte

- **Versão**: v347
- **Data**: 16/04/2026
- **Compatibilidade**: Windows 10+ com .NET Framework 4.8
- **Suporte**: suporte@exodo.com.br

**Pronto para emissão 100% local!** 🚀
