import 'dart:convert';

/// Situações possíveis de um pedido de compra.
///
/// O fluxo é: rascunho -> enviado -> recebido_parcial -> recebido.
/// `cancelado` encerra o pedido sem mexer no estoque.
class StatusPedidoCompra {
  static const String rascunho = 'rascunho';
  static const String enviado = 'enviado';
  static const String recebidoParcial = 'recebido_parcial';
  static const String recebido = 'recebido';
  static const String cancelado = 'cancelado';

  static const List<String> todos = [
    rascunho,
    enviado,
    recebidoParcial,
    recebido,
    cancelado,
  ];

  /// Pedidos que ainda esperam mercadoria (entram no cálculo do selo
  /// "JÁ PEDIDO" do relatório de reposição).
  static const List<String> emAberto = [rascunho, enviado, recebidoParcial];

  static String rotulo(String status) {
    switch (status) {
      case rascunho:
        return 'Rascunho';
      case enviado:
        return 'Enviado ao fornecedor';
      case recebidoParcial:
        return 'Recebido parcialmente';
      case recebido:
        return 'Recebido';
      case cancelado:
        return 'Cancelado';
      default:
        return status.isEmpty ? 'Rascunho' : status;
    }
  }

  static bool estaEmAberto(String status) => emAberto.contains(status);
}

/// Um item (produto) de um pedido de compra.
class ItemPedidoCompra {
  final String id;
  final String produtoId;
  final String produtoNome;
  final String? codigo;
  final String unidade;
  final double quantidade;
  final double quantidadeRecebida;
  final double precoCusto;
  final String? observacao;

  ItemPedidoCompra({
    required this.id,
    required this.produtoId,
    required this.produtoNome,
    this.codigo,
    this.unidade = 'UN',
    required this.quantidade,
    this.quantidadeRecebida = 0,
    this.precoCusto = 0,
    this.observacao,
  });

