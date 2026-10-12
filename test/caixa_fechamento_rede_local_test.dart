// REGRESSÃO: caixa fechado no OUTRO PC precisa bloquear a venda aqui.
//
// Cenário real relatado no caixa da loja:
//   1. o operador fechou o caixa pela máquina 2;
//   2. o fechamento chegou na máquina 1 pela rede local (sincronizador da LAN
//      gravando no PostgreSQL + aviso no canal `exodo_ui_event`);
//   3. a máquina 1 recarregou as listas de caixa... mas o status continuava
//      "aberto" porque `caixaAberto` devolvia um FLAG guardado, e o flag não era
//      reavaliado depois da recarga. O PDV então deixou lançar a venda num caixa
//      que já tinha sido fechado na outra máquina.
//
// A correção: o status passa a ser DERIVADO das listas (abertura sem fechamento
// = aberto) em todo lugar, e `_carregarCaixaLocal` reavalia o flag ao final da
// recarga local.
//
// Causa raiz encontrada nos dados reais: existia uma ABERTURA ÓRFÃ (aberta em
// 03/10 e nunca fechada) no banco. A busca de "caixa aberto" pegava qualquer
// abertura sem fechamento — então, depois de fechar o caixa do dia, o órfão
// assumia o posto e o sistema voltava a dizer "caixa ABERTO" para sempre. Foi
// isso que deixou o caixa 1 vender depois de o caixa 2 fechar.
//
// A regra agora é por SESSÃO: vale a abertura MAIS RECENTE (do operador, quando
// há responsável ativo); aberturas antigas sem fechamento são lixo de histórico
// e não mantêm o caixa aberto.
//
// O que fica travado aqui:
//   1. abertura sem fechamento -> caixa ABERTO;
//   2. fechamento que chega DEPOIS (isto é, vindo do outro PC) -> caixa FECHADO;
//   3. o mesmo vale com responsável ativo (caixa do próprio operador);
//   4. fechamento de OUTRA pessoa não fecha o caixa deste operador;
//   5. abertura ÓRFÃ antiga não mantém o caixa aberto depois de fechar;
//   6. reabrir depois de fechar volta a liberar.
//
// Rodar: flutter test test/caixa_fechamento_rede_local_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

AberturaCaixa aberturaDeTeste({
  required String id,
  String? responsavel,
  DateTime? dataAbertura,
}) =>
    AberturaCaixa(
      id: id,
      numero: 'CAIXA-$id',
      dataAbertura: dataAbertura ?? DateTime(2026, 10, 4, 11, 23, 7),
      valorInicial: 100,
      responsavel: responsavel,
    );

