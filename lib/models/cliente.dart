import 'package:sistema_exodo_novo/utils/date_parser.dart';
import 'pet.dart';
import 'endereco_cliente.dart';


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
  final List<EnderecoCliente> enderecos; // Lista de endereços do cliente

  // Informações adicionais
  final DateTime? dataNascimento;
  final String? profissao;
  final String? observacoes;
  final String? fotoPath; // Caminho da foto do cliente
  final Map<String, dynamic>? dadosExtras; // Dados extras personalizados
  final List<Pet> pets; // Lista de pets do cliente

  // Crédito
  final double? limiteCredito;
  final double saldoDevedor; // Valor que o cliente está devendo (fiado)
  final bool bloqueado;
  final String? motivoBloqueio;

  // Autenticação (para login no e-commerce)
  final String? senha; // Senha para login no e-commerce (hash ou texto simples)
  final String? emailLogin; // Email usado para login (pode ser diferente do email principal)
  
  // Configurações específicas
  final bool habilitaTaxiDog; // Define se o cliente pode agendar com Taxi Dog
  
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
    List<Pet>? pets,
    this.limiteCredito,
    this.saldoDevedor = 0.0,
    this.bloqueado = false,
    this.motivoBloqueio,
    this.senha,
    this.emailLogin,
    this.habilitaTaxiDog = false,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
    List<EnderecoCliente>? enderecos,
  }) : pets = pets ?? [],
       enderecos = enderecos ?? [];

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
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      nomeFantasia: map['nomeFantasia']?.toString(),
      tipoPessoa: map['tipoPessoa'] != null
          ? TipoPessoa.values.firstWhere(
              (t) => t.name == map['tipoPessoa'],
              orElse: () => TipoPessoa.fisica,
            )
          : TipoPessoa.fisica,
      cpfCnpj: map['cpfCnpj']?.toString(),
      rgIe: map['rgIe']?.toString(),
      email: map['email']?.toString(),
      telefone: map['telefone']?.toString() ?? '',
      telefone2: map['telefone2']?.toString(),
      whatsapp: map['whatsapp']?.toString(),
      endereco: map['endereco']?.toString(),
      numero: map['numero']?.toString(),
      complemento: map['complemento']?.toString(),
      bairro: map['bairro']?.toString(),
      cidade: map['cidade']?.toString(),
      estado: map['estado']?.toString(),
      cep: map['cep']?.toString(),
      pontoReferencia: map['pontoReferencia']?.toString(),
      dataNascimento: map['dataNascimento'] != null
          ? DateParser.parse(map['dataNascimento'])
          : null,
      profissao: map['profissao']?.toString(),
      observacoes: map['observacoes']?.toString(),
      fotoPath: map['fotoPath']?.toString(),
      dadosExtras: map['dadosExtras'] != null ? Map<String, dynamic>.from(map['dadosExtras']) : null,
      pets: map['pets'] != null
          ? (map['pets'] as List).map((p) => Pet.fromMap(p as Map<String, dynamic>)).toList()
          : [],
      enderecos: map['enderecos'] != null
          ? (map['enderecos'] as List).map((e) => EnderecoCliente.fromMap(e as Map<String, dynamic>)).toList()
          : [],
      limiteCredito: (map['limiteCredito'] as num?)?.toDouble(),
      saldoDevedor: (map['saldoDevedor'] as num? ?? 0).toDouble(),
      bloqueado: map['bloqueado'] ?? false,
      motivoBloqueio: map['motivoBloqueio']?.toString(),
      senha: map['senha']?.toString(),
      emailLogin: map['emailLogin']?.toString(),
      habilitaTaxiDog: map['habilitaTaxiDog'] ?? false,
      ativo: map['ativo'] ?? true,
      createdAt: DateParser.parse(map['createdAt']),
      updatedAt: DateParser.parse(map['updatedAt']),
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
      'pets': pets.map((p) => p.toMap()).toList(),
      'enderecos': enderecos.map((e) => e.toMap()).toList(),
      'limiteCredito': limiteCredito,
      'saldoDevedor': saldoDevedor,
      'bloqueado': bloqueado,
      'motivoBloqueio': motivoBloqueio,
      'senha': senha,
      'emailLogin': emailLogin,
      'habilitaTaxiDog': habilitaTaxiDog,
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
    List<Pet>? pets,
    List<EnderecoCliente>? enderecos,
    double? limiteCredito,
    double? saldoDevedor,
    bool? bloqueado,
    String? motivoBloqueio,
    String? senha,
    String? emailLogin,
    bool? habilitaTaxiDog,
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
      pets: pets ?? this.pets,
      enderecos: enderecos ?? this.enderecos,
      limiteCredito: limiteCredito ?? this.limiteCredito,
      saldoDevedor: saldoDevedor ?? this.saldoDevedor,
      bloqueado: bloqueado ?? this.bloqueado,
      motivoBloqueio: motivoBloqueio ?? this.motivoBloqueio,
      senha: senha ?? this.senha,
      emailLogin: emailLogin ?? this.emailLogin,
      habilitaTaxiDog: habilitaTaxiDog ?? this.habilitaTaxiDog,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
