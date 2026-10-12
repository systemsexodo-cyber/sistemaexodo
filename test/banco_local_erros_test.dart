// Classificação das falhas do banco local (PostgreSQL do computador).
//
// Por que isto existe: quando a leitura do banco local falha, ela responde
// LISTA VAZIA — igual a uma tabela sem dados. Sem separar as duas coisas, o
// sistema abria as telas esperando a nuvem, mesmo com os dados no PostgreSQL
// local ("entra na empresa vazio e só carrega quando sincroniza com a nuvem").
// Os erros usados aqui são cópias REAIS do crash_db.txt da máquina.
//
// Rodar: flutter test test/banco_local_erros_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  group('falhaDeConexao', () {
    test('reconhece os erros que o app já registrou de verdade', () {
      // Senha recusada no handshake (é o que acontece quando o app não achou o
      // .env e tentou a senha padrão).
      expect(
        DatabaseService.falhaDeConexao(
          'PgException: Severity.error Socket error: FormatException: '
          'Missing extension byte (at offset 10)',
        ),
        isTrue,
      );
      // Servidor travado/ocupado.
      expect(
        DatabaseService.falhaDeConexao(
          'SocketException: Connection timed out, host: 127.0.0.1, port: 5432 '
          '(OS Error: Connection timed out, errno = 10060)',
        ),
        isTrue,
      );
      // Serviço desligado.
      expect(
        DatabaseService.falhaDeConexao(
          'SocketException: Connection refused (OS Error: Connection refused, '
          'errno = 10061)',
        ),
        isTrue,
      );
      // Limite de conexões do PostgreSQL (passa sozinho depois).
      expect(
        DatabaseService.falhaDeConexao(
          'PgException: FATAL: sorry, too many clients already',
        ),
        isTrue,
      );
    });

    test('erro de SQL NÃO é falha de conexão (repetir não adianta)', () {
      expect(
        DatabaseService.falhaDeConexao(
          'PgException: column "perfil_tributario_id" does not exist',
        ),
        isFalse,
      );
      expect(DatabaseService.falhaDeConexao(null), isFalse);
      expect(DatabaseService.falhaDeConexao('lista vazia'), isFalse);
    });
  });

  group('erroTransitorioDoBanco', () {
    test('impasse (40P01) e serialização (40001) valem repetir', () {
      // Cópia REAL do aviso que apareceu no Histórico de Vendas.
      expect(
        DatabaseService.erroTransitorioDoBanco(
          'Severity.unknown 40P01: impasse detectado detail: Processo 7192 '
          'espera por ShareLock em transação 3267261; bloqueado pelo processo '
          '8764. hint: Veja log do servidor.',
        ),
        isTrue,
      );
      expect(
        DatabaseService.erroTransitorioDoBanco(
          'PgException: ERROR: could not serialize access due to concurrent '
          'update (SQLSTATE 40001)',
        ),
        isTrue,
      );
      expect(
        DatabaseService.erroTransitorioDoBanco('PgException: deadlock detected'),
        isTrue,
      );
      expect(
        DatabaseService.erroTransitorioDoBanco(
          'PgException: ERROR: lock not available (SQLSTATE 55P03)',
        ),
        isTrue,
      );
    });

    test('erro de SQL comum NÃO vira repetição', () {
      expect(
        DatabaseService.erroTransitorioDoBanco(
          'PgException: column "perfil_tributario_id" does not exist',
        ),
        isFalse,
      );
      expect(DatabaseService.erroTransitorioDoBanco(null), isFalse);
    });

    test('impasse não é falha de conexão, mas ainda assim é repetível', () {
      const impasse =
          'Severity.unknown 40P01: impasse detectado detail: Processo 7192 '
          'espera por ShareLock em transação 3267261.';
      expect(DatabaseService.falhaDeConexao(impasse), isFalse);
      expect(DatabaseService.erroTransitorioDoBanco(impasse), isTrue);
    });
  });

  group('dicaDoErroLocal', () {
    test('senha recusada aponta o DB_PASSWORD do .env', () {
      final dica = DatabaseService.dicaDoErroLocal(
        'PgException: Severity.error Socket error: FormatException: '
        'Missing extension byte (at offset 10)',
      );
      expect(dica, contains('SENHA'));
      expect(dica, contains('.env'));
    });

    test('conexão recusada manda ligar o serviço do PostgreSQL', () {
      final dica = DatabaseService.dicaDoErroLocal(
        'SocketException: Connection refused (OS Error: Connection refused)',
      );
      expect(dica, contains('DESLIGADO'));
      expect(dica, contains('PostgreSQL'));
    });

    test('timeout fala de conexão travada', () {
      final dica = DatabaseService.dicaDoErroLocal(
        'SocketException: Connection timed out, host: 127.0.0.1, port: 5432',
      );
      expect(dica, contains('não respondeu no tempo esperado'));
    });

    test('erro de SQL cai no texto genérico, sem inventar diagnóstico', () {
      final dica = DatabaseService.dicaDoErroLocal(
        'PgException: column "x" does not exist',
      );
      expect(dica, contains('Falha ao ler o banco local'));
      expect(dica, isNot(contains('SENHA')));
      expect(dica, isNot(contains('DESLIGADO')));
    });
  });

  // Rótulo curto do chip do topo: precisa dizer o MOTIVO em poucas palavras,
  // senão o usuário tem que abrir o tooltip só para saber o que aconteceu.
  group('rotuloCurtoDoErroLocal', () {
    test('cada motivo tem seu próprio rótulo', () {
      expect(
        DatabaseService.rotuloCurtoDoErroLocal(
          'Socket error: FormatException: Missing extension byte',
        ),
        'SENHA DO BANCO LOCAL',
      );
      expect(
        DatabaseService.rotuloCurtoDoErroLocal(
          'SocketException: Connection refused (OS Error: Connection refused)',
        ),
        'BANCO LOCAL DESLIGADO',
      );
      expect(
        DatabaseService.rotuloCurtoDoErroLocal(
          'SocketException: Connection timed out, host: 127.0.0.1',
        ),
        'BANCO LOCAL LENTO',
      );
    });

    test('erro de SQL continua no rótulo genérico', () {
      final rotulo = DatabaseService.rotuloCurtoDoErroLocal(
        'PgException: column "x" does not exist',
      );
      expect(rotulo, 'BANCO LOCAL');
      expect(rotulo, isNot(contains('DESLIGADO')));
      expect(rotulo, isNot(contains('SENHA')));
    });

    test('sem erro anotado também mostra o rótulo genérico', () {
      expect(DatabaseService.rotuloCurtoDoErroLocal(null), 'BANCO LOCAL');
    });
  });

  group('bancoLocalAtendeu', () {
    test('leitura ok (mesmo vazia) é independência', () {
      final db = DatabaseService();
      db.marcarLeituraLocalOkParaTeste();
      expect(db.bancoLocalAtendeu, isTrue);
      expect(db.bancoLocalFalhou, isFalse);
    });

    test('leitura que falhou não atendeu', () {
      final db = DatabaseService();
      db.marcarLeituraLocalFalhouParaTeste('Connection refused');
      expect(db.bancoLocalAtendeu, isFalse);
      expect(db.bancoLocalFalhou, isTrue);
    });
  });
}
