import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/faixa_numeracao_service.dart';

/// A faixa reservada é o que impede dois PCs offline de emitirem o mesmo
/// número de venda. Aqui está a conta e a leitura/gravação do bloco.
void main() {
  group('calcularReserva', () {
    test('reserva o bloco a partir do contador da nuvem', () {
      final r = calcularReserva(valorNoContador: 434, aPartirDe: 1, tamanho: 500)!;
      expect(r.inicio, 434);
      expect(r.fim, 933);
      expect(r.tamanho, 500);
      expect(r.proximoLivre, 934, reason: 'o contador da nuvem fica no próximo livre');
    });

    test('contador zerado começa no 1 (primeira reserva da empresa)', () {
      final r = calcularReserva(valorNoContador: 0, aPartirDe: 1, tamanho: 500)!;
      expect(r.inicio, 1);
      expect(r.fim, 500);
      expect(r.proximoLivre, 501);
    });

    test('contador atrasado nunca entrega número já emitido', () {
      // A loja já está no 433 (PC antigo vendia sem faixa), mas o contador
      // da nuvem ainda diz 300: reservar de 300 entregaria número usado.
      final r = calcularReserva(valorNoContador: 300, aPartirDe: 434, tamanho: 100)!;
      expect(r.inicio, 434);
      expect(r.fim, 533);
      expect(r.proximoLivre, 534);
    });

    test('contador adiantado manda (a outra máquina reservou antes)', () {
      final r = calcularReserva(valorNoContador: 900, aPartirDe: 434, tamanho: 100)!;
      expect(r.inicio, 900);
      expect(r.fim, 999);
    });

    test('tamanho inválido não reserva nada', () {
      expect(calcularReserva(valorNoContador: 10, aPartirDe: 1, tamanho: 0), isNull);
      expect(calcularReserva(valorNoContador: 10, aPartirDe: 1, tamanho: -5), isNull);
    });

    test('piso inválido vira 1', () {
      final r = calcularReserva(valorNoContador: 0, aPartirDe: 0, tamanho: 10)!;
      expect(r.inicio, 1);
    });
  });

  group('FaixaNumeracao', () {
    test('consumir esgota o bloco e sobra o que ainda dá para vender offline', () {
      var faixa = const FaixaNumeracao(tipo: 'venda', inicio: 434, fim: 436, proximo: 434);
      expect(faixa.restantes, 3);
      expect(faixa.esgotada, isFalse);

      faixa = faixa.avancar();
      expect(faixa.proximo, 435);
      expect(faixa.restantes, 2);

      faixa = faixa.avancar().avancar();
      expect(faixa.proximo, 437);
      expect(faixa.esgotada, isTrue);
      expect(faixa.restantes, 0);
    });

    test('ida e volta pelo JSON guardado no exodo_config', () {
      const original =
          FaixaNumeracao(tipo: 'pedido', inicio: 10, fim: 20, proximo: 12, origem: 'nuvem');
      final lida = FaixaNumeracao.fromJson(jsonEncode(original.toJson()), tipo: 'pedido')!;

      expect(lida.tipo, 'pedido');
      expect(lida.inicio, 10);
      expect(lida.fim, 20);
      expect(lida.proximo, 12);
      expect(lida.origem, 'nuvem');
    });

    test('conteúdo corrompido devolve null em vez de derrubar a venda', () {
      expect(FaixaNumeracao.fromJson('isso não é json', tipo: 'venda'), isNull);
      expect(FaixaNumeracao.fromJson(null, tipo: 'venda'), isNull);
      expect(FaixaNumeracao.fromJson('{"i":0,"f":0}', tipo: 'venda'), isNull);
      expect(FaixaNumeracao.fromJson('{"i":5,"f":1}', tipo: 'venda'), isNull);
    });
  });

  group('FaixaNumeracaoService (bloco local)', () {
    late Map<String, Object?> config;
    late FaixaNumeracaoService servico;

    setUp(() {
      config = {};
      servico = FaixaNumeracaoService(
        lerConfig: (chave) async => config[chave],
        salvarConfig: (chave, valor) async => config[chave] = valor,
        tamanhoPadrao: 50,
      );
    });

    test('sem bloco guardado não inventa número', () async {
      expect(await servico.lerLocal('venda', 'E1'), isNull);
    });

    test('grava e relê o bloco por empresa', () async {
      const faixa = FaixaNumeracao(tipo: 'venda', inicio: 100, fim: 149, proximo: 101);
      await servico.salvarLocal(faixa, 'E1');

      final lida = await servico.lerLocal('venda', 'E1');
      expect(lida!.inicio, 100);
      expect(lida.proximo, 101);
      expect(lida.restantes, 49);

      // Bloco é por empresa: a empresa nova não herda o da anterior.
      expect(await servico.lerLocal('venda', 'E2'), isNull);
      expect(servico.chaveLocal('venda', 'E1'), 'exodo_faixa_local_venda_E1');
      expect(servico.chaveContador('venda', 'E1'), 'exodo_faixa_venda_E1');
    });

    test('o consumo grava o bloco avançado, então o app não repete número', () async {
      var faixa = const FaixaNumeracao(tipo: 'venda', inicio: 7, fim: 8, proximo: 7);
      await servico.salvarLocal(faixa.avancar(), 'E1');

      final lida = await servico.lerLocal('venda', 'E1');
      expect(lida!.proximo, 8, reason: 'o 7 já foi usado e não pode sair de novo');
    });

    test('empresa vazia não grava bloco órfão', () async {
      await servico.salvarLocal(
          const FaixaNumeracao(tipo: 'venda', inicio: 1, fim: 2, proximo: 1), '');
      expect(config, isEmpty);
      expect(await servico.lerLocal('venda', ''), isNull);
    });
  });
}
