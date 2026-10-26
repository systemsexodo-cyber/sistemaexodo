// Auto-start do PostgreSQL local: o app liga o banco sozinho quando encontra
// "connection refused" (BANCO LOCAL DESLIGADO).
//
// Cenário real: o PC desligou/ serviço parou e o sistema abriu sem os dados
// locais (Fluxo de Caixa vazio). Antes disso a única saída era rodar o
// iniciar_postgres.bat na mão.
//
// Aqui testamos a parte que decide ONDE está o PostgreSQL (pg_ctl + pgdata),
// quando vale tentar de novo (intervalo mínimo) e a sondagem da porta — sem
// ligar nenhum processo de verdade.
//
// Rodar: flutter test test/postgres_local_starter_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/postgres_local_starter.dart';

void main() {
  setUp(PostgresLocalStarter.reiniciarParaTeste);
  tearDown(PostgresLocalStarter.reiniciarParaTeste);

  group('intervalo entre tentativas', () {
    test('a primeira tentativa sempre pode', () {
      expect(PostgresLocalStarter.podeTentar(DateTime(2026, 1, 1)), isTrue);
    });

    test('depois de tentar, só passa o intervalo mínimo', () {
      final agora = DateTime(2026, 1, 1, 12, 0, 0);
      PostgresLocalStarter.marcarTentativa(agora);

      expect(
        PostgresLocalStarter.podeTentar(agora.add(const Duration(seconds: 5))),
        isFalse,
        reason: 'sem intervalo, cada leitura que falha dispararia um start',
      );
      expect(
        PostgresLocalStarter.podeTentar(agora.add(const Duration(seconds: 61))),
        isTrue,
      );
      expect(
        PostgresLocalStarter.intervaloPassou(
          agora,
          agora,
          intervalo: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('onde está o PostgreSQL embarcado', () {
    late Directory raiz;

    setUp(() {
      raiz = Directory.systemTemp.createTempSync('exodo_pg_');
    });

    tearDown(() {
      try {
        raiz.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('acha pg_ctl e pgdata na raiz da instalação', () {
      File(p.join(raiz.path, 'postgresql', 'bin', 'pg_ctl.exe'))
          .createSync(recursive: true);
      File(p.join(raiz.path, 'pgdata', 'postgresql.conf'))
          .createSync(recursive: true);

      expect(
        PostgresLocalStarter.localizarPgCtl([raiz.path]),
        p.joinAll([raiz.path, 'postgresql', 'bin', 'pg_ctl.exe']),
      );
      expect(
        PostgresLocalStarter.localizarDataDir([raiz.path]),
        p.joinAll([raiz.path, 'pgdata']),
      );
    });

    test('NÃO confunde a pasta data do pacote Flutter com o cluster', () {
      // O bundle do Flutter tem "data/" com flutter_assets, mas sem
      // postgresql.conf — nunca pode ser usado como -D do pg_ctl.
      File(p.join(raiz.path, 'data', 'flutter_assets', 'AssetManifest.json'))
          .createSync(recursive: true);

      expect(PostgresLocalStarter.localizarDataDir([raiz.path]), isNull);
    });

    test('sobe os pais a partir da pasta do executável', () {
      final bases = PostgresLocalStarter.basesCandidatos(
        cwd: p.join(raiz.path, 'build', 'windows', 'x64', 'runner', 'Debug'),
        exeDir: p.join(raiz.path, 'outro'),
      );
      expect(bases, contains(raiz.path));
    });
  });

  group('sondagem da porta', () {
    test('true quando o servidor escuta, false quando não há nada', () async {
      final servidor = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final porta = servidor.port;
      try {
        expect(
          await PostgresLocalStarter.portaAberta('127.0.0.1', porta),
          isTrue,
        );
      } finally {
        await servidor.close();
      }

      // Porta recém-fechada: não deve mais aceitar conexão.
      final portaFechada = porta;
      expect(
        await PostgresLocalStarter.portaAberta('127.0.0.1', portaFechada),
        isFalse,
      );
    });
  });

  group('só tenta ligar o banco quando o host é deste computador', () {
    test('reconhece as formas de dizer "aqui mesmo"', () async {
      for (final host in const ['', 'localhost', 'LOCALHOST', '127.0.0.1', '::1']) {
        expect(
          await PostgresLocalStarter.hostEhDesteComputador(host),
          isTrue,
          reason: 'o host "$host" é este computador',
        );
      }
    });

    test('recusa host remoto, inexistente e IP de outra máquina', () async {
      for (final host in const [
        'banco-de-teste.invalid',
        'aws-1-us-west-2.pooler.supabase.com',
        '203.0.113.9',
      ]) {
        expect(
          await PostgresLocalStarter.hostEhDesteComputador(host),
          isFalse,
          reason: 'o host "$host" NÃO é este computador',
        );
      }
    });

    test('não gasta os minutos do start local quando o host não é local',
        () async {
      // Antes desta trava, `tentarIniciar` seguia para o serviço do Windows,
      // o pg_ctl e a espera da porta — até ~2 minutos por tentativa, mesmo com
      // DB_HOST apontando para fora. Agora volta na hora, sem tocar em processo.
      EnvConfig.aplicarOverrides({'DB_HOST': 'banco-de-teste.invalid'});
      addTearDown(EnvConfig.limparOverrides);

      final relogio = Stopwatch()..start();
      final (iniciado, mensagem) = await PostgresLocalStarter.tentarIniciar();
      relogio.stop();

      expect(iniciado, isFalse);
      expect(mensagem, contains('não é este computador'));
      expect(
        relogio.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'nem tentar deve ser rápido quando o host é remoto',
      );
    });
  });
}
