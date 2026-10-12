import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Transforma o erro "RenderFlex overflowed" num relatório que diz **qual**
/// widget estourou e **qual filho** é o gigante.
///
/// O log padrão do Flutter, para estouro de layout, mostra só o `creator` do
/// RenderFlex (a correntinha de widgets pais) e para aí: ele não diz qual dos
/// filhos tem 300 mil pixels de altura. Sem isso, achar o culpado num app com
/// centenas de telas vira adivinhação.
///
/// Aqui a gente pega o [FlutterErrorDetails] que o próprio Flutter reportou,
/// encontra o RenderFlex que estourou e conta:
///  - os filhos, com tamanho e o widget que criou cada um (o gigante fica
///    marcado com `<== GIGANTE`);
///  - o caminho até a raiz, incluindo o **texto** dos `RenderParagraph` (é
///    assim que se descobre, por exemplo, que o gigante é um `Text` com um erro
///    enorme dentro de um diálogo).
///
/// Só produz relatório em modo debug — em release o Flutter nem reporta esse
/// erro — e nunca lança: diagnóstico não pode derrubar o app.
class DiagnosticoLayoutService {
  /// A partir deste tamanho (px) um filho é marcado como gigante no relatório.
  static const double alturaSuspeita = 2000;

  static const int _profundidadeMaxima = 6;
  static const int _linhasMaximas = 140;
  static const int _ancestraisMaximos = 40;

  /// Devolve o relatório do estouro, ou `null` quando o erro não é estouro de
  /// layout (aí o log padrão do Flutter já basta).
  static String? relatorioDeEstouro(FlutterErrorDetails details) {
    try {
      final estouro = _renderFlexQueEstourou(details);
      if (estouro == null) return null;

      final linhas = <String>[
        '---- DIAGNÓSTICO DO ESTOURO DE LAYOUT ----',
        '      eixo: ${estouro.direction == Axis.horizontal ? 'horizontal' : 'vertical'}',
        '      tamanho: ${estouro.hasSize ? estouro.size : '(sem tamanho)'} | limites: ${estouro.constraints}',
        '      criado por: ${_quemCriou(estouro)}',
        '      filhos (do maior para o menor; o gigante está marcado):',
      ];
      final filhos = <RenderObject>[];
      _coletarFilhos(estouro, filhos);
      filhos.sort((a, b) => _altura(b).compareTo(_altura(a)));
      for (final filho in filhos.take(20)) {
        linhas.add('        ${_linhaDoFilho(filho)}');
      }
      if (filhos.isEmpty) linhas.add('        (nenhum filho renderizado)');

      linhas.add('      caminho até a raiz:');
      _ancestrais(estouro, linhas);

      // O log não pode virar um romance: corta o excesso (mas avisa que cortou,
      // para não parecer que a árvore terminou ali).
      if (linhas.length > _linhasMaximas) {
        final cortadas = linhas.length - _linhasMaximas;
        linhas.removeRange(_linhasMaximas, linhas.length);
        linhas.add('      ... ($cortadas linha(s) do diagnóstico cortadas)');
      }
      return linhas.join('\n');
    } catch (e) {
      // Diagnóstico não pode virar problema: se falhar, o log normal segue.
      return '---- DIAGNÓSTICO DO ESTOURO falhou: $e ----';
    }
  }

  static RenderFlex? _renderFlexQueEstourou(FlutterErrorDetails details) {
    for (final info in details.informationCollector?.call() ??
        const <DiagnosticsNode>[]) {
      final valor = info.value;
      if (valor is RenderFlex) return valor;
    }
    final excecao = details.exception;
    if (excecao is FlutterError) {
      for (final diagnostico in excecao.diagnostics) {
        final valor = diagnostico.value;
        if (valor is RenderFlex) return valor;
      }
    }
    return null;
  }

  static void _coletarFilhos(
    RenderObject pai,
    List<RenderObject> destino, [
    int nivel = 1,
  ]) {
    if (nivel > _profundidadeMaxima || destino.length >= 60) return;
    pai.visitChildren((filho) {
      destino.add(filho);
      _coletarFilhos(filho, destino, nivel + 1);
    });
  }

  /// Tamanho do objeto, quando ele é uma caixa já medida (`hasSize`/`size`
  /// existem em [RenderBox], não em todo [RenderObject]).
  static Size? _tamanhoDe(RenderObject no) =>
      no is RenderBox && no.hasSize ? no.size : null;

  static double _altura(RenderObject no) => _tamanhoDe(no)?.height ?? 0;

  static String _linhaDoFilho(RenderObject no) {
    final tamanho = _tamanhoDe(no);
    final gigante =
        (tamanho?.height ?? 0) >= alturaSuspeita ? '  <== GIGANTE' : '';
    return '[${tamanho ?? '(sem tamanho)'}] ${no.runtimeType}$gigante'
        '${_textoResumido(no)} — criado por ${_quemCriou(no)}';
  }

  static void _ancestrais(RenderObject no, List<String> linhas) {
    RenderObject? pai = no.parent;
    var voltas = 0;
    while (pai != null && voltas < _ancestraisMaximos) {
      linhas.add(
          '        ${pai.runtimeType}${_textoResumido(pai)} — criado por ${_quemCriou(pai)}');
      pai = pai.parent;
      voltas++;
    }
    if (pai != null) linhas.add('        ... (caminho cortado)');
  }

  /// O texto de um `RenderParagraph`, resumido: é o que denuncia um `Text` com
  /// conteúdo gigante (um erro de sincronização enorme, por exemplo).
  static String _textoResumido(RenderObject no) {
    if (no is! RenderParagraph) return '';
    final texto = no.text.toPlainText().replaceAll('\n', ' ⏎ ').trim();
    if (texto.isEmpty) return '';
    return ' "${texto.length > 90 ? '${texto.substring(0, 90)}…' : texto}"';
  }

  /// O widget que criou este RenderObject (o nome que aparece no código).
  static String _quemCriou(RenderObject no) {
    final criador = no.debugCreator;
    if (criador is DebugCreator) {
      final widget = criador.element.widget;
      final chave = widget.key;
      return '${widget.runtimeType}${chave == null ? '' : ' (key $chave)'}';
    }
    return criador?.toString() ?? 'desconhecido';
  }
}