FechamentoCaixa fechamentoDeTeste({
  required String id,
  required String aberturaCaixaId,
  DateTime? dataFechamento,
}) =>
    FechamentoCaixa(
      id: id,
      aberturaCaixaId: aberturaCaixaId,
      dataFechamento: dataFechamento ?? DateTime(2026, 10, 4, 11, 30),
      valorEsperado: 100,
      valorReal: 100,
      diferenca: 0,
      sangrias: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // Canais de plugin que o DataService toca ao inicializar (som/conectividade).
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

  setUp(() {
    prepararAmbiente();
  });

  test('abertura sem fechamento deixa o caixa ABERTO', () {
    final ds = DataService();
    ds.aberturasCaixa.add(aberturaDeTeste(id: 'a1'));

    expect(ds.caixaAberto, isTrue,
        reason: 'Existe abertura sem fechamento: o PDV deve permitir a venda.');
    expect(ds.aberturaCaixaAtual?.id, 'a1');
  });

  test('fechamento que chega DEPOIS (rede local) FECHA o caixa', () {
    final ds = DataService();
    ds.aberturasCaixa.add(aberturaDeTeste(id: 'a1'));
    expect(ds.caixaAberto, isTrue);

    // É exatamente isto que o sincronizador da LAN grava aqui quando o caixa é
    // fechado no outro PC: o fechamento da abertura que estava aberta.
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f1', aberturaCaixaId: 'a1'));

    expect(ds.caixaAberto, isFalse,
        reason: 'Caixa fechado na outra máquina não pode liberar venda aqui.');
    expect(ds.aberturaCaixaAtual, isNull);
    expect(ds.aberturasCaixaAbertas, isEmpty);
  });

  test('com responsável ativo, o fechamento da rede local também bloqueia', () {
    final ds = DataService();
    ds.responsavelAtivo = 'carlos@gmail.com';
    ds.aberturasCaixa
        .add(aberturaDeTeste(id: 'a1', responsavel: 'carlos@gmail.com'));

    expect(ds.caixaAberto, isTrue);

    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f1', aberturaCaixaId: 'a1'));

    expect(ds.caixaAberto, isFalse,
        reason: 'O caixa DO OPERADOR foi fechado: não pode vender.');
  });

  test('fechamento de OUTRA pessoa não fecha o caixa deste operador', () {
    final ds = DataService();
    ds.responsavelAtivo = 'carlos@gmail.com';
    ds.aberturasCaixa
        .add(aberturaDeTeste(id: 'a1', responsavel: 'carlos@gmail.com'));

    // Outra abertura (de outro operador) foi fechada na rede local.
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'a2',
      responsavel: 'silva@gmail.com',
      dataAbertura: DateTime(2026, 10, 4, 9, 0),
    ));
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f2', aberturaCaixaId: 'a2'));

    expect(ds.caixaAberto, isTrue,
        reason: 'O caixa do carlos continua aberto — só o da silva foi fechado.');
    expect(ds.aberturaCaixaAtual?.id, 'a1');
  });

  test('abertura ÓRFÃ antiga não mantém o caixa aberto', () {
    // Estado REAL encontrado no banco: CAIXA-002 (03/10) ficou sem fechamento.
    // O caixa do dia (04/10) foi aberto e depois FECHADO. O sistema precisa
    // dizer FECHADO — antes o órfão assumia e liberava a venda para sempre.
    final ds = DataService();
    ds.responsavelAtivo = 'user';

    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'orfa',
      responsavel: 'user',
      dataAbertura: DateTime(2026, 10, 3, 20, 30, 50),
    ));
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'hoje',
      responsavel: 'user',
      dataAbertura: DateTime(2026, 10, 4, 14, 23, 7),
    ));

    expect(ds.caixaAberto, isTrue);
    expect(ds.aberturaCaixaAtual?.id, 'hoje');

    // O caixa de hoje foi fechado (aqui mesmo ou pela rede local).
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f-hoje', aberturaCaixaId: 'hoje'));

    expect(ds.caixaAberto, isFalse,
        reason: 'O órfão de ontem NÃO pode manter o caixa aberto.');
    expect(ds.aberturaCaixaAtual, isNull);
  });

  test('abertura ÓRFÃ também não bloqueia o caixa atual sem responsável', () {
    final ds = DataService();
    // Sem responsável ativo: vale a sessão mais recente.
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'orfa',
      dataAbertura: DateTime(2026, 10, 3, 20, 30, 50),
    ));
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'hoje',
      dataAbertura: DateTime(2026, 10, 4, 14, 23, 7),
    ));
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f-hoje', aberturaCaixaId: 'hoje'));

    expect(ds.caixaAberto, isFalse);
    expect(ds.aberturaCaixaAtual, isNull);
  });

  test('reabrir cria uma sessão NOVA, ignorando o órfão antigo', () {
    final ds = DataService();
    ds.responsavelAtivo = 'user';
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'orfa',
      responsavel: 'user',
      dataAbertura: DateTime(2026, 10, 3, 20, 30, 50),
    ));
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'hoje',
      responsavel: 'user',
      dataAbertura: DateTime(2026, 10, 4, 14, 23, 7),
    ));
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f-hoje', aberturaCaixaId: 'hoje'));
    expect(ds.caixaAberto, isFalse);

    // O operador reabre: sessão nova, mais recente que o órfão.
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'nova',
      responsavel: 'user',
      dataAbertura: DateTime(2026, 10, 4, 15, 0),
    ));

    expect(ds.caixaAberto, isTrue);
    expect(ds.aberturaCaixaAtual?.id, 'nova');
  });

  test('filtro "Meu Caixa" usa a sessão mais recente do operador', () {
    final ds = DataService();
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'orfa',
      responsavel: 'carlos@gmail.com',
      dataAbertura: DateTime(2026, 10, 3, 20, 0),
    ));
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'ultima',
      responsavel: 'carlos@gmail.com',
      dataAbertura: DateTime(2026, 10, 4, 14, 0),
    ));
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f-ultima', aberturaCaixaId: 'ultima'));

    expect(ds.ultimaAberturaDoOperador('carlos@gmail.com')?.id, 'ultima',
        reason: 'O filtro do histórico não pode apontar para a abertura órfã.');
  });

  test('reabrir depois de fechar volta a liberar a venda', () {
    final ds = DataService();
    ds.aberturasCaixa.add(aberturaDeTeste(id: 'a1'));
    ds.fechamentosCaixa
        .add(fechamentoDeTeste(id: 'f1', aberturaCaixaId: 'a1'));
    expect(ds.caixaAberto, isFalse);

    // Nova abertura (o operador reabriu o caixa).
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'a2',
      dataAbertura: DateTime(2026, 10, 4, 12, 0),
    ));

    expect(ds.caixaAberto, isTrue);
    expect(ds.aberturaCaixaAtual?.id, 'a2');
  });

  test('abertura sozinha e sem fechamento conta como aberta', () {
    final ds = DataService();
    ds.aberturasCaixa.add(aberturaDeTeste(
      id: 'antiga',
      dataAbertura: DateTime(2026, 10, 3, 20, 30, 50),
    ));

    expect(ds.caixaAberto, isTrue,
        reason: 'É a única abertura: é a sessão atual e está sem fechamento.');
    expect(ds.aberturaCaixaAtual?.id, 'antiga');
  });
}
