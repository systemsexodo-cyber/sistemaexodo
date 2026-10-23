// CADA EMPRESA TEM O SEU PRÓPRIO USUÁRIO MASTER.
//
// Antes existia UM único usuário "user" (sem empresa) que enxergava todas as
// empresas e era reaproveitado em todas — o que fazia dados ligados ao usuário
// (responsável do caixa, numeração, permissões) atravessarem as empresas.
//
// Agora: a conta de suporte GLOBAL ("user" sem empresa) continua existindo para
// o login e para enxergar todas, mas CADA empresa ganha o seu próprio master
// "user" (vinculado ao empresaId dela), criado quando a empresa é criada e
// garantido ao carregar as empresas já existentes.
//
// Roda sem PostgreSQL: injeta um armazenamento em memória no AuthService.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Map<String, List<Map<String, dynamic>>> banco;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('exodo-master-empresa-');
    banco = {};
    // A gravação de usuários só é liberada quando o banco local não está
    // marcado como falho (o boot faz essa marcação). Zera para o teste não
    // depender do estado de um banco real.
    DatabaseService().limparFalhaDoBancoLocal();
  });

  // A pasta de emergência pode ficar com o arquivo em uso no Windows; a
  // limpeza do temporário não pode derrubar o teste.
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

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

  Map<String, dynamic> usuarioGlobal() => {
    'id': '1',
    'nome': 'Usuário',
    'email': 'user',
    'senha': 'kP4#%vMJ',
    'tipo': 'administrador',
    'empresa_id': null,
    'is_master': true,
    'ativo': true,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  Map<String, dynamic> empresa(String id, String nome) => {
    'id': id,
    'razao_social': nome,
    'nome_fantasia': nome,
    'ativo': true,
  };

  test('cada empresa ganha o seu master "user" ao carregar as empresas',
      () async {
    final storage = criarStorage();
    await storage.salvarLista('usuarios', [usuarioGlobal()]);
    await storage.salvarLista('empresas', [
      empresa('E1', 'Empresa Um'),
      empresa('E2', 'Empresa Dois'),
    ]);

    final auth = AuthService(storage: storage, carregarAutomaticamente: false);
    await auth.carregarUsuariosNoBoot();
    // A leitura da mensalidade local pode tocar o banco real; o que importa é
    // que o master de cada empresa é garantido no `finally` de carregarEmpresas.
    try {
      await auth.carregarEmpresas();
    } catch (_) {}

    final masters = auth.usuarios
        .where((u) => u.email.toLowerCase() == 'user')
        .toList();

    final globais = masters
        .where((u) => u.empresaId == null || u.empresaId!.isEmpty)
        .toList();
    expect(
      globais.length,
      1,
      reason: 'precisa existir UMA conta de suporte global (sem empresa)',
    );

    expect(
      masters.any((u) => u.empresaId == 'E1'),
      isTrue,
      reason: 'a empresa E1 precisa ter o seu próprio usuário "user"',
    );
    expect(
      masters.any((u) => u.empresaId == 'E2'),
      isTrue,
      reason: 'a empresa E2 precisa ter o seu próprio usuário "user"',
    );

    expect(
      auth.getUsuariosDaEmpresa('E1').any((u) => u.email == 'user'),
      isTrue,
    );
    expect(
      auth.getUsuariosDaEmpresa('E2').any((u) => u.email == 'user'),
      isTrue,
    );

    // E precisa ter sido PERSISTIDO (não só em memória).
    final salvos = await storage.carregarLista('usuarios');
    expect(
      salvos.any((u) => u['email'] == 'user' && u['empresa_id'] == 'E1'),
      isTrue,
      reason: 'o master da E1 precisa ser gravado no banco local',
    );
    expect(
      salvos.any((u) => u['email'] == 'user' && u['empresa_id'] == 'E2'),
      isTrue,
      reason: 'o master da E2 precisa ser gravado no banco local',
    );
  });
}
