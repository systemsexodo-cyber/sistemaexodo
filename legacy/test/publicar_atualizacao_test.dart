// Testes da PUBLICAÇÃO de atualização pela nuvem.
//
// O que está travado aqui — cada item é um defeito que existia antes:
//
//   1. o registro mandado para a `bridge_config` só tem colunas que existem lá
//      (id, version, download_url). Mandar 'ativo' fazia o PostgREST recusar o
//      registro inteiro (PGRST204) e NENHUMA publicação funcionava;
//   2. o pacote é gravado por VERSÃO (nome com a versão), então publicar para
//      uma empresa não troca o arquivo que outra já baixou;
//   3. o pacote leva o que realmente muda o programa (`data/app.so` +
//      flutter_assets + executável) — o `.exe` sozinho é só o runner do Flutter;
//   4. pacote cortado, que não é zip, ou sem `data/app.so` é RECUSADO antes de
//      encostar na instalação;
//   5. o destino de cada empresa vira um registro `app_update_<id>` próprio, e
//      a comparação de versões é numérica (1.0.9 < 1.0.10) e entende o '!' de
//      publicação forçada.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

/// Bytes que não comprimem (senão o zip de teste fica pequeno demais para
/// passar pela trava de tamanho mínimo).
List<int> _aleatorios(int quantidade) {
  final saida = List<int>.filled(quantidade, 0);
  var x = 987654321;
  for (var i = 0; i < quantidade; i++) {
    x = (1103515245 * x + 12345) & 0x7fffffff;
    saida[i] = (x >> 16) & 0xff;
  }
  return saida;
}

