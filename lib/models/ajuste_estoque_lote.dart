import 'dart:convert';

/// Registro de um **ajuste em massa** (Ajuste Geral • Estoque e Preço).
///
/// Cada aplicação na tela de ajuste vira um lote: ele guarda o valor que cada
/// produto tinha ANTES e o valor que passou a ter (estoque e/ou preço). Com
/// isso o ajuste fica auditável (quem, quando, o que mudou) e pode ser
/// desfeito por inteiro depois — a reversão grava movimentações de estorno no
/// histórico de estoque, em vez de apagar o que já foi registrado.
class AjusteEstoqueLoteItem {
  final String produtoId;
  final String produtoNome;
  final String? produtoCodigo;

  /// Estoque do produto antes do ajuste (null quando o lote não mexeu nele).
  final double? estoqueAnterior;

  /// Estoque aplicado pelo ajuste (null quando o lote não mexeu nele).
  final double? estoqueNovo;

  /// Qual ESTOQUE foi ajustado pelo item (null = o total do produto, como era
  /// antes de a tela de Ajuste Geral ganhar o seletor Loja/Depósito).
  ///
  /// Guardado para o DESFAZER devolver a quantidade ao mesmo lugar: o valor
  /// anterior sem esse id seria reaplicado sobre o TOTAL, bagunçando os saldos
  /// por estoque.
  final String? estoqueId;

  /// Preço de venda antes do ajuste (null quando o lote não mexeu nele).
  final double? precoAnterior;

  /// Preço de venda aplicado pelo ajuste (null quando o lote não mexeu nele).
  final double? precoNovo;

  const AjusteEstoqueLoteItem({
    required this.produtoId,
    required this.produtoNome,
    this.produtoCodigo,
    this.estoqueAnterior,
    this.estoqueNovo,
    this.estoqueId,
    this.precoAnterior,
    this.precoNovo,
  });

  bool get alterouEstoque =>
      estoqueAnterior != null &&
      estoqueNovo != null &&
      (estoqueNovo! - estoqueAnterior!).abs() >= 0.0005;

  bool get alterouPreco =>
      precoAnterior != null &&
      precoNovo != null &&
      (precoNovo! - precoAnterior!).abs() >= 0.005;

  factory AjusteEstoqueLoteItem.fromMap(Map<String, dynamic> map) {
    return AjusteEstoqueLoteItem(
      produtoId: map['produto_id'] ?? map['produtoId'] ?? '',
      produtoNome: map['produto_nome'] ?? map['produtoNome'] ?? '',
      produtoCodigo: map['produto_codigo'] ?? map['produtoCodigo'],
      estoqueAnterior: _paraDouble(map['estoque_anterior'] ?? map['estoqueAnterior']),
      estoqueNovo: _paraDouble(map['estoque_novo'] ?? map['estoqueNovo']),
      estoqueId: map['estoque_id'] ?? map['estoqueId'],
      precoAnterior: _paraDouble(map['preco_anterior'] ?? map['precoAnterior']),
      precoNovo: _paraDouble(map['preco_novo'] ?? map['precoNovo']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'produto_codigo': produtoCodigo,
      'estoque_anterior': estoqueAnterior,
      'estoque_novo': estoqueNovo,
      'estoque_id': estoqueId,
      'preco_anterior': precoAnterior,
      'preco_novo': precoNovo,
    };
  }

  static double? _paraDouble(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString());
  }
}

class AjusteEstoqueLote {
  final String id;

  /// Data/hora local em que o ajuste foi aplicado.
  final DateTime data;

  final String? usuario;
  final String? observacao;

  /// De onde veio o ajuste (ex.: 'Ajuste em massa', 'Inventário').
  final String origem;

  final List<AjusteEstoqueLoteItem> itens;

  /// `true` depois que o lote foi revertido pelo botão DESFAZER.
  final bool desfeito;
  final DateTime? dataDesfeito;
  final String? usuarioDesfeito;

  AjusteEstoqueLote({
    required this.id,
    required this.data,
    this.usuario,
    this.observacao,
    this.origem = 'Ajuste em massa',
    this.itens = const [],
    this.desfeito = false,
    this.dataDesfeito,
    this.usuarioDesfeito,
  });

  int get totalItens => itens.length;
  int get totalEstoques => itens.where((i) => i.alterouEstoque).length;
  int get totalPrecos => itens.where((i) => i.alterouPreco).length;

  bool get podeSerDesfeito => !desfeito && itens.isNotEmpty;

  AjusteEstoqueLote copyWith({
    bool? desfeito,
    DateTime? dataDesfeito,
    String? usuarioDesfeito,
  }) {
    return AjusteEstoqueLote(
      id: id,
      data: data,
      usuario: usuario,
      observacao: observacao,
      origem: origem,
      itens: itens,
      desfeito: desfeito ?? this.desfeito,
      dataDesfeito: dataDesfeito ?? this.dataDesfeito,
      usuarioDesfeito: usuarioDesfeito ?? this.usuarioDesfeito,
    );
  }

  /// Converte datas vindas do banco/nuvem (UTC) para hora local.
  static DateTime _paraLocal(dynamic v) {
    if (v == null) return DateTime.now();
    DateTime d;
    if (v is DateTime) {
      d = v;
    } else {
      try {
        d = DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.now();
      }
    }
    return d.isUtc ? d.toLocal() : d;
  }

  factory AjusteEstoqueLote.fromMap(Map<String, dynamic> map) {
    final itensBrutos = map['itens'] ?? map['itens_json'];
    final itens = <AjusteEstoqueLoteItem>[];
    if (itensBrutos is List) {
      for (final bruto in itensBrutos) {
        if (bruto is Map) {
          itens.add(AjusteEstoqueLoteItem.fromMap(Map<String, dynamic>.from(bruto)));
        }
      }
    } else if (itensBrutos is String && itensBrutos.trim().isNotEmpty) {
      // Tolerância a jsonb serializado como texto por algum driver.
      try {
        final decodificado = jsonDecode(itensBrutos);
        if (decodificado is List) {
          for (final bruto in decodificado) {
            if (bruto is Map) {
              itens.add(AjusteEstoqueLoteItem.fromMap(Map<String, dynamic>.from(bruto)));
            }
          }
        }
      } catch (_) {
        // itens ilegíveis: o lote continua válido, só sem detalhamento.
      }
    }

    return AjusteEstoqueLote(
      id: map['id']?.toString() ?? '',
      data: _paraLocal(map['data']),
      usuario: map['usuario'],
      observacao: map['observacao'],
      origem: map['origem'] ?? 'Ajuste em massa',
      itens: itens,
      desfeito: map['desfeito'] == true ||
          map['desfeito'] == 1 ||
          map['desfeito']?.toString().toLowerCase() == 'true',
      dataDesfeito: map['data_desfeito'] != null || map['dataDesfeito'] != null
          ? _paraLocal(map['data_desfeito'] ?? map['dataDesfeito'])
          : null,
      usuarioDesfeito: map['usuario_desfeito'] ?? map['usuarioDesfeito'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      // Gravar em UTC (convenção do projeto) para a data não "andar" no banco.
      'data': data.toUtc().toIso8601String(),
      'usuario': usuario,
      'observacao': observacao,
      'origem': origem,
      'itens': itens.map((i) => i.toMap()).toList(),
      'total_itens': totalItens,
      'total_estoques': totalEstoques,
      'total_precos': totalPrecos,
      'desfeito': desfeito,
      'data_desfeito': dataDesfeito?.toUtc().toIso8601String(),
      'usuario_desfeito': usuarioDesfeito,
    };
  }
}
