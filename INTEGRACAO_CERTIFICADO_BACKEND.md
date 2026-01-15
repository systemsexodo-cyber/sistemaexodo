# Integração do Backend Python para Validação de Certificados

## Resumo

O cadastro de empresa agora utiliza o backend Python (PyNFe) para validar certificados digitais, com fallback automático para o serviço local caso o backend não esteja disponível.

## Arquivos Modificados

### 1. `lib/services/certificado_backend_service.dart` (NOVO)
- Serviço Flutter para comunicação com o backend Python
- Método `validarCertificado()` que envia certificado em base64 e senha para o backend
- Método `verificarDisponibilidade()` para verificar se o backend está rodando
- Tratamento de erros com fallback automático

### 2. `lib/pages/adicionar_empresa_page.dart`
- **Importação**: Adicionado `certificado_backend_service.dart`
- **`_processarCertificadoPFX()`**: 
  - Tenta validar via backend Python primeiro
  - Se backend não disponível ou falhar, usa serviço local (fallback)
  - Mostra mensagem indicando qual método foi usado
- **`_processarCertificadoPEM()`**: 
  - Mesma estratégia: backend primeiro, fallback local
  - Valida certificados PEM via backend Python
- **`_selecionarCertificadoWindows()`**: 
  - Após exportar certificado do Windows, valida via backend Python
  - Mostra informações do certificado (CNPJ, validade) após validação

### 3. `backend_pynfe/services/certificado_service.py`
- **Suporte a PEM**: Adicionado método `_carregar_pem()` para processar certificados PEM
- **Detecção automática**: Método `_is_pem_format()` detecta se o certificado é PEM ou PFX
- **`carregar_certificado()`**: Agora suporta tanto PFX quanto PEM automaticamente
- **Extração de informações**: Extrai CNPJ, validade, subject e issuer de ambos os formatos

### 4. `backend_pynfe/app.py`
- Endpoint `/api/certificado/validar` já existia e está funcionando
- Aceita certificados em base64 (PFX ou PEM)
- Retorna informações de validação (CNPJ, validade, dias restantes)

## Fluxo de Validação

### 1. Certificado PFX
```
Usuário seleciona arquivo PFX
    ↓
Sistema salva em base64
    ↓
Tenta validar via backend Python
    ├─ Sucesso → Mostra informações (CNPJ, validade)
    └─ Falha → Tenta serviço local (fallback)
        ├─ Sucesso → Mostra informações
        └─ Falha → Mostra erro mas permite salvar
```

### 2. Certificado PEM
```
Usuário seleciona arquivo PEM
    ↓
Sistema salva em base64
    ↓
Tenta validar via backend Python
    ├─ Sucesso → Mostra informações
    └─ Falha → Tenta serviço local (fallback)
        ├─ Sucesso → Mostra informações
        └─ Falha → Mostra erro mas permite salvar
```

### 3. Certificado do Windows
```
Usuário seleciona certificado do Windows
    ↓
Sistema exporta certificado (PEM ou PFX)
    ↓
Converte para base64
    ↓
Tenta validar via backend Python
    ├─ Sucesso → Mostra informações completas
    └─ Falha → Salva sem validação (certificado já foi validado pelo Windows)
```

## Vantagens

1. **Validação Robusta**: Usa biblioteca Python (cryptography) que é mais robusta para processar certificados
2. **Suporte a Múltiplos Formatos**: PFX e PEM são suportados automaticamente
3. **Fallback Automático**: Se o backend não estiver disponível, usa o serviço local
4. **Feedback ao Usuário**: Mostra claramente qual método foi usado (backend ou local)
5. **Informações Detalhadas**: Extrai e exibe CNPJ, validade e dias restantes

## Como Usar

### 1. Certificado PFX
1. Clique em "Selecionar Certificado"
2. Escolha arquivo `.pfx` ou `.p12`
3. Digite a senha quando solicitado
4. Sistema valida automaticamente via backend Python (se disponível)

### 2. Certificado PEM
1. Clique em "Selecionar Certificado"
2. Escolha arquivo `.pem`, `.crt` ou `.key`
3. Digite a senha se o certificado estiver protegido
4. Sistema valida automaticamente via backend Python (se disponível)

### 3. Certificado do Windows
1. Clique em "Selecionar Certificado do Windows"
2. Escolha o certificado na lista
3. Digite a senha quando solicitado
4. Sistema exporta e valida automaticamente via backend Python (se disponível)

## Requisitos

- Backend Python rodando em `http://localhost:5000` (ou URL configurada)
- Dependências Python instaladas: `cryptography`, `pyOpenSSL`
- Certificado válido com chave privada

## Notas

- Se o backend não estiver disponível, o sistema usa automaticamente o serviço local
- Certificados são sempre salvos em base64 para garantir portabilidade
- Validação é feita em tempo real ao selecionar o certificado
- Mensagens de erro são claras e orientam o usuário sobre o problema


