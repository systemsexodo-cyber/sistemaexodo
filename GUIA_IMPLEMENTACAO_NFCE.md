# 📚 Guia de Implementação NFC-e - Bibliotecas e Como Começar

## 🎯 Opções de Implementação

Para Flutter/Dart, existem **3 abordagens principais**:

### **1. API Pronta (Recomendado para começar rápido)**
Usar uma API de terceiros que já faz toda a comunicação com a SEFAZ.

### **2. Biblioteca Nativa**
Usar bibliotecas que fazem a comunicação direta com a SEFAZ.

### **3. Implementação Manual**
Desenvolver do zero usando WebServices SOAP da SEFAZ.

---

## 🚀 Opção 1: APIs Prontas (Mais Fácil)

### **A) Focus NFe API** ⭐ (Recomendado)
- **Site:** https://focusnfe.com.br
- **Documentação:** https://doc.focusnfe.com.br
- **Vantagens:**
  - API REST simples
  - Documentação completa
  - Ambiente de homologação gratuito
  - Suporte técnico
- **Preço:** Pago (mas tem plano gratuito para testes)
- **Biblioteca Flutter:** Não tem oficial, mas é fácil integrar via HTTP

**Como usar:**
```dart
// Adicionar ao pubspec.yaml
dependencies:
  http: ^1.1.0  # Para fazer requisições HTTP
  dio: ^5.4.0   # Alternativa mais completa ao http
```

**Exemplo básico:**
```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> emitirNFCe() async {
  final url = Uri.parse('https://api.focusnfe.com.br/v2/nfce');
  final headers = {
    'Authorization': 'Token SEU_TOKEN_AQUI',
    'Content-Type': 'application/json',
  };
  
  final body = {
    'ref': 'REF123',
    'cnpj_emitente': '12345678000190',
    // ... outros campos
  };
  
  final response = await http.post(url, headers: headers, body: jsonEncode(body));
  print(response.body);
}
```

### **B) NFe.io**
- **Site:** https://nfe.io
- **Documentação:** https://nfe.io/docs
- **Vantagens:** API REST, boa documentação
- **Preço:** Pago

### **C) Tecnospeed**
- **Site:** https://tecnospeed.com.br
- **Vantagens:** Componente completo, suporte técnico
- **Preço:** Pago

---

## 🔧 Opção 2: Bibliotecas Nativas

### **A) NFePHP (PHP) - Via Backend**
- **GitHub:** https://github.com/nfephp-org/sped-nfe
- **Como usar:** Criar um backend PHP que usa essa biblioteca e fazer chamadas via API REST
- **Vantagem:** Biblioteca muito completa e testada

### **B) ACBr (Delphi/Pascal) - Via Backend**
- **Site:** https://projetoacbr.com.br
- **Como usar:** Criar um backend que usa ACBr e expor via API REST
- **Vantagem:** Biblioteca oficial, muito confiável

### **C) Implementação Manual em Dart**
Não existe biblioteca pronta em Dart/Flutter, mas você pode implementar:

**Bibliotecas necessárias:**
```yaml
dependencies:
  # Já temos no projeto:
  xml: ^6.4.2              # Para gerar XML da NFC-e
  http: ^1.1.0             # Para comunicação SOAP com SEFAZ
  pointycastle: ^3.7.3    # Para assinatura digital (cryptography)
  # ou
  cryptography: ^2.7.0     # Alternativa para criptografia
  asn1lib: ^1.5.0          # Para manipular certificados
```

---

## 📦 Bibliotecas Necessárias (Adicionar ao pubspec.yaml)

### **Para API Pronta (Opção 1):**
```yaml
dependencies:
  http: ^1.1.0              # Requisições HTTP
  dio: ^5.4.0               # Cliente HTTP mais completo (opcional)
```

