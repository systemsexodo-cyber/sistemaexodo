// PROVA DE FOGO OFFLINE — nada pode sumir do banco local ao reabrir.
//
// Cenário real: sem internet, o operador abre o caixa, faz vendas e fecha o
// caixa; ao reabrir o sistema (mesmo sem nuvem) TUDO precisa continuar lá.
//
// O teste usa o banco PostgreSQL LOCAL de verdade (o mesmo do app) e deixa a
// base como estava: os registros de teste são gravados com ids próprios e
// APAGADOS no final. Nenhuma chamada à nuvem é feita (Supabase indisponível
// neste ambiente de teste = exatamente o modo offline).
//
// Rodar: flutter test test/offline_persistencia_reabertura_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

  void prepararAmbiente() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(canal), (call) async => null);
    }
    for (final canal in const [
      'xyz.luan/audioplayers.global/events',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockStreamHandler(EventChannel(canal),
          MockStreamHandler.inline(onListen: (args, sink) {}));
    }
  }

  VendaBalcao vendaDeTeste({
    required String id,
    required String numero,
    required double total,
    required String operador,
  }) =>
      VendaBalcao(
        id: id,
        numero: numero,
        dataVenda: DateTime.now(),
        itens: [
          ItemVendaBalcao(
            id: 'produto-de-teste-inexistente',
            nome: 'Item de Teste Offline',
            precoUnitario: total,
            quantidade: 1,
          ),
        ],
        tipoPagamento: TipoPagamento.dinheiro,
        valorTotal: total,
        operador: operador,
      );

  test('offline: caixa e vendas sobrevivem ao reabrir o sistema', () async {
    prepararAmbiente();
    final ds = DataService();

    final marca = DateTime.now().millisecondsSinceEpoch;
    final responsavel = 'teste-offline-$marca@local';

    // Ids de teste (para limpeza no final).
    String? idAbertura;
    String? idFechamento;
    String? idVendaA;
    String? idVendaB;

    try {
      // ---------- 1. ABRIR O SISTEMA (empresa definida, sem nuvem) ----------
      await ds.definirEmpresaAtual(bmj, modoLeve: true);

      // ---------- 2. OPERAR TOTALMENTE OFFLINE ----------
      final abertura =
          await ds.abrirCaixaComValor(100.0, responsavel: responsavel);
      idAbertura = abertura.id;

      final vendaA = vendaDeTeste(
        id: 'teste-offline-venda-$marca-a',
        numero: 'TST-$marca',
        total: 20.0,
        operador: responsavel,
      );
      final vendaB = vendaDeTeste(
        id: 'teste-offline-venda-$marca-b',
        numero: 'TST-${marca}b',
        total: 35.5,
        operador: responsavel,
      );
      idVendaA = vendaA.id;
      idVendaB = vendaB.id;

      await ds.addVendaBalcao(vendaA);
      await ds.addVendaBalcao(vendaB);

      final fechamento = await ds.registrarFechamentoCaixa(
        valorEsperado: 155.5,
        valorReal: 155.5,
        abertura: abertura,
      );
      idFechamento = fechamento?.id;

      // Fechar o app: descarrega o que estiver pendente no banco local.
      await ds.salvarDadosAgora();

      // ---------- 3. REABRIR O SISTEMA ----------
      await ds.definirEmpresaAtual(null);
      await ds.definirEmpresaAtual(bmj, modoLeve: true);

      // ---------- 4. NADA PODE TER SUMIDO ----------
      expect(ds.aberturasCaixa.any((a) => a.id == abertura.id), isTrue,
          reason: 'a abertura de caixa feita offline tem de voltar do banco '
              'local depois de reabrir o sistema');

      expect(
        ds.vendasBalcao.any(
            (v) => v.id == vendaA.id && (v.valorTotal - 20.0).abs() < 0.001),
        isTrue,
        reason: 'a venda offline (R\$ 20) tem de voltar intacta',
      );
      expect(
        ds.vendasBalcao.any(
            (v) => v.id == vendaB.id && (v.valorTotal - 35.5).abs() < 0.001),
        isTrue,
        reason: 'a venda offline (R\$ 35,50) tem de voltar intacta',
      );

      if (idFechamento != null) {
        expect(ds.fechamentosCaixa.any((f) => f.id == idFechamento), isTrue,
            reason: 'o fechamento de caixa offline tem de voltar do banco '
                'local');
      }
    } finally {
      // ---------- 5. LIMPEZA: deixa a base como estava ----------
      try {
        final db = DatabaseService();
        db.setEmpresaId(bmj);
        if (idAbertura != null) {
          await db.removerItemPostgres(
              LocalStorageService.keyAberturasCaixa, idAbertura, bmj);
        }
        if (idVendaA != null) {
          await db.removerItemPostgres(
              LocalStorageService.keyVendasBalcao, idVendaA, bmj);
        }
        if (idVendaB != null) {
          await db.removerItemPostgres(
              LocalStorageService.keyVendasBalcao, idVendaB, bmj);
        }
        if (idFechamento != null) {
          await db.removerItemPostgres(
              LocalStorageService.keyFechamentosCaixa, idFechamento, bmj);
        }
        // Remove da fila persistida qualquer operação de teste que tenha sobrado.
        final fila = await db.carregarConfig('exodo_sync_queue');
        if (fila is List) {
          final ids = {idAbertura, idFechamento, idVendaA, idVendaB};
          final restante = fila.where((item) {
            if (item is! Map) return true;
            return !ids.contains(item['data_id']?.toString());
          }).toList();
          if (restante.length != fila.length) {
            await db.salvarConfig('exodo_sync_queue', restante);
          }
        }
      } catch (e) {
        // Limpeza é best-effort: não deve mascarar o resultado do teste.
        // ignore: avoid_print
        print('>>> [Teste] limpeza falhou: $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
