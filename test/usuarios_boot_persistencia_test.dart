// O USUÁRIO QUE SUMIA A CADA REINÍCIO DO APP.
//
// Sintoma relatado: o operador cria um usuário, ele aparece na lista e, depois
// de fechar e abrir o app, NÃO está mais lá. A lista sempre voltava aos mesmos
// três (user, carlos, silvio).
//
// Causa: a ordem do boot em `AuthService._carregarDadosSalvos()`. A primeira
// coisa que rodava era `_carregarUsuariosPadrao()` — e ele GRAVA na hora. Como
// durante o boot a memória começa VAZIA, esse save levava só o master "user"
// para `cache_dados.usuarios` e APAGAVA a lista salva. A leitura de usuários só
// acontecia DEPOIS, já lendo a lista mutilada; no fim, `_restaurarUsuariosLocais`
// recriava os três conhecidos. Resultado: todo usuário criado era descartado no
// reinício seguinte.
//
// A correção (a) inverte a ordem — LER primeiro, aplicar os padrões depois — e
// (b) trava `_salvarUsuarios()` enquanto a lista salva não tiver sido lida.
//
// Este teste NÃO usa o PostgreSQL: injeta um armazenamento em memória no
// `AuthService` e roda a MESMA sequência de boot do app
// (`carregarUsuariosNoBoot`), exigindo que a lista salva sobreviva.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Map<String, List<Map<String, dynamic>>> banco;
  var falharGravacao = false;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exodo-usuarios-boot-');
    banco = {};
    falharGravacao = false;
    // O boot só libera a gravação quando o banco local não está marcado como
    // falho. Nada aqui toca o PostgreSQL, então limpamos o sinal para o teste
    // não depender do estado de um banco real.
    DatabaseService().limparFalhaDoBancoLocal();
  });

  tearDown(() => dir.delete(recursive: true));

  LocalStorageService criarStorage() => LocalStorageService(
    emergencyCacheDirectory: dir,
    databaseListWriter: (key, lista, {bool isSync = false}) async {
      if (falharGravacao) throw StateError('Falha simulada de gravação');
      banco[key] = lista
          .map((linha) => Map<String, dynamic>.from(linha))
          .toList();
    },
    databaseListReader: (key) async => (banco[key] ?? [])
        .map((linha) => Map<String, dynamic>.from(linha))
        .toList(),
  );

  Map<String, dynamic> usuario(String id, String email, {String? empresaId}) =>
      {
        'id': id,
        'nome': id,
        'email': email,
        'senha': 'senha-$id',
        'tipo': 'operador',
        'empresa_id': empresaId,
        'ativo': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

  Usuario novoUsuario(String id, String email) => Usuario(
    id: id,
    nome: id,
    email: email,
    senha: 'senha-123',
    tipo: TipoUsuario.operador,
    empresaId: 'E1',
    ativo: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  test('o boot preserva o usuário criado pelo operador', () async {
    final storage = criarStorage();

    // O que está SALVO antes de abrir o app: os 3 usuários de sempre + o que o
    // operador criou. É esta lista que o boot não pode encolher.
    await storage.salvarLista('usuarios', [
      usuario('1', 'user'),
      usuario('carlos', 'carlos'),
      usuario('silvio', 'silvio'),
      usuario('novo-1', 'novo@empresa.com', empresaId: 'E1'),
    ]);

    final auth = AuthService(storage: storage, carregarAutomaticamente: false);
    await auth.carregarUsuariosNoBoot();

    final depois = await storage.carregarLista('usuarios');
    final emails = depois.map((u) => u['email']?.toString()).toList();
    print('usuários salvos depois do boot: $emails');

    expect(
      emails,
      contains('novo@empresa.com'),
      reason: 'o usuário criado pelo operador não pode ser apagado no boot',
    );
    expect(
      depois.length,
      4,
      reason: 'o boot não pode reduzir a lista de usuários já salva',
    );

    // E o app precisa estar com a lista completa em memória.
    expect(
      auth.usuarios.map((u) => u.email).toList(),
      containsAll(<String>['user', 'carlos', 'silvio', 'novo@empresa.com']),
    );
  });

  test('lê permissões do formato legado dados_app do banco', () {
    final legado = Usuario.fromMap({
      'id': 'legado-1',
      'nome': 'Usuário legado',
      'email': 'legado@empresa.com',
      'senha': 'senha-legada',
      'perfil': 'gerente',
      'dados_usuario': '{"empresa_id":"E1"}',
      'dados_app':
          '{"is_master":true,"permissoes_personalizadas":["vendas.editar"],'
          '"permissoes_negadas":["estoque.excluir"],'
          '"telas_ocultas":["relatorios"],"serie_nfce":2}',
      'ativo': true,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    expect(legado.empresaId, 'E1');
    expect(legado.tipo, TipoUsuario.gerente);
    expect(legado.isMaster, isTrue);
    expect(legado.permissoesPersonalizadas, {'vendas.editar'});
    expect(legado.permissoesNegadas, {'estoque.excluir'});
    expect(legado.telasOcultas, ['relatorios']);
    expect(legado.serieNfce, 2);
  });

  test('alterações e permissões ficam salvas e podem ser removidas', () async {
    final storage = criarStorage();
    await storage.salvarLista('usuarios', [
      usuario('1', 'user'),
      usuario('operador-1', 'operador@empresa.com', empresaId: 'E1'),
    ]);
    final auth = AuthService(storage: storage, carregarAutomaticamente: false);
    await auth.carregarUsuariosNoBoot();
    final operador = auth.usuarios.firstWhere((u) => u.id == 'operador-1');

    await auth.atualizarUsuario(
      operador.copyWith(
        nome: 'Operador Atualizado',
        permissoesPersonalizadas: <String>{'vendas.editar'},
        permissoesNegadas: <String>{'estoque.excluir'},
        telasOcultas: <String>['relatorios'],
      ),
    );

    final primeiraLeitura = await storage.carregarLista('usuarios');
    final salvo = Usuario.fromMap(
      primeiraLeitura.firstWhere((u) => u['id'] == 'operador-1'),
    );
    expect(salvo.nome, 'Operador Atualizado');
    expect(salvo.permissoesPersonalizadas, {'vendas.editar'});
    expect(salvo.permissoesNegadas, {'estoque.excluir'});
    expect(salvo.telasOcultas, ['relatorios']);

    final reaberto = AuthService(
      storage: storage,
      carregarAutomaticamente: false,
    );
    await reaberto.carregarUsuariosNoBoot();
    final usuarioReaberto = reaberto.usuarios.firstWhere(
      (u) => u.id == 'operador-1',
    );
    expect(usuarioReaberto.permissoesPersonalizadas, {'vendas.editar'});
    expect(usuarioReaberto.permissoesNegadas, {'estoque.excluir'});
    expect(usuarioReaberto.telasOcultas, ['relatorios']);

    await reaberto.atualizarUsuario(
      usuarioReaberto.copyWith(
        permissoesPersonalizadas: <String>{},
        permissoesNegadas: <String>{},
        telasOcultas: <String>[],
      ),
    );
    final limpos = await storage.carregarLista('usuarios');
    final usuarioLimpo = Usuario.fromMap(
      limpos.firstWhere((u) => u['id'] == 'operador-1'),
    );
    expect(usuarioLimpo.permissoesPersonalizadas, isEmpty);
    expect(usuarioLimpo.permissoesNegadas, isEmpty);
    expect(usuarioLimpo.telasOcultas, isEmpty);
  });

  test(
    'falha de gravação é exibida e a edição não fica falsa em memória',
    () async {
      final storage = criarStorage();
      await storage.salvarLista('usuarios', [
        usuario('1', 'user'),
        usuario('operador-1', 'operador@empresa.com', empresaId: 'E1'),
      ]);
      final auth = AuthService(
        storage: storage,
        carregarAutomaticamente: false,
      );
      await auth.carregarUsuariosNoBoot();
      final operador = auth.usuarios.firstWhere((u) => u.id == 'operador-1');
      falharGravacao = true;

      await expectLater(
        auth.atualizarUsuario(
          operador.copyWith(nome: 'Alteração não persistida'),
        ),
        throwsStateError,
      );

      expect(
        auth.usuarios.firstWhere((u) => u.id == 'operador-1').nome,
        operador.nome,
        reason: 'uma edição não persistida deve ser revertida em memória',
      );
      expect(
        banco['usuarios']!.firstWhere((u) => u['id'] == 'operador-1')['nome'],
        operador.nome,
        reason: 'falha não pode substituir os dados que já estavam salvos',
      );
    },
  );

  test('primeiro boot (nada salvo) cria e persiste o master', () async {
    final storage = criarStorage();
    final auth = AuthService(storage: storage, carregarAutomaticamente: false);
    await auth.carregarUsuariosNoBoot();

    final depois = await storage.carregarLista('usuarios');
    print('primeiro boot gravou: ${depois.map((u) => u['email']).toList()}');

    expect(
      depois.map((u) => u['email']?.toString()),
      contains('user'),
      reason:
          'sem nenhum usuário salvo, o master precisa ser criado e gravado '
          '(senão a gravação ficou bloqueada para sempre)',
    );
  });

  test(
    'gravação antes de ler é bloqueada (a trava que causou a perda)',
    () async {
      final storage = criarStorage();
      await storage.salvarLista('usuarios', [usuario('1', 'user')]);
      final writesAntes = banco['usuarios']!.length;

      // Sem rodar o boot: a lista salva ainda não foi lida nesta sessão.
      final auth = AuthService(
        storage: storage,
        carregarAutomaticamente: false,
      );

      // A operação deve falhar, não aparentar sucesso sem persistir.
      await expectLater(
        auth.adicionarUsuario(novoUsuario('novo-sem-boot', 'novo@empresa.com')),
        throwsStateError,
      );

      final depois = await storage.carregarLista('usuarios');
      expect(
        depois.map((u) => u['email']?.toString()),
        isNot(contains('novo@empresa.com')),
        reason: 'gravar antes de ler sobrescreveria a lista salva',
      );
      expect(
        banco['usuarios']!.length,
        writesAntes,
        reason: 'a lista salva não pode mudar antes de ter sido lida',
      );
    },
  );
}
