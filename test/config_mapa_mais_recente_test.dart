// Regressão: "Personalização da loja volta ao antigo".
//
// O merge da empresa começava pela cópia da NUVEM e só preenchia chaves que
// faltavam. Como `configuracoes['ecommerce']` sempre existe na nuvem, a
// personalização salva no PC era descartada no boot / ao selecionar a empresa.
//
// Estes testes cobrem a regra nova: a seção `ecommerce` (e `agendamento`) com o
// carimbo MAIS NOVO vence, independentemente do lado em que está.
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/utils/perfis_tributarios_merge.dart';

Map<String, dynamic> _config({
  String? modo,
  String? carimbo,
  Map<String, dynamic>? extras,
}) {
  final config = <String, dynamic>{};
  if (modo != null) {
    config['ecommerce'] = <String, dynamic>{
      'modoExibicao': modo,
      'corFundoLoja': '#E91E63',
    };
  }
  if (carimbo != null) {
    config[chaveEcommerceAtualizadoEm] = carimbo;
  }
  if (extras != null) config.addAll(extras);
  return config;
}

void main() {
  final t0 = DateTime.utc(2026, 11, 11, 21, 43, 6);
  final t1 = DateTime.utc(2026, 11, 11, 21, 43, 32);

  test('carimbo local mais novo vence (bug: nuvem revertia o delivery)', () {
    final local = _config(modo: 'delivery', carimbo: t1.toIso8601String());
    final nuvem = _config(modo: 'ecommerce', carimbo: t0.toIso8601String());

    final vencedor = configMapaVencedor(
      chave: 'ecommerce',
      chaveCarimbo: chaveEcommerceAtualizadoEm,
      configLocal: local,
      configRemota: nuvem,
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect(vencedor, isNotNull);
    expect(vencedor!['modoExibicao'], 'delivery');
  });

  test('carimbo da nuvem mais novo vence', () {
    final local = _config(modo: 'delivery', carimbo: t0.toIso8601String());
    final nuvem = _config(modo: 'ecommerce', carimbo: t1.toIso8601String());

    final vencedor = configMapaVencedor(
      chave: 'ecommerce',
      chaveCarimbo: chaveEcommerceAtualizadoEm,
      configLocal: local,
      configRemota: nuvem,
      updatedAtLocal: t1,
      updatedAtRemota: t0,
    );

    expect(vencedor!['modoExibicao'], 'ecommerce');
  });

  test('carimbo só de um lado decide, ignorando updatedAt da empresa', () {
    final local = _config(modo: 'delivery', carimbo: t0.toIso8601String());
    final nuvem = _config(modo: 'ecommerce');

    final vencedor = configMapaVencedor(
      chave: 'ecommerce',
      chaveCarimbo: chaveEcommerceAtualizadoEm,
      configLocal: local,
      configRemota: nuvem,
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect(vencedor!['modoExibicao'], 'delivery');
  });

  test('sem carimbo nos dois lados: updatedAt maior vence', () {
    final local = _config(modo: 'delivery');
    final nuvem = _config(modo: 'ecommerce');

    final vencedor = configMapaVencedor(
      chave: 'ecommerce',
      chaveCarimbo: chaveEcommerceAtualizadoEm,
      configLocal: local,
      configRemota: nuvem,
      updatedAtLocal: t1,
      updatedAtRemota: t0,
    );

    expect(vencedor!['modoExibicao'], 'delivery');
  });

  test('seção vencedora mantém chaves que só existem na perdedora', () {
    final local = _config(
      modo: 'delivery',
      carimbo: t1.toIso8601String(),
      extras: {
        'ecommerce': <String, dynamic>{
          'modoExibicao': 'delivery',
          'campoNovo': 'x',
        },
      },
    );
    final nuvem = _config(
      modo: 'ecommerce',
      carimbo: t0.toIso8601String(),
      extras: {
        'ecommerce': <String, dynamic>{
          'modoExibicao': 'ecommerce',
          'campoAntigo': 'y',
        },
      },
    );

    final vencedor = configMapaVencedor(
      chave: 'ecommerce',
      chaveCarimbo: chaveEcommerceAtualizadoEm,
      configLocal: local,
      configRemota: nuvem,
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect(vencedor!['modoExibicao'], 'delivery');
    expect(vencedor['campoNovo'], 'x');
    expect(vencedor['campoAntigo'], 'y');
  });

  test('aplicar copia a seção vencedora e o carimbo para o destino', () {
    final local = _config(modo: 'delivery', carimbo: t1.toIso8601String());
    final nuvem = _config(modo: 'ecommerce', carimbo: t0.toIso8601String());
    final destino = <String, dynamic>{};

    aplicarEcommerceMaisRecente(
      destino,
      local,
      nuvem,
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect((destino['ecommerce'] as Map)['modoExibicao'], 'delivery');
    expect(destino[chaveEcommerceAtualizadoEm], t1.toIso8601String());
  });

  test('agendamento segue a mesma regra', () {
    final local = <String, dynamic>{
      'agendamento': {'bairrosTaxiDog': ['Centro']},
      chaveAgendamentoAtualizadoEm: t1.toIso8601String(),
    };
    final nuvem = <String, dynamic>{
      'agendamento': {'bairrosTaxiDog': []},
      chaveAgendamentoAtualizadoEm: t0.toIso8601String(),
    };
    final destino = <String, dynamic>{};

    aplicarAgendamentoMaisRecente(
      destino,
      local,
      nuvem,
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect((destino['agendamento'] as Map)['bairrosTaxiDog'], ['Centro']);
  });

  test('nenhum dos lados tem a seção: nada é escrito', () {
    final destino = <String, dynamic>{};

    aplicarEcommerceMaisRecente(
      destino,
      <String, dynamic>{},
      <String, dynamic>{},
      updatedAtLocal: t0,
      updatedAtRemota: t1,
    );

    expect(destino.containsKey('ecommerce'), isFalse);
  });
}
