import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sistema_exodo_novo/services/mercado_pago_mensalidade_service.dart';

void main() {
  test('gera Pix pelo endpoint seguro e interpreta QR dinâmico', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/create-pix'));
      expect(jsonDecode(request.body), {
        'empresa_id': 'empresa-123',
        'email': 'cliente@example.com',
      });
      return http.Response(
        jsonEncode({
          'pagamento_id': '123456789',
          'qr_code': 'pix-copia-cola',
          'qr_code_base64': 'aW1hZ2Vt',
          'mes_referencia': '2026-11',
          'valor': 99.9,
        }),
        200,
      );
    });
    final service = MercadoPagoMensalidadeService(
      client: client,
      functionsUrl: Uri.parse(
        'https://servidorsupabase.tail9b4943.ts.net/'
        'functions/v1/mercado-pago-mensalidade',
      ),
    );
    addTearDown(service.dispose);

    final pix = await service.criarPix(
      empresaId: 'empresa-123',
      emailPagador: 'cliente@example.com',
    );

    expect(pix.pagamentoId, '123456789');
    expect(pix.codigoCopiaCola, 'pix-copia-cola');
    expect(pix.qrCodeBase64, 'aW1hZ2Vt');
    expect(pix.mesReferencia, '2026-11');
    expect(pix.valor, 99.9);
  });

  test('não aceita cobrança sem dados Pix', () {
    expect(
      () => PixMensalidade.fromMap({'pagamento_id': '123', 'qr_code': ''}),
      throwsFormatException,
    );
  });

  test('retorna a confirmação e a data de pagamento do endpoint', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/payment-status'));
      expect(jsonDecode(request.body), {
        'empresa_id': 'empresa-123',
        'pagamento_id': '123456789',
      });
      return http.Response(
        jsonEncode({
          'aprovado': true,
          'liberado': true,
          'pago_em': '2026-11-15T12:00:00.000Z',
        }),
        200,
      );
    });
    final service = MercadoPagoMensalidadeService(
      client: client,
      functionsUrl: Uri.parse(
        'https://servidorsupabase.tail9b4943.ts.net/'
        'functions/v1/mercado-pago-mensalidade',
      ),
    );
    addTearDown(service.dispose);

    final status = await service.pagamentoAprovado(
      empresaId: 'empresa-123',
      pagamentoId: '123456789',
    );

    expect(status.aprovado, isTrue);
    expect(status.pagoEm, '2026-11-15T12:00:00.000Z');
  });
}
