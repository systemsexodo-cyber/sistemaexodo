# 🔗 Integração com Backend Python (PyNFe)

## 📋 Visão Geral

Este documento explica como integrar o Flutter com o backend Python que usa PyNFe para emissão de NFC-e.

## 🏗️ Arquitetura

```
Flutter App
    ↓ HTTP/REST
Backend Python (Flask)
    ↓ PyNFe
SEFAZ
```

## 🚀 Passo a Passo

### 1. Configurar Backend Python

#### 1.1. Instalar Dependências

```bash
cd backend_pynfe
python -m venv venv
venv\Scripts\activate  # Windows
# ou
source venv/bin/activate  # Linux/Mac

pip install -r requirements.txt
```

#### 1.2. Configurar Variáveis de Ambiente

```bash
cp .env.example .env
# Editar .env com suas configurações
```

#### 1.3. Iniciar Servidor

```bash
python app.py
```

O servidor será iniciado em `http://localhost:5000`

### 2. Configurar Flutter

#### 2.1. Adicionar Dependência HTTP (se ainda não tiver)

O projeto já tem `http: ^1.6.0` no `pubspec.yaml`, então está pronto!

#### 2.2. Usar NFCeBackendService

Substitua o uso de `NFCeService` por `NFCeBackendService`:

```dart
import 'package:sistema_exodo/services/nfce_backend_service.dart';

// Criar instância do serviço
final nfceBackendService = NFCeBackendService(
  baseUrl: 'http://localhost:5000', // ou IP do servidor
);

// Emitir NFC-e
try {
  final nfce = await nfceBackendService.emitir(
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
  
  // NFC-e emitida com sucesso!
  print('NFC-e emitida: ${nfce.chaveAcesso}');
} catch (e) {
  print('Erro ao emitir NFC-e: $e');
}
```

### 3. Verificar Conexão

Antes de emitir, verifique se o backend está disponível:

```dart
final backendService = NFCeBackendService();
final disponivel = await backendService.verificarConexao();

if (!disponivel) {
  // Mostrar erro ao usuário
  print('Backend não está disponível. Verifique se o servidor Python está rodando.');
  return;
}
```

## 📡 Endpoints Disponíveis

### POST /api/nfce/emitir
Emite uma NFC-e

**Request:**
```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "razao_social": "Empresa Teste",
    "certificado_base64": "...",
    "senha_certificado": "...",
    ...
  },
  "produtos": [...],
  "pagamentos": [...],
  "consumidor": {...}
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "chave_acesso": "35200112345678000190650010000000011234567890",
    "numero": "1",
    "serie": "1",
    "protocolo": "123456789012345",
    "status": "autorizada",
    "xml": "...",
    "qr_code": "..."
  }
}
```

### POST /api/nfce/consultar
Consulta status de uma NFC-e

### POST /api/certificado/validar
Valida um certificado digital

### GET /health
Verifica se o servidor está funcionando

## 🔧 Configuração para Produção

### 1. Alterar URL do Backend

```dart
final nfceBackendService = NFCeBackendService(
  baseUrl: 'https://seu-servidor.com', // URL do servidor em produção
);
```

### 2. Configurar HTTPS

O backend deve usar HTTPS em produção. Configure um certificado SSL.

### 3. Configurar CORS

O backend já tem CORS configurado para aceitar requisições do Flutter.

## 🐛 Troubleshooting

### Backend não responde

1. Verifique se o servidor Python está rodando:
   ```bash
   python app.py
   ```

2. Verifique se a porta está correta (padrão: 5000)

3. Verifique firewall/antivírus

### Erro de certificado

1. Verifique se o certificado está em base64 válido
2. Verifique se a senha está correta
3. Verifique se o certificado não está expirado

### Erro de conexão

1. Verifique se o Flutter tem permissão de internet
2. Verifique se o backend está acessível
3. Verifique se não há proxy bloqueando

## 📝 Notas Importantes

1. **PyNFe pode precisar de ajustes:** A biblioteca PyNFe pode não estar 100% atualizada. Pode ser necessário fazer ajustes no código do backend.

2. **Certificados temporários:** Os certificados são salvos temporariamente no servidor. Certifique-se de que o diretório temporário tem permissões de escrita.

3. **Ambiente:** Por padrão, o sistema usa ambiente de homologação. Altere `ambiente_homologacao` para `false` em produção.

4. **Performance:** A comunicação via HTTP adiciona latência. Considere isso na experiência do usuário.

## 🔄 Migração da Implementação Manual

Para migrar da implementação manual para o backend:

1. **Mantenha ambas as implementações** inicialmente
2. **Adicione um flag de configuração** para escolher qual usar
3. **Teste o backend** em homologação
4. **Migre gradualmente** para o backend

Exemplo:

```dart
class NFCeServiceFactory {
  static NFCeServiceBase criar({bool usarBackend = false}) {
    if (usarBackend) {
      return NFCeBackendService();
    } else {
      return NFCeService(); // Implementação manual
    }
  }
}
```

## ✅ Vantagens do Backend Python

- ✅ Biblioteca PyNFe mais completa e testada
- ✅ Menos código para manter no Flutter
- ✅ Atualizações automáticas da biblioteca
- ✅ Facilita testes e debug

## ⚠️ Desvantagens

- ⚠️ Precisa criar e manter um backend
- ⚠️ Dependência de servidor
- ⚠️ Mais complexidade de arquitetura
- ⚠️ Latência adicional (HTTP)

## 📚 Referências

- **PyNFe:** https://github.com/TadaSoftware/PyNFe
- **Flask:** https://flask.palletsprojects.com/
- **Flask-CORS:** https://flask-cors.readthedocs.io/


