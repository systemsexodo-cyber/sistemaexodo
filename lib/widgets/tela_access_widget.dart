import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tela_sistema.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import '../services/auth_service.dart';
import '../services/tela_access_service.dart';

/// Widget que só renderiza seu filho se o usuário atual tiver acesso à tela especificada
class TelaAccessWidget extends StatelessWidget {
  final TelaSistema tela;
  final Widget child;
  final Widget? fallback; // Widget a ser mostrado se não tiver acesso

  const TelaAccessWidget({
    super.key,
    required this.tela,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuario = authService.usuarioAtual;
    final empresa = authService.empresaAtual;

    if (TelaAccessService.podeAcessarTela(usuario, empresa, tela)) {
      return child;
    } else {
      return fallback ?? const SizedBox.shrink();
    }
  }
}

/// Widget que só renderiza seu filho se o usuário atual tiver acesso a PELO MENOS UMA das telas especificadas
class TelaAccessAnyWidget extends StatelessWidget {
  final List<TelaSistema> telas;
  final Widget child;
  final Widget? fallback;

  const TelaAccessAnyWidget({
    super.key,
    required this.telas,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuario = authService.usuarioAtual;
    final empresa = authService.empresaAtual;

    final temAcesso = telas.any(
      (tela) => TelaAccessService.podeAcessarTela(usuario, empresa, tela),
    );

    if (temAcesso) {
      return child;
    } else {
      return fallback ?? const SizedBox.shrink();
    }
  }
}

/// Classe helper para verificar acesso às telas em qualquer lugar do código
class TelaAccessHelper {
  static bool podeAcessarTela(
    Usuario? usuario,
    Empresa? empresa,
    TelaSistema tela,
  ) {
    return TelaAccessService.podeAcessarTela(usuario, empresa, tela);
  }

  static bool podeAcessarTelaPorCodigo(
    Usuario? usuario,
    Empresa? empresa,
    String codigoTela,
  ) {
    return TelaAccessService.podeAcessarTelaPorCodigo(usuario, empresa, codigoTela);
  }
}

