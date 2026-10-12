import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/database_service.dart';

/// Migrações de schema versionadas (scripts/migrations).
///
/// O que importa aqui é a REGRA que decide quais arquivos rodam e em que ordem:
/// é ela que garante que uma instalação antiga receba o schema novo quando o
/// instalador é atualizado.
void main() {
  group('versaoDoArquivoMigracao', () {
    test('lê a versão do prefixo numérico', () {
      expect(DatabaseService.versaoDoArquivoMigracao('005_ajustes.sql'), 5);
      expect(DatabaseService.versaoDoArquivoMigracao('012_converter.sql'), 12);
    });

    test('ignora arquivo sem prefixo numérico', () {
      expect(DatabaseService.versaoDoArquivoMigracao('README.md'), isNull);
      expect(DatabaseService.versaoDoArquivoMigracao('ajustes.sql'), isNull);
    });
  });

  group('ordenação dos arquivos de migração', () {
    test('ordena por número, não por texto (005 antes de 010)', () {
      final nomes = [
        '010_remover_tabelas_fantasma.sql',
        '005_ajustes_estoque_lote.sql',
        '009_sessao_exclusiva_usuario.sql',
      ];
      final versoes = nomes
          .map(DatabaseService.versaoDoArquivoMigracao)
          .whereType<int>()
          .toList()
        ..sort();
      expect(versoes, [5, 9, 10]);
    });
  });

  group('pasta real scripts/migrations', () {
    test('existe e tem os arquivos esperados nesta versão do projeto', () {
      // Roda do diretório do projeto (flutter test), então o caminho relativo
      // aponta para o repositório.
      final dir = Directory(p.join('scripts', 'migrations'));
      expect(dir.existsSync(), isTrue,
          reason: 'scripts/migrations deve existir (fonte única das migrações)');

      final versoes = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.sql'))
          .map((f) => DatabaseService.versaoDoArquivoMigracao(f.path))
          .whereType<int>()
          .toList()
        ..sort();

      expect(versoes, contains(5),
          reason: 'a migração do ajustes_estoque_lote (local + nuvem) precisa estar aqui');
      expect(versoes.toSet().length, versoes.length,
          reason: 'não pode haver duas migrações com a mesma versão');
    });
  });
}
