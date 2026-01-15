# 🔴 O Que Falta - Implementação NFC-e

## ⚠️ **CRÍTICO - Ajustes Técnicos Necessários**

### 1. 🔴 **Assinatura Digital Real** (Prioridade ALTA)
**Arquivo:** `lib/services/assinatura_service.dart`

**Problema:**
- Método `_rsaSignatureToBytes()` retorna array vazio (placeholder)
- Conversão do `RSASignature` para bytes não implementada

**O que fazer:**
```dart
// Precisar verificar estrutura do RSASignature no PointyCastle 4.0.0
// Possivelmente usar: signature.m (BigInt) e converter para bytes
```

**Impacto:** Sem isso, a NFC-e não será aceita pela SEFAZ (assinatura inválida)

---

### 2. 🔴 **Parsing PKCS12** (Prioridade ALTA)
**Arquivo:** `lib/services/pkcs12_service.dart`

**Problema:**
- Parsing do certificado PFX não implementado
- Não extrai chave privada RSA
- Não extrai certificado X509

**O que fazer:**
- Implementar parsing completo do ASN.1 do PKCS12
- Extrair chave privada para assinatura
- Extrair certificado X509 para incluir no XML

**Impacto:** Sem isso, não é possível assinar o XML

---

### 3. 🟡 **Download de Certificado** (Prioridade MÉDIA)
**Arquivo:** `lib/services/certificado_service.dart`

**Problema:**
- Método `_downloadCertificado()` não implementado
- Não faz download de certificado de URL (Firebase Storage, etc)

**O que fazer:**
- Implementar download HTTP do certificado
- Salvar temporariamente no dispositivo

---

## 🖥️ **Interface do Usuário - Integração**

### 4. 🔴 **Botão "Emitir NFC-e" na Finalização de Venda** (Prioridade ALTA)
**Arquivo:** `lib/pages/venda_direta_page.dart`

**O que fazer:**
- Adicionar opção "Emitir NFC-e" após finalizar venda
- Criar diálogo para confirmar emissão
- Chamar `NFCeService.emitir()`
- Exibir status (em processamento, autorizada, rejeitada)
- Mostrar QR Code após autorização

**Exemplo de código:**
```dart
ElevatedButton.icon(
  icon: Icon(Icons.receipt),
  label: Text('Emitir NFC-e'),
  onPressed: () async {
    // Emitir NFC-e
    final nfce = await nfceService.emitir(...);
    // Mostrar resultado
  },
)
```

---

### 5. 🟡 **Tela de Visualização de NFC-e** (Prioridade MÉDIA)
**Arquivo:** `lib/pages/nfce_detalhes_page.dart` (criar)

**O que fazer:**
- Criar tela para visualizar NFC-e emitida
- Mostrar todos os dados (chave, protocolo, itens, etc)
- Exibir QR Code
- Botão para imprimir DANFE
- Botão para reenviar por email
- Botão para cancelar (se autorizada)

---

### 6. 🟡 **Lista de NFC-e Emitidas** (Prioridade MÉDIA)
**Arquivo:** `lib/pages/nfce_lista_page.dart` (criar)

**O que fazer:**
- Listar todas as NFC-e emitidas
- Filtros (data, status, número)
- Busca por chave de acesso
- Indicadores visuais de status
- Acesso rápido para visualizar/impressão

---

### 7. 🟡 **Configurações NFC-e** (Prioridade BAIXA)
**Arquivo:** `lib/pages/nfce_configuracoes_page.dart` (criar)

**O que fazer:**
- Configurar ambiente (Homologação/Produção)
- Testar conexão com SEFAZ
- Validar certificado digital
- Configurar impressora
- Configurar email para envio

---

## 💾 **Armazenamento e Persistência**

### 8. 🔴 **Salvar NFC-e no DataService** (Prioridade ALTA)
**Arquivo:** `lib/services/data_service.dart`

**O que fazer:**
- Adicionar lista de NFC-e no DataService
- Métodos: `adicionarNFCe()`, `obterNFCe()`, `listarNFCe()`
- Salvar no localStorage/Firebase
- Sincronizar com Firebase

---

### 9. 🟡 **Armazenar XMLs** (Prioridade MÉDIA)
**O que fazer:**
- Salvar XML enviado e XML retornado
- Armazenar por 5 anos (obrigatório)
- Criar sistema de backup
- Opção de exportar XMLs

---

