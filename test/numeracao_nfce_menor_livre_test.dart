// NUMERAÇÃO DA NFC-e — sempre o MENOR número disponível.
//
// Pedido do caixa: a nota saiu com o número 791252835, um valor que parece
// sorteado — "troque a numeração sempre para menor disponível".
//
// De onde vinha o salto: a sequência era "maior número já emitido + 1" e o
// contador da empresa (`ultimo_numero_nfce`) entrava na conta como piso. Uma vez
// contaminado por um número fora da sequência (o fallback de timestamp do
// bridge), TODA venda seguinte continuava a partir dele — a sequência nunca
// voltava. Agora o número é o menor livre da série, contando como usados todos
// os números já transmitidos (autorizada, pendente, cancelada, inutilizada,
// substituída), e o contador da empresa só decide quando não há NENHUMA nota
// guardada (empresa que veio de outro sistema com a numeração já avançada).
//
// Rodar: flutter test test/numeracao_nfce_menor_livre_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

NFCe _nota(
  String numero, {
  String serie = '1',
  String status = 'autorizada',
  String empresaId = 'E1',
}) =>
    NFCe(
      id: 'id-$serie-$numero',
      numero: numero,
      serie: serie,
      dataEmissao: DateTime(2026, 10, 11),
      empresaId: empresaId,
      itens: const [],
      valorTotal: 22,
      pagamentos: const [],
      status: status,
      createdAt: DateTime(2026, 10, 11),
      updatedAt: DateTime(2026, 10, 11),
    );

Empresa _empresa({String? ultimoNumeroNfce}) => Empresa(
      id: 'E1',
      razaoSocial: 'Loja Teste NFCe',
      slug: 'loja-teste-nfce',
      createdAt: DateTime(2026, 10, 11),
      updatedAt: DateTime(2026, 10, 11),
      configuracoes: ultimoNumeroNfce == null
          ? const {}
          : {'ultimo_numero_nfce': ultimoNumeroNfce},
    );

DataService _dataService({String? ultimoNumeroNfce, List<NFCe> notas = const []}) {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa(ultimoNumeroNfce: ultimoNumeroNfce));
  ds.nfces.addAll(notas);
  return ds;
}

void main() {
  // O DataService abre canais de plataforma no construtor (conexão e áudio);
  // sem o mock, o plugin de áudio derruba o teste com MissingPluginException.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => call.method == 'create' ? 1 : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
  });

  group('menor número livre da série', () {
    test('continua a sequência de onde ela parou', () {
      expect(
        DataService.menorNumeroLivreNfce(numerosUsados: const [1, 2, 3]),
        4,
      );
    });

    test('número sorteado no passado não puxa mais a sequência', () {
      final numero = DataService.menorNumeroLivreNfce(
        numerosUsados: const [1, 2, 3, 791252835],
      );

      expect(numero, 4, reason: 'a numeração volta para logo depois do 3');
      expect(numero, isNot(791252835),
          reason: 'o número transmitido nunca pode sair de novo (rejeição 539)');
    });

    test('buraco na sequência é preenchido (é o menor disponível)', () {
      expect(
        DataService.menorNumeroLivreNfce(numerosUsados: const [1, 3]),
        2,
      );
    });

    test('começa a procurar no primeiro número registrado, não no 1', () {
      expect(
        DataService.menorNumeroLivreNfce(numerosUsados: const [10, 791252835]),
        11,
        reason: 'abaixo do primeiro registro não há evidência: não dá para '
            'voltar ao 1 e arriscar repetir número antigo',
      );
    });

    test('só o número sorteado no banco: volta para o início da série', () {
      expect(
        DataService.menorNumeroLivreNfce(numerosUsados: const [791252835]),
        1,
        reason: 'um salto isolado não é a sequência da loja',
      );
    });

    test('série com número inicial próprio começa nele', () {
      expect(
        DataService.menorNumeroLivreNfce(
          numerosUsados: const [],
          numeroInicial: 5,
        ),
        5,
      );
      expect(
        DataService.menorNumeroLivreNfce(
          numerosUsados: const [5, 6],
          numeroInicial: 5,
        ),
        7,
      );
    });

    test('número inicial inválido vira 1', () {
      expect(
        DataService.menorNumeroLivreNfce(numerosUsados: const [], numeroInicial: 0),
        1,
      );
    });

    test('empresa migrada, sem nota nenhuma, respeita o contador', () {
      expect(
        DataService.menorNumeroLivreNfce(
          numerosUsados: const [],
          ultimoNumeroDaEmpresa: 242,
        ),
        243,
        reason: 'a empresa veio de outro sistema já no 242 — não pode voltar ao 1',
      );
    });

    test('contador inflado é ignorado quando há notas guardadas', () {
      expect(
        DataService.menorNumeroLivreNfce(
          numerosUsados: const [1, 2, 3],
          ultimoNumeroDaEmpresa: 791252834,
        ),
        4,
        reason: 'com notas na mão, quem manda é a lista — não o contador',
      );
    });
  });

  group('conta do DataService', () {
    test('nota sorteada não puxa a próxima venda', () {
      final ds = _dataService(
        ultimoNumeroNfce: '791252835',
        notas: [_nota('791252835'), _nota('10')],
      );

      expect(ds.getProximoNumeroNfce(), 11);
      ds.dispose();
    });

    test('nota cancelada continua contando como usada', () {
      final ds = _dataService(
        notas: [_nota('1'), _nota('2', status: 'cancelada'), _nota('3')],
      );

      expect(ds.getProximoNumeroNfce(), 4);
      ds.dispose();
    });

    test('cada série tem a própria sequência', () {
      final ds = _dataService(
        notas: [_nota('5', serie: '2'), _nota('6', serie: '2')],
      );

      expect(ds.getProximoNumeroNfce(serie: '2'), 7);
      expect(ds.getProximoNumeroNfce(serie: '1'), 1,
          reason: 'a série 1 ainda não emitiu nada');
      ds.dispose();
    });

    test('nota rejeitada/pendente segura o número (não reusa na SEFAZ)', () {
      final ds = _dataService(notas: [_nota('7', status: 'pendente')]);

      expect(ds.getProximoNumeroNfce(), 8);
      ds.dispose();
    });

    test('empresa nova começa no 1', () {
      final ds = _dataService();

      expect(ds.getProximoNumeroNfce(), 1);
      ds.dispose();
    });
  });
}
