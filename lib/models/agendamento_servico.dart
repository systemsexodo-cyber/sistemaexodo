import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/models/item_material.dart';

/// Modelo para representar um agendamento de serviço
class AgendamentoServico {
  final String id;
  final String numero;
  final String? servicoId;
  final Servico? servico;
  final List<String> servicosIds;
  final List<Servico> servicos;
  final String? clienteId;
  final Cliente? cliente;
  final String? petId;
  final Pet? pet;
  final DateTime dataAgendamento;
  final int duracaoMinutos;
  final int intervaloMinutos;
  final String? observacoes;
  final String status;
  final String? tipoEntrega;
  final double? valorTaxiDog;
  final String? bairroEntrega;
  final String? pedidoId;
  final String? numeroPedido;
  final bool recebido;
  final DateTime? dataRecebimento;
  final List<ItemMaterial> materiais;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? petNome;
  final String? endereco;
  final String? numeroEndereco;
  final String? complemento;
  final String? pontoReferencia;
  final bool excluido;
  final bool travado;
  final String? funcionarioId;
  final String? funcionarioNome;
  final bool recorrente;
  final bool isPago;
  final String? pagamentoInfo;
  final DateTime createdAt;
  final DateTime updatedAt;

  AgendamentoServico({
    required this.id,
    required this.numero,
    this.servicoId,
    this.servico,
    List<String>? servicosIds,
    List<Servico>? servicos,
    this.clienteId,
    this.cliente,
    this.petId,
    this.pet,
    required this.dataAgendamento,
    this.duracaoMinutos = 60,
    this.intervaloMinutos = 0,
    this.observacoes,
    this.status = 'Agendado',
    this.tipoEntrega,
    this.valorTaxiDog,
    this.bairroEntrega,
    this.pedidoId,
    this.numeroPedido,
    this.recebido = false,
    this.dataRecebimento,
    this.clienteNome,
    this.clienteTelefone,
    this.petNome,
    this.endereco,
    this.numeroEndereco,
    this.complemento,
    this.pontoReferencia,
    this.excluido = false,
    this.travado = false,
    this.funcionarioId,
    this.funcionarioNome,
    this.recorrente = false,
    this.isPago = false,
    this.pagamentoInfo,
    List<ItemMaterial>? materiais,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : servicosIds = servicosIds ?? (servicoId != null ? [servicoId] : []),
        servicos = servicos ?? (servico != null ? [servico] : []),
        materiais = materiais ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  DateTime get dataTerminoEfetiva => dataAgendamento.add(Duration(minutes: duracaoMinutos + intervaloMinutos));
  DateTime get dataTerminoServico => dataAgendamento.add(Duration(minutes: duracaoMinutos));
  DateTime get dataTermino => dataTerminoEfetiva;

  String? get servicoNome {
    if (servicos.isNotEmpty) {
      return servicos.map((s) => s.nome).join(', ');
    }
    return servico?.nome;
  }

  double get valorTotal {
    double total = 0;
    if (servicos.isNotEmpty) {
      for (var s in servicos) {
        total += s.precoTotal;
      }
    } else if (servico != null) {
      total = servico!.precoTotal;
    }
    return total;
  }

  bool get isAtivo => status != 'Cancelado' && status != 'Aguardando Confirmação' && status != 'Em Espera' && !excluido;
  bool get isAguardandoConfirmacao => status == 'Aguardando Confirmação';
  bool get isEmEspera => status == 'Em Espera';
  bool get isEmAndamento => status == 'Em Andamento';
  bool get isConcluido => status == 'Concluído';
  bool get isCancelado => status == 'Cancelado';

  bool temConflito(AgendamentoServico outro) {
    if (id == outro.id) return false;
    if (!isAtivo || !outro.isAtivo) return false;
    final outroTermino = outro.dataTermino;
    final inicioDentro = (dataAgendamento.isAfter(outro.dataAgendamento) || dataAgendamento.isAtSameMomentAs(outro.dataAgendamento)) &&
                        dataAgendamento.isBefore(outroTermino);
    final terminoDentro = dataTermino.isAfter(outro.dataAgendamento) &&
                         (dataTermino.isBefore(outroTermino) || dataTermino.isAtSameMomentAs(outroTermino));
    final englobaCompleto = dataAgendamento.isBefore(outro.dataAgendamento) && dataTermino.isAfter(outroTermino);
    return inicioDentro || terminoDentro || englobaCompleto;
  }

  /// Verifica conflito ignorando se está ativo (útil para fila de espera)
  bool temSobreposicaoHorario(AgendamentoServico outro) {
    if (id == outro.id) return false;
    if (excluido || outro.excluido) return false;
    
    final outroTermino = outro.dataTermino;
    final inicioDentro = (dataAgendamento.isAfter(outro.dataAgendamento) || dataAgendamento.isAtSameMomentAs(outro.dataAgendamento)) &&
                        dataAgendamento.isBefore(outroTermino);
    final terminoDentro = dataTermino.isAfter(outro.dataAgendamento) &&
                         (dataTermino.isBefore(outroTermino) || dataTermino.isAtSameMomentAs(outroTermino));
    final englobaCompleto = dataAgendamento.isBefore(outro.dataAgendamento) && dataTermino.isAfter(outroTermino);
    return inicioDentro || terminoDentro || englobaCompleto;
  }

  AgendamentoServico copyWith({
    String? id,
    String? numero,
    String? servicoId,
    Servico? servico,
    List<String>? servicosIds,
    List<Servico>? servicos,
    String? clienteId,
    Cliente? cliente,
    String? petId,
    Pet? pet,
    DateTime? dataAgendamento,
    int? duracaoMinutos,
    int? intervaloMinutos,
    String? observacoes,
    String? status,
    String? tipoEntrega,
    double? valorTaxiDog,
    String? bairroEntrega,
    String? pedidoId,
    String? numeroPedido,
    bool? recebido,
    DateTime? dataRecebimento,
    List<ItemMaterial>? materiais,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clienteNome,
    String? clienteTelefone,
    String? petNome,
    String? endereco,
    String? numeroEndereco,
    String? complemento,
    String? pontoReferencia,
    bool? excluido,
    bool? travado,
    String? funcionarioId,
    String? funcionarioNome,
    bool? recorrente,
    bool? isPago,
    String? pagamentoInfo,
  }) {
    return AgendamentoServico(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      servicoId: servicoId ?? this.servicoId,
      servico: servico ?? this.servico,
      servicosIds: servicosIds ?? this.servicosIds,
      servicos: servicos ?? this.servicos,
      clienteId: clienteId ?? this.clienteId,
      cliente: cliente ?? this.cliente,
      petId: petId ?? this.petId,
      pet: pet ?? this.pet,
      dataAgendamento: dataAgendamento ?? this.dataAgendamento,
      duracaoMinutos: duracaoMinutos ?? this.duracaoMinutos,
      intervaloMinutos: intervaloMinutos ?? this.intervaloMinutos,
      observacoes: observacoes ?? this.observacoes,
      status: status ?? this.status,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      valorTaxiDog: valorTaxiDog ?? this.valorTaxiDog,
      bairroEntrega: bairroEntrega ?? this.bairroEntrega,
      pedidoId: pedidoId ?? this.pedidoId,
      numeroPedido: numeroPedido ?? this.numeroPedido,
      recebido: recebido ?? this.recebido,
      dataRecebimento: dataRecebimento ?? this.dataRecebimento,
      materiais: materiais ?? this.materiais,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      petNome: petNome ?? this.petNome,
      endereco: endereco ?? this.endereco,
      numeroEndereco: numeroEndereco ?? this.numeroEndereco,
      complemento: complemento ?? this.complemento,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
      excluido: excluido ?? this.excluido,
      travado: travado ?? this.travado,
      funcionarioId: funcionarioId ?? this.funcionarioId,
      funcionarioNome: funcionarioNome ?? this.funcionarioNome,
      recorrente: recorrente ?? this.recorrente,
      isPago: isPago ?? this.isPago,
      pagamentoInfo: pagamentoInfo ?? this.pagamentoInfo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'servicoId': servicoId,
      'servicosIds': servicosIds,
      'clienteId': clienteId,
      'petId': petId,
      'dataAgendamento': dataAgendamento.toIso8601String(),
      'duracaoMinutos': duracaoMinutos,
      'intervaloMinutos': intervaloMinutos,
      'observacoes': observacoes,
      'status': status,
      'tipoEntrega': tipoEntrega,
      'valorTaxiDog': valorTaxiDog,
      'bairroEntrega': bairroEntrega,
      'pedidoId': pedidoId,
      'numeroPedido': numeroPedido,
      'recebido': recebido,
      'dataRecebimento': dataRecebimento?.toIso8601String(),
      'clienteNome': clienteNome,
      'clienteTelefone': clienteTelefone,
      'petNome': petNome,
      'endereco': endereco,
      'numeroEndereco': numeroEndereco,
      'complemento': complemento,
      'pontoReferencia': pontoReferencia,
      'excluido': excluido,
      'travado': travado,
      'funcionarioId': funcionarioId,
      'funcionarioNome': funcionarioNome,
      'recorrente': recorrente,
      'isPago': isPago,
      'pagamentoInfo': pagamentoInfo,
      'pet': pet?.toMap(),
      'servico': servico?.toMap(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'materiais': materiais.map((m) => m.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AgendamentoServico.fromMap(Map<String, dynamic> map) {
    String? sId = map['servicoId']?.toString();
    List<String> sIds = [];
    if (map['servicosIds'] != null && map['servicosIds'] is List) {
      sIds = List<String>.from(map['servicosIds']);
    } else if (sId != null) {
      sIds = [sId];
    }

    return AgendamentoServico(
      id: map['id']?.toString() ?? '',
      numero: map['numero']?.toString() ?? 'AGD-0000',
      servicoId: sId,
      servicosIds: sIds,
      clienteId: map['clienteId']?.toString(),
      petId: map['petId']?.toString(),
      dataAgendamento: DateParser.parse(map['dataAgendamento']),
      duracaoMinutos: map['duracaoMinutos'] ?? 60,
      intervaloMinutos: map['intervaloMinutos'] ?? 0,
      observacoes: map['observacoes']?.toString(),
      status: map['status']?.toString() ?? 'Agendado',
      tipoEntrega: map['tipoEntrega']?.toString(),
      valorTaxiDog: (map['valorTaxiDog'] as num?)?.toDouble(),
      bairroEntrega: map['bairroEntrega']?.toString(),
      pedidoId: map['pedidoId']?.toString(),
      numeroPedido: map['numeroPedido']?.toString(),
      recebido: (map['recebido'] as bool?) ?? false,
      dataRecebimento: map['dataRecebimento'] != null 
          ? DateParser.parse(map['dataRecebimento']) 
          : null,
      materiais: map['materiais'] != null && map['materiais'] is List
          ? (map['materiais'] as List).map((m) => ItemMaterial.fromMap(m as Map<String, dynamic>)).toList()
          : <ItemMaterial>[],
      createdAt: DateParser.parse(map['createdAt']),
      updatedAt: DateParser.parse(map['updatedAt']),
      clienteNome: map['clienteNome']?.toString(),
      clienteTelefone: map['clienteTelefone']?.toString(),
      petNome: map['petNome']?.toString(),
      endereco: map['endereco']?.toString(),
      numeroEndereco: map['numeroEndereco']?.toString(),
      complemento: map['complemento']?.toString(),
      pontoReferencia: map['pontoReferencia']?.toString(),
      excluido: (map['excluido'] as bool?) ?? false,
      travado: (map['travado'] as bool?) ?? false,
      funcionarioId: map['funcionarioId']?.toString(),
      funcionarioNome: map['funcionarioNome']?.toString(),
      recorrente: (map['recorrente'] as bool?) ?? false,
      isPago: (map['isPago'] as bool?) ?? false,
      pagamentoInfo: map['pagamentoInfo']?.toString(),
      pet: map['pet'] != null ? Pet.fromMap(Map<String, dynamic>.from(map['pet'])) : null,
      servico: map['servico'] != null ? Servico.fromMap(Map<String, dynamic>.from(map['servico'])) : null,
      servicos: map['servicos'] != null 
          ? (map['servicos'] as List).map((s) => Servico.fromMap(Map<String, dynamic>.from(s))).toList()
          : [],
    );
  }
}