Future<String> _criarZip(
  Directory pasta,
  String nome,
  Map<String, List<int>> arquivos,
) async {
  final caminho = p.join(pasta.path, nome);
  final encoder = ZipFileEncoder();
  encoder.create(caminho);
  for (final entrada in arquivos.entries) {
    final arquivo = File(p.join(pasta.path, '_tmp_${entrada.key.replaceAll('/', '_')}'));
    await arquivo.writeAsBytes(entrada.value);
    await encoder.addFile(arquivo, entrada.key);
  }
  await encoder.close();
  return caminho;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  HttpOverrides.global = null;

  group('registro da publicação (bridge_config)', () {
    test('manda SÓ as colunas que existem na tabela', () {
      final registro = AppUpdateService.registroDaPublicacao(
        configId: 'app_update_empresa-a',
        versao: '1.0.37',
        url: 'https://exemplo/atualizacoes/sistema_exodo_novo_1.0.37.zip',
      );
      expect(registro.keys.toSet(), {'id', 'version', 'download_url'});
      // 'ativo' NÃO existe na bridge_config: era ele que fazia o PostgREST
      // recusar o registro e a publicação não acontecer.
      expect(registro.containsKey('ativo'), isFalse);
      expect(registro['id'], 'app_update_empresa-a');
      expect(registro['version'], '1.0.37');
    });

    test('cada destino tem o seu id', () {
      expect(AppUpdateService.idConfigDoDestino(null), 'app_latest');
      expect(AppUpdateService.idConfigDoDestino(''), 'app_latest');
      expect(AppUpdateService.idConfigDoDestino('empresa-a'),
          'app_update_empresa-a');
    });
  });

  group('nome do pacote na nuvem', () {
    test('carrega a versão no nome (um arquivo por versão)', () {
      expect(AppUpdateService.nomePacoteDaVersao('1.0.37'),
          'sistema_exodo_novo_1.0.37.zip');
      // nunca o nome antigo, que era compartilhado por todas as versões
      expect(AppUpdateService.nomePacoteDaVersao('1.0.37'),
          isNot('sistema_exodo_novo.exe'));
    });

    test('limpa o que estragaria a URL e a versão forçada', () {
      expect(AppUpdateService.nomePacoteDaVersao('!1.0.37'),
          'sistema_exodo_novo_1.0.37.zip');
      expect(AppUpdateService.nomePacoteDaVersao('1.0.37 beta/2'),
          'sistema_exodo_novo_1.0.37_beta_2.zip');
      expect(AppUpdateService.nomePacoteDaVersao('   '),
          'sistema_exodo_novo_sem_versao.zip');
    });

    test('versões diferentes nunca caem no mesmo arquivo', () {
      expect(AppUpdateService.nomePacoteDaVersao('1.0.37'),
          isNot(AppUpdateService.nomePacoteDaVersao('1.0.38')));
    });
  });

  group('comparação de versão', () {
    test('só atualiza quando a da nuvem é maior', () {
      expect(AppUpdateService.deveAtualizar('1.0.36', '1.0.37'), isTrue);
      expect(AppUpdateService.deveAtualizar('1.0.36', '1.0.36'), isFalse);
      expect(AppUpdateService.deveAtualizar('1.0.36', '1.0.35'), isFalse);
    });

    test('compara número, não texto (1.0.9 é MENOR que 1.0.10)', () {
      expect(AppUpdateService.deveAtualizar('1.0.9', '1.0.10'), isTrue);
      expect(AppUpdateService.deveAtualizar('1.0.10', '1.0.9'), isFalse);
    });

    test("'!' força a atualização mesmo para quem está na frente", () {
      expect(AppUpdateService.deveAtualizar('1.0.40', '!1.0.37'), isTrue);
      expect(AppUpdateService.deveAtualizar('1.0.37', '!1.0.37'), isTrue);
    });
  });

  group('leitura do que está publicado', () {
    test('separa a global das direcionadas e ignora o resto da tabela', () {
      final publicacoes = AppUpdateService.interpretarPublicacoes([
        {
          'id': 'latest',
          'version': '1.0.0',
          'download_url': 'https://exemplo/bridge.exe',
        },
        {
          'id': 'sync_latest',
          'version': '1.0.0',
          'download_url': 'https://exemplo/sync.exe',
        },
        {
          'id': 'app_latest',
          'version': '1.0.38',
          'download_url': 'https://exemplo/g.zip',
          'updated_at': '2026-09-23T10:00:00Z',
        },
        {
          'id': 'app_update_empresa-a',
          'version': '!1.0.37',
          'download_url': 'https://exemplo/a.zip',
        },
      ]);

      expect(publicacoes.length, 2);
      // a global vem primeiro: é ela que vale para quem não tem direcionamento
      expect(publicacoes.first.global, isTrue);
      expect(publicacoes.first.versao, '1.0.38');
      expect(publicacoes.first.forcada, isFalse);
      expect(publicacoes.first.atualizadoEm, isNotNull);

      final daEmpresa = publicacoes.last;
      expect(daEmpresa.global, isFalse);
      expect(daEmpresa.empresaId, 'empresa-a');
      expect(daEmpresa.versao, '1.0.37');
      expect(daEmpresa.forcada, isTrue);
    });

    test('aguenta linha sem versão e sem link (registro antigo)', () {
      final publicacoes = AppUpdateService.interpretarPublicacoes([
        {'id': 'app_latest', 'version': '1.0.15', 'download_url': ''},
      ]);
      expect(publicacoes.single.versao, '1.0.15');
      expect(publicacoes.single.url, isEmpty);
    });
  });

  group('trava do pacote baixado', () {
    late Directory pasta;

    setUp(() async {
      pasta = await Directory.systemTemp.createTemp('exodo_pacote_teste_');
    });

    tearDown(() {
      if (pasta.existsSync()) pasta.deleteSync(recursive: true);
    });

    test('recusa o que não é zip (página de erro salva como arquivo)', () async {
      expect(AppUpdateService.pacotePareceZip([0x3C, 0x68, 0x74, 0x6D]),
          isFalse); // "<htm"
      final caminho = p.join(pasta.path, 'atualizacao_pendente.zip');
      await File(caminho).writeAsBytes(List<int>.filled(1200 * 1024, 0x3C));

      final (ok, mensagem) = await AppUpdateService.prepararPacoteBaixado(
          caminho, p.join(pasta.path, 'atualizacao_pendente'));

      expect(ok, isFalse);
      expect(mensagem, contains('zip'));
      expect(Directory(p.join(pasta.path, 'atualizacao_pendente')).existsSync(),
          isFalse);
    });

    test('recusa download cortado', () async {
      final caminho = p.join(pasta.path, 'cortado.zip');
      await File(caminho).writeAsBytes(List<int>.filled(400, 0x50));

      final (ok, mensagem) = await AppUpdateService.prepararPacoteBaixado(
          caminho, p.join(pasta.path, 'staging'));

      expect(ok, isFalse);
      expect(mensagem, contains('incompleto'));
    });

    test('recusa zip sem o data/app.so (só o .exe não atualiza nada)', () async {
      final zip = await _criarZip(pasta, 'so_exe.zip', {
        'sistema_exodo_novo.exe': _aleatorios(1300 * 1024),
      });

      final (ok, mensagem) = await AppUpdateService.prepararPacoteBaixado(
          zip, p.join(pasta.path, 'staging'));

      expect(ok, isFalse);
      expect(mensagem, contains('data/app.so'));
    });

    test('aceita e extrai o pacote completo', () async {
      final zip = await _criarZip(pasta, 'bom.zip', {
        'data/app.so': _aleatorios(1300 * 1024),
        'data/flutter_assets/AssetManifest.json': List<int>.filled(20, 0x7B),
      });
      final staging = p.join(pasta.path, 'staging');

      final (ok, mensagem) =
          await AppUpdateService.prepararPacoteBaixado(zip, staging);

      expect(ok, isTrue, reason: mensagem);
      expect(File(p.join(staging, 'data', 'app.so')).existsSync(), isTrue);
      expect(
          File(p.join(staging, 'data', 'flutter_assets', 'AssetManifest.json'))
              .existsSync(),
        isTrue,
      );
    });
  });

  group('pacote que vai subir', () {
    late Directory pasta;

    setUp(() async {
      pasta = await Directory.systemTemp.createTemp('exodo_release_teste_');
      await Directory(p.join(pasta.path, 'data', 'flutter_assets'))
          .create(recursive: true);
      await File(p.join(pasta.path, 'data', 'app.so'))
          .writeAsBytes(_aleatorios(64 * 1024));
      await File(p.join(pasta.path, 'data', 'flutter_assets', 'AssetManifest.json'))
          .writeAsString('{}');
      await File(p.join(pasta.path, 'sistema_exodo_novo.exe'))
          .writeAsBytes(List<int>.filled(85 * 1024, 0x4D));
    });

    tearDown(() {
      if (pasta.existsSync()) pasta.deleteSync(recursive: true);
    });

    test('monta o pacote com o programa, as telas e o executável', () async {
      final pacote =
          await AppUpdateService.empacotarAtualizacao(pasta: pasta.path);

      expect(pacote, isNotNull);
      expect(pacote!.conteudo,
          containsAll(['data/app.so', 'data/flutter_assets', 'sistema_exodo_novo.exe']));
      expect(pacote.bytes, greaterThan(0));

      // O zip de verdade tem os três — e o app.so é o que atualiza o programa.
      final arquivo = ZipDecoder().decodeBytes(
          await File(pacote.caminho).readAsBytes());
      final nomes = arquivo.files.map((f) => f.name).toList();
      expect(nomes, contains('data/app.so'));
      expect(nomes, contains('sistema_exodo_novo.exe'));
      expect(nomes, contains('data/flutter_assets/AssetManifest.json'));

      File(pacote.caminho).deleteSync();
    });

    test('sem programa compilado não inventa pacote', () async {
      final vazia = await Directory.systemTemp.createTemp('exodo_vazio_');
      expect(await AppUpdateService.empacotarAtualizacao(pasta: vazia.path),
          isNull);
      vazia.deleteSync(recursive: true);
    });
  });

  group('gerar versão (numeração automática)', () {
    test('numera a próxima versão em cada tipo', () {
      expect(AppUpdateService.proximaVersao('1.0.36', TipoIncrementoVersao.correcao),
          '1.0.37');
      expect(AppUpdateService.proximaVersao('1.0.36', TipoIncrementoVersao.versaoNova),
          '1.1.0');
      expect(AppUpdateService.proximaVersao('1.0.36', TipoIncrementoVersao.versaoGrande),
          '2.0.0');
      // sem texto para número errado; e sem "9.10" virando "9.1"
      expect(AppUpdateService.proximaVersao('1.9.9', TipoIncrementoVersao.correcao),
          '1.9.10');
      expect(AppUpdateService.proximaVersao('!1.0.36', TipoIncrementoVersao.correcao),
          '1.0.37');
      expect(AppUpdateService.proximaVersao('', TipoIncrementoVersao.correcao),
          '0.0.1');
      expect(AppUpdateService.proximaVersao('abc', TipoIncrementoVersao.versaoNova),
          '0.1.0');
      expect(AppUpdateService.proximaVersao('1.2', TipoIncrementoVersao.correcao),
          '1.2.1');
    });

    test('os detalhes ficam ao lado do pacote da MESMA versão', () {
      expect(AppUpdateService.nomeNotasDaVersao('1.0.37'),
          'sistema_exodo_novo_1.0.37.notas.txt');
      expect(
        AppUpdateService.nomeNotasDaVersao('1.0.37').replaceAll('.notas.txt', '.zip'),
        AppUpdateService.nomePacoteDaVersao('1.0.37'),
      );
    });

    test('monta o endereço dos detalhes a partir do pacote', () {
      const pacote = 'https://x.supabase.co/storage/v1/object/public/'
          'atualizacoes/sistema_exodo_novo_1.0.37.zip';
      expect(
        AppUpdateService.urlDasNotas(pacote),
        'https://x.supabase.co/storage/v1/object/public/'
        'atualizacoes/sistema_exodo_novo_1.0.37.notas.txt',
      );
      // link antigo (.exe) não tem detalhes ao lado
      expect(AppUpdateService.urlDasNotas('https://x/sistema_exodo_novo.exe'),
          isNull);
      expect(AppUpdateService.urlDasNotas(''), isNull);
    });

    test('histórico guarda versão, data, destino e detalhes', () {
      final entrada = AppUpdateService.entradaDoHistorico(
        versao: '1.0.37',
        detalhes: 'Corrige o caixa\nAjusta o estoque',
        destino: 'TODOS os clientes',
        quando: DateTime(2026, 9, 23, 10, 52),
      );
      expect(entrada, contains('## 1.0.37 — 23/09/2026 10:52'));
      expect(entrada, contains('- destino: TODOS os clientes'));
      expect(entrada, contains('- Corrige o caixa'));
      expect(entrada, contains('- Ajusta o estoque'));

      final semDetalhes = AppUpdateService.entradaDoHistorico(
        versao: '1.0.38',
        detalhes: '   ',
        destino: 'empresas: BMJ',
        quando: DateTime(2026, 9, 24, 8, 5),
      );
      expect(semDetalhes, contains('(sem detalhes informados)'));
    });

    test('lê e grava a versão no código sem estragar o arquivo', () async {
      final pasta = await Directory.systemTemp.createTemp('exodo_projeto_');
      final arquivo =
          File(p.join(pasta.path, 'lib', 'services', 'app_update_service.dart'));
      await arquivo.create(recursive: true);
      await arquivo.writeAsString('class AppUpdateService {\n'
          '  static const String currentAppVersion = "1.0.36";\n'
          '}\n');

      expect(await AppUpdateService.lerVersaoDoCodigo(pasta.path), '1.0.36');

      final (ok, mensagem) =
          await AppUpdateService.gravarVersaoNoCodigo(pasta.path, '1.0.37');
      expect(ok, isTrue, reason: mensagem);
      final conteudo = await arquivo.readAsString();
      expect(conteudo, contains('currentAppVersion = "1.0.37"'));
      expect(conteudo, contains('class AppUpdateService {'));
      expect(await AppUpdateService.lerVersaoDoCodigo(pasta.path), '1.0.37');

      // versão inválida não encosta no arquivo
      final (invalida, motivo) =
          await AppUpdateService.gravarVersaoNoCodigo(pasta.path, 'duas casas');
      expect(invalida, isFalse);
      expect(motivo, contains('inválida'));
      expect(await AppUpdateService.lerVersaoDoCodigo(pasta.path), '1.0.37');

      // pasta sem o arquivo: diz onde procurou, não explode
      final vazia = await Directory.systemTemp.createTemp('exodo_sem_codigo_');
      expect(await AppUpdateService.lerVersaoDoCodigo(vazia.path), isNull);
      final (semArquivo, _) =
          await AppUpdateService.gravarVersaoNoCodigo(vazia.path, '1.0.37');
      expect(semArquivo, isFalse);

      pasta.deleteSync(recursive: true);
      vazia.deleteSync(recursive: true);
    });

    test('este projeto tem a linha da versão no formato esperado', () async {
      final versao =
          await AppUpdateService.lerVersaoDoCodigo(Directory.current.path);
      expect(versao, isNotNull,
          reason: 'o assistente depende de "currentAppVersion = \"x.y.z\""');
      expect(versao, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });
  });

  group('escolher a versão na hora de publicar', () {
    test('o nome do pacote diz a versão — e o que NÃO é pacote é ignorado',
        () {
      expect(AppUpdateService.versaoDoNomeDoPacote('sistema_exodo_novo_1.0.37.zip'),
          '1.0.37');
      expect(
          AppUpdateService.versaoDoNomeDoPacote('sistema_exodo_novo_1.2.3.4.zip'),
          '1.2.3.4');
      expect(AppUpdateService.versaoDoNomeDoPacote(' sistema_exodo_novo_2.0.0.zip '),
          '2.0.0');
      // Os detalhes da versão ficam ao lado do pacote: não são pacote.
      expect(
          AppUpdateService.versaoDoNomeDoPacote(
              'sistema_exodo_novo_1.0.37.notas.txt'),
          isNull);
      expect(AppUpdateService.versaoDoNomeDoPacote('sistema_exodo_novo.exe'),
          isNull);
      expect(AppUpdateService.versaoDoNomeDoPacote('sistema_exodo_novo_v1.zip'),
          isNull);
      expect(AppUpdateService.versaoDoNomeDoPacote('outro_1.0.37.zip'), isNull);
      expect(AppUpdateService.versaoDoNomeDoPacote(''), isNull);
    });

    test('ida e volta: nome do pacote ↔ versão', () {
      for (final versao in ['1.0.9', '1.0.10', '2.0.0', '1.2.3.4']) {
        expect(
          AppUpdateService.versaoDoNomeDoPacote(
              AppUpdateService.nomePacoteDaVersao(versao)),
          versao,
        );
      }
    });

    test('compara versão pelo NÚMERO (1.0.10 é maior que 1.0.9)', () {
      expect(AppUpdateService.compararVersoes('1.0.10', '1.0.9'), greaterThan(0));
      expect(AppUpdateService.compararVersoes('1.0.9', '1.0.10'), lessThan(0));
      expect(AppUpdateService.compararVersoes('1.0.37', '1.0.37'), 0);
      // '!' é marca de publicação forçada, não faz parte do número.
      expect(AppUpdateService.compararVersoes('!1.1.0', '1.0.37'), greaterThan(0));
      expect(AppUpdateService.compararVersoes('1.0', '1.0.0'), 0);
    });

    test('a numeração automática parte da MAIOR versão conhecida', () {
      // O código está atrás do que já foi publicado: publicar 1.0.38 de novo
      // seria repetir um número que já existe na nuvem.
      final base = AppUpdateService.maiorVersao(['1.0.36', '1.0.41', '1.0.40']);
      expect(base, '1.0.41');
      expect(AppUpdateService.proximaVersao(base, TipoIncrementoVersao.correcao),
          '1.0.42');
      expect(
          AppUpdateService.proximaVersao(base, TipoIncrementoVersao.versaoNova),
          '1.1.0');
      expect(
          AppUpdateService.proximaVersao(base, TipoIncrementoVersao.versaoGrande),
          '2.0.0');

      expect(AppUpdateService.maiorVersao([]), '');
      expect(AppUpdateService.maiorVersao(['  ', '']), '');
      expect(AppUpdateService.maiorVersao(['1.0.9', '']), '1.0.9');
    });

    test('lê os pacotes que já estão na nuvem (da mais nova para a mais antiga)',
        () {
      final versoes = AppUpdateService.interpretarVersoesNaNuvem([
        {
          'name': 'sistema_exodo_novo_1.0.36.zip',
          'metadata': {'size': 10485760},
          'updated_at': '2026-09-21T09:00:00.000Z',
        },
        // mesmas notas da 1.0.36: não é pacote
        {
          'name': 'sistema_exodo_novo_1.0.36.notas.txt',
          'metadata': {'size': 100},
          'updated_at': '2026-09-21T09:01:00.000Z',
        },
        {
          'name': 'sistema_exodo_novo_1.0.37.zip',
          'metadata': {'size': 12582912},
          'updated_at': '2026-09-22T10:00:00.000Z',
        },
        // pacote velho (o exe que era publicado antes): fora da lista
        {
          'name': 'sistema_exodo_novo.exe',
          'metadata': {'size': 85504},
          'updated_at': '2026-07-29T00:16:31.124Z',
        },
        // sem metadata: não pode explodir
        {'name': 'sistema_exodo_novo_1.0.35.zip'},
      ]);

      expect(versoes.map((v) => v.versao).toList(),
          ['1.0.37', '1.0.36', '1.0.35']);
      expect(versoes.first.tamanhoLegivel, '12.0 MB');
      expect(versoes.last.bytes, 0);

      // O Storage responde em UTC e a tela mostra no horário desta máquina:
      // a checagem é feita sobre o horário local para valer em qualquer fuso.
      final esperado =
          DateTime.parse('2026-09-22T10:00:00.000Z').toLocal();
      String dois(int n) => n.toString().padLeft(2, '0');
      expect(
        versoes.first.quandoLegivel,
        '${dois(esperado.day)}/${dois(esperado.month)} '
        '${dois(esperado.hour)}:${dois(esperado.minute)}',
      );

      // o mesmo arquivo aparecendo duas vezes (listagem paginada) fica uma vez,
      // com a data mais recente
      final repetido = AppUpdateService.interpretarVersoesNaNuvem([
        {
          'name': 'sistema_exodo_novo_1.0.37.zip',
          'metadata': {'size': 1000},
          'updated_at': '2026-09-20T10:00:00.000Z',
        },
        {
          'name': 'sistema_exodo_novo_1.0.37.zip',
          'metadata': {'size': 2000},
          'updated_at': '2026-09-23T10:00:00.000Z',
        },
      ]);
      expect(repetido.length, 1);
      expect(repetido.first.bytes, 2000);
    });

    test('reaproveitar um pacote que NÃO está na nuvem é recusado sem gravar nada',
        () async {
      // Destino de teste (id que não é de nenhuma empresa real) e uma versão
      // que não existe: o caminho tem que parar ANTES de mexer na nuvem.
      const destinoFalso = '00000000-0000-0000-0000-000000000000';
      const versaoFalsa = '99.99.99';
      await _iniciarSupabase();

      final antes = await Supabase.instance.client
          .from('bridge_config')
          .select()
          .eq('id', 'app_update_$destinoFalso')
          .maybeSingle();

      final (ok, mensagem) = await AppUpdateService.publicarAtualizacao(
        versao: versaoFalsa,
        empresaIds: const [destinoFalso],
        usarPacoteDaNuvem: true,
      );

      expect(ok, isFalse);
      expect(mensagem, contains('não tem pacote na nuvem'));

      final depois = await Supabase.instance.client
          .from('bridge_config')
          .select()
          .eq('id', 'app_update_$destinoFalso')
          .maybeSingle();
      expect(depois, isNull,
          reason: 'versão inexistente não pode criar direcionamento');
      expect(antes, isNull,
          reason: 'o id de teste não deveria existir antes do teste');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('lista as versões da nuvem de verdade (só leitura)', () async {
      await _iniciarSupabase();
      final versoes = await AppUpdateService.listarVersoesNaNuvem();
      print('pacotes na nuvem: ${versoes.length}');
      for (final v in versoes) {
        print('  $v');
        // o que entra na lista é sempre pacote de versão, no formato do app
        expect(v.versao, matches(RegExp(r'^\d+\.\d+(\.\d+)+$')));
      }
      // da mais nova para a mais antiga
      for (var i = 1; i < versoes.length; i++) {
        expect(AppUpdateService.compararVersoes(
                versoes[i - 1].versao, versoes[i].versao),
            greaterThanOrEqualTo(0));
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}

/// Sobe o cliente do Supabase para os testes que falam com a nuvem real
/// (só leitura: nenhum deles grava versão para os clientes).
Future<void> _iniciarSupabase() async {
  try {
    Supabase.instance.client;
  } catch (_) {
    await Supabase.initialize(
        url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
  }
}
