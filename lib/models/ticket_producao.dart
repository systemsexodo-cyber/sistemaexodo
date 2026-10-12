import '../utils/date_parser.dart';

/// Uma VIA DE PRODUÇÃO que não chegou à impressora do setor.
///
/// Quando um pedido/venda é lançado, `ProducaoPdfService.imprimirTicketsProducao`
/// manda uma via para o setor de cada item (Cozinha, Bar, ...). Se a impressora
/// do setor está desligada, sem papel ou com o nome errado, a via não sai — e
/// até agora o app não guardava nada: o erro só aparecia no console e ninguém
/// percebia.
///
/// Este registro guarda o que faltou imprimir, com o PAYLOAD do ticket
/// (itens + detalhes) para poder ser reimpresso depois pelo Monitor de Produção,
/// de preferência só o setor que falhou.
///
/// O estado é da MÁQUINA (a impressora é local): fica na fila local, não na
/// nuvem.
class TicketProducao {
  final String id;
  final String empresaId;
  final String documento; // nº do pedido/venda/mesa
  final String tipoDocumento; // ex.: 'PEDIDO DE PRODUÇÃO', 'PEDIDO DELIVERY'
  final String setor; // departamento (Cozinha, Bar, ...)
  final String impressora; // nome no Windows; '' = impressora padrão do terminal
  final String? cliente;
  final String? referencia; // mesa/comanda (ex.: 'MESA 5')
  /// Linhas prontas para a tela (ex.: ['2x X-Burger', '1x Coca-Cola']).
  final List<String> resumoItens;
  final int tentativas;
  final String? ultimoErro;
  final DateTime criadoEm;
  final DateTime ultimaTentativaEm;
  /// Itens do ticket no formato aceito por `ItemProducaoInput`.
  final List<Map<String, dynamic>> payloadItens;
  /// Detalhes do ticket (mesa, cliente, entrega, pagamento...).
  final Map<String, dynamic> payloadDetalhes;

  TicketProducao({
    required this.id,
    this.empresaId = '',
    required this.documento,
    this.tipoDocumento = 'PEDIDO DE PRODUÇÃO',
    required this.setor,
    this.impressora = '',
    this.cliente,
    this.referencia,
    this.resumoItens = const [],
    this.tentativas = 1,
    this.ultimoErro,
    DateTime? criadoEm,
    DateTime? ultimaTentativaEm,
    this.payloadItens = const [],
    this.payloadDetalhes = const {},
  })  : criadoEm = criadoEm ?? DateTime.now(),
        ultimaTentativaEm = ultimaTentativaEm ?? criadoEm ?? DateTime.now();

  /// Quantos itens a via leva (o que o setor precisa produzir).
  int get quantidadeItens => resumoItens.isEmpty ? payloadItens.length : resumoItens.length;

  bool get usaPadraoDoTerminal => impressora.trim().isEmpty;

  String get descricaoImpressora =>
      usaPadraoDoTerminal ? 'Padrão do terminal' : impressora;

  /// Identifica o mesmo destino dentro do mesmo documento, para a fila não
  /// acumular uma entrada por tentativa.
  String get chave =>
      '$empresaId|${documento.trim().toUpperCase()}|${setor.trim().toLowerCase()}|'
      '${impressora.trim().toLowerCase()}';

