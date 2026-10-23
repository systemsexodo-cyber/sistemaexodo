import 'package:flutter/material.dart';

import '../models/pedido_compra.dart';

/// Cor de destaque de cada situação do pedido de compra.
Color corStatusPedidoCompra(String status) {
  switch (status) {
    case StatusPedidoCompra.rascunho:
      return Colors.blueGrey;
    case StatusPedidoCompra.enviado:
      return Colors.blueAccent;
    case StatusPedidoCompra.recebidoParcial:
      return Colors.orangeAccent;
    case StatusPedidoCompra.recebido:
      return const Color(0xFF00C853);
    case StatusPedidoCompra.cancelado:
      return Colors.redAccent;
    default:
      return Colors.blueGrey;
  }
}

/// Ícone que acompanha cada situação.
IconData iconeStatusPedidoCompra(String status) {
  switch (status) {
    case StatusPedidoCompra.rascunho:
      return Icons.edit_note_rounded;
    case StatusPedidoCompra.enviado:
      return Icons.local_shipping_outlined;
    case StatusPedidoCompra.recebidoParcial:
      return Icons.inventory_2_outlined;
    case StatusPedidoCompra.recebido:
      return Icons.check_circle_outline_rounded;
    case StatusPedidoCompra.cancelado:
      return Icons.cancel_outlined;
    default:
      return Icons.shopping_cart_outlined;
  }
}

/// Selo compacto com a situação do pedido.
class PedidoCompraStatusBadge extends StatelessWidget {
  final String status;
  final bool compacto;

  const PedidoCompraStatusBadge({
    super.key,
    required this.status,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = corStatusPedidoCompra(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 7 : 10,
        vertical: compacto ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconeStatusPedidoCompra(status),
            color: cor,
            size: compacto ? 10 : 12,
          ),
          SizedBox(width: compacto ? 3 : 5),
          Text(
            StatusPedidoCompra.rotulo(status),
            style: TextStyle(
              color: cor,
              fontSize: compacto ? 9 : 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