## 🔧 **Funcionalidades Adicionais**

### 10. 🟡 **Cancelamento de NFC-e** (Prioridade MÉDIA)
**Arquivo:** `lib/services/nfce_service.dart`

**O que fazer:**
- Método `cancelarNFCe()`
- Enviar evento de cancelamento para SEFAZ
- Atualizar status da NFC-e
- Validar prazo (até 24h após emissão)

---

### 11. 🟡 **Contingência Offline** (Prioridade MÉDIA)
**O que fazer:**
- Detectar quando SEFAZ está offline
- Armazenar NFC-e pendentes
- Tentar reenvio automático
- Modo offline com numeração especial

---

### 12. 🟡 **Consulta de Status** (Prioridade BAIXA)
**Arquivo:** `lib/services/sefaz_service.dart`

**O que fazer:**
- Implementar método `consultarStatus()` completo
- Consultar status de NFC-e na SEFAZ
- Atualizar status local

---

### 13. 🟡 **Envio por Email** (Prioridade BAIXA)
**O que fazer:**
- Enviar DANFE por email ao consumidor
- Configurar SMTP
- Template de email

---

## 🐛 **Correções e Melhorias**

### 14. 🟡 **Quantidade Real dos Produtos** (Prioridade MÉDIA)
**Arquivos:** 
- `lib/services/xml_builder_service.dart` (linha 165)
- `lib/services/nfce_service.dart` (linha 178)

**Problema:** Usa quantidade fixa 1.0

**O que fazer:**
- Passar quantidade real do carrinho
- Considerar quantidade na venda

---

### 15. 🟡 **Código IBGE do Município** (Prioridade MÉDIA)
**Arquivo:** `lib/services/xml_builder_service.dart` (linha 309)

**Problema:** Usa código fixo de São Paulo

**O que fazer:**
- Buscar código IBGE do município da empresa
- Adicionar campo no cadastro da empresa
- Ou usar API para buscar

---

### 16. 🟡 **Cálculo Correto do Digest do QR Code** (Prioridade BAIXA)
**Arquivo:** `lib/services/qr_code_service.dart` (linha 35)

**Problema:** Usa hash SHA-1 simples

**O que fazer:**
- Implementar cálculo correto conforme especificação oficial
- Verificar manual de integração

---

### 17. 🟡 **Renderização do QR Code no PDF** (Prioridade BAIXA)
**Arquivo:** `lib/services/danfe_service.dart` (linha 216)

**Problema:** Apenas texto, não imagem do QR Code

**O que fazer:**
- Gerar imagem do QR Code
- Inserir no PDF do DANFE

---

## 📋 **Checklist de Implementação**

### **Fase 1: Funcionalidade Básica (CRÍTICO)**
- [ ] ✅ Assinatura digital real
- [ ] ✅ Parsing PKCS12
- [ ] ✅ Integração com tela de venda
- [ ] ✅ Salvar NFC-e no DataService
- [ ] ✅ Exibir QR Code após emissão

### **Fase 2: Interface Completa**
- [ ] Tela de visualização de NFC-e
- [ ] Lista de NFC-e emitidas
- [ ] Impressão de DANFE
- [ ] Cancelamento de NFC-e

### **Fase 3: Funcionalidades Avançadas**
- [ ] Contingência offline
- [ ] Consulta de status
- [ ] Envio por email
- [ ] Armazenamento de XMLs

### **Fase 4: Ajustes e Melhorias**
- [ ] Quantidade real dos produtos
- [ ] Código IBGE correto
- [ ] Digest correto do QR Code
- [ ] QR Code no PDF

---

## 🎯 **Prioridades Resumidas**

### **URGENTE (Fazer Agora):**
1. ✅ Assinatura digital real
2. ✅ Parsing PKCS12
3. ✅ Botão na tela de venda
4. ✅ Salvar no DataService

### **IMPORTANTE (Próxima Semana):**
5. Tela de visualização
6. Lista de NFC-e
7. Cancelamento
8. Quantidade real

### **Desejável (Futuro):**
9. Contingência offline
10. Envio por email
11. Melhorias no DANFE

---

## 🚀 **Próximo Passo Recomendado**

**Começar pela Fase 1:**
1. Implementar parsing PKCS12 (biblioteca ou exemplo)
2. Ajustar assinatura digital
3. Integrar botão na tela de venda
4. Testar emissão em homologação

**Depois disso, a NFC-e estará funcional para uso básico!**

