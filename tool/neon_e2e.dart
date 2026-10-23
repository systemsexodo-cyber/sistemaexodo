import 'dart:io';

import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/neon_service.dart';

/// Prova de ponta a ponta dos serviços do Neon usando o MESMO código que o
/// aplicativo usa (`lib/services/neon_service.dart`).
///
/// Rode na raiz do projeto:
///
///   dart run tool/neon_e2e.dart
///
/// Sai com código 0 quando todos os serviços configurados respondem.
Future<void> main() async {
  stdout.writeln('=' * 72);
  stdout.writeln('Neon E2E — arquivo de credenciais: ${NeonConfig.nomeArquivo}');
  stdout.writeln(
    'Serviços configurados: '
    '${NeonConfig.servicosConfigurados.isEmpty ? "(nenhum)" : NeonConfig.servicosConfigurados.join(", ")}',
  );
  stdout.writeln('=' * 72);

  if (!NeonConfig.configurado) {
    stderr.writeln(
      'Nenhuma credencial do Neon encontrada. Rode:\n'
      '  neon env pull --file ${NeonConfig.nomeArquivo}',
    );
    exit(2);
  }

  final resultados = await NeonService.testarTudo();
  for (final r in resultados) {
    stdout.writeln(r);
  }

  stdout.writeln('-' * 72);
  stdout.writeln('Dados migrados (lidos pelo código do app):');
  try {
    final conn = await NeonService.abrirConexao();
    try {
      for (final t in const ['empresas', 'usuarios', 'produtos', 'clientes', 'nfces', 'pedidos']) {
        final r = await conn.execute('SELECT count(*) FROM $t');
        stdout.writeln('  $t = ${r.first.first}');
      }
    } finally {
      await conn.close();
    }
  } catch (e) {
    stdout.writeln('  FALHA: $e');
  }

  stdout.writeln('=' * 72);
  final falhas = resultados.where((r) => !r.ok).toList();
  stdout.writeln(
    'resumo: ${resultados.length - falhas.length}/${resultados.length} OK',
  );
  exit(falhas.isEmpty ? 0 : 1);
}
