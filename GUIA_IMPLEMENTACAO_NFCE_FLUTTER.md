# 📱 Guia de Implementação de NFC-e no Flutter com Certificado Digital

## 🎯 Visão Geral

Este guia descreve como implementar a emissão de NFC-e no Flutter usando certificado digital A1 (PFX/PEM), seguindo as melhores práticas de segurança.

## ⚠️ Importante: Abordagem Recomendada

**A melhor prática para emissão de NFC-e é utilizar um Backend dedicado.**

### Por quê?

1. **Segurança**: O certificado digital (especialmente a chave privada) é um documento de altíssima segurança. Expor o arquivo PFX ou a chave privada PEM no código-fonte de um aplicativo Flutter (que pode ser descompilado) é um **risco de segurança grave**.

2. **Complexidade**: A lógica de assinatura XML (XML Digital Signature) e a comunicação com os Web Services da SEFAZ são complexas e mudam com frequência. Bibliotecas maduras de backend (como o **ACBr** em Delphi/Lazarus, **NFePHP** em PHP, ou soluções em C#/.NET) já lidam com essa complexidade.

### Fluxo Recomendado (Backend)

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Flutter   │────────▶│   Backend   │────────▶│   SEFAZ     │
│  (Frontend) │         │  (Servidor) │         │ (Web Service)│
└─────────────┘         └─────────────┘         └─────────────┘
     │                          │                          │
     │ 1. Envia dados da venda │                          │
     │                          │ 2. Monta XML da NFC-e   │
     │                          │ 3. Assina XML (PFX/PEM) │
     │                          │ 4. Envia para SEFAZ     │
     │                          │                          │
     │ 5. Recebe resultado      │ 5. Retorna protocolo    │
     │    (QR Code, URL)        │    (QR Code, URL)       │
     └──────────────────────────┴──────────────────────────┘
```

**Vantagens:**
- ✅ Chave privada protegida no servidor
- ✅ Lógica complexa isolada no backend
- ✅ Fácil manutenção e atualizações
- ✅ Melhor performance
- ✅ Conformidade com boas práticas de segurança

## 🔄 Abordagem Frontend (NÃO RECOMENDADA, mas implementada)

Se por algum motivo você precisar fazer a assinatura ou a autenticação de cliente diretamente no Flutter, o sistema implementa:

### 1. Conversão PFX → PEM

O sistema converte automaticamente o certificado PFX para PEM usando OpenSSL:

**PASSO 1: Extrair Certificado Público**
```bash
openssl pkcs12 -in certificado.pfx -clcerts -nokeys -out certificado_publico.pem
```

**PASSO 2: Extrair Chave Privada**
```bash
openssl pkcs12 -in certificado.pfx -nocerts -nodes -out chave_privada.pem
```

**PASSO 3: Combinar (Opcional)**
```bash
cat chave_privada.pem certificado_publico.pem > certificado_completo.pem
```

### 2. Uso do SecurityContext

O sistema fornece `SecurityContextService` para configurar certificado para autenticação HTTPS:

#### Opção 1: Carregar de Assets (Conforme Guia Oficial)

```dart
import 'package:sistema_exodo_01-12/services/security_context_service.dart';
import 'dart:io';

// 1. Adicione os arquivos PEM ao seu projeto (na pasta assets)
//    - assets/certificado_publico.pem
//    - assets/chave_privada.pem

// 2. Configure o pubspec.yaml:
//    flutter:
//      assets:
//        - assets/certificado_publico.pem
//        - assets/chave_privada.pem

// 3. Carregue e use o certificado:
final client = await SecurityContextService.createHttpClientWithCertificate(
  caminhoCertificadoAsset: 'assets/certificado_publico.pem',
  caminhoChavePrivadaAsset: 'assets/chave_privada.pem',
  senhaChave: 'SUA_SENHA_DA_CHAVE', // ou null se usar -nodes
);

// 4. Usar para requisições HTTPS autenticadas
final request = await client.getUrl(Uri.parse('https://web-service-sefaz.com.br/nfe'));
final response = await request.close();
```

#### Opção 2: Usar Conteúdo PEM Diretamente

```dart
import 'package:sistema_exodo_01-12/services/security_context_service.dart';
import 'dart:io';

// Criar HttpClient com certificado a partir de strings PEM
final client = SecurityContextService.criarHttpClientComCertificado(
  certificadoPEM: certificadoPEMContent,
  chavePrivadaPEM: chavePrivadaPEMContent,
  senhaChave: null, // Se a chave não tiver senha (usando -nodes)
);

// Usar para requisições HTTPS autenticadas
final request = await client.getUrl(Uri.parse('https://web-service-sefaz.com.br/nfe'));
final response = await request.close();
```

#### Opção 3: Carregar de Arquivos Locais

```dart
import 'package:sistema_exodo_01-12/services/security_context_service.dart';
import 'dart:io';

// Criar SecurityContext a partir de arquivos PEM gerados pela conversão
final securityContext = await SecurityContextService.criarSecurityContextDeArquivos(
  caminhoCertificado: '/caminho/certificado_publico.pem',
  caminhoChavePrivada: '/caminho/chave_privada.pem',
  senhaChave: null, // Se a chave não tiver senha
);

// Criar HttpClient
final client = HttpClient(context: securityContext);
```

### 3. Processamento Automático

O sistema processa automaticamente:

1. **Conversão PFX → PEM** (quando necessário)
2. **Extração de informações** (CNPJ, validade)
3. **Preparação para assinatura** (chave privada RSA)
4. **Configuração para HTTPS** (SecurityContext)

## 📋 Componentes do Sistema

| Componente | Propósito | Status |
| :--- | :--- | :--- |
| **CertificadoConverterService** | Converte PFX para PEM usando OpenSSL | ✅ Implementado |
| **PKCS12Service** | Processa PFX diretamente (parsing nativo) | ✅ Implementado |
| **PEMCertificateService** | Processa arquivos PEM | ✅ Implementado |
| **SecurityContextService** | Configura certificado para HTTPS | ✅ Implementado |
| **CertificadoOpenSSLService** | Processamento robusto usando OpenSSL | ✅ Implementado |
| **AssinaturaService** | Assina XML da NFC-e | ✅ Implementado |

## 🔐 Segurança

### ⚠️ Avisos Importantes

1. **Nunca commite certificados ou chaves privadas no Git**
   - Use `.gitignore` para excluir arquivos `.pfx`, `.pem`, `.key`
   - Armazene certificados de forma segura (variáveis de ambiente, vaults)

2. **Proteja a chave privada**
   - Se usar frontend, considere criptografar a chave privada
   - Use senha forte para proteger a chave privada PEM
   - Considere usar `-nodes` apenas em desenvolvimento

3. **Valide certificados**
   - Verifique validade antes de usar
   - Verifique CNPJ correspondente
   - Monitore expiração

### 🔒 Boas Práticas

- ✅ Use backend dedicado para produção
- ✅ Armazene certificados de forma segura
- ✅ Monitore expiração de certificados
- ✅ Use HTTPS para todas as comunicações
- ✅ Valide certificados antes de usar
- ✅ Implemente logs de auditoria

## 🚀 Como Usar

### Opção 1: Backend (Recomendado)

1. Configure backend dedicado (Node.js, PHP, C#, etc.)
2. Flutter envia dados da venda para backend
3. Backend processa NFC-e e retorna resultado
4. Flutter exibe QR Code e URL de consulta

### Opção 2: Frontend (Não Recomendado)

1. **Converter certificado PFX para PEM:**
   ```dart
   final resultado = await CertificadoConverterService.converterPFXParaPEM(
     caminhoPFX: 'certificado.pfx',
     senha: 'senha_do_pfx',
   );
   ```

2. **Processar certificado:**
   ```dart
   final certificado = await CertificadoService().carregarCertificado(
     'certificado.pfx',
     'senha',
     certificadoDigitalBytes: base64Bytes,
   );
   ```

3. **Assinar XML:**
   ```dart
   final xmlAssinado = await AssinaturaService().assinarXML(
     xmlOriginal,
     certificado,
   );
   ```

4. **Enviar para SEFAZ:**
   ```dart
   final client = SecurityContextService.criarHttpClientComCertificado(
     certificadoPEM: certPEM,
     chavePrivadaPEM: keyPEM,
   );
   // Fazer requisição HTTPS
   ```

## 📚 Referências

- [OpenSSL PKCS12 Documentation](https://www.openssl.org/docs/man1.1.1/man1/pkcs12.html)
- [Flutter Security Best Practices](https://flutter.dev/docs/development/data-and-backend/security)
- [Dart SecurityContext](https://api.dart.dev/stable/dart-io/SecurityContext-class.html)
- [XML Digital Signature](https://www.w3.org/TR/xmldsig-core/)
- [SEFAZ - Documentação NFC-e](https://www.nfe.fazenda.gov.br/portal/listaConteudo.aspx?tipoConteudo=/fq1VY8L0vU=)

## ✅ Checklist de Implementação

### Backend (Recomendado)
- [ ] Configurar servidor backend dedicado
- [ ] Implementar API para receber dados da venda
- [ ] Integrar biblioteca de NFC-e (ACBr, NFePHP, etc.)
- [ ] Configurar certificado digital no servidor
- [ ] Implementar comunicação com SEFAZ
- [ ] Implementar tratamento de erros
- [ ] Implementar logs de auditoria

### Frontend (Não Recomendado)
- [ ] Converter certificado PFX para PEM
- [ ] Implementar processamento de certificado
- [ ] Implementar assinatura XML
- [ ] Configurar SecurityContext para HTTPS
- [ ] Implementar comunicação com SEFAZ
- [ ] Implementar tratamento de erros
- [ ] Implementar validação de certificado
- [ ] Implementar monitoramento de expiração

## 🎯 Conclusão

Para produção, **sempre use um backend dedicado**. O sistema atual implementa suporte frontend para desenvolvimento e testes, mas não é recomendado para produção devido a questões de segurança.

---

**Última atualização:** Implementação completa com suporte a SecurityContext e conversão PFX → PEM

