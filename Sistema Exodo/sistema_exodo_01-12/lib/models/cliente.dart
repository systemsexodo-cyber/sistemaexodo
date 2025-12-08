/// Tipo de pessoa
enum TipoPessoa { fisica, juridica }

extension TipoPessoaExtension on TipoPessoa {
  String get nome {
    switch (this) {
      case TipoPessoa.fisica:
        return 'Pessoa Física';
      case TipoPessoa.juridica:
        return 'Pessoa Jurídica';
    }
  }
}

class Cliente {
  final String id;
  final String nome;
  final String? nomeFantasia; // Para PJ
  final TipoPessoa tipoPessoa;
  final String? cpfCnpj;
  final String? rgIe; // RG ou Inscrição Estadual

  // Contato
  final String? email;
  final String telefone;
  final String? telefone2;
  final String? whatsapp;

  // Endereço principal
  final String? endereco;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final String? cep;
  final String? pontoReferencia;

  // Informações adicionais
  final DateTime? dataNascimento;
  final String? profissao;
  final String? observacoes;
  final String? fotoPath; // Caminho da foto do cliente
  final Map<String, dynamic>? dadosExtras; // Dados extras personalizados

  // Crédito
  final double? limiteCredito;
  final double saldoDevedor; // Valor que o cliente está devendo (fiado)
  final bool bloqueado;
  final String? motivoBloqueio;

  // Controle
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;

