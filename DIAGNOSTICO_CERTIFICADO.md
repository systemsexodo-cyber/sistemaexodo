# 🔍 DIAGNÓSTICO: Certificado não processa na NFC-e

## ✅ CORREÇÕES IMPLEMENTADAS:

### 1. **Detecção melhorada de PEM**
   - Agora detecta `windows:pem:` na URL
   - Verifica conteúdo PEM antes de processar
   - Logs detalhados em cada etapa

### 2. **Logs detalhados**
   - `certificado_service.dart`: Logs em cada etapa de processamento
   - `nfce_service.dart`: Logs ao carregar certificado
   - `adicionar_empresa_page.dart`: Logs ao salvar/carregar empresa

### 3. **Salvamento garantido**
   - `certificadoDigitalBytes` sempre salvo em base64
   - `certificadoWindowsThumbprint` salvo quando vem do Windows
   - `certificadoWindowsSubject` salvo para identificação

## 🧪 COMO TESTAR:

### 1. **Salvar certificado:**
   - Vá em "Empresas" → "Adicionar/Editar Empresa"
   - Selecione certificado (Windows ou arquivo)
   - Preencha senha
   - Salve a empresa
   - **Verifique os logs no console:**
     ```
     >>> [AdicionarEmpresa] Carregando certificado da empresa:
     >>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (XXXX chars)
     ```

### 2. **Emitir NFC-e:**
   - Vá em "Venda Direta"
   - Adicione produtos
   - Clique em "Emitir NFC-e"
   - **Verifique os logs no console:**
     ```
     >>> [NFCe] Carregando certificado digital...
     >>> [NFCe] certificadoDigitalBytes: presente (XXXX chars)
     >>> [Certificado] Certificado em base64 detectado
     >>> [Certificado] ✓✓✓ Detectado PEM em base64 (texto)
     >>> [NFCe] ✓✓✓ Certificado carregado com sucesso
     ```

## 🔧 SE AINDA NÃO FUNCIONAR:

### Verifique os logs:

1. **Ao salvar empresa:**
   - Procure por: `>>> [AdicionarEmpresa]`
   - Verifique se `certificadoDigitalBytes` está presente

2. **Ao emitir NFC-e:**
   - Procure por: `>>> [NFCe]` e `>>> [Certificado]`
   - Verifique qual etapa está falhando

### Possíveis problemas:

1. **Certificado não está sendo salvo:**
   - Verifique se `_certificadoDigitalBytes` não é null antes de salvar
   - Verifique se está sendo salvo em `configuracoes['certificadoDigitalBytes']`

2. **Certificado não está sendo carregado:**
   - Verifique se `empresa.configuracoes?['certificadoDigitalBytes']` não é null
   - Verifique se a URL está correta (`windows:pem:` ou caminho do arquivo)

3. **Certificado não está sendo processado:**
   - Verifique se é PEM válido (contém `-----BEGIN CERTIFICATE-----`)
   - Verifique se a senha está correta
   - Verifique os logs de erro específicos

## 📋 LOGS ESPERADOS:

### Ao salvar empresa:
```
>>> [AdicionarEmpresa] Carregando certificado da empresa:
>>> [AdicionarEmpresa]   certificadoDigitalUrl: windows:pem:CN=...
>>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (5000 chars)
>>> [AdicionarEmpresa]   certificadoWindowsThumbprint: ABC123...
>>> [AdicionarEmpresa] Certificado do Windows carregado: CN=...
```

### Ao emitir NFC-e:
```
>>> [NFCe] ========================================
>>> [NFCe] Carregando certificado digital...
>>> [NFCe] certificadoDigitalUrl: windows:pem:CN=...
>>> [NFCe] certificadoDigitalBytes: presente (5000 chars)
>>> [NFCe] ========================================
>>> [Certificado] ========================================
>>> [Certificado] Certificado em base64 detectado
>>> [Certificado] URL: windows:pem:CN=...
>>> [Certificado] Tamanho base64: 5000 caracteres
>>> [Certificado] ========================================
>>> [Certificado] isPEMFromUrl: true
>>> [Certificado] Base64 decodificado: 3750 bytes
>>> [Certificado] Decodificado como UTF-8: 3750 caracteres
>>> [Certificado] ✓✓✓ Detectado PEM em base64 (texto)
>>> [Certificado] PEM decodificado: 3750 caracteres
>>> [Certificado] Arquivo PEM temporário salvo: C:\...\certificado_pem_1234567890.pem
>>> [NFCe] ✓✓✓ Certificado carregado com sucesso
>>> [NFCe] CNPJ: 12.345.678/0001-90
>>> [NFCe] Validade: 2025-12-31
>>> [NFCe] Chave privada: presente
```

## ✅ PRONTO!

Agora o sistema tem logs detalhados em cada etapa. Teste e me envie os logs se ainda não funcionar!




