/// Forma de pagamento personalizada cadastrada pela própria empresa.
///
/// Permite nomes livres (ex: "Caju", "VR", "Crédito 3x") além das formas
/// fixas do sistema. Cada forma carrega a taxa cobrada pela maquininha, que
/// pode ser um valor fixo por transação (R$) e/ou um percentual sobre o valor.
///
/// As formas personalizadas são gravadas em `Empresa.configuracoes`, sob a
/// chave "formas_pagamento_custom".
class FormaPagamentoCustom {
  final String id;
  final String nome;

  /// Taxa fixa cobrada a cada transação, em reais.
  final double taxaFixa;

  /// Taxa percentual cobrada sobre o valor da transação (0 a 100).
  final double taxaPercentual;

  /// Se false, a forma não aparece no PDV.
  final bool ativo;

  const FormaPagamentoCustom({
    required this.id,
    required this.nome,
    this.taxaFixa = 0.0,
    this.taxaPercentual = 0.0,
    this.ativo = true,
  });

  /// Retorna true quando a forma cobra alguma taxa da maquininha.
  bool get temTaxa => taxaFixa > 0 || taxaPercentual > 0;

  /// Taxa total cobrada para um valor de transação.
  double calcularTaxa(double valor) {
    if (valor <= 0) return 0.0;
    return (valor * taxaPercentual / 100.0) + taxaFixa;
  }

  factory FormaPagamentoCustom.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0.0;
    }

    return FormaPagamentoCustom(
      id: map['id']?.toString() ?? '',
      nome: (map['nome'] ?? map['nomeForma'] ?? '').toString(),
      taxaFixa: toDouble(map['taxaFixa'] ?? map['taxa_fixa']),
      taxaPercentual: toDouble(
        map['taxaPercentual'] ?? map['taxa_percentual'] ?? map['taxaPerc'],
      ),
      ativo: map['ativo'] == null
          ? true
          : (map['ativo'] is bool
              ? map['ativo'] as bool
              : map['ativo'].toString().toLowerCase() == 'true'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'taxaFixa': taxaFixa,
      'taxaPercentual': taxaPercentual,
      'ativo': ativo,
    };
  }

  FormaPagamentoCustom copyWith({
    String? id,
    String? nome,
    double? taxaFixa,
    double? taxaPercentual,
    bool? ativo,
  }) {
    return FormaPagamentoCustom(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      taxaFixa: taxaFixa ?? this.taxaFixa,
      taxaPercentual: taxaPercentual ?? this.taxaPercentual,
      ativo: ativo ?? this.ativo,
    );
  }
}