### **Para Implementação Manual (Opção 3):**
```yaml
dependencies:
  # Já temos:
  xml: ^6.4.2               # Geração de XML
  http: ^1.1.0              # Comunicação SOAP
  
  # Adicionar:
  pointycastle: ^3.7.3      # Criptografia e assinatura digital
  asn1lib: ^1.5.0           # Manipulação de certificados
  qr_flutter: ^4.1.0        # Geração de QR Code
  pdf: ^3.10.7              # Geração do DANFE-NFC-e (opcional)
  printing: ^5.12.0         # Impressão do DANFE (opcional)
```

---

## 🏁 Como Começar - Passo a Passo

### **Fase 1: Escolher a Abordagem**

**Recomendação:** Começar com **Focus NFe API** (Opção 1A) porque:
- ✅ Mais rápido de implementar
- ✅ Menos complexidade técnica
- ✅ Ambiente de homologação gratuito
- ✅ Documentação excelente
- ✅ Suporte técnico

### **Fase 2: Configurar Ambiente**

#### **2.1. Adicionar Dependências**
```bash
cd sistema_exodo_01-12
flutter pub add http
# ou
flutter pub add dio
```

#### **2.2. Criar Conta na API Escolhida**
- Focus NFe: https://focusnfe.com.br/cadastro
- Obter token de acesso
- Configurar ambiente de homologação

#### **2.3. Configurar Certificado Digital**
- Fazer upload do certificado (.pfx) na API
- Ou configurar para usar certificado local

### **Fase 3: Criar Serviço de NFC-e**

Criar arquivo: `lib/services/nfce_service.dart`

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/empresa.dart';
import '../models/produto.dart';

class NFCeService {
  final String apiToken;
  final bool ambienteHomologacao;
  
  NFCeService({
    required this.apiToken,
    this.ambienteHomologacao = true,
  });
  
  String get baseUrl => ambienteHomologacao
      ? 'https://homologacao.focusnfe.com.br/v2'
      : 'https://api.focusnfe.com.br/v2';
  
