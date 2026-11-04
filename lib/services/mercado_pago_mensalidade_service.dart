import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'env_config.dart';

class PixMensalidade {
  final String pagamentoId;
  final String codigoCopiaCola;
  final String? qrCodeBase64;
  final String? ticketUrl;
  final String mesReferencia;
  final double valor;

  const PixMensalidade({
    required this.pagamentoId,
    required this.codigoCopiaCola,
    required this.mesReferencia,
    required this.valor,
    this.qrCodeBase64,
    this.ticketUrl,
  });

  factory PixMensalidade.fromMap(Map<String, dynamic> map) {
    final codigo = (map['qr_code'] ?? '').toString().trim();
    final pagamentoId = (map['pagamento_id'] ?? '').toString().trim();
    if (codigo.isEmpty || pagamentoId.isEmpty) {
      throw const FormatException(
        'O Mercado Pago não retornou os dados da cobrança Pix.',
      );
    }
    return PixMensalidade(
      pagamentoId: pagamentoId,
      codigoCopiaCola: codigo,
      qrCodeBase64: map['qr_code_base64']?.toString(),
      ticketUrl: map['ticket_url']?.toString(),
      mesReferencia: (map['mes_referencia'] ?? '').toString(),
      valor: (map['valor'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StatusPagamentoMensalidade {
  final bool aprovado;
  final String? pagoEm;

  const StatusPagamentoMensalidade({required this.aprovado, this.pagoEm});
}

class MercadoPagoMensalidadeService {
  final http.Client _client;
  final Uri _functionsUrl;

  MercadoPagoMensalidadeService({http.Client? client, Uri? functionsUrl})
    : _client = client ?? http.Client(),
      _functionsUrl = functionsUrl ?? _resolveFunctionsUrl();

  static Uri _resolveFunctionsUrl() {
    final configured = EnvConfig.env['SUPABASE_FUNCTIONS_URL']?.trim();
    return Uri.parse(
      configured != null && configured.isNotEmpty
          ? configured
          : 'https://servidorsupabase.tail9b4943.ts.net/'
                'functions/v1/mercado-pago-mensalidade',
    );
  }

  Uri _endpoint(String action) => _functionsUrl.replace(
    path: '${_functionsUrl.path.replaceFirst(RegExp(r'/+$'), '')}/$action',
  );

  void dispose() => _client.close();

  Future<PixMensalidade> criarPix({
    required String empresaId,
    required String emailPagador,
  }) async {
    if (empresaId.trim().isEmpty) {
      throw ArgumentError('Empresa inválida para gerar a cobrança.');
    }
    final email = emailPagador.trim();
    if (!email.contains('@')) {
      throw ArgumentError('Não encontrei um e-mail válido para a cobrança.');
    }

    final response = await _client
        .post(
          _endpoint('create-pix'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'empresa_id': empresaId, 'email': email}),
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('Resposta inválida do servidor de pagamentos.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        (body['erro'] ?? 'Não foi possível gerar o Pix.').toString(),
      );
    }
    debugPrint('>>> [Mensalidade] Cobrança Pix recebida do servidor.');
    return PixMensalidade.fromMap(body);
  }

  Future<StatusPagamentoMensalidade> pagamentoAprovado({
    required String empresaId,
    required String pagamentoId,
  }) async {
    final response = await _client
        .post(
          _endpoint('payment-status'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'empresa_id': empresaId,
            'pagamento_id': pagamentoId,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Não foi possível consultar a confirmação do Pix.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return StatusPagamentoMensalidade(
      aprovado: body['aprovado'] == true && body['liberado'] == true,
      pagoEm: body['pago_em']?.toString(),
    );
  }
}
