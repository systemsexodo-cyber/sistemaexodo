import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/carrinho_service.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';

class CarrinhoDrawer extends StatelessWidget {
  final NumberFormat formatoMoeda;
  final VoidCallback onCheckout;
  final Color? corPrimaria;

  const CarrinhoDrawer({
    super.key,
    required this.formatoMoeda,
    required this.onCheckout,
    this.corPrimaria,
  });

  @override
  Widget build(BuildContext context) {
    final carrinho = Provider.of<CarrinhoService>(context);
    final dataService = Provider.of<DataService>(context, listen: false);
    final corP = corPrimaria ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 12, 20),
            decoration: BoxDecoration(
              color: corP.withOpacity(0.05),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: corP.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.shopping_bag_outlined, color: corP, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meu Carrinho',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${carrinho.totalItens} ${carrinho.totalItens == 1 ? 'item' : 'itens'}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // Lista de Itens
          Expanded(
            child: carrinho.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: carrinho.itens.length,
                    itemBuilder: (context, index) {
                      final item = carrinho.itens[index];
                      // Buscar foto do produto
                      String? fotoUrl;
                      try {
                        final produto = dataService.produtos.firstWhere((p) => p.id == item.itemId);
                        fotoUrl = produto.fotoPrincipalUrl ?? (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : null);
                      } catch (_) {}

                      return _buildCarrinhoItem(context, item, fotoUrl, carrinho);
                    },
                  ),
          ),

          // Bottom Summary
          if (!carrinho.isEmpty)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Subtotal',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          formatoMoeda.format(carrinho.valorTotal),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatoMoeda.format(carrinho.valorTotal),
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: corP),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: onCheckout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: corP,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: corP.withOpacity(0.4),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Finalizar Compra', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(width: 12),
                          Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 24),
          const Text(
            'Carrinho Vazio',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          const Text(
            'Você ainda não adicionou\nnenhum produto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildCarrinhoItem(BuildContext context, dynamic item, String? fotoUrl, CarrinhoService carrinho) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Imagem
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 70,
              height: 70,
              color: Colors.grey[50],
              child: fotoUrl != null
                  ? Image.network(fotoUrl, fit: BoxFit.cover)
                  : const Icon(Icons.image, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  formatoMoeda.format(item.preco),
                  style: TextStyle(color: corPrimaria ?? Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildQuantidadeBtn(Icons.remove, () => carrinho.atualizarQuantidade(item.id, item.quantidade - 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('${item.quantidade}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    _buildQuantidadeBtn(Icons.add, () => carrinho.atualizarQuantidade(item.id, item.quantidade + 1)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => carrinho.removerItem(item.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantidadeBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.black87),
        ),
      ),
    );
  }
}
