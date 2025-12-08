/// Registro de um pagamento realizado
class RegistroPagamento {
  final String id;
  final double valor;
  final DateTime dataPagamento;
  final String? formaPagamento;
  final String? observacao;

  RegistroPagamento({
    required this.id,
    required this.valor,
    required this.dataPagamento,
    this.formaPagamento,
    this.observacao,
  });

  factory RegistroPagamento.fromMap(Map<String, dynamic> map) {
    return RegistroPagamento(
      id: map['id'] ?? '',
      valor: (map['valor'] ?? 0).toDouble(),
      dataPagamento: DateTime.parse(map['dataPagamento']),
      formaPagamento: map['formaPagamento'],
      observacao: map['observacao'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'valor': valor,
      'dataPagamento': dataPagamento.toIso8601String(),
      'formaPagamento': formaPagamento,
      'observacao': observacao,
    };
  }
}

/// Tipo de conta a pagar
enum TipoContaPagar {
  notaEntrada, // Pagamento de nota de entrada
  despesaFixa, // Despesa fixa (ex: aluguel, salário)
  despesaVariavel, // Despesa variável (ex: energia, água)
}

extension TipoContaPagarExtension on TipoContaPagar {
  String get nome {
    switch (this) {
      case TipoContaPagar.notaEntrada:
        return 'Nota de Entrada';
      case TipoContaPagar.despesaFixa:
        return 'Despesa Fixa';
      case TipoContaPagar.despesaVariavel:
        return 'Despesa Variável';
    }
  }
}

/// Status da conta a pagar
enum StatusContaPagar {
  pendente,
  pago,
  vencido,
  cancelado,
}

extension StatusContaPagarExtension on StatusContaPagar {
  String get nome {
    switch (this) {
      case StatusContaPagar.pendente:
        return 'Pendente';
      case StatusContaPagar.pago:
        return 'Pago';
      case StatusContaPagar.vencido:
        return 'Vencido';
      case StatusContaPagar.cancelado:
        return 'Cancelado';
    }
  }
}

/// Modelo para representar uma conta a pagar
class ContaPagar {
  final String id;
  final String? numero; // Número da conta (ex: CP-0001)
  
  // Tipo e categoria
  final TipoContaPagar tipo;
  final String? categoria; // Categoria da despesa (ex: Aluguel, Energia, etc)
  
  // Descrição
  final String descricao;
  final String? observacoes;
  
  // Valores
  final double valor;
  final double? valorPago;
  
  // Datas
  final DateTime dataVencimento;
  final DateTime? dataPagamento;
  final DateTime dataCriacao;
  final DateTime updatedAt;
  
  // Relacionamentos
  final String? notaEntradaId; // ID da nota de entrada (se tipo = notaEntrada)
  final String? notaEntradaNumero; // Número da nota de entrada
  final String? fornecedorId; // ID do fornecedor
  final String? fornecedorNome; // Nome do fornecedor
  
  // Status
  final StatusContaPagar status;
  
  // Forma de pagamento (quando pago)
  final String? formaPagamento; // Dinheiro, PIX, Boleto, etc
  
  // Histórico de pagamentos
  final List<RegistroPagamento> historicoPagamentos;
  
  // Recorrência (para despesas fixas)
  final bool recorrente;
  final int? intervaloRecorrencia; // Em dias (ex: 30 para mensal)
  final DateTime? proximaDataRecorrencia;
  
  // Controle
  final bool ativo;
  final String? usuarioCriacao; // ID do usuário que criou
  final String? usuarioPagamento; // ID do usuário que pagou

  ContaPagar({
    required this.id,
    this.numero,
    required this.tipo,
    this.categoria,
    required this.descricao,
    this.observacoes,
    required this.valor,
    this.valorPago,
    required this.dataVencimento,
    this.dataPagamento,
    DateTime? dataCriacao,
    DateTime? updatedAt,
    this.notaEntradaId,
    this.notaEntradaNumero,
    this.fornecedorId,
    this.fornecedorNome,
    StatusContaPagar? status,
    this.formaPagamento,
    List<RegistroPagamento>? historicoPagamentos,
    this.recorrente = false,
    this.intervaloRecorrencia,
    this.proximaDataRecorrencia,
    this.ativo = true,
    this.usuarioCriacao,
    this.usuarioPagamento,
  }) : status = status ?? StatusContaPagar.pendente,
       dataCriacao = dataCriacao ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       historicoPagamentos = historicoPagamentos ?? [];

  /// Verifica se a conta está vencida
  bool get isVencida {
    if (status == StatusContaPagar.pago || 
        status == StatusContaPagar.cancelado) {
      return false;
    }
    return DateTime.now().isAfter(dataVencimento);
  }

  /// Verifica se a conta está próxima do vencimento (5 dias)
  bool get isProximoVencimento {
    if (status == StatusContaPagar.pago || 
        status == StatusContaPagar.cancelado) {
      return false;
    }
    final diasRestantes = dataVencimento.difference(DateTime.now()).inDays;
    return diasRestantes >= 0 && diasRestantes <= 5;
  }

  /// Retorna o valor pendente
  double get valorPendente {
    if (status == StatusContaPagar.pago) return 0.0;
    return valor - (valorPago ?? 0.0);
  }

