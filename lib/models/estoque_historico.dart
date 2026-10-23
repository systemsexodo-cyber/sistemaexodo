class EstoqueHistorico {
  final String id;
  final String produtoId;
  final DateTime data;
  final double quantidade;
  final String tipo; // 'entrada', 'saida', 'ajuste', 'zerado'
  final String? usuario;
  final String? observacao;
  final String? fornecedorId;
  final String? fornecedorNome;
  final double? custoUnitario; // Custo unitário da mercadoria no momento da movimentação
  final double? valorCusto; // Valor de custo total (custoUnitario × |quantidade|) — usado em quebras/perdas
  final String? motivo; // 'venda', 'quebra', 'perda', 'consumo', etc.

  EstoqueHistorico({
    required this.id,
    required this.produtoId,
    required this.data,
    required this.quantidade,
    required this.tipo,
    this.usuario,
    this.observacao,
    this.fornecedorId,
    this.fornecedorNome,
    this.custoUnitario,
    this.valorCusto,
    this.motivo,
  });

  /// Quebras de mercadoria (saída de estoque lançada pelo PDV, não é venda)
  bool get ehQuebra => (motivo?.toLowerCase() == 'quebra') ||
      (observacao?.toLowerCase().contains('motivo: quebra') ?? false);

  /// Movimento de ZERAMENTO: o saldo do produto foi levado a 0 de propósito.
  ///
  /// NÃO conta como entrada nem como saída nos totais das telas — é uma
  /// conciliação de saldo (aparece como "Estoque zerado" na listagem). Um
  /// produto com saldo negativo, por exemplo, ao ser zerado NÃO gera uma
  /// "entrada" de 193: gera este registro, com o delta assinado em
  /// [quantidade] (0 − saldo anterior), para o histórico continuar fechando.
  bool get ehZeramento => tipo == 'zerado';

  /// Saldo que o produto tinha ANTES do zeramento (quando o registro é um
  /// zeramento). Ex.: delta +193 → o saldo anterior era −193.
  double? get saldoAnteriorNoZeramento => ehZeramento ? -quantidade : null;

  /// Converte datas vinda de banco/nuvem (UTC) para hora local.
  static DateTime _paraLocal(dynamic v) {
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

  factory EstoqueHistorico.fromMap(Map<String, dynamic> map) {
    return EstoqueHistorico(
      id: map['id']?.toString() ?? '',
      produtoId: map['produto_id'] ?? map['produtoId'] ?? '',
      data: _paraLocal(map['data']),
      quantidade: map['quantidade'] != null
          ? (map['quantidade'] is num
              ? (map['quantidade'] as num).toDouble()
              : double.tryParse(map['quantidade'].toString()) ?? 0.0)
          : 0.0,
      tipo: map['tipo'] ?? '',
      usuario: map['usuario'],
      observacao: map['observacao'],
      fornecedorId: map['fornecedor_id'] ?? map['fornecedorId'],
      fornecedorNome: map['fornecedor_nome'] ?? map['fornecedorNome'],
      custoUnitario: map['custo_unitario'] != null
          ? (map['custo_unitario'] is num
              ? (map['custo_unitario'] as num).toDouble()
              : double.tryParse(map['custo_unitario'].toString()))
          : null,
      valorCusto: map['valor_custo'] != null
          ? (map['valor_custo'] is num
              ? (map['valor_custo'] as num).toDouble()
              : double.tryParse(map['valor_custo'].toString()))
          : null,
      motivo: map['motivo'] ?? _motivoDaObservacao(map['observacao']),
    );
  }

  static String? _motivoDaObservacao(dynamic obs) {
    if (obs == null) return null;
    final s = obs.toString().toLowerCase();
    final m = RegExp(r'motivo: ([a-z_]+)').firstMatch(s);
    return m?.group(1);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      // SEM isto a linha nascia ÓRFÃ: a tabela tem `produto_id` e a tela de
      // histórico do produto filtra por ele (`h.produtoId == produto.id`), mas o
      // mapa nunca o continha — o histórico de cada produto aparecia VAZIO e as
      // quebras não achavam o produto.
      'produto_id': produtoId,
      // Gravar em UTC (convenção do projeto, igual à VendaBalcao) para a data
      // não "andar" ao salvar/recarregar do banco (timestamptz) ou do Supabase.
      'data': data.toUtc().toIso8601String(),
      // A tabela não tem DEFAULT: sem enviar aqui nascia NULL (300 linhas do
      // banco local estavam assim). O instante do movimento é o do registro.
      'created_at': data.toUtc().toIso8601String(),
      'quantidade': quantidade,
      'tipo': tipo,
      'usuario': usuario,
      'observacao': observacao,
      'fornecedor_nome': fornecedorNome,
      'custo_unitario': custoUnitario,
      'valor_custo': valorCusto,
      'motivo': motivo,
    };
  }
}
