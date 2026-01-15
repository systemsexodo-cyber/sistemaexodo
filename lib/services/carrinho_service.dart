import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/carrinho_item.dart';
import '../../models/produto.dart';
import '../../models/variacao_produto.dart';
import 'local_storage_service.dart';

class CarrinhoService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  final List<CarrinhoItem> _itens = [];
  String? _empresaId;

  List<CarrinhoItem> get itens => List.unmodifiable(_itens);

  int get totalItens => _itens.fold(0, (sum, item) => sum + item.quantidade);

  double get valorTotal => _itens.fold(0.0, (sum, item) => sum + item.subtotal);

  bool get isEmpty => _itens.isEmpty;

  void configurarEmpresa(String empresaId) {
    if (_empresaId == empresaId) return;
    _empresaId = empresaId;
    _carregarCarrinho();
  }

  Future<void> _carregarCarrinho() async {
    if (_empresaId == null) return;
    
    try {
      final jsonStr = await _storage.carregar('carrinho_$_empresaId');
      if (jsonStr != null) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _itens.clear();
        _itens.addAll(decoded.map((item) => CarrinhoItem.fromMap(item as Map<String, dynamic>)));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao carregar carrinho: $e');
    }
  }

  Future<void> _salvarCarrinho() async {
    if (_empresaId == null) return;
    
    try {
      final jsonStr = jsonEncode(_itens.map((item) => item.toMap()).toList());
      await _storage.salvar('carrinho_$_empresaId', jsonStr);
    } catch (e) {
      debugPrint('Erro ao salvar carrinho: $e');
    }
  }

  void adicionarProduto(Produto produto, {int quantidade = 1, List<VariacaoProduto>? variacoes}) {
    final index = _itens.indexWhere((item) => 
      item.itemId == produto.id && 
      item.isProduto && 
      _compararVariacoes(item.variacoesSelecionadas, variacoes)
    );

    if (index >= 0) {
      _itens[index] = _itens[index].copyWith(quantidade: _itens[index].quantidade + quantidade);
    } else {
      _itens.add(CarrinhoItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: 'produto',
        itemId: produto.id,
        nome: produto.nome,
        preco: produto.precoAtual,
        quantidade: quantidade,
        variacoesSelecionadas: variacoes,
        pesoGramas: produto.pesoGramas,
      ));
    }
    
    _salvarCarrinho();
    notifyListeners();
  }

  void removerItem(String itemId) {
    _itens.removeWhere((item) => item.id == itemId);
    _salvarCarrinho();
    notifyListeners();
  }

  void atualizarQuantidade(String itemId, int quantidade) {
    final index = _itens.indexWhere((item) => item.id == itemId);
    if (index >= 0) {
      if (quantidade <= 0) {
        _itens.removeAt(index);
      } else {
        _itens[index] = _itens[index].copyWith(quantidade: quantidade);
      }
      _salvarCarrinho();
      notifyListeners();
    }
  }

  void limparCarrinho() {
    _itens.clear();
    _salvarCarrinho();
    notifyListeners();
  }

  bool _compararVariacoes(List<VariacaoProduto>? v1, List<VariacaoProduto>? v2) {
    if (v1 == null && v2 == null) return true;
    if (v1 == null || v2 == null) return false;
    if (v1.length != v2.length) return false;
    
    for (int i = 0; i < v1.length; i++) {
       // Assumindo que a ordem pode ser diferente, mas para o carrinho geralmente é a mesma se vier da mesma seleção
       if (v1[i].id != v2[i].id) return false;
       if (v1[i].valor != v2[i].valor) return false;
    }
    return true;
  }
}
