import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Largura (lógica) abaixo da qual a tela é tratada como "celular".
///
/// É o mesmo limite usado nas páginas (700 px): tudo que é ajuste de toque
/// parte daqui para não haver duas definições brigando.
const double kLarguraCelular = 700.0;

/// True quando a janela é estreita (celular em retrato).
bool ehCelular(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kLarguraCelular;

/// True quando o app está rodando em um aparelho de toque (Android/iOS).
///
/// Usa `defaultTargetPlatform` em vez de `dart:io` para continuar compilando
/// na Web.
bool get sistemaMovel =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Vibração curta de confirmação (seleção de item, troca de aba, abrir tela).
///
/// É o retorno que o dedo espera no celular. Em desktop/Web não faz nada.
Future<void> toqueHaptico() async {
  if (!sistemaMovel) return;
  try {
    await HapticFeedback.selectionClick();
  } catch (_) {
    // Aparelho sem motor de vibração: segue sem feedback.
  }
}

/// Vibração mais firme para ações que mudam algo (salvar, apagar, concluir).
Future<void> toqueHapticoForte() async {
  if (!sistemaMovel) return;
  try {
    await HapticFeedback.mediumImpact();
  } catch (_) {}
}

/// Comportamento de rolagem voltado para o dedo.
///
/// * no celular qualquer área rola (inclusive dentro de diálogos/planilhas);
/// * a rolagem tem a física elástica nativa em vez do "brilho" do Android;
/// * arastar com o mouse/trackpad continua funcionando no PC.
class ExodoScrollBehavior extends MaterialScrollBehavior {
  const ExodoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (ehCelular(context)) {
      // AlwaysScrollable: permite "puxar" a lista mesmo quando ela cabe na
      // tela (é o gesto que o usuário tenta primeiro).
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return super.getScrollPhysics(context);
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Sem o brilho/esticamento colorido do overscroll: atrapalha a leitura da
    // tela no celular e some com o feedback do conteúdo.
    return child;
  }
}

/// Fecha o teclado ao tocar em uma área "vazia" da tela.
///
/// Só entra no celular (ver `main.dart`). Toques em botões e campos continuam
/// chegando ao widget de baixo — o `GestureDetector` só ganha a disputa quando
/// ninguém abaixo tratou o toque.
class ToqueForaFechaTeclado extends StatelessWidget {
  final Widget child;

  const ToqueForaFechaTeclado({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
