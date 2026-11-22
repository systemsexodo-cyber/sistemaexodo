import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/produto.dart';

/// Lista horizontal de produtos que combinam com o item que o cliente abriu.
///
/// É o cross-sell da loja online: o cliente vê a sugestão na própria tela do
/// produto e adiciona os complementos sem sair da vitrine.
class SugestoesProduto extends StatelessWidget {
  final String titulo;
  final List<Produto> produtos;
  final NumberFormat formatoMoeda;
  final Color corPrimaria;
  final Color corTexto;
  final void Function(Produto) onAdicionar;

  const SugestoesProduto({
    super.key,
    required this.titulo,
    required this.produtos,
    required this.formatoMoeda,
    required this.corPrimaria,
    required this.corTexto,
    required this.onAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    if (produtos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: corPrimaria),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: corTexto,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Aproveite e leve junto',
          style: TextStyle(fontSize: 12, color: corTexto.withOpacity(0.6)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 202,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: produtos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _CardSugestao(
              produto: produtos[index],
              formatoMoeda: formatoMoeda,
              corPrimaria: corPrimaria,
              corTexto: corTexto,
              onAdicionar: onAdicionar,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardSugestao extends StatefulWidget {
  final Produto produto;
  final NumberFormat formatoMoeda;
  final Color corPrimaria;
  final Color corTexto;
  final void Function(Produto) onAdicionar;

  const _CardSugestao({
    required this.produto,
    required this.formatoMoeda,
    required this.corPrimaria,
    required this.corTexto,
    required this.onAdicionar,
  });

  @override
  State<_CardSugestao> createState() => _CardSugestaoState();
}

class _CardSugestaoState extends State<_CardSugestao> {
  bool _adicionado = false;

  @override
  Widget build(BuildContext context) {
    final produto = widget.produto;
    final corTexto = widget.corTexto;
    final fotoUrl = produto.fotoPrincipalUrl ??
        (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : null);

    return Container(
      width: 142,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 90,
            child: fotoUrl != null && fotoUrl.isNotEmpty
                ? Image.network(
                    fotoUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.image_not_supported,
                          size: 24, color: corTexto.withOpacity(0.3)),
                    ),
                  )
                : Center(
                    child: Icon(Icons.image,
                        size: 24, color: corTexto.withOpacity(0.3)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produto.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: corTexto,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.formatoMoeda.format(produto.precoAtual),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: produto.promocaoAtiva
                        ? Colors.redAccent
                        : widget.corPrimaria,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: ElevatedButton(
                    onPressed: _adicionado
                        ? null
                        : () {
                            widget.onAdicionar(produto);
                            setState(() => _adicionado = true);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _adicionado ? Colors.green : widget.corPrimaria,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.green.withOpacity(0.6),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      _adicionado ? 'Adicionado' : 'Adicionar',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