  Cliente({
    required this.id,
    required this.nome,
    this.nomeFantasia,
    this.tipoPessoa = TipoPessoa.fisica,
    this.cpfCnpj,
    this.rgIe,
    this.email,
    required this.telefone,
    this.telefone2,
    this.whatsapp,
    this.endereco,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    this.cep,
    this.pontoReferencia,
    this.dataNascimento,
    this.profissao,
    this.observacoes,
    this.fotoPath,
    this.dadosExtras,
    this.limiteCredito,
    this.saldoDevedor = 0.0,
    this.bloqueado = false,
    this.motivoBloqueio,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Retorna o crédito disponível (limite - saldo devedor)
  double get creditoDisponivel {
    if (limiteCredito == null) return 0;
    return (limiteCredito! - saldoDevedor).clamp(0, double.infinity);
  }

  /// Verifica se o cliente pode comprar fiado o valor informado
  bool podeFiar(double valor) {
    if (bloqueado) return false;
    if (limiteCredito == null) return false;
    return creditoDisponivel >= valor;
  }

  /// Retorna o endereço completo formatado
  String get enderecoCompleto {
    final partes = <String>[];
    if (endereco != null && endereco!.isNotEmpty) {
      partes.add(endereco!);
      if (numero != null && numero!.isNotEmpty) {
        partes.add(numero!);
      }
    }
    if (complemento != null && complemento!.isNotEmpty) {
      partes.add(complemento!);
    }
    if (bairro != null && bairro!.isNotEmpty) {
      partes.add(bairro!);
    }
    if (cidade != null && cidade!.isNotEmpty) {
      String cidadeEstado = cidade!;
      if (estado != null && estado!.isNotEmpty) {
        cidadeEstado += ' - $estado';
      }
      partes.add(cidadeEstado);
    }
    if (cep != null && cep!.isNotEmpty) {
      partes.add('CEP: $cep');
    }
    return partes.isEmpty ? 'Endereço não informado' : partes.join(', ');
  }

  /// CPF/CNPJ formatado
  String? get cpfCnpjFormatado {
    if (cpfCnpj == null || cpfCnpj!.isEmpty) return null;
    final limpo = cpfCnpj!.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpo.length == 11) {
      // CPF: 000.000.000-00
      return '${limpo.substring(0, 3)}.${limpo.substring(3, 6)}.${limpo.substring(6, 9)}-${limpo.substring(9)}';
    } else if (limpo.length == 14) {
      // CNPJ: 00.000.000/0000-00
      return '${limpo.substring(0, 2)}.${limpo.substring(2, 5)}.${limpo.substring(5, 8)}/${limpo.substring(8, 12)}-${limpo.substring(12)}';
    }
    return cpfCnpj;
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      nomeFantasia: map['nomeFantasia'],
      tipoPessoa: map['tipoPessoa'] != null
          ? TipoPessoa.values.firstWhere(
              (t) => t.name == map['tipoPessoa'],
              orElse: () => TipoPessoa.fisica,
            )
          : TipoPessoa.fisica,
      cpfCnpj: map['cpfCnpj'],
      rgIe: map['rgIe'],
      email: map['email'],
      telefone: map['telefone'] ?? '',
      telefone2: map['telefone2'],
      whatsapp: map['whatsapp'],
      endereco: map['endereco'],
      numero: map['numero'],
      complemento: map['complemento'],
      bairro: map['bairro'],
      cidade: map['cidade'],
      estado: map['estado'],
      cep: map['cep'],
      pontoReferencia: map['pontoReferencia'],
      dataNascimento: map['dataNascimento'] != null
          ? DateTime.parse(map['dataNascimento'])
          : null,
      profissao: map['profissao'],
      observacoes: map['observacoes'],
      fotoPath: map['fotoPath'],
      dadosExtras: map['dadosExtras'] != null ? Map<String, dynamic>.from(map['dadosExtras']) : null,
      limiteCredito: map['limiteCredito']?.toDouble(),
      saldoDevedor: (map['saldoDevedor'] ?? 0).toDouble(),
      bloqueado: map['bloqueado'] ?? false,
      motivoBloqueio: map['motivoBloqueio'],
      ativo: map['ativo'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'nomeFantasia': nomeFantasia,
      'tipoPessoa': tipoPessoa.name,
      'cpfCnpj': cpfCnpj,
      'rgIe': rgIe,
      'email': email,
      'telefone': telefone,
      'telefone2': telefone2,
      'whatsapp': whatsapp,
      'endereco': endereco,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'cep': cep,
      'pontoReferencia': pontoReferencia,
      'dataNascimento': dataNascimento?.toIso8601String(),
      'profissao': profissao,
      'observacoes': observacoes,
      'fotoPath': fotoPath,
      'dadosExtras': dadosExtras,
      'limiteCredito': limiteCredito,
      'saldoDevedor': saldoDevedor,
      'bloqueado': bloqueado,
      'motivoBloqueio': motivoBloqueio,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Cliente copyWith({
    String? id,
    String? nome,
    String? nomeFantasia,
    TipoPessoa? tipoPessoa,
    String? cpfCnpj,
    String? rgIe,
    String? email,
    String? telefone,
    String? telefone2,
    String? whatsapp,
    String? endereco,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? cep,
    String? pontoReferencia,
    DateTime? dataNascimento,
    String? profissao,
    String? observacoes,
    String? fotoPath,
    Map<String, dynamic>? dadosExtras,
    double? limiteCredito,
    double? saldoDevedor,
    bool? bloqueado,
    String? motivoBloqueio,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Cliente(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      tipoPessoa: tipoPessoa ?? this.tipoPessoa,
      cpfCnpj: cpfCnpj ?? this.cpfCnpj,
      rgIe: rgIe ?? this.rgIe,
      email: email ?? this.email,
      telefone: telefone ?? this.telefone,
      telefone2: telefone2 ?? this.telefone2,
      whatsapp: whatsapp ?? this.whatsapp,
      endereco: endereco ?? this.endereco,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      cep: cep ?? this.cep,
      pontoReferencia: pontoReferencia ?? this.pontoReferencia,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      profissao: profissao ?? this.profissao,
      observacoes: observacoes ?? this.observacoes,
      fotoPath: fotoPath ?? this.fotoPath,
      dadosExtras: dadosExtras ?? this.dadosExtras,
      limiteCredito: limiteCredito ?? this.limiteCredito,
      saldoDevedor: saldoDevedor ?? this.saldoDevedor,
      bloqueado: bloqueado ?? this.bloqueado,
      motivoBloqueio: motivoBloqueio ?? this.motivoBloqueio,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
