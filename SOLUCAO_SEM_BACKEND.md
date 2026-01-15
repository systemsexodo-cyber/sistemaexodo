# ✅ Solução NFC-e SEM Backend - 100% Flutter

## 🎯 Solução: API Pronta (Focus NFe)

A melhor solução para **não precisar rodar backend** é usar uma **API pronta** como Focus NFe, que funciona diretamente do Flutter via HTTP.

## ✨ Vantagens

- ✅ **Zero configuração** - Não precisa instalar nada
- ✅ **Zero manutenção** - API mantida pela Focus NFe
- ✅ **Funciona offline** - Pode preparar requisição offline
- ✅ **100% Flutter** - Tudo no app, sem backend
- ✅ **Ambiente de teste gratuito** - Para homologação
- ✅ **Documentação completa** - Muito bem documentado

## 📦 O que você precisa

### 1. Criar conta na Focus NFe
- Site: https://focusnfe.com.br
- Crie uma conta (grátis para testes)
- Obtenha seu **Token de API**

### 2. Adicionar dependência (já tem no projeto)
```yaml
dependencies:
  http: ^1.6.0  # ✅ Já está no pubspec.yaml
```

### 3. Usar o serviço criado
```dart
import 'package:sistema_exodo_novo/services/nfce_focus_service.dart';

// Criar serviço
final nfceService = NFCeFocusService(
  apiToken: 'SEU_TOKEN_AQUI',
  ambienteHomologacao: true, // false para produção
);

// Emitir NFC-e
final nfce = await nfceService.emitir(
  empresa: empresa,
  produtos: produtos,
  quantidades: quantidades,
  pagamentos: pagamentos,
  valorTotal: valorTotal,
);
```

## 🚀 Como Implementar

### Passo 1: Adicionar campo Token na Empresa

No modelo `Empresa`, adicione:
```dart
final String? focusNFeToken; // Token da API Focus NFe
```

### Passo 2: Configurar Token na Tela de Empresa

Na tela de cadastro/edição de empresa, adicione campo para o token.

### Passo 3: Usar no NFCeService

Modifique `nfce_service.dart` para usar Focus NFe quando tiver token:

```dart
if (empresa.focusNFeToken != null && empresa.focusNFeToken!.isNotEmpty) {
  // Usar Focus NFe (sem backend)
  final focusService = NFCeFocusService(
    apiToken: empresa.focusNFeToken!,
    ambienteHomologacao: empresa.ambienteHomologacao ?? true,
  );
  return await focusService.emitir(...);
} else {
  // Usar backend Python/PHP (se configurado)
  // ... código atual
}
```

## 💰 Custos Focus NFe

### Plano Gratuito (Homologação)
- ✅ Ambiente de homologação gratuito
- ✅ Testes ilimitados
- ✅ Ideal para desenvolvimento

### Planos Pagos (Produção)
- **Starter:** ~R$ 0,50 por NFC-e
- **Business:** Descontos por volume
- **Enterprise:** Personalizado

**Comparação:**
- Backend próprio: Precisa manter servidor, atualizações, etc.
- Focus NFe: Paga apenas pelo uso, sem manutenção

## 🔄 Alternativas de API

### 1. Focus NFe ⭐ (Recomendado)
- **Site:** https://focusnfe.com.br
- **Documentação:** https://doc.focusnfe.com.br
- **Vantagens:** Mais popular, melhor documentação
- **Preço:** R$ 0,50/NFC-e (produção)

### 2. NFe.io
- **Site:** https://nfe.io
- **Vantagens:** API moderna
- **Preço:** Similar

### 3. Tecnospeed
- **Site:** https://tecnospeed.com.br
- **Vantagens:** Suporte técnico dedicado
- **Preço:** Contato comercial

## 📝 Exemplo Completo

```dart
// 1. Configurar serviço
final nfceService = NFCeFocusService(
  apiToken: 'seu-token-aqui',
  ambienteHomologacao: true,
);

// 2. Emitir NFC-e
try {
  final nfce = await nfceService.emitir(
    empresa: empresa,
    produtos: produtos,
    quantidades: {'produto1': 2.0, 'produto2': 1.0},
    pagamentos: [
      NFCePagamento(tipo: '01', valor: 100.0), // Dinheiro
    ],
    valorTotal: 100.0,
    cpfCnpjConsumidor: '12345678901',
    nomeConsumidor: 'João Silva',
  );

  print('NFC-e autorizada!');
  print('Chave: ${nfce.chaveAcesso}');
  print('QR Code: ${nfce.qrCode}');
} catch (e) {
  print('Erro: $e');
}
```

## ✅ Checklist de Implementação

- [ ] Criar conta na Focus NFe
- [ ] Obter token de API
- [ ] Adicionar campo `focusNFeToken` no modelo `Empresa`
- [ ] Adicionar campo na tela de cadastro de empresa
- [ ] Modificar `NFCeService` para usar Focus NFe quando tiver token
- [ ] Testar em homologação
- [ ] Configurar token de produção quando estiver pronto

## 🎯 Resultado Final

Com essa solução:
- ✅ **Zero backend** - Tudo no Flutter
- ✅ **Zero instalação** - Apenas HTTP
- ✅ **Zero manutenção** - Focus NFe cuida de tudo
- ✅ **Funciona offline** - Pode preparar requisição
- ✅ **Escalável** - Focus NFe escala automaticamente

## 📞 Suporte Focus NFe

- **Documentação:** https://doc.focusnfe.com.br
- **Suporte:** suporte@focusnfe.com.br
- **Chat:** Disponível no site

---

**Esta é a solução mais simples e prática para não precisar rodar backend!** 🚀


