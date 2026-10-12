// ENTRADA/SAÍDA de estoque pelo cadastro do produto (o diálogo "Ajuste de
// Estoque").
//
// O que este teste trava é o CONTRATO com a tela, que era onde estava o
// problema: quando o movimento não pode ser feito, a tela precisa receber uma
// mensagem que diga o que fazer — antes ela recebia um `Exception: Produto não
// encontrado.` cru, sem ação possível.
//
// Rodar: flutter test test/entrada_estoque_cadastro_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

/// Tira o "Exception: " do texto, como a tela faz antes de mostrar.
String textoDaTela(Object erro) {
  final texto = erro.toString();
  return texto.startsWith('Exception: ') ? texto.substring(11) : texto;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() {
    // O DataService escuta conexão no construtor: sem o canal de teste o
    // construtor explode antes de qualquer asserção.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      // O DataService também cria um AudioPlayer (som de notificação).
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
    }
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockStreamHandler(
          EventChannel(canal), MockStreamHandler.inline(onListen: (args, sink) {}));
    }
  });

  group('movimento de estoque do cadastro recusa com mensagem acionável', () {
    test('produto ainda não salvo (id vazio): manda salvar antes', () async {
      final ds = DataService();
      Object? erro;
      try {
        await ds.ajustarEstoquePontual(
          produtoId: '',
          quantidade: 1,
          entrada: true,
        );
      } catch (e) {
        erro = e;
      }
      expect(erro, isNotNull);
      final texto = textoDaTela(erro!);
      expect(texto, contains('Salve o produto'));
      expect(texto.startsWith('Exception:'), isFalse);
      expect(texto, isNot(equals('Produto não encontrado.')));
    });

    test('produto que não existe em lugar nenhum: diz o que conferir', () async {
      final ds = DataService();
      Object? erro;
      try {
        await ds.ajustarEstoquePontual(
          produtoId: 'PRODUTO-QUE-NAO-EXISTE-123',
          quantidade: 1,
          entrada: true,
        );
      } catch (e) {
        erro = e;
      }
      expect(erro, isNotNull);
      final texto = textoDaTela(erro!);
      expect(texto, contains('lista de Produtos'));
      expect(texto, isNot(equals('Produto não encontrado.')));
    });

    test('quantidade zero ou negativa também tem mensagem clara', () async {
      final ds = DataService();
      Object? erro;
      try {
        await ds.ajustarEstoquePontual(
          produtoId: 'QUALQUER-ID',
          quantidade: 0,
          entrada: true,
        );
      } catch (e) {
        erro = e;
      }
      expect(erro, isNotNull);
      expect(textoDaTela(erro!), 'Informe uma quantidade maior que zero.');
    });
  });
}
