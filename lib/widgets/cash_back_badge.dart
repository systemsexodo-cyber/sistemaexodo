import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Widget que mostra o saldo disponível de cash back do cliente.
///
/// Para o futuro: quando você trocar por uma API, aqui cai tudo que o PDV
/// precisa para exibir — ele não fica acoplado à origem do saldo.
class CashBackBadge extends StatelessWidget {
  final double saldo;
  final VoidCallback? onPress;
  final String? tituloExtra;
  final bool somenteVisu;

  const CashBackBadge({
    super.key,
    required this.saldo,
    this.onPress,
    this.tituloExtra,
    this.somenteVisu = false,
  });

  @override
  Widget build(BuildContext context) {
    final formato =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
    final saldoTexto =
        saldo > 0 ? formato.format(saldo) : 'R\$ 0,00';
    final corDoSaldo = saldo > 0 ? Colors.amber : Colors.grey.shade600;
    final icone = saldo > 0 ? Icons.local_atm : Icons.local_atm_outlined;

    final textoFinal = tituloExtra != null && tituloExtra!.isNotEmpty
        ? '$tituloExtra: $saldoTexto'
        : 'Cash Back: $saldoTexto';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: somenteVisu ? null : onPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: corDoSaldo.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: corDoSaldo.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icone,
                size: 16,
                color: corDoSaldo,
              ),
              const SizedBox(width: 6),
              Text(
                textoFinal,
                style: TextStyle(
                  color: corDoSaldo,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
