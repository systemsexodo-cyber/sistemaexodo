# 🚀 Como Usar Focus NFe - Sem Backend!

## ✅ Solução Completa Implementada

Criei uma solução que funciona **100% no Flutter**, sem precisar rodar backend nenhum!

## 📦 O que foi criado

1. **`NFCeFocusService`** - Serviço completo para Focus NFe
2. **Campo `focusNFeToken`** no modelo `Empresa`
3. **Documentação completa**

## 🎯 Passo a Passo

### 1. Criar conta na Focus NFe

1. Acesse: https://focusnfe.com.br
2. Clique em "Criar Conta"
3. Preencha seus dados
4. Confirme o email
5. Faça login

### 2. Obter Token de API

1. No painel da Focus NFe, vá em **"API"** ou **"Integração"**
2. Copie seu **Token de API**
3. Guarde esse token (você vai usar no app)

### 3. Configurar Token na Empresa

No app, ao cadastrar/editar empresa:
- Adicione o campo **"Token Focus NFe"**
- Cole o token que você copiou
- Salve

### 4. Usar no Código

O serviço já está criado! Basta usar:

```dart
import 'package:sistema_exodo_novo/services/nfce_focus_service.dart';

// Se a empresa tem token Focus NFe, usar API
if (empresa.focusNFeToken != null && empresa.focusNFeToken!.isNotEmpty) {
  final focusService = NFCeFocusService(
    apiToken: empresa.focusNFeToken!,
    ambienteHomologacao: empresa.ambienteHomologacao ?? true,
  );
  
  final nfce = await focusService.emitir(
    empresa: empresa,
    produtos: produtos,
    quantidades: quantidades,
    pagamentos: pagamentos,
    valorTotal: valorTotal,
  );
  
  // NFC-e emitida com sucesso!
} else {
  // Usar backend Python/PHP (se configurado)
}
```

## 💰 Custos

### Homologação (Testes)
- ✅ **GRÁTIS** - Ambiente de homologação é gratuito
- ✅ Testes ilimitados
- ✅ Ideal para desenvolvimento

### Produção
- **Starter:** R$ 0,50 por NFC-e
- **Business:** Descontos por volume
- **Enterprise:** Personalizado

**Comparação:**
- Backend próprio: Precisa manter servidor, atualizações, etc.
- Focus NFe: Paga apenas pelo uso, sem manutenção

## ✨ Vantagens

- ✅ **Zero instalação** - Não precisa instalar nada
- ✅ **Zero manutenção** - Focus NFe cuida de tudo
- ✅ **Zero backend** - Tudo funciona no Flutter
- ✅ **Funciona offline** - Pode preparar requisição offline
- ✅ **Escalável** - Focus NFe escala automaticamente
- ✅ **Atualizações automáticas** - Focus NFe atualiza conforme SEFAZ

## 🔧 Integração no NFCeService

Modifique `lib/services/nfce_service.dart`:

```dart
Future<NFCe> emitir({...}) async {
  // Se tem token Focus NFe, usar API (sem backend)
  if (empresa.focusNFeToken != null && empresa.focusNFeToken!.isNotEmpty) {
    final focusService = NFCeFocusService(
      apiToken: empresa.focusNFeToken!,
      ambienteHomologacao: ambienteHomologacao,
    );
    return await focusService.emitir(
      empresa: empresa,
      produtos: produtos,
      quantidades: quantidades,
      pagamentos: pagamentos,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      observacoes: observacoes,
    );
  }
  
  // Senão, usar backend Python/PHP (código atual)
  // ... resto do código
}
```

## 📝 Exemplo Completo

```dart
// 1. Criar serviço
final nfceService = NFCeFocusService(
  apiToken: 'seu-token-aqui',
  ambienteHomologacao: true, // false para produção
);

// 2. Emitir NFC-e
try {
  final nfce = await nfceService.emitir(
    empresa: empresa,
    produtos: [
      Produto(id: '1', nome: 'Produto 1', preco: 10.0, ...),
    ],
    quantidades: {'1': 2.0},
    pagamentos: [
      NFCePagamento(tipo: '01', valor: 20.0), // Dinheiro
    ],
    valorTotal: 20.0,
    cpfCnpjConsumidor: '12345678901',
    nomeConsumidor: 'João Silva',
  );

  print('✅ NFC-e autorizada!');
  print('Chave: ${nfce.chaveAcesso}');
  print('QR Code: ${nfce.qrCode}');
  
  // Mostrar QR Code para o cliente
  // Salvar NFC-e no banco de dados
  
} catch (e) {
  print('❌ Erro: $e');
}
```

## 🎯 Próximos Passos

1. ✅ Criar conta na Focus NFe
2. ✅ Obter token de API
3. ✅ Adicionar campo na tela de empresa
4. ✅ Integrar no NFCeService
5. ✅ Testar em homologação
6. ✅ Configurar produção quando estiver pronto

## 📞 Suporte Focus NFe

- **Documentação:** https://doc.focusnfe.com.br
- **Suporte:** suporte@focusnfe.com.br
- **Chat:** Disponível no site
- **WhatsApp:** Disponível no site

---

**Esta é a solução mais simples: zero backend, zero instalação, zero manutenção!** 🚀


