import 'package:uuid/uuid.dart';

class Motorista {
  final String id;
  final String nome;
  final String? telefone;
  final String? cpf;
  final String? cnh;
  final String? veiculoPlaca;
  final String? veiculoModelo;
  final bool ativo;
  final String tipoComissao; // 'Fixo por Entrega', 'Diária', 'Porcentagem'
  final double valorComissao; // Valor correspondente ao tipo (Ex: R$5 por entrega)
  /// Valor da DIÁRIA: R$ fixo por DIA trabalhado. 0 = não paga diária.
  ///
  /// Existe separado do [valorComissao] porque o entregador pode receber as
  /// duas coisas SOMADAS: a diária do dia mais o valor de cada entrega.
  final double valorDiaria;
  final double taxaPadrao; // Compatibilidade com a tabela (mesmo que valorComissao se for Fixo)
  final DateTime dataCadastro;

  Motorista({
    String? id,
    required this.nome,
    this.telefone,
    this.cpf,
    this.cnh,
    String? veiculoPlaca,
    String? placaVeiculo, // Para compatibilidade com novos códigos
    String? veiculoModelo,
    String? tipoVeiculo, // Para compatibilidade com novos códigos
    this.ativo = true,
    this.tipoComissao = 'Fixo por Entrega',
    this.valorComissao = 0.0,
    this.valorDiaria = 0.0,
    this.taxaPadrao = 0.0,
    DateTime? dataCadastro,
  }) : id = id ?? const Uuid().v4(),
       veiculoPlaca = veiculoPlaca ?? placaVeiculo,
       veiculoModelo = veiculoModelo ?? tipoVeiculo ?? 'Moto',
       dataCadastro = dataCadastro ?? DateTime.now();

  // Getters para compatibilidade com código que usa nomes novos
  String? get placaVeiculo => veiculoPlaca;
  String? get tipoVeiculo => veiculoModelo;
  DateTime get criadoEm => dataCadastro;

  // ── Cálculo da comissão do entregador ─────────────────────────────────
  //
  // A comissão é a SOMA de duas partes independentes:
  //   1. DIÁRIA: R$ fixo por dia trabalhado (se [valorDiaria] > 0);
  //   2. POR ENTREGA: R$ fixo por entrega, ou % sobre a taxa da entrega.
  //
  // Antes existia uma única escolha ('Fixo por Entrega' | 'Diária' |
  // 'Porcentagem'), então quem pagava diária MAIS valor por entrega não tinha
  // como cadastrar as duas coisas.

  /// Diária efetiva do cadastro.
  ///
  /// Cadastros antigos do tipo 'Diária' guardavam o valor da diária em
  /// [valorComissao] (não existia campo próprio) — continua valendo.
  double get valorDiariaEfetiva {
    if (valorDiaria > 0) return valorDiaria;
    if (tipoComissao == 'Diária') return valorComissao;
    return 0.0;
  }

  /// Parte da comissão referente às ENTREGAS do período.
  ///
  /// [somaTaxasEntregas] é a soma da taxa de entrega das entregas do período
  /// (só importa para 'Porcentagem').
  double comissaoPorEntregas({
    required int entregas,
    required double somaTaxasEntregas,
  }) {
    switch (tipoComissao) {
      case 'Porcentagem':
        return somaTaxasEntregas * (valorComissao / 100);
      case 'Diária':
        // 'Diária' = o pagamento é por dia, não por entrega. O valor está na
        // diária efetiva (acima).
        return 0.0;
      case 'Fixo por Entrega':
      default:
        return valorComissao * entregas;
    }
  }

  /// Comissão total do período: diária × dias trabalhados + parte por entrega.
  double calcularComissao({
    required int entregas,
    required double somaTaxasEntregas,
    required int diasTrabalhados,
  }) {
    final diaria = valorDiariaEfetiva * diasTrabalhados;
    final porEntrega = comissaoPorEntregas(
      entregas: entregas,
      somaTaxasEntregas: somaTaxasEntregas,
    );
    return diaria + porEntrega;
  }

  factory Motorista.fromMap(Map<String, dynamic> map) {
    return Motorista(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      telefone: map['telefone']?.toString(),
      cpf: map['cpf']?.toString(),
      cnh: map['cnh']?.toString(),
      veiculoPlaca: map['placa']?.toString() ?? map['veiculo_placa']?.toString() ?? map['veiculoPlaca']?.toString() ?? map['placa_veiculo']?.toString() ?? map['placaVeiculo']?.toString(),
      veiculoModelo: map['veiculo_modelo']?.toString() ?? map['veiculoModelo']?.toString() ?? map['tipo_veiculo']?.toString() ?? map['tipoVeiculo']?.toString(),
      ativo: map['ativo'] == 1 || map['ativo'] == true || map['ativo'] == 'true',
      tipoComissao: map['tipo_comissao']?.toString() ?? map['tipoComissao']?.toString() ?? 'Fixo por Entrega',
      valorComissao: (map['valor_comissao'] ?? map['valorComissao'] ?? map['taxa_padrao'] ?? map['taxaPadrao'] ?? 0).toDouble(),
      valorDiaria: (map['valor_diaria'] ?? map['valorDiaria'] ?? 0).toDouble(),
      taxaPadrao: (map['taxa_padrao'] ?? map['taxaPadrao'] ?? 0).toDouble(),
      dataCadastro: map['data_cadastro'] != null ? DateTime.parse(map['data_cadastro']) : 
                    (map['dataCadastro'] != null ? DateTime.parse(map['dataCadastro']) : 
                    (map['criado_em'] != null ? DateTime.parse(map['criado_em']) :
                    (map['criadoEm'] != null ? DateTime.parse(map['criadoEm']) : DateTime.now()))),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'cpf': cpf,
      'cnh': cnh,
      'placa': veiculoPlaca,
      'veiculo_placa': veiculoPlaca,
      'veiculo_modelo': veiculoModelo,
      'ativo': ativo,
      'tipo_comissao': tipoComissao,
      'valor_comissao': valorComissao,
      'valor_diaria': valorDiaria,
      'taxa_padrao': taxaPadrao,
      'data_cadastro': dataCadastro.toIso8601String(),
    };
  }

  Motorista copyWith({
    String? id,
    String? nome,
    String? telefone,
    String? cpf,
    String? cnh,
    String? veiculoPlaca,
    String? veiculoModelo,
    bool? ativo,
    String? tipoComissao,
    double? valorComissao,
    double? valorDiaria,
    double? taxaPadrao,
    DateTime? dataCadastro,
  }) {
    return Motorista(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      cpf: cpf ?? this.cpf,
      cnh: cnh ?? this.cnh,
      veiculoPlaca: veiculoPlaca ?? this.veiculoPlaca,
      veiculoModelo: veiculoModelo ?? this.veiculoModelo,
      ativo: ativo ?? this.ativo,
      tipoComissao: tipoComissao ?? this.tipoComissao,
      valorComissao: valorComissao ?? this.valorComissao,
      valorDiaria: valorDiaria ?? this.valorDiaria,
      taxaPadrao: taxaPadrao ?? this.taxaPadrao,
      dataCadastro: dataCadastro ?? this.dataCadastro,
    );
  }
}
