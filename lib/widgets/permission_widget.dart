import 'package:flutter/material.dart';
import '../models/usuario.dart';
import '../models/permissao.dart';
import '../services/permission_service.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

/// Widget que exibe seu conteúdo apenas se o usuário tiver a permissão necessária
class PermissionWidget extends StatelessWidget {
  final TipoPermissao permissao;
  final Widget child;
  final Widget? fallback; // Widget exibido se não tiver permissão

  const PermissionWidget({
    Key? key,
    required this.permissao,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final permissionService = PermissionService();
    final usuario = authService.usuarioAtual;

    final temPermissao = permissionService.temPermissao(usuario, permissao);

    if (temPermissao) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Widget que exibe seu conteúdo apenas se o usuário tiver pelo menos uma das permissões
class PermissionAnyWidget extends StatelessWidget {
  final List<TipoPermissao> permissoes;
  final Widget child;
  final Widget? fallback;

  const PermissionAnyWidget({
    Key? key,
    required this.permissoes,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final permissionService = PermissionService();
    final usuario = authService.usuarioAtual;

    final temPermissao = permissionService.temAlgumaPermissao(usuario, permissoes);

    if (temPermissao) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Widget que exibe seu conteúdo apenas se o usuário tiver todas as permissões
class PermissionAllWidget extends StatelessWidget {
  final List<TipoPermissao> permissoes;
  final Widget child;
  final Widget? fallback;

  const PermissionAllWidget({
    Key? key,
    required this.permissoes,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final permissionService = PermissionService();
    final usuario = authService.usuarioAtual;

    final temPermissao = permissionService.temTodasPermissoes(usuario, permissoes);

    if (temPermissao) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Widget que exibe seu conteúdo apenas se o usuário tiver a permissão por código
class PermissionCodeWidget extends StatelessWidget {
  final String codigoPermissao;
  final Widget child;
  final Widget? fallback;

  const PermissionCodeWidget({
    Key? key,
    required this.codigoPermissao,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final permissionService = PermissionService();
    final usuario = authService.usuarioAtual;

    final temPermissao = permissionService.temPermissaoPorCodigo(usuario, codigoPermissao);

    if (temPermissao) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Helper para verificar permissões em métodos
class PermissionHelper {
  static PermissionService get _permissionService => PermissionService();

  /// Verifica se o usuário tem uma permissão
  static bool temPermissao(Usuario? usuario, TipoPermissao permissao) {
    return _permissionService.temPermissao(usuario, permissao);
  }

  /// Verifica se o usuário tem uma permissão por código
  static bool temPermissaoPorCodigo(Usuario? usuario, String codigoPermissao) {
    return _permissionService.temPermissaoPorCodigo(usuario, codigoPermissao);
  }

  /// Verifica se o usuário tem pelo menos uma das permissões
  static bool temAlgumaPermissao(Usuario? usuario, List<TipoPermissao> permissoes) {
    return _permissionService.temAlgumaPermissao(usuario, permissoes);
  }

  /// Verifica se o usuário tem todas as permissões
  static bool temTodasPermissoes(Usuario? usuario, List<TipoPermissao> permissoes) {
    return _permissionService.temTodasPermissoes(usuario, permissoes);
  }
}





