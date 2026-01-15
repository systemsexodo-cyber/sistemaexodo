/// Status possíveis de uma entrega
enum StatusEntrega {
  aguardando, // Aguardando entrega
  entregue, // Entregue com sucesso
}

extension StatusEntregaExtension on StatusEntrega {
  String get nome {
    switch (this) {
      case StatusEntrega.aguardando:
        return 'Aguardando';
      case StatusEntrega.entregue:
        return 'Entregue';
    }
  }

  String get icone {
    switch (this) {
      case StatusEntrega.aguardando:
        return 'hourglass_empty';
      case StatusEntrega.entregue:
        return 'done_all';
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
      id: map['id'] ?? '',
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

  // Itens da entrega
  final int quantidadeVolumes;
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
    this.quantidadeVolumes = 1,
    this.pesoTotal,
  });

  /// Verifica se a entrega está atrasada
  bool get estaAtrasada {
    if (dataPrevisao == null) return false;
    if (status == StatusEntrega.entregue) {
      return false;
    }
    return DateTime.now().isAfter(dataPrevisao!);
  }

  /// Verifica se pode alterar para determinado status
  bool podeAlterarPara(StatusEntrega novoStatus) {
    // Regras de transição de status
    switch (status) {
      case StatusEntrega.aguardando:
        return novoStatus == StatusEntrega.entregue;
      case StatusEntrega.entregue:
        return false; // Estado final
    }
  }

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
      id: map['id'] ?? '',
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
      taxaEntrega: map['taxaEntrega']?.toDouble(),
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
      quantidadeVolumes: map['quantidadeVolumes'] ?? 1,
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
    int? quantidadeVolumes,
    double? pesoTotal,
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
      dataEntrega: dataEntrega ?? this.dataEntrega,
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
      quantidadeVolumes: quantidadeVolumes ?? this.quantidadeVolumes,
      pesoTotal: pesoTotal ?? this.pesoTotal,
    );
  }

  /// Adiciona um evento ao histórico e retorna nova entrega
  Entrega adicionarEvento(EventoEntrega evento) {
    return copyWith(historico: [...historico, evento], status: evento.status);
  }
}

/// Modelo de Motorista/Entregador
class Motorista {
  final String id;
  final String nome;
  final String telefone;
  final String? cpf;
  final String? cnh;
  final String? veiculoModelo;
  final String? veiculoPlaca;
  final bool ativo;
  final DateTime dataCadastro;

  Motorista({
    required this.id,
    required this.nome,
    required this.telefone,
    this.cpf,
    this.cnh,
    this.veiculoModelo,
    this.veiculoPlaca,
    this.ativo = true,
    required this.dataCadastro,
  });

  factory Motorista.fromMap(Map<String, dynamic> map) {
    return Motorista(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      telefone: map['telefone'] ?? '',
      cpf: map['cpf'],
      cnh: map['cnh'],
      veiculoModelo: map['veiculoModelo'],
      veiculoPlaca: map['veiculoPlaca'],
      ativo: map['ativo'] ?? true,
      dataCadastro: map['dataCadastro'] != null
          ? DateTime.parse(map['dataCadastro'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'cpf': cpf,
      'cnh': cnh,
      'veiculoModelo': veiculoModelo,
      'veiculoPlaca': veiculoPlaca,
      'ativo': ativo,
      'dataCadastro': dataCadastro.toIso8601String(),
    };
  }

  Motorista copyWith({
    String? id,
    String? nome,
    String? telefone,
    String? cpf,
    String? cnh,
    String? veiculoModelo,
    String? veiculoPlaca,
    bool? ativo,
    DateTime? dataCadastro,
  }) {
    return Motorista(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      cpf: cpf ?? this.cpf,
      cnh: cnh ?? this.cnh,
      veiculoModelo: veiculoModelo ?? this.veiculoModelo,
      veiculoPlaca: veiculoPlaca ?? this.veiculoPlaca,
      ativo: ativo ?? this.ativo,
      dataCadastro: dataCadastro ?? this.dataCadastro,
    );
  }
}
