// Testes do diagnóstico de estouro de layout.
//
// Motivo: o usuário vê tela vermelha ao ajustar o estoque e o log do Flutter
// não diz QUAL widget tem o conteúdo gigante. Este serviço existe para o
// próximo erro já sair no log dizendo o culpado — então o contrato dele é:
//  - devolver `null` quando o erro não é estouro de layout;
//  - apontar o filho gigante (com tamanho e o widget que o criou);
//  - mostrar o caminho até a raiz, com o texto dos `RenderParagraph`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/diagnostico_layout_service.dart';

void main() {
  test('erro que não é estouro de layout não gera relatório', () {
    final details = FlutterErrorDetails(exception: Exception('qualquer coisa'));
    expect(DiagnosticoLayoutService.relatorioDeEstouro(details), isNull);
  });

  testWidgets('relatório aponta o filho gigante e o caminho até a raiz',
      (tester) async {
    FlutterErrorDetails? capturado;
    final anterior = FlutterError.onError;
    FlutterError.onError = (details) => capturado = details;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            width: 200,
            child: Column(
              children: [
                SizedBox(height: 9000, width: 100),
                SizedBox(height: 20, width: 100),
              ],
            ),
          ),
        ),
      ),
    );
    FlutterError.onError = anterior;

    expect(capturado, isNotNull, reason: 'o estouro deveria ser reportado');
    expect(capturado!.exception.toString(), contains('overflow'));

    final relatorio = DiagnosticoLayoutService.relatorioDeEstouro(capturado!);
    expect(relatorio, isNotNull);
    expect(relatorio, contains('DIAGNÓSTICO DO ESTOURO DE LAYOUT'));
    expect(relatorio, contains('eixo: vertical'));
    expect(relatorio, contains('9000.0'), reason: 'o filho gigante é listado');
    expect(relatorio, contains('GIGANTE'));
    expect(relatorio, contains('caminho até a raiz'));
    // O caminho começa no que envolveu o estouro (a Column do nosso exemplo).
    expect(relatorio, contains('Column'));
  });

  testWidgets('relatório mostra o texto do parágrafo que estourou',
      (tester) async {
    FlutterErrorDetails? capturado;
    final anterior = FlutterError.onError;
    FlutterError.onError = (details) => capturado = details;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 30,
            width: 100,
            child: Column(
              children: [
                SizedBox(
                  height: 4000,
                  width: 100,
                  child: Text('ERRO DE SINCRONIZACAO GIGANTE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    FlutterError.onError = anterior;

    final relatorio = DiagnosticoLayoutService.relatorioDeEstouro(capturado!);
    expect(relatorio, isNotNull);
    expect(relatorio, contains('ERRO DE SINCRONIZACAO GIGANTE'),
        reason: 'o texto do parágrafo é o que denuncia o culpado');
  });
}
