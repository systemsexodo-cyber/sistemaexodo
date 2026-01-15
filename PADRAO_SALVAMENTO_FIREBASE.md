# Padrão de Salvamento no Firebase

Este documento descreve o padrão que deve ser seguido ao criar novos tipos de dados no sistema para garantir que sejam salvos imediatamente no Firebase.

## 📋 Visão Geral

Todos os dados criados ou atualizados no sistema devem ser salvos **imediatamente** no Firebase, não apenas no localStorage. Isso garante sincronização em tempo real entre dispositivos.

## 🔧 Passos para Implementar um Novo Tipo de Dado

### 1. Criar Métodos no FirebaseService

No arquivo `lib/services/firebase_service.dart`, adicione:

#### a) Constante da Subcoleção
```dart
static const String _subCollectionNovaEntidade = 'nova_entidade';
```

#### b) Método de Salvamento Individual
```dart
/// Salva uma nova entidade individual no Firebase
Future<void> salvarNovaEntidade(String empresaId, NovaEntidade item) async {
  try {
    final docRef = _getSubCollection(empresaId, _subCollectionNovaEntidade).doc(item.id);
    await docRef.set(item.toMap());
    debugPrint('>>> [Firebase] Nova entidade salva: ${item.nome} (ID: ${item.id})');
  } catch (e, stackTrace) {
    debugPrint('>>> [Firebase] ERRO ao salvar nova entidade: $e');
    debugPrint('>>> [Firebase] StackTrace: $stackTrace');
    rethrow;
  }
}
```

#### c) Método de Remoção (se necessário)
```dart
/// Remove uma nova entidade do Firebase
Future<void> removerNovaEntidade(String empresaId, String itemId) async {
  try {
    await _getSubCollection(empresaId, _subCollectionNovaEntidade).doc(itemId).delete();
    debugPrint('>>> [Firebase] Nova entidade removida: $itemId');
  } catch (e, stackTrace) {
    debugPrint('>>> [Firebase] ERRO ao remover nova entidade: $e');
    debugPrint('>>> [Firebase] StackTrace: $stackTrace');
    rethrow;
  }
}
```

#### d) Adicionar nos Métodos de Sincronização em Lote

Adicione a nova entidade nos seguintes métodos:
- `salvarTudoNoFirebase()` - adicionar no parâmetro e no loop de salvamento
- `_salvarEmBatches()` - adicionar chamada para `_salvarLista()`
- `carregarTudoDoFirebase()` - adicionar no `Future.wait()` e no mapeamento dos resultados

### 2. Atualizar Métodos CRUD no DataService

No arquivo `lib/services/data_service.dart`, ao criar métodos `add`, `update` ou `delete`, sempre seguir este padrão:

```dart
Future<void> addNovaEntidade(NovaEntidade item) async {
  // 1. Adicionar na lista local
  _novaEntidade.add(item);
  
  // 2. Notificar listeners
  notifyListeners();
  
  // 3. Salvar automaticamente (localStorage)
  _salvarAutomaticamente();
  
  // 4. Salvar IMEDIATAMENTE no Firebase
  if (_firebaseHabilitado && _empresaIdAtual != null) {
    _firebaseService.salvarNovaEntidade(_empresaIdAtual!, item).catchError((e) {
      debugPrint('>>> Erro ao salvar nova entidade no Firebase: $e');
      _adicionarSincronizacaoPendente();
    });
  }
}

void updateNovaEntidade(NovaEntidade item) {
  final index = _novaEntidade.indexWhere((e) => e.id == item.id);
  if (index != -1) {
    // 1. Atualizar na lista local
    _novaEntidade[index] = item;
    
    // 2. Notificar listeners
    notifyListeners();
    
    // 3. Salvar automaticamente (localStorage)
    _salvarAutomaticamente();
    
    // 4. Salvar IMEDIATAMENTE no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarNovaEntidade(_empresaIdAtual!, item).catchError((e) {
        debugPrint('>>> Erro ao atualizar nova entidade no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }
}

void deleteNovaEntidade(String id) {
  // 1. Remover da lista local
  _novaEntidade.removeWhere((e) => e.id == id);
  
  // 2. Notificar listeners
  notifyListeners();
  
  // 3. Salvar automaticamente (localStorage)
  _salvarAutomaticamente();
  
  // 4. Remover IMEDIATAMENTE do Firebase
  if (_firebaseHabilitado && _empresaIdAtual != null) {
    _firebaseService.removerNovaEntidade(_empresaIdAtual!, id).catchError((e) {
      debugPrint('>>> Erro ao remover nova entidade do Firebase: $e');
      _adicionarSincronizacaoPendente();
    });
  }
}
```

## ✅ Checklist

Ao criar um novo tipo de dado, verificar:

- [ ] Constante `_subCollection[Nome]` criada no FirebaseService
- [ ] Método `salvar[Nome]()` criado no FirebaseService
- [ ] Método `remover[Nome]()` criado no FirebaseService (se necessário)
- [ ] Adicionado em `salvarTudoNoFirebase()`
- [ ] Adicionado em `_salvarEmBatches()`
- [ ] Adicionado em `carregarTudoDoFirebase()`
- [ ] Métodos CRUD no DataService salvam imediatamente no Firebase
- [ ] Tratamento de erro com `catchError` e `_adicionarSincronizacaoPendente()`

## 🔍 Exemplos de Implementação Completa

Consulte os seguintes exemplos já implementados:
- **Cliente**: `addCliente()`, `updateCliente()`, `deleteCliente()`
- **Produto**: `addProduto()`, `updateProduto()`, `deleteProduto()`
- **Funcionário**: `addFuncionario()`, `updateFuncionario()`, `deleteFuncionario()`
- **Conta a Pagar**: `addContaPagar()`, `updateContaPagar()`, `deleteContaPagar()`

## ⚠️ Importante

1. **Sempre** salvar no Firebase imediatamente após adicionar/atualizar na lista local
2. **Sempre** usar `catchError` para tratar falhas de conexão
3. **Sempre** chamar `_adicionarSincronizacaoPendente()` em caso de erro para tentar novamente depois
4. **Nunca** bloquear a UI aguardando o Firebase (usar `.catchError()` sem `await`)

## 📝 Notas

- O salvamento no Firebase é assíncrono e não bloqueia a UI
- Se o Firebase falhar, o dado fica salvo no localStorage e será sincronizado depois
- A fila de sincronização (`SyncQueueService`) tenta novamente quando a conexão for restaurada






