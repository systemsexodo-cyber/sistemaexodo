import 'package:sistema_exodo_novo/models/servico_realizado.dart';

/// Status da NFS-e em relação ao emissor nacional / prefeitura.
enum NfseStatus {
  rascunho,
  enviado,
  autorizado,
  cancelado,
  rejeitado,
  erro,
}

/// Dados da Nota Fiscal de Serviço Eletrônica (NFS-e).
///
/// Vinculada a um [ServicoRealizado] já quitado (recebido).
class Nfse {
  final String id;
  final String servicoId;
  final String numeroServico; // SRV-0001 etc.

  /// Número da NFS-e atribuído pela prefeitura/ADN (após autorização).
  final String? numeroNfse;

  /// Série da NFS-e.
  final String? serie;

  /// Chave de acesso / identificador da nota (adotado pelo município/ADN).
  final String? chaveAcesso;

  /// Protocolo de recebimento/lote (retorno do webservice).
  final String? protocolo;

  /// Data de emissão da nota.
  final DateTime dataEmissao;

  /// Data de autorização pela prefeitura (quando autorizado).
  final DateTime? dataAutorizacao;

  /// Valor total dos serviços (base de cálculo do ISS).
  final double valorServicos;

  /// Alíquota de ISS aplicada (%).
  final double aliquotaIss;

  /// Valor do ISS calculado.
  final double valorIss;

  /// Valor total da nota (serviços + ISS, quando aplicável).
  final double valorTotal;

  /// Código do serviço na Lista Nacional de Serviços (NBS), ex: "12.01".
  final String codigoServico;

  /// Descrição do serviço prestado.
  final String descricaoServico;

  /// CNPJ/CPF do tomador (cliente).
  final String cpfCnpjTomador;

  /// Nome do tomador.
  final String nomeTomador;

  /// Status atual da nota.
  final NfseStatus status;

  /// Observações / motivo de rejeição ou cancelamento.
  final String? observacao;

  /// Link para o DANFSE / PDF gerado.
  final String? pdfUrl;

  final DateTime createdAt;
  final DateTime updatedAt;