  TicketProducao copyWith({
    String? id,
    String? empresaId,
    String? documento,
    String? tipoDocumento,
    String? setor,
    String? impressora,
    String? cliente,
    String? referencia,
    List<String>? resumoItens,
    int? tentativas,
    String? ultimoErro,
    DateTime? criadoEm,
    DateTime? ultimaTentativaEm,
    List<Map<String, dynamic>>? payloadItens,
    Map<String, dynamic>? payloadDetalhes,
  }) {
    return TicketProducao(
      id: id ?? this.id,
      empresaId: empresaId ?? this.empresaId,
      documento: documento ?? this.documento,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      setor: setor ?? this.setor,
      impressora: impressora ?? this.impressora,
      cliente: cliente ?? this.cliente,
      referencia: referencia ?? this.referencia,
      resumoItens: resumoItens ?? this.resumoItens,
      tentativas: tentativas ?? this.tentativas,
      ultimoErro: ultimoErro ?? this.ultimoErro,
      criadoEm: criadoEm ?? this.criadoEm,
      ultimaTentativaEm: ultimaTentativaEm ?? this.ultimaTentativaEm,
      payloadItens: payloadItens ?? this.payloadItens,
      payloadDetalhes: payloadDetalhes ?? this.payloadDetalhes,
    );
  }

  /// Registra uma nova falha mantendo a primeira hora (`criadoEm`) — é ela que
  /// diz há quanto tempo o setor está sem a via.
  TicketProducao comNovaFalha(String? erro) => TicketProducao(
        id: id,
        empresaId: empresaId,
        documento: documento,
        tipoDocumento: tipoDocumento,
        setor: setor,
        impressora: impressora,
        cliente: cliente,
        referencia: referencia,
        resumoItens: resumoItens,
        tentativas: tentativas + 1,
        ultimoErro: erro ?? ultimoErro,
        criadoEm: criadoEm,
        ultimaTentativaEm: DateTime.now(),
        payloadItens: payloadItens,
        payloadDetalhes: payloadDetalhes,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empresa_id': empresaId,
      'documento': documento,
      'tipo_documento': tipoDocumento,
      'setor': setor,
      'impressora': impressora,
      'cliente': cliente,
      'referencia': referencia,
      'resumo_itens': resumoItens,
      'tentativas': tentativas,
      'ultimo_erro': ultimoErro,
      'criado_em': criadoEm.toIso8601String(),
      'ultima_tentativa_em': ultimaTentativaEm.toIso8601String(),
      'payload_itens': payloadItens,
      'payload_detalhes': payloadDetalhes,
    };
  }

  factory TicketProducao.fromMap(Map<String, dynamic> map) {
    DateTime? data(dynamic valor) {
      if (valor == null) return null;
      if (valor is DateTime) return valor;
      return DateTime.tryParse(valor.toString());
    }

    List<Map<String, dynamic>> mapas(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final criadoEm = DateParser.parse(map['criado_em'] ?? map['criadoEm']);

    return TicketProducao(
      id: (map['id'] ?? '').toString(),
      empresaId: (map['empresa_id'] ?? map['empresaId'] ?? '').toString(),
      documento: (map['documento'] ?? '').toString(),
      tipoDocumento:
          (map['tipo_documento'] ?? map['tipoDocumento'] ?? 'PEDIDO DE PRODUÇÃO')
              .toString(),
      setor: (map['setor'] ?? '').toString(),
      impressora: (map['impressora'] ?? '').toString(),
      cliente: map['cliente']?.toString(),
      referencia: map['referencia']?.toString(),
      resumoItens: ((map['resumo_itens'] ?? map['resumoItens']) as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      tentativas: (map['tentativas'] as num?)?.toInt() ?? 1,
      ultimoErro: map['ultimo_erro']?.toString() ?? map['ultimoErro']?.toString(),
      criadoEm: criadoEm,
      ultimaTentativaEm:
          data(map['ultima_tentativa_em'] ?? map['ultimaTentativaEm']) ?? criadoEm,
      payloadItens: mapas(map['payload_itens'] ?? map['payloadItens']),
      payloadDetalhes: Map<String, dynamic>.from(
        (map['payload_detalhes'] ?? map['payloadDetalhes']) is Map
            ? (map['payload_detalhes'] ?? map['payloadDetalhes']) as Map
            : const {},
      ),
    );
  }

  @override
  String toString() =>
      'TicketProducao($documento • $setor • $descricaoImpressora • '
      '$tentativas tentativa(s))';
}
