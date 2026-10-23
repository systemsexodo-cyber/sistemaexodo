export 'package:sistema_exodo_novo/models/motorista.dart';

/// Lê a taxa da entrega do mapa, aceitando os nomes de coluna usados pelos
/// bancos que guardam entregas.
///
/// `taxaEntrega` é o nome do modelo (e do JSON antigo); `valorFrete`/`valor_frete`
/// são as colunas numéricas da tabela LOCAL `entregas` (as únicas que existem
/// lá) e `taxa_entrega` é a coluna da NUVEM. Lendo só `taxaEntrega`, a taxa
/// voltava NULL para TODA entrega gravada e a comissão por entrega (% sobre a
/// taxa) saía R$ 0,00 na tela de Comissões.
double? _taxaDoMap(Map<String, dynamic> map) {
  final valor = map['taxaEntrega'] ??
      map['valorFrete'] ??
      map['valor_frete'] ??
      map['taxa_entrega'];
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString().replaceAll(',', '.'));
}

/// Status possíveis de uma entrega
enum StatusEntrega {
  aguardando, // Aguardando entrega
  romaneioCriado, // Romaneio já foi gerado
  emEntrega, // Saiu para entrega
  entregue, // Entregue com sucesso
  cancelado, // Entrega cancelada
}

extension StatusEntregaExtension on StatusEntrega {
  String get nome {
    switch (this) {
      case StatusEntrega.aguardando:
        return 'Aguardando';
      case StatusEntrega.romaneioCriado:
        return 'Romaneio Criado';
      case StatusEntrega.emEntrega:
        return 'Em Entrega';
      case StatusEntrega.entregue:
        return 'Entregue';
      case StatusEntrega.cancelado:
        return 'Cancelado';
    }
  }

  String get icone {
    switch (this) {
      case StatusEntrega.aguardando:
        return 'hourglass_empty';
      case StatusEntrega.romaneioCriado:
        return 'assignment';
      case StatusEntrega.emEntrega:
        return 'local_shipping';
      case StatusEntrega.entregue:
        return 'done_all';
      case StatusEntrega.cancelado:
        return 'cancel';
    }
  }

  dynamic get cor {
    switch (this) {
      case StatusEntrega.aguardando:
        return 'orange';
      case StatusEntrega.romaneioCriado:
        return 'blue';
      case StatusEntrega.emEntrega:
        return 'deepPurple';
      case StatusEntrega.entregue:
        return 'green';
      case StatusEntrega.cancelado:
        return 'red';
    }
  }
}

/// Registro de evento/histórico da entrega
class EventoEntrega {
  final String id;
  final DateTime dataHora;
  final StatusEntrega status;
  final String? descricao;
  final String? localizacao;
  final String? responsavel;

  EventoEntrega({
    required this.id,
    required this.dataHora,
    required this.status,
    this.descricao,
    this.localizacao,
    this.responsavel,
  });

  factory EventoEntrega.fromMap(Map<String, dynamic> map) {
    return EventoEntrega(
      id: map['id']?.toString() ?? '',
      dataHora: DateTime.parse(map['dataHora']),
      status: StatusEntrega.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => StatusEntrega.aguardando,
      ),
      descricao: map['descricao'],
      localizacao: map['localizacao'],
      responsavel: map['responsavel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dataHora': dataHora.toIso8601String(),
      'status': status.name,
      'descricao': descricao,
      'localizacao': localizacao,
      'responsavel': responsavel,
    };
  }
}

/// Modelo principal de Entrega
class Entrega {
  final String id;
  final String pedidoId;
  final String? pedidoNumero; // PED-0001

  // Dados do destinatário
  final String clienteNome;
  final String? clienteTelefone;
  final String enderecoEntrega;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? cep;
  final String? pontoReferencia;

  // Controle de entrega
  final StatusEntrega status;
  final DateTime dataCriacao;
  final DateTime? dataPrevisao;
  final DateTime? dataEntrega;

  // Motorista/Entregador
  final String? motoristaId;
  final String? motoristaNome;
  final String? motoristaTelefone;
  final String? veiculoPlaca;

  // Rota e logística
  final int? ordemRota; // Posição na rota do dia
  final String? codigoRastreio;
  final double? taxaEntrega;
  final String? tipoEntrega; // Normal, Expressa, Agendada
  final String? periodoEntrega; // Manhã, Tarde, Noite

  // Confirmação
  final String? assinaturaRecebedor;
  final String? nomeRecebedor;
  final String? documentoRecebedor;
  final String? fotoComprovante; // Path da foto
  final double? latitude;
  final double? longitude;

  // Observações
  final String? observacoes;
  final String? motivoFalha;

  // Histórico de eventos
  final List<EventoEntrega> historico;

  // Custos e Financeiro
  final double? comissaoMotorista;
  final double quantidadeVolumes;
  final double? pesoTotal;

