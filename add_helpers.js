const fs = require('fs');
let c = fs.readFileSync('lib/pages/contas_receber_page.dart', 'utf8');

// Find the last closing brace of the class
const idx = c.lastIndexOf('}\n');

const helpers = `
  IconData _getIconeTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      case TipoPagamento.transferencia:
        return Icons.swap_horiz;
    }
  }

  Color _getCorTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return const Color(0xFF00BFA5);
      case TipoPagamento.cartaoCredito:
        return Colors.deepPurple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return const Color(0xFFE91E63);
      case TipoPagamento.fiado:
        return const Color(0xFFD84315);
      case TipoPagamento.outro:
        return Colors.grey;
      case TipoPagamento.alimentacao:
        return const Color(0xFF00897B);
      case TipoPagamento.transferencia:
        return const Color(0xFF42A5F5);
    }
  }
`;

c = c.slice(0, idx) + helpers + '}\n';
fs.writeFileSync('lib/pages/contas_receber_page.dart', c, 'utf8');
console.log('Helpers added. New length:', c.length);