  Future<Map<String, dynamic>> emitirNFCe({
    required Empresa empresa,
    required List<Produto> produtos,
    required double valorTotal,
    // ... outros parâmetros
  }) async {
    final url = Uri.parse('$baseUrl/nfce');
    
    final headers = {
      'Authorization': 'Token $apiToken',
      'Content-Type': 'application/json',
    };
    
    final body = {
      'ref': DateTime.now().millisecondsSinceEpoch.toString(),
      'cnpj_emitente': empresa.cnpj?.replaceAll(RegExp(r'[^\d]'), ''),
      'natureza_operacao': 'VENDA',
      'data_emissao': DateTime.now().toIso8601String(),
      'tipo_documento': '1', // 1=Entrada, 0=Saída
      'local_destino': '1', // 1=Interna
      'finalidade': '1', // 1=Normal
      'consumidor_final': '1', // 1=Sim
      'presenca_comprador': '1', // 1=Presencial
      'itens': produtos.map((p) => {
        'codigo_produto': p.codigo ?? p.id,
        'descricao': p.nome,
        'cfop': p.cfop ?? '5102',
        'ncm': p.ncm ?? '00000000',
        'cest': p.cest,
        'unidade_comercial': p.unidade,
        'quantidade_comercial': '1.00',
        'valor_unitario_comercial': p.preco.toStringAsFixed(2),
        'valor_total': p.preco.toStringAsFixed(2),
        'icms_origem': p.origem ?? '0',
        'icms_situacao_tributaria': p.csosn ?? p.icmsCst ?? '102',
        'icms_aliquota': (p.icmsAliquota ?? 0).toStringAsFixed(2),
      }).toList(),
      'valor_total': valorTotal.toStringAsFixed(2),
    };
    
    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erro ao emitir NFC-e: ${response.body}');
      }
    } catch (e) {
      throw Exception('Erro na comunicação: $e');
    }
  }
  
  Future<Map<String, dynamic>> consultarNFCe(String referencia) async {
    final url = Uri.parse('$baseUrl/nfce/$referencia');
    
    final headers = {
      'Authorization': 'Token $apiToken',
    };
    
    final response = await http.get(url, headers: headers);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erro ao consultar NFC-e: ${response.body}');
    }
  }
  
  Future<String> cancelarNFCe(String referencia, String justificativa) async {
    final url = Uri.parse('$baseUrl/nfce/$referencia/cancelamento');
    
    final headers = {
      'Authorization': 'Token $apiToken',
      'Content-Type': 'application/json',
    };
    
    final body = {
      'justificativa': justificativa,
    };
    
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(body),
    );
    
    if (response.statusCode == 200) {
      return 'NFC-e cancelada com sucesso';
    } else {
      throw Exception('Erro ao cancelar NFC-e: ${response.body}');
    }
  }
}
```

### **Fase 4: Integrar com o Sistema**

#### **4.1. Adicionar Botão "Emitir NFC-e" na Finalização de Venda**

No arquivo `venda_direta_page.dart`, adicionar opção para emitir NFC-e após finalizar a venda.

#### **4.2. Criar Tela de Configuração NFC-e**

Criar tela para configurar:
- Token da API
- Ambiente (Homologação/Produção)
- Certificado Digital

### **Fase 5: Testar em Homologação**

1. Criar conta na Focus NFe (ambiente de homologação)
2. Obter token de teste
3. Fazer primeira emissão de teste
4. Verificar se NFC-e foi autorizada
5. Testar consulta e cancelamento

### **Fase 6: Ir para Produção**

1. Solicitar credenciamento na SEFAZ
2. Obter CSC e ID Token
3. Configurar certificado digital de produção
4. Alterar ambiente para produção
5. Fazer primeira emissão real

---

## 📋 Checklist de Implementação

### **Pré-requisitos:**
- [ ] Certificado Digital ICP-Brasil adquirido
- [ ] Inscrição Estadual ativa
- [ ] CNPJ regularizado
- [ ] Conta criada na API escolhida (Focus NFe, etc)

### **Desenvolvimento:**
- [ ] Adicionar dependências (`http` ou `dio`)
- [ ] Criar serviço `NFCeService`
- [ ] Criar modelo de dados para NFC-e
- [ ] Integrar com tela de venda
- [ ] Criar tela de configuração
- [ ] Implementar geração de QR Code
- [ ] Implementar impressão do DANFE-NFC-e

### **Testes:**
- [ ] Testar emissão em homologação
- [ ] Testar consulta de NFC-e
- [ ] Testar cancelamento
- [ ] Testar contingência offline
- [ ] Validar todos os campos obrigatórios

### **Produção:**
- [ ] Credenciamento na SEFAZ
- [ ] Obter CSC e ID Token
- [ ] Configurar certificado de produção
- [ ] Primeira emissão real
- [ ] Treinar equipe

---

## 🔗 Links Úteis

### **Documentação:**
- Focus NFe: https://doc.focusnfe.com.br
- NFe.io: https://nfe.io/docs
- Manual de Integração NFC-e (varia por estado)

### **SEFAZ por Estado:**
- **SP:** https://www.nfce.fazenda.sp.gov.br
- **RJ:** https://www.nfce.fazenda.rj.gov.br
- **MG:** https://www.nfce.mg.gov.br
- **RS:** https://www.sefaz.rs.gov.br
- (Consultar SEFAZ do seu estado)

### **Ferramentas:**
- Validador de XML: https://www.nfce.fazenda.sp.gov.br/QRCode
- Gerador de QR Code: https://www.qr-code-generator.com

---

## 💡 Dicas Importantes

1. **Sempre teste em homologação primeiro**
2. **Mantenha backup do certificado digital**
3. **Armazene XMLs por 5 anos (obrigatório)**
4. **Implemente contingência offline**
5. **Valide todos os campos antes de enviar**
6. **Trate erros da SEFAZ adequadamente**
7. **Monitore o status das NFC-e emitidas**

---

## 🚨 Erros Comuns

1. **Certificado expirado** → Renovar certificado
2. **CSC inválido** → Verificar CSC na SEFAZ
3. **XML malformado** → Validar estrutura XML
4. **Timeout na SEFAZ** → Implementar retry
5. **Campos obrigatórios faltando** → Validar antes de enviar

---

**Próximo passo:** Escolher a API (recomendo Focus NFe) e começar pela Fase 2!