  Entrega({
    required this.id,
    required this.pedidoId,
    this.pedidoNumero,
    required this.clienteNome,
    this.clienteTelefone,
    required this.enderecoEntrega,
    this.complemento,
    this.bairro,
    this.cidade,
    this.cep,
    this.pontoReferencia,
    this.status = StatusEntrega.aguardando,
    required this.dataCriacao,
    this.dataPrevisao,
    this.dataEntrega,
    this.motoristaId,
    this.motoristaNome,
    this.motoristaTelefone,
    this.veiculoPlaca,
    this.ordemRota,
    this.codigoRastreio,
    this.taxaEntrega,
    this.tipoEntrega,
    this.periodoEntrega,
    this.assinaturaRecebedor,
    this.nomeRecebedor,
    this.documentoRecebedor,
    this.fotoComprovante,
    this.latitude,
    this.longitude,
    this.observacoes,
    this.motivoFalha,
    this.historico = const [],
    this.comissaoMotorista,
    this.quantidadeVolumes = 1.0,
    this.pesoTotal,
  });

  /// Retorna o endereço completo formatado
  String get enderecoCompleto {
    final partes = <String>[enderecoEntrega];
    if (complemento != null && complemento!.isNotEmpty) {
      partes.add(complemento!);
    }
    if (bairro != null && bairro!.isNotEmpty) partes.add(bairro!);
    if (cidade != null && cidade!.isNotEmpty) partes.add(cidade!);
    if (cep != null && cep!.isNotEmpty) partes.add('CEP: $cep');
    return partes.join(', ');
  }
  factory Entrega.fromMap(Map<String, dynamic> map) {
    return Entrega(
      id: map['id']?.toString() ?? '',
      pedidoId: map['pedidoId'] ?? '',
      pedidoNumero: map['pedidoNumero'],
      clienteNome: map['clienteNome'] ?? '',
      clienteTelefone: map['clienteTelefone'],
      enderecoEntrega: map['enderecoEntrega'] ?? '',
      complemento: map['complemento'],
      bairro: map['bairro'],
      cidade: map['cidade'],
      cep: map['cep'],
      pontoReferencia: map['pontoReferencia'],
      status: StatusEntrega.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => StatusEntrega.aguardando,
      ),
      dataCriacao: map['dataCriacao'] != null
          ? DateTime.parse(map['dataCriacao'])
          : DateTime.now(),
      dataPrevisao: map['dataPrevisao'] != null
          ? DateTime.parse(map['dataPrevisao'])
          : null,
      dataEntrega: map['dataEntrega'] != null
          ? DateTime.parse(map['dataEntrega'])
          : null,
      motoristaId: map['motoristaId'],
      motoristaNome: map['motoristaNome'],
      motoristaTelefone: map['motoristaTelefone'],
      veiculoPlaca: map['veiculoPlaca'],
      ordemRota: map['ordemRota'],
      codigoRastreio: map['codigoRastreio'],
      taxaEntrega: _taxaDoMap(map),
      tipoEntrega: map['tipoEntrega'],
      periodoEntrega: map['periodoEntrega'],
      assinaturaRecebedor: map['assinaturaRecebedor'],
      nomeRecebedor: map['nomeRecebedor'],
      documentoRecebedor: map['documentoRecebedor'],
      fotoComprovante: map['fotoComprovante'],
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      observacoes: map['observacoes'],
      motivoFalha: map['motivoFalha'],
      historico: map['historico'] != null
          ? (map['historico'] as List)
                .map((e) => EventoEntrega.fromMap(e))
                .toList()
          : [],
      comissaoMotorista: (map['comissaoMotorista'] as num?)?.toDouble(),
      quantidadeVolumes: (map['quantidadeVolumes'] as num?)?.toDouble() ?? 1.0,
      pesoTotal: map['pesoTotal']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pedidoId': pedidoId,
      'pedidoNumero': pedidoNumero,
      'clienteNome': clienteNome,
      'clienteTelefone': clienteTelefone,
      'enderecoEntrega': enderecoEntrega,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'cep': cep,
      'pontoReferencia': pontoReferencia,
      'status': status.name,
      'dataCriacao': dataCriacao.toIso8601String(),
      'dataPrevisao': dataPrevisao?.toIso8601String(),
      'dataEntrega': dataEntrega?.toIso8601String(),
      'motoristaId': motoristaId,
      'motoristaNome': motoristaNome,
      'motoristaTelefone': motoristaTelefone,
      'veiculoPlaca': veiculoPlaca,
      'ordemRota': ordemRota,
      'codigoRastreio': codigoRastreio,
      'taxaEntrega': taxaEntrega,
      // A taxa da entrega é o que a tela de Comissões usa para pagar o motoboy
      // (% sobre a taxa). Cada banco guarda isso numa coluna com nome
      // diferente — a tabela LOCAL `entregas` em `valorFrete`/`valor_frete` e a
      // NUVEM em `taxa_entrega`. Mandando os quatro nomes, quem grava escolhe a
      // coluna que existe (a camada de gravação descarta as demais). Sem isso a
      // taxa nunca saía daqui, ficava NULL no banco e a comissão por entrega
      // saía R$ 0,00.
      'valorFrete': taxaEntrega,
      'valor_frete': taxaEntrega,
      'taxa_entrega': taxaEntrega,
      'tipoEntrega': tipoEntrega,
      'periodoEntrega': periodoEntrega,
      'assinaturaRecebedor': assinaturaRecebedor,
      'nomeRecebedor': nomeRecebedor,
      'documentoRecebedor': documentoRecebedor,
      'fotoComprovante': fotoComprovante,
      'latitude': latitude,
      'longitude': longitude,
      'observacoes': observacoes,
      'motivoFalha': motivoFalha,
      'historico': historico.map((e) => e.toMap()).toList(),
      'comissaoMotorista': comissaoMotorista,
      'quantidadeVolumes': quantidadeVolumes,
      'pesoTotal': pesoTotal,
    };
  }

  Entrega copyWith({
    String? id,
    String? pedidoId,
    String? pedidoNumero,
    String? clienteNome,
    String? clienteTelefone,
    String? enderecoEntrega,
    String? complemento,
    String? bairro,
    String? cidade,
    String? cep,
    String? pontoReferencia,
    StatusEntrega? status,
    DateTime? dataCriacao,
    DateTime? dataPrevisao,
    DateTime? dataEntrega,
    String? motoristaId,
    String? motoristaNome,
    String? motoristaTelefone,
    String? veiculoPlaca,
    int? ordemRota,
    String? codigoRastreio,
    double? taxaEntrega,
    String? tipoEntrega,
    String? periodoEntrega,
    String? assinaturaRecebedor,
    String? nomeRecebedor,
    String? documentoRecebedor,
    String? fotoComprovante,
    double? latitude,
    double? longitude,
    String? observacoes,
    String? motivoFalha,
    List<EventoEntrega>? historico,
    double? quantidadeVolumes,
    double? pesoTotal,
    /// Zera [dataEntrega] (desfazer uma entrega concluída).
    ///
    /// Existe porque `copyWith` não consegue gravar null por parâmetro.
    bool limparDataEntrega = false,
  }) {
    return Entrega(
      id: id ?? this.id,
      pedidoId: pedidoId ?? this.pedidoId,
      pedidoNumero: pedidoNumero ?? this.pedidoNumero,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      enderecoEntrega: enderecoEntrega ?? this.enderecoEntrega,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      cep: cep ?? this.cep,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
      status: status ?? this.status,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataPrevisao: dataPrevisao ?? this.dataPrevisao,
      dataEntrega: limparDataEntrega ? null : (dataEntrega ?? this.dataEntrega),
      motoristaId: motoristaId ?? this.motoristaId,
      motoristaNome: motoristaNome ?? this.motoristaNome,
      motoristaTelefone: motoristaTelefone ?? this.motoristaTelefone,
      veiculoPlaca: veiculoPlaca ?? this.veiculoPlaca,
      ordemRota: ordemRota ?? this.ordemRota,
      codigoRastreio: codigoRastreio ?? this.codigoRastreio,
      taxaEntrega: taxaEntrega ?? this.taxaEntrega,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      periodoEntrega: periodoEntrega ?? this.periodoEntrega,
      assinaturaRecebedor: assinaturaRecebedor ?? this.assinaturaRecebedor,
      nomeRecebedor: nomeRecebedor ?? this.nomeRecebedor,
      documentoRecebedor: documentoRecebedor ?? this.documentoRecebedor,
      fotoComprovante: fotoComprovante ?? this.fotoComprovante,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      observacoes: observacoes ?? this.observacoes,
      motivoFalha: motivoFalha ?? this.motivoFalha,
      historico: historico ?? this.historico,
      comissaoMotorista: comissaoMotorista ?? this.comissaoMotorista,
      quantidadeVolumes: quantidadeVolumes ?? this.quantidadeVolumes,
      pesoTotal: pesoTotal ?? this.pesoTotal,
    );
  }

  /// Adiciona um evento ao histórico e retorna nova entrega
  Entrega adicionarEvento(EventoEntrega evento) {
    return copyWith(historico: [...historico, evento], status: evento.status);
  }

  /// Verifica se pode alterar para um determinado status
  bool podeAlterarPara(StatusEntrega novoStatus) {
    // Se for o mesmo status, não precisa alterar
    if (status == novoStatus) return false;
    
    // Permitir todas as transições para máxima flexibilidade (correções, voltar status, etc)
    return true;
  }

  bool get estaAtrasada {
    if (status == StatusEntrega.entregue || status == StatusEntrega.cancelado) {
      return false;
    }
    if (dataPrevisao == null) return false;
    return DateTime.now().isAfter(dataPrevisao!);
  }
}