  factory ItemPedidoCompra.fromMap(Map<String, dynamic> map) {
    final produtoId = _texto(map['produtoId'] ?? map['produto_id']);
    return ItemPedidoCompra(
      id: _texto(map['id']).isEmpty
          ? '${produtoId}_${DateTime.now().microsecondsSinceEpoch}'
          : _texto(map['id']),
      produtoId: produtoId,
      produtoNome: _texto(
        map['produtoNome'] ?? map['produto_nome'] ?? map['nome'],
      ),
      codigo: _textoOuNulo(map['codigo'] ?? map['codigoProduto']),
      unidade: _texto(map['unidade']).isEmpty ? 'UN' : _texto(map['unidade']),
      quantidade: _numero(map['quantidade']),
      quantidadeRecebida: _numero(
        map['quantidadeRecebida'] ?? map['quantidade_recebida'],
      ),
      precoCusto: _numero(
        map['precoCusto'] ?? map['preco_custo'] ?? map['custo'],
      ),
      observacao: _textoOuNulo(map['observacao'] ?? map['observacoes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produtoId': produtoId,
      'produtoNome': produtoNome,
      'codigo': codigo,
      'unidade': unidade,
      'quantidade': quantidade,
      'quantidadeRecebida': quantidadeRecebida,
      'precoCusto': precoCusto,
      'observacao': observacao,
    };
  }

  double get valorTotal => quantidade * precoCusto;

  double get valorRecebido => quantidadeRecebida * precoCusto;

  /// Quanto ainda falta receber (nunca negativo).
  double get quantidadePendente {
    final pendente = quantidade - quantidadeRecebida;
    return pendente < 0 ? 0 : pendente;
  }

  bool get recebido => quantidadePendente <= 0.0001;

  bool get parcial => quantidadeRecebida > 0.0001 && !recebido;

  ItemPedidoCompra copyWith({
    String? id,
    String? produtoId,
    String? produtoNome,
    String? codigo,
    String? unidade,
    double? quantidade,
    double? quantidadeRecebida,
    double? precoCusto,
    String? observacao,
  }) {
    return ItemPedidoCompra(
      id: id ?? this.id,
      produtoId: produtoId ?? this.produtoId,
      produtoNome: produtoNome ?? this.produtoNome,
      codigo: codigo ?? this.codigo,
      unidade: unidade ?? this.unidade,
      quantidade: quantidade ?? this.quantidade,
      quantidadeRecebida: quantidadeRecebida ?? this.quantidadeRecebida,
      precoCusto: precoCusto ?? this.precoCusto,
      observacao: observacao ?? this.observacao,
    );
  }
}

/// Pedido de compra persistido no sistema.
///
/// O fornecedor é identificado pelo nome (o cadastro de produtos usa
/// `fornecedorNome`) e mantém o id quando ele existir. Os itens guardam uma
/// fotografia do produto (nome/código/custo) para o pedido continuar legível
/// mesmo se o cadastro for alterado depois.
class PedidoCompra {
  final String id;
  final String numero;
  final String fornecedorId;
  final String fornecedorNome;
  final String? fornecedorCnpj;
  final String? fornecedorTelefone;
  final String status;
  final List<ItemPedidoCompra> itens;
  final String? observacao;
  final String? usuario;
  final String? estoqueDestinoId;
  final String? estoqueDestinoNome;
  final DateTime dataCriacao;
  final DateTime? dataEnvio;
  final DateTime? previsaoEntrega;
  final DateTime? dataRecebimento;
  final DateTime? dataCancelamento;
  final String? motivoCancelamento;
  final DateTime createdAt;
  final DateTime updatedAt;

  PedidoCompra({
    required this.id,
    required this.numero,
    this.fornecedorId = '',
    required this.fornecedorNome,
    this.fornecedorCnpj,
    this.fornecedorTelefone,
    this.status = StatusPedidoCompra.rascunho,
    required this.itens,
    this.observacao,
    this.usuario,
    this.estoqueDestinoId,
    this.estoqueDestinoNome,
    DateTime? dataCriacao,
    this.dataEnvio,
    this.previsaoEntrega,
    this.dataRecebimento,
    this.dataCancelamento,
    this.motivoCancelamento,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : dataCriacao = dataCriacao ?? DateTime.now(),
       createdAt = createdAt ?? dataCriacao ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory PedidoCompra.fromMap(Map<String, dynamic> map) {
    final dataCriacao = _data(
      map['dataCriacao'] ??
          map['data_criacao'] ??
          map['dataPedido'] ??
          map['createdAt'] ??
          map['created_at'],
    );
    return PedidoCompra(
      id: _texto(map['id']),
      numero: _texto(map['numero'] ?? map['numeroPedido']),
      fornecedorId: _texto(map['fornecedorId'] ?? map['fornecedor_id']),
      fornecedorNome: _texto(map['fornecedorNome'] ?? map['fornecedor_nome']),
      fornecedorCnpj: _textoOuNulo(
        map['fornecedorCnpj'] ?? map['fornecedor_cnpj'],
      ),
      fornecedorTelefone: _textoOuNulo(
        map['fornecedorTelefone'] ?? map['fornecedor_telefone'],
      ),
      status: _texto(map['status']).isEmpty
          ? StatusPedidoCompra.rascunho
          : _texto(map['status']),
      itens: _itensDoPedido(map['itens']),
      observacao: _textoOuNulo(map['observacao'] ?? map['observacoes']),
      usuario: _textoOuNulo(map['usuario'] ?? map['operador']),
      estoqueDestinoId: _textoOuNulo(
        map['estoqueDestinoId'] ?? map['estoque_destino_id'],
      ),
      estoqueDestinoNome: _textoOuNulo(
        map['estoqueDestinoNome'] ?? map['estoque_destino_nome'],
      ),
      dataCriacao: dataCriacao,
      dataEnvio: _data(map['dataEnvio'] ?? map['data_envio']),
      previsaoEntrega: _data(map['previsaoEntrega'] ?? map['previsao_entrega']),
      dataRecebimento: _data(map['dataRecebimento'] ?? map['data_recebimento']),
      dataCancelamento: _data(
        map['dataCancelamento'] ?? map['data_cancelamento'],
      ),
      motivoCancelamento: _textoOuNulo(
        map['motivoCancelamento'] ?? map['motivo_cancelamento'],
      ),
      createdAt: _data(map['createdAt'] ?? map['created_at']) ?? dataCriacao,
      updatedAt:
          _data(map['updatedAt'] ?? map['updated_at']) ??
          dataCriacao ??
          DateTime.now(),
    );
  }

  /// Serializa no padrão de colunas da tabela (`pedidos_compra` usa
  /// snake_case no PostgreSQL local e no Supabase). [fromMap] continua lendo
  /// as duas grafias para não perder dados antigos gravados em camelCase.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'fornecedor_id': fornecedorId,
      'fornecedor_nome': fornecedorNome,
      'fornecedor_cnpj': fornecedorCnpj,
      'fornecedor_telefone': fornecedorTelefone,
      'status': status,
      'itens': itens.map((item) => item.toMap()).toList(),
      'observacao': observacao,
      'usuario': usuario,
      'estoque_destino_id': estoqueDestinoId,
      'estoque_destino_nome': estoqueDestinoNome,
      'data_criacao': dataCriacao.toUtc().toIso8601String(),
      'data_envio': dataEnvio?.toUtc().toIso8601String(),
      'previsao_entrega': previsaoEntrega?.toUtc().toIso8601String(),
      'data_recebimento': dataRecebimento?.toUtc().toIso8601String(),
      'data_cancelamento': dataCancelamento?.toUtc().toIso8601String(),
      'motivo_cancelamento': motivoCancelamento,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  double get valorTotal =>
      itens.fold(0.0, (total, item) => total + item.valorTotal);

  double get quantidadeTotal =>
      itens.fold(0.0, (total, item) => total + item.quantidade);

  double get quantidadeRecebida =>
      itens.fold(0.0, (total, item) => total + item.quantidadeRecebida);

  double get quantidadePendente =>
      itens.fold(0.0, (total, item) => total + item.quantidadePendente);

  int get itensPendentes => itens.where((item) => !item.recebido).length;

  bool get emAberto => StatusPedidoCompra.estaEmAberto(status);

  bool get cancelado => status == StatusPedidoCompra.cancelado;

  bool get recebido => status == StatusPedidoCompra.recebido;

  bool get podeReceber => emAberto && quantidadePendente > 0.0001;

  double get percentualRecebido {
    if (quantidadeTotal <= 0) return 0;
    final percentual = (quantidadeRecebida / quantidadeTotal) * 100;
    return percentual.clamp(0, 100).toDouble();
  }

  String get statusRotulo => StatusPedidoCompra.rotulo(status);

  String get descricaoPrazo {
    if (dataRecebimento != null) {
      return 'Recebido em ${_formatarData(dataRecebimento!)}';
    }
    if (previsaoEntrega != null) {
      return 'Previsão: ${_formatarData(previsaoEntrega!)}';
    }
    return 'Criado em ${_formatarData(dataCriacao)}';
  }

  PedidoCompra copyWith({
    String? id,
    String? numero,
    String? fornecedorId,
    String? fornecedorNome,
    String? fornecedorCnpj,
    String? fornecedorTelefone,
    String? status,
    List<ItemPedidoCompra>? itens,
    String? observacao,
    String? usuario,
    String? estoqueDestinoId,
    String? estoqueDestinoNome,
    DateTime? dataCriacao,
    DateTime? dataEnvio,
    DateTime? previsaoEntrega,
    DateTime? dataRecebimento,
    DateTime? dataCancelamento,
    String? motivoCancelamento,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PedidoCompra(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      fornecedorCnpj: fornecedorCnpj ?? this.fornecedorCnpj,
      fornecedorTelefone: fornecedorTelefone ?? this.fornecedorTelefone,
      status: status ?? this.status,
      itens: itens ?? this.itens,
      observacao: observacao ?? this.observacao,
      usuario: usuario ?? this.usuario,
      estoqueDestinoId: estoqueDestinoId ?? this.estoqueDestinoId,
      estoqueDestinoNome: estoqueDestinoNome ?? this.estoqueDestinoNome,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataEnvio: dataEnvio ?? this.dataEnvio,
      previsaoEntrega: previsaoEntrega ?? this.previsaoEntrega,
      dataRecebimento: dataRecebimento ?? this.dataRecebimento,
      dataCancelamento: dataCancelamento ?? this.dataCancelamento,
      motivoCancelamento: motivoCancelamento ?? this.motivoCancelamento,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// Resultado de um recebimento (parcial ou total) de pedido de compra.
class ResultadoRecebimentoPedidoCompra {
  final PedidoCompra pedido;
  final int itensRecebidos;
  final double quantidadeRecebida;
  final List<String> avisos;

  const ResultadoRecebimentoPedidoCompra({
    required this.pedido,
    required this.itensRecebidos,
    required this.quantidadeRecebida,
    this.avisos = const [],
  });

  bool get completo => pedido.status == StatusPedidoCompra.recebido;
}

// ============ Helpers de serialização ============

String _texto(dynamic valor) => valor == null ? '' : valor.toString().trim();

String? _textoOuNulo(dynamic valor) {
  final texto = _texto(valor);
  return texto.isEmpty ? null : texto;
}

double _numero(dynamic valor) {
  if (valor == null) return 0;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString().replaceAll(',', '.')) ?? 0;
}

DateTime? _data(dynamic valor) {
  if (valor == null) return null;
  if (valor is DateTime) return valor;
  return DateTime.tryParse(valor.toString());
}

List<ItemPedidoCompra> _itensDoPedido(dynamic bruto) {
  dynamic lista = bruto;
  if (bruto is String) {
    final texto = bruto.trim();
    if (texto.isEmpty) return [];
    try {
      lista = jsonDecode(texto);
    } catch (_) {
      return [];
    }
  }
  if (lista is! List) return [];
  final itens = <ItemPedidoCompra>[];
  for (final item in lista) {
    if (item is Map) {
      itens.add(ItemPedidoCompra.fromMap(Map<String, dynamic>.from(item)));
    }
  }
  return itens;
}

String _formatarData(DateTime data) {
  final d = data.day.toString().padLeft(2, '0');
  final m = data.month.toString().padLeft(2, '0');
  return '$d/$m/${data.year}';
}