  /// Retorna o status atualizado (considerando vencimento)
  StatusContaPagar get statusAtualizado {
    if (status == StatusContaPagar.pago || 
        status == StatusContaPagar.cancelado) {
      return status;
    }
    return isVencida ? StatusContaPagar.vencido : StatusContaPagar.pendente;
  }

  /// Cria uma cópia do objeto com campos atualizados
  ContaPagar copyWith({
    String? id,
    String? numero,
    TipoContaPagar? tipo,
    String? categoria,
    String? descricao,
    String? observacoes,
    double? valor,
    double? valorPago,
    DateTime? dataVencimento,
    DateTime? dataPagamento,
    DateTime? dataCriacao,
    DateTime? updatedAt,
    String? notaEntradaId,
    String? notaEntradaNumero,
    String? fornecedorId,
    String? fornecedorNome,
    StatusContaPagar? status,
    String? formaPagamento,
    List<RegistroPagamento>? historicoPagamentos,
    bool? recorrente,
    int? intervaloRecorrencia,
    DateTime? proximaDataRecorrencia,
    bool? ativo,
    String? usuarioCriacao,
    String? usuarioPagamento,
  }) {
    return ContaPagar(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      tipo: tipo ?? this.tipo,
      categoria: categoria ?? this.categoria,
      descricao: descricao ?? this.descricao,
      observacoes: observacoes ?? this.observacoes,
      valor: valor ?? this.valor,
      valorPago: valorPago ?? this.valorPago,
      dataVencimento: dataVencimento ?? this.dataVencimento,
      dataPagamento: dataPagamento ?? this.dataPagamento,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      updatedAt: updatedAt ?? DateTime.now(),
      notaEntradaId: notaEntradaId ?? this.notaEntradaId,
      notaEntradaNumero: notaEntradaNumero ?? this.notaEntradaNumero,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      status: status ?? this.status,
      formaPagamento: formaPagamento ?? this.formaPagamento,
      historicoPagamentos: historicoPagamentos ?? this.historicoPagamentos,
      recorrente: recorrente ?? this.recorrente,
      intervaloRecorrencia: intervaloRecorrencia ?? this.intervaloRecorrencia,
      proximaDataRecorrencia: proximaDataRecorrencia ?? this.proximaDataRecorrencia,
      ativo: ativo ?? this.ativo,
      usuarioCriacao: usuarioCriacao ?? this.usuarioCriacao,
      usuarioPagamento: usuarioPagamento ?? this.usuarioPagamento,
    );
  }

  /// Converte para Map (para salvar no Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'tipo': tipo.name,
      'categoria': categoria,
      'descricao': descricao,
      'observacoes': observacoes,
      'valor': valor,
      'valorPago': valorPago,
      'dataVencimento': dataVencimento.toIso8601String(),
      'dataPagamento': dataPagamento?.toIso8601String(),
      'dataCriacao': dataCriacao.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'notaEntradaId': notaEntradaId,
      'notaEntradaNumero': notaEntradaNumero,
      'fornecedorId': fornecedorId,
      'fornecedorNome': fornecedorNome,
      'status': status.name,
      'formaPagamento': formaPagamento,
      'historicoPagamentos': historicoPagamentos.map((p) => p.toMap()).toList(),
      'recorrente': recorrente,
      'intervaloRecorrencia': intervaloRecorrencia,
      'proximaDataRecorrencia': proximaDataRecorrencia?.toIso8601String(),
      'ativo': ativo,
      'usuarioCriacao': usuarioCriacao,
      'usuarioPagamento': usuarioPagamento,
    };
  }

  /// Cria a partir de um Map (do Firestore)
  factory ContaPagar.fromMap(Map<String, dynamic> map) {
    return ContaPagar(
      id: map['id'] ?? '',
      numero: map['numero'],
      tipo: TipoContaPagar.values.firstWhere(
        (e) => e.name == map['tipo'],
        orElse: () => TipoContaPagar.despesaVariavel,
      ),
      categoria: map['categoria'],
      descricao: map['descricao'] ?? '',
      observacoes: map['observacoes'],
      valor: (map['valor'] ?? 0).toDouble(),
      valorPago: map['valorPago']?.toDouble(),
      dataVencimento: map['dataVencimento'] != null
          ? DateTime.parse(map['dataVencimento'])
          : DateTime.now(),
      dataPagamento: map['dataPagamento'] != null
          ? DateTime.parse(map['dataPagamento'])
          : null,
      dataCriacao: map['dataCriacao'] != null
          ? DateTime.parse(map['dataCriacao'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      notaEntradaId: map['notaEntradaId'],
      notaEntradaNumero: map['notaEntradaNumero'],
      fornecedorId: map['fornecedorId'],
      fornecedorNome: map['fornecedorNome'],
      status: StatusContaPagar.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => StatusContaPagar.pendente,
      ),
      formaPagamento: map['formaPagamento'],
      historicoPagamentos: map['historicoPagamentos'] != null
          ? (map['historicoPagamentos'] as List)
              .map((p) => RegistroPagamento.fromMap(p))
              .toList()
          : [],
      recorrente: map['recorrente'] ?? false,
      intervaloRecorrencia: map['intervaloRecorrencia'],
      proximaDataRecorrencia: map['proximaDataRecorrencia'] != null
          ? DateTime.parse(map['proximaDataRecorrencia'])
          : null,
      ativo: map['ativo'] ?? true,
      usuarioCriacao: map['usuarioCriacao'],
      usuarioPagamento: map['usuarioPagamento'],
    );
  }
}
