import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../../services/carrinho_service.dart';
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
      constraints: const BoxConstraints(maxWidth: 420),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.85),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(32)),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            ),
            child: Column(
              children: [
                _buildHeader(context, carrinho),
                Expanded(
                  child: carrinho.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: carrinho.itens.length,
                          itemBuilder: (context, index) {
                            final item = carrinho.itens[index];
                            String? fotoUrl;
                            try {
                              final produto = dataService.produtos
                                  .firstWhere((p) => p.id == item.itemId);
                              fotoUrl = produto.fotoPrincipalUrl ??
                                  (produto.fotosUrls.isNotEmpty
                                      ? produto.fotosUrls.first
                                      : null);
                            } catch (_) {}
                            return _buildItem(context, item, fotoUrl, carrinho, corP);
                          },
                        ),
                ),
                if (!carrinho.isEmpty) _buildSummary(context, carrinho, corP),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CarrinhoService carrinho) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sacola',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${carrinho.totalItens} ${carrinho.totalItens == 1 ? 'item' : 'itens'}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4)),
                ),
              ],
            ),
          ),
          if (!carrinho.isEmpty)
            TextButton.icon(
              onPressed: () => _confirmarLimpar(context, carrinho),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.redAccent),
              label: const Text('Limpar', style: TextStyle(color: Colors.redAccent)),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.white10),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarLimpar(BuildContext context, CarrinhoService carrinho) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Limpar a sacola?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Todos os itens serão removidos.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok == true) carrinho.limparCarrinho();
  }

  Widget _buildSummary(BuildContext context, CarrinhoService carrinho, Color corP) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${carrinho.totalItens} ${carrinho.totalItens == 1 ? 'item' : 'itens'}',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
              ),
              Text(
                formatoMoeda.format(carrinho.valorTotal),
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                formatoMoeda.format(carrinho.valorTotal),
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 62,
            child: ElevatedButton(
              onPressed: onCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: corP,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 8,
                shadowColor: corP.withOpacity(0.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'FINALIZAR PEDIDO',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Continuar comprando',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    dynamic item,
    String? fotoUrl,
    CarrinhoService carrinho,
    Color corP,
  ) {
    final subtotal = item.subtotal as double;
    final precoUnitario = item.preco as double;
    final quantidade = item.quantidade as int;
    final mostraUnitario = quantidade > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 72,
              height: 72,
              color: Colors.white10,
              child: fotoUrl != null
                  ? Image.network(fotoUrl, fit: BoxFit.cover)
                  : const Icon(Icons.image, color: Colors.white24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.nome as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                      tooltip: 'Remover item',
                      onPressed: () => carrinho.removerItem(item.id as String),
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                Text(
                  mostraUnitario
                      ? '${formatoMoeda.format(precoUnitario)} cada'
                      : formatoMoeda.format(precoUnitario),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _qtyBtn(
                      Icons.remove,
                      () => carrinho.atualizarQuantidade(
                        item.id as String,
                        quantidade - 1,
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      alignment: Alignment.center,
                      child: Text(
                        '$quantidade',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _qtyBtn(
                      Icons.add,
                      () => carrinho.atualizarQuantidade(
                        item.id as String,
                        quantidade + 1,
                      ),
                      destaque: true,
                    ),
                    const Spacer(),
                    Text(
                      formatoMoeda.format(subtotal),
                      style: TextStyle(
                        color: corP,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
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

  Widget _qtyBtn(IconData icon, VoidCallback onTap, {bool destaque = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: destaque ? Colors.white12 : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 20),
          Text(
            'Seu carrinho está vazio',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: const Text('Ver produtos'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
          ),
        ],
      ),
    );
  }
}
