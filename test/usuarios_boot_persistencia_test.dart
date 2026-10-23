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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exodo-usuarios-boot-');
    banco = {};
    // O boot só libera a gravação quando o banco local não está marcado como
    // falho. Nada aqui toca o PostgreSQL, então limpamos o sinal para o teste
    // não depender do estado de um banco real.
    DatabaseService().limparFalhaDoBancoLocal();
  });

  tearDown(() => dir.delete(recursive: true));

  LocalStorageService criarStorage() => LocalStorageService(
    emergencyCacheDirectory: dir,
    databaseListWriter: (key, lista, {bool isSync = false}) async {
      banco[key] = lista
          .map((linha) => Map<String, dynamic>.from(linha))
          .toList();
    },
    databaseListReader: (key) async => (banco[key] ?? [])
        .map((linha) => Map<String, dynamic>.from(linha))
        .toList(),
  );

  Map<String, dynamic> usuario(String id, String email, {String? empresaId}) => {
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

  test('gravação antes de ler é bloqueada (a trava que causou a perda)', () async {
    final storage = criarStorage();
    await storage.salvarLista('usuarios', [usuario('1', 'user')]);

    // Sem rodar o boot: a lista salva ainda não foi lida nesta sessão.
    final auth = AuthService(storage: storage, carregarAutomaticamente: false);

    // `adicionarUsuario` grava via `_salvarUsuarios`; com a trava ativa nada é
    // escrito e a lista salva continua intacta.
    await auth.adicionarUsuario(novoUsuario('novo-sem-boot', 'novo@empresa.com'));

    final depois = await storage.carregarLista('usuarios');
    expect(
      depois.map((u) => u['email']?.toString()),
      isNot(contains('novo@empresa.com')),
      reason: 'gravar antes de ler sobrescreveria a lista salva',
    );
    expect(
      depois.length,
      1,
      reason: 'a lista salva não pode mudar antes de ter sido lida',
    );
  });
}