  Nfse({
    required this.id,
    required this.servicoId,
    required this.numeroServico,
    this.numeroNfse,
    this.serie,
    this.chaveAcesso,
    this.protocolo,
    required this.dataEmissao,
    this.dataAutorizacao,
    required this.valorServicos,
    required this.aliquotaIss,
    required this.valorIss,
    required this.valorTotal,
    required this.codigoServico,
    required this.descricaoServico,
    required this.cpfCnpjTomador,
    required this.nomeTomador,
    this.status = NfseStatus.rascunho,
    this.observacao,
    this.pdfUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Se a nota já foi autorizada (válida fiscalmente).
  bool get autorizado => status == NfseStatus.autorizado;

  /// Se a nota pode ser cancelada (autorizada e dentro do prazo municipal).
  bool get podeCancelar => autorizado;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'servico_id': servicoId,
      'numero_servico': numeroServico,
      'numero_nfse': numeroNfse,
      'serie': serie,
      'chave_acesso': chaveAcesso,
      'protocolo': protocolo,
      'data_emissao': dataEmissao.toUtc().toIso8601String(),
      'data_autorizacao': dataAutorizacao?.toUtc().toIso8601String(),
      'valor_servicos': valorServicos,
      'aliquota_iss': aliquotaIss,
      'valor_iss': valorIss,
      'valor_total': valorTotal,
      'codigo_servico': codigoServico,
      'descricao_servico': descricaoServico,
      'cpf_cnpj_tomador': cpfCnpjTomador,
      'nome_tomador': nomeTomador,
      'status': status.name,
      'observacao': observacao,
      'pdf_url': pdfUrl,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Nfse.fromMap(Map<String, dynamic> map) {
    return Nfse(
      id: map['id']?.toString() ?? '',
      servicoId: map['servicoId']?.toString() ?? map['servico_id']?.toString() ?? '',
      numeroServico:
          map['numeroServico']?.toString() ?? map['numero_servico']?.toString() ?? '',
      numeroNfse: map['numeroNfse']?.toString() ?? map['numero_nfse']?.toString(),
      serie: map['serie']?.toString(),
      chaveAcesso: map['chaveAcesso']?.toString() ?? map['chave_acesso']?.toString(),
      protocolo: map['protocolo']?.toString(),
      dataEmissao: DateTime.tryParse(
        map['dataEmissao']?.toString() ?? map['data_emissao']?.toString() ?? '',
      ) ?? DateTime.now(),
      dataAutorizacao: map['dataAutorizacao'] != null ||
              map['data_autorizacao'] != null
          ? DateTime.tryParse(
              (map['dataAutorizacao'] ?? map['data_autorizacao']).toString(),
            )
          : null,
      valorServicos: (map['valorServicos'] ?? map['valor_servicos'] ?? 0) is num
          ? (map['valorServicos'] ?? map['valor_servicos'] as num).toDouble()
          : double.tryParse((map['valorServicos'] ?? map['valor_servicos'] ?? 0).toString()) ?? 0,
      aliquotaIss: (map['aliquotaIss'] ?? map['aliquota_iss'] ?? 0) is num
          ? (map['aliquotaIss'] ?? map['aliquota_iss'] as num).toDouble()
          : double.tryParse((map['aliquotaIss'] ?? map['aliquota_iss'] ?? 0).toString()) ?? 0,
      valorIss: (map['valorIss'] ?? map['valor_iss'] ?? 0) is num
          ? (map['valorIss'] ?? map['valor_iss'] as num).toDouble()
          : double.tryParse((map['valorIss'] ?? map['valor_iss'] ?? 0).toString()) ?? 0,
      valorTotal: (map['valorTotal'] ?? map['valor_total'] ?? 0) is num
          ? (map['valorTotal'] ?? map['valor_total'] as num).toDouble()
          : double.tryParse((map['valorTotal'] ?? map['valor_total'] ?? 0).toString()) ?? 0,
      codigoServico: map['codigoServico']?.toString() ??
          map['codigo_servico']?.toString() ??
          '',
      descricaoServico: map['descricaoServico']?.toString() ??
          map['descricao_servico']?.toString() ??
          '',
      cpfCnpjTomador: map['cpfCnpjTomador']?.toString() ??
          map['cpf_cnpj_tomador']?.toString() ??
          '',
      nomeTomador: map['nomeTomador']?.toString() ??
          map['nome_tomador']?.toString() ??
          '',
      status: NfseStatus.values.firstWhere(
        (e) => e.name == (map['status']?.toString() ?? 'rascunho'),
        orElse: () => NfseStatus.rascunho,
      ),
      observacao: map['observacao']?.toString(),
      pdfUrl: map['pdfUrl']?.toString() ?? map['pdf_url']?.toString(),
      createdAt: DateTime.tryParse(
        map['createdAt']?.toString() ?? map['created_at']?.toString() ?? '',
      ) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(
        map['updatedAt']?.toString() ?? map['updated_at']?.toString() ?? '',
      ) ?? DateTime.now(),
    );
  }

  Nfse copyWith({
    String? id,
    String? servicoId,
    String? numeroServico,
    String? numeroNfse,
    String? serie,
    String? chaveAcesso,
    String? protocolo,
    DateTime? dataEmissao,
    DateTime? dataAutorizacao,
    double? valorServicos,
    double? aliquotaIss,
    double? valorIss,
    double? valorTotal,
    String? codigoServico,
    String? descricaoServico,
    String? cpfCnpjTomador,
    String? nomeTomador,
    NfseStatus? status,
    String? observacao,
    String? pdfUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Nfse(
      id: id ?? this.id,
      servicoId: servicoId ?? this.servicoId,
      numeroServico: numeroServico ?? this.numeroServico,
      numeroNfse: numeroNfse ?? this.numeroNfse,
      serie: serie ?? this.serie,
      chaveAcesso: chaveAcesso ?? this.chaveAcesso,
      protocolo: protocolo ?? this.protocolo,
      dataEmissao: dataEmissao ?? this.dataEmissao,
      dataAutorizacao: dataAutorizacao ?? this.dataAutorizacao,
      valorServicos: valorServicos ?? this.valorServicos,
      aliquotaIss: aliquotaIss ?? this.aliquotaIss,
      valorIss: valorIss ?? this.valorIss,
      valorTotal: valorTotal ?? this.valorTotal,
      codigoServico: codigoServico ?? this.codigoServico,
      descricaoServico: descricaoServico ?? this.descricaoServico,
      cpfCnpjTomador: cpfCnpjTomador ?? this.cpfCnpjTomador,
      nomeTomador: nomeTomador ?? this.nomeTomador,
      status: status ?? this.status,
      observacao: observacao ?? this.observacao,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
