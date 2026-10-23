import 'package:flutter/services.dart';

/// Item genérico de uma rota de entregas.
///
/// Serve para montar o texto que o operador copia e envia no WhatsApp do
/// motoboy. É intencionalmente "burro" (só dados prontos) para poder ser
/// alimentado tanto por [Pedido] quanto por [Entrega].
class RotaItemTexto {
  final String? numero;
  final String? cliente;
  final String? telefone;
  final String? endereco;
  final double? valor;
  final bool pago;
  final bool entregue;
  final String? observacao;

  const RotaItemTexto({
    this.numero,
    this.cliente,
    this.telefone,
    this.endereco,
    this.valor,
    this.pago = false,
    this.entregue = false,
    this.observacao,
  });
}

/// Montagem de texto de rota formatado para o WhatsApp (usa *negrito* que o
/// WhatsApp entende) + envio para a área de transferência.
class RotaTexto {
  RotaTexto._();

  /// Monta o texto da rota do motoboy.
  static String montar({
    String titulo = 'ROTA DE ENTREGA',
    String? motorista,
    DateTime? data,
    required List<RotaItemTexto> itens,
    String? observacoes,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🛵 *$titulo*');
    if (motorista != null && motorista.trim().isNotEmpty) {
      buffer.writeln('👤 Motoboy: *${motorista.trim()}*');
    }

    final d = data ?? DateTime.now();
    buffer.writeln(
      '📅 ${_dois(d.day)}/${_dois(d.month)}/${d.year} '
      '${_dois(d.hour)}:${_dois(d.minute)}',
    );

    final pendentes = itens.where((i) => !i.entregue).length;
    buffer.write('📍 ${itens.length} entrega(s)');
    if (pendentes != itens.length) {
      buffer.write(' • $pendentes pendente(s)');
    }
    buffer.writeln();
    buffer.writeln();

    if (itens.isEmpty) {
      buffer.writeln('_Nenhuma entrega._');
    }

    for (var i = 0; i < itens.length; i++) {
      final item = itens[i];
      final tituloItem =
          item.numero != null && item.numero!.trim().isNotEmpty
              ? '*${item.numero!.trim()}*'
              : '*Entrega ${i + 1}*';
      buffer.writeln('${i + 1}) $tituloItem${item.entregue ? ' ✅' : ''}');

      if (item.cliente != null && item.cliente!.trim().isNotEmpty) {
        buffer.writeln('   👤 ${item.cliente!.trim()}');
      }
      if (item.telefone != null && item.telefone!.trim().isNotEmpty) {
        buffer.writeln('   📞 ${item.telefone!.trim()}');
      }
      if (item.endereco != null && item.endereco!.trim().isNotEmpty) {
        buffer.writeln('   🏠 ${item.endereco!.trim()}');
      }
      if (item.valor != null) {
        final status = item.entregue
            ? 'ENTREGUE'
            : (item.pago ? 'PAGO' : 'A RECEBER');
        buffer.writeln(
          '   💰 R\$ ${item.valor!.toStringAsFixed(2).replaceAll('.', ',')} • '
          '$status',
        );
      }
      if (item.observacao != null && item.observacao!.trim().isNotEmpty) {
        buffer.writeln('   📝 ${item.observacao!.trim()}');
      }
      buffer.writeln();
    }

    if (observacoes != null && observacoes.trim().isNotEmpty) {
      buffer.writeln('📝 Obs: ${observacoes.trim()}');
    }

    final link = montarLinkMaps(itens);
    if (link != null) {
      buffer.writeln('🗺️ Rota no Google Maps:');
      buffer.writeln(link);
    }

    return buffer.toString().trimRight();
  }

  /// Monta um link do Google Maps com todas as paradas, na ordem da lista.
  /// Prioriza as entregas ainda pendentes.
  static String? montarLinkMaps(List<RotaItemTexto> itens) {
    var enderecos = itens
        .where((i) => !i.entregue)
        .map((i) => i.endereco?.trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    if (enderecos.isEmpty) {
      enderecos = itens
          .map((i) => i.endereco?.trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (enderecos.isEmpty) return null;

    final path = enderecos.map(Uri.encodeComponent).join('/');
    return 'https://www.google.com/maps/dir//$path';
  }

  /// Copia o texto para a área de transferência.
  static Future<void> copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
  }

  static String _dois(int v) => v.toString().padLeft(2, '0');
}
