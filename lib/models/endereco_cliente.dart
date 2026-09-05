import 'package:uuid/uuid.dart';

/// Modelo para representar um endereço adicional do cliente
class EnderecoCliente {
  final String id;
  final String tipo; // Ex: Casa, Trabalho, Mãe
  final String logradouro;
  final String numero;
  final String? complemento;
  final String bairro;
  final String cidade;
  final String uf;
  final String? cep;
  final String? pontoReferencia;
  final bool isDefault;

  EnderecoCliente({
    String? id,
    required this.tipo,
    required this.logradouro,
    required this.numero,
    this.complemento,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.cep,
    this.pontoReferencia,
    this.isDefault = false,
  }) : id = id ?? const Uuid().v4();

  String get enderecoCompleto {
    final partes = <String>[];
    partes.add('$logradouro, $numero');
    if (complemento != null && complemento!.isNotEmpty) partes.add(complemento!);
    partes.add(bairro);
    partes.add('$cidade - $uf');
    if (cep != null && cep!.isNotEmpty) partes.add('CEP: $cep');
    return partes.join(', ');
  }

  factory EnderecoCliente.fromMap(Map<String, dynamic> map) {
    return EnderecoCliente(
      id: map['id']?.toString(),
      tipo: map['tipo']?.toString() ?? map['rotulo']?.toString() ?? 'Endereço',
      logradouro: map['logradouro']?.toString() ?? map['endereco']?.toString() ?? '',
      numero: map['numero']?.toString() ?? '',
      complemento: map['complemento']?.toString(),
      bairro: map['bairro']?.toString() ?? '',
      cidade: map['cidade']?.toString() ?? '',
      uf: map['uf']?.toString() ?? map['estado']?.toString() ?? '',
      cep: map['cep']?.toString(),
      pontoReferencia: map['pontoReferencia']?.toString(),
      isDefault: map['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'logradouro': logradouro,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'cep': cep,
      'pontoReferencia': pontoReferencia,
      'isDefault': isDefault,
    };
  }

  EnderecoCliente copyWith({
    String? id,
    String? tipo,
    String? logradouro,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? uf,
    String? cep,
    String? pontoReferencia,
    bool? isDefault,
  }) {
    return EnderecoCliente(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      logradouro: logradouro ?? this.logradouro,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      uf: uf ?? this.uf,
      cep: cep ?? this.cep,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
