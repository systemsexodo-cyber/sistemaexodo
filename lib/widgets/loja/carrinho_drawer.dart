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
                // HEADER
                _buildHeader(context, carrinho),
                
                // LISTA
                Expanded(
                  child: carrinho.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: carrinho.itens.length,
                          itemBuilder: (context, index) {
                            final item = carrinho.itens[index];
                            String? fotoUrl;
                            try {
                              final produto = dataService.produtos.firstWhere((p) => p.id == item.itemId);
                              fotoUrl = produto.fotoPrincipalUrl ?? (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : null);
                            } catch (_) {}
                            return _buildItem(context, item, fotoUrl, carrinho, corP);
                          },
                        ),
                ),

                // SUMMARY
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
      padding: const EdgeInsets.fromLTRB(24, 60, 16, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sacola',
                style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                '${carrinho.totalItens} ${carrinho.totalItens == 1 ? 'item' : 'itens'}',
                style: TextStyle(color: Colors.white.withOpacity(0.4)),
              ),
            ],
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

  Widget _buildSummary(BuildContext context, CarrinhoService carrinho, Color corP) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18)),
              Text(
                formatoMoeda.format(carrinho.valorTotal),
                style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: onCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: corP,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 10,
                shadowColor: corP.withOpacity(0.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('FINALIZAR PEDIDO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  SizedBox(width: 12),
                  Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, dynamic item, String? fotoUrl, CarrinhoService carrinho, Color corP) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 70, height: 70,
              color: Colors.white10,
              child: fotoUrl != null ? Image.network(fotoUrl, fit: BoxFit.cover) : const Icon(Icons.image, color: Colors.white24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(formatoMoeda.format(item.preco), style: TextStyle(color: corP, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _qtyBtn(Icons.remove, () => carrinho.atualizarQuantidade(item.id, item.quantidade - 1), Colors.white10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('${item.quantidade}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    _qtyBtn(Icons.add, () => carrinho.atualizarQuantidade(item.id, item.quantidade + 1), corP.withOpacity(0.2)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
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

  Widget _qtyBtn(IconData icon, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 20),
          Text('Seu carrinho está vazio', style: TextStyle(color: Colors.white.withOpacity(0.3))),
        ],
      ),
    );
  }
}
