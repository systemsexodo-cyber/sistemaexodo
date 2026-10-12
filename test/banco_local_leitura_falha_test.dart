// Quando o banco local não atende, o app PRECISA saber — e não tratar a falha
// como "não tem dados".
//
// Este teste é isolado de propósito: o `EnvConfig` guarda o `.env` em cache na
// PRIMEIRA leitura, então aqui é escrito um `.env` de teste (com senha errada)
// antes de qualquer leitura, e a pasta atual é trocada para ele. O objetivo não
// é o PostgreSQL recusar a senha em si, e sim provar que a recusa chega até a
// camada de cima (`bancoLocalFalhou` + dica legível) em vez de virar uma lista
// vazia silenciosa.
//
// Rodar: flutter test test/banco_local_leitura_falha_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('leitura com credencial errada vira FALHA VISÍVEL, não lista vazia',
      () async {
    final raiz = await Directory.systemTemp.createTemp('exodo_db_teste_');
    addTearDown(() {
      try {
        raiz.deleteSync(recursive: true);
      } catch (_) {}
    });
    File(p.join(raiz.path, '.env')).writeAsStringSync(
      'DB_HOST=127.0.0.1\n'
      'DB_PORT=5432\n'
      'DB_NAME=exodo_db\n'
      'DB_USER=exodo_user\n'
      'DB_PASSWORD=senha_que_nao_existe_no_banco_local\n',
    );

    final pastaAnterior = Directory.current;
    Directory.current = raiz.path;
    addTearDown(() => Directory.current = pastaAnterior);

    const empresa = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
    final db = DatabaseService();
    db.setEmpresaId(empresa);

    final produtos = await db.carregarLista('empresa_${empresa}_exodo_produtos');

    expect(produtos, isEmpty);
    expect(
      db.bancoLocalFalhou,
      isTrue,
      reason: 'a falha do banco local tem que ficar registrada (senão o sistema '
          'conclui que o banco está vazio e espera a nuvem)',
    );
    expect(
      DatabaseService.dicaDoErroLocal(db.ultimoErroDoBancoLocal),
      contains('SENHA'),
      reason: 'a dica precisa dizer que a senha do .env não confere',
    );
    expect(DatabaseService.falhaDeConexao(db.ultimoErroDoBancoLocal), isTrue,
        reason: 'senha recusada é falha de conexão — vale repetir a leitura');
  },
      // O driver tenta duas vezes, e o PostgreSQL local deste computador pode
      // estar desligado (aí a tentativa custa o timeout do socket).
      timeout: const Timeout(Duration(minutes: 3)));
}
