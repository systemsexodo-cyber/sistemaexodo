import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/produto.dart';

class ProdutoCard extends StatefulWidget {
  final Produto produto;
  final NumberFormat formatoMoeda;
  final bool descontoPixAtivo;
  final double percentualDescontoPix;
  final String estiloCards;
  final bool isCompacto;
  final Function(Produto) onAddToCart;
  final Function(Produto) onShowDetails;
  final Color? corPrimaria;

  const ProdutoCard({
    super.key,
    required this.produto,
    required this.formatoMoeda,
    required this.descontoPixAtivo,
    required this.percentualDescontoPix,
    this.estiloCards = 'padrao',
    this.isCompacto = false,
    required this.onAddToCart,
    required this.onShowDetails,
    this.corPrimaria,
  });

  @override
  State<ProdutoCard> createState() => _ProdutoCardState();
}

class _ProdutoCardState extends State<ProdutoCard> {
  bool isCardHovered = false;

  @override
  Widget build(BuildContext context) {
    final produto = widget.produto;
    final formatoMoeda = widget.formatoMoeda;
    final temEstoque = produto.estoqueTotal > 0;
    final fotoUrl = produto.fotoPrincipalUrl ?? 
                    (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : null);
    final corPrimaria = widget.corPrimaria ?? Theme.of(context).colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..scale(isCardHovered ? 1.02 : 1.0)
          ..translate(0.0, isCardHovered ? -2.0 : 0.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: isCardHovered
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      corPrimaria.withOpacity(0.02),
                    ],
                  )
                : null,
            color: isCardHovered ? null : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCardHovered 
                  ? corPrimaria.withOpacity(0.4)
                  : Colors.grey[200]!,
              width: isCardHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isCardHovered
                    ? corPrimaria.withOpacity(0.2)
                    : Colors.black.withOpacity(0.06),
                blurRadius: isCardHovered ? 8 : 3,
                offset: Offset(0, isCardHovered ? 2 : 0.5),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Imagem do produto
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: InkWell(
                  onTap: () => widget.onShowDetails(produto),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: _buildImagemComHover(
                        fotoUrl: fotoUrl,
                        produto: produto,
                        corPrimaria: corPrimaria,
                      ),
                    ),
                  ),
                ),
              ),
              // Informações do produto
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.fromLTRB(
                  widget.isCompacto ? 6.0 : 8.0,
                  widget.isCompacto ? 4.0 : 4.0,
                  widget.isCompacto ? 6.0 : 8.0,
                  widget.isCompacto ? 0.0 : 0.0,
                ),
                decoration: BoxDecoration(
                  gradient: isCardHovered
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).cardColor.withOpacity(0.95),
                            Theme.of(context).cardColor,
                          ],
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      produto.nome,
                      maxLines: widget.isCompacto ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (produto.promocaoAtiva) ...[
                          Row(
                            children: [
                              Text(
                                formatoMoeda.format(produto.preco),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${produto.percentualDesconto.toStringAsFixed(0)}% OFF',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 0.5),
                        ],
                        Text(
                          formatoMoeda.format(produto.precoAtual),
                          style: TextStyle(
                            fontSize: widget.isCompacto ? 13 : 16,
                            fontWeight: FontWeight.bold,
                            color: produto.promocaoAtiva 
                                ? Colors.red[700]
                                : corPrimaria,
                            shadows: isCardHovered ? [
                              Shadow(
                                color: corPrimaria.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ] : null,
                          ),
                        ),
                        if (widget.descontoPixAtivo && widget.percentualDescontoPix > 0 && !widget.isCompacto) ...[
                          const SizedBox(height: 0.5),
                          Row(
                            children: [
                              Icon(
                                Icons.pix,
                                size: 14,
                                color: Colors.green[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${formatoMoeda.format(produto.precoAtual * (1 - widget.percentualDescontoPix / 100))} no PIX',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    if (!temEstoque) ...[
                      const SizedBox(height: 0.5),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.isCompacto ? 4 : 6, 
                          vertical: widget.isCompacto ? 1 : 2
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red[200]!, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: widget.isCompacto ? 10 : 12, color: Colors.red[700]),
                            const SizedBox(width: 2),
                            Text(
                              'Esgotado',
                              style: TextStyle(
                                fontSize: widget.isCompacto ? 9 : 10,
                                color: Colors.red[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Padding(
                      padding: EdgeInsets.only(
                        top: !temEstoque ? 2 : 3,
                        bottom: 4,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        transform: Matrix4.identity()..scale(isCardHovered && temEstoque ? 1.02 : 1.0),
                        child: SizedBox(
                          width: double.infinity,
                          height: widget.isCompacto ? 26 : 30,
                          child: ElevatedButton(
                            onPressed: temEstoque
                                ? () => widget.onAddToCart(produto)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: temEstoque 
                                  ? corPrimaria
                                  : Colors.grey[300],
                              foregroundColor: temEstoque ? Colors.white : Colors.grey[600],
                              elevation: isCardHovered && temEstoque ? 4 : (temEstoque ? 1 : 0),
                              shadowColor: isCardHovered && temEstoque
                                  ? corPrimaria.withOpacity(0.5)
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  temEstoque ? Icons.shopping_cart_outlined : Icons.block,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  temEstoque ? 'Adicionar' : 'Indisponível',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagemComHover({
    required String? fotoUrl,
    required Produto produto,
    required Color corPrimaria,
  }) {
    bool isImageHovered = false;
    
    return StatefulBuilder(
      builder: (context, setImgState) {
        return MouseRegion(
          onEnter: (_) => setImgState(() => isImageHovered = true),
          onExit: (_) => setImgState(() => isImageHovered = false),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[50],
            ),
            clipBehavior: Clip.antiAlias,
            child: fotoUrl != null && fotoUrl.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        transform: Matrix4.identity()
                          ..scale(isImageHovered ? 1.2 : 1.0),
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                        ),
                        child: Image.network(
                          fotoUrl,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.image_not_supported, size: 32, color: Colors.grey),
                            );
                          },
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: isImageHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 400),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.4),
                              ],
                            ),
                          ),
                          child: Center(
                            child: AnimatedScale(
                              scale: isImageHovered ? 1.0 : 0.8,
                              duration: const Duration(milliseconds: 400),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in, color: corPrimaria, size: 20),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Ver detalhes',
                                      style: TextStyle(
                                        color: corPrimaria,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (produto.promocaoAtiva)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${produto.percentualDesconto.toStringAsFixed(0)}% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : const Center(child: Icon(Icons.image, size: 40, color: Colors.grey)),
          ),
        );
      },
    );
  }
}
