// Testes da configuração da rede local feita PELO APP (tela "Rede LAN").
//
// Roda SEM rede e SEM banco: as partes que conversam com o mundo (procurar PCs,
// testar conexão, preparar o PC) entram na tela por injeção. O que precisa ser
// verdade aqui é:
//
//   1. gravar no .env mexe SÓ nas chaves da LAN e preserva o resto do arquivo
//      (comentários e as chaves da nuvem não podem se perder);
//   2. a tela lê a configuração salva e mostra a situação certa;
//   3. procurar na rede preenche o par encontrado e salvar guarda o que estava
//      na tela;
//   4. a varredura da rede mira a /24 deste PC e nunca nele mesmo.
//
// Rodar: flutter test test/configuracao_lan_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/pages/configuracao_lan_page.dart';
import 'package:sistema_exodo_novo/services/lan_config_service.dart';

/// Saída real do `nbtstat -c` num PC da rede da loja (o cache de nomes do
/// Windows): o IP aparece no fim de cada linha.
const String _nbtstatCache = '''
    Ethernet:
    Endereco-Ip n : [192.168.0.107] Identificador de escopo: []

                  Tabela de nomes de caches remotas de NetBIOS

        Nome              Tipo       Endereco Host   Duracao [seg]
    ---------------------------------------------------------------
    DESKTOP-CM5TIL7<00>  EXCLUSIVO       192.168.0.117       599
    DESKTOP-CM5TIL7<20>  EXCLUSIVO       192.168.0.117       571
    WORKGROUP      <1E>  GRUPO           192.168.0.1         297
''';

const String _envExemplo = '''
DB_HOST=localhost
DB_PORT=5432
DB_NAME=exodo_db

# ===========================
# REDE LOCAL
# ===========================
# PAR_HOST=nao_mexer_nisso
PAR_HOST=
PAR_PORT=5432

SUPABASE_URL=https://exemplo.supabase.co
''';

void main() {
  group('aplicarValores (.env)', () {
    test('troca só as chaves da LAN e preserva o resto do arquivo', () {
      final novo = RedeLocalService.aplicarValores(
        _envExemplo,
        const ConfigRedeLocal(host: '192.168.0.12', ligado: true, porta: 5433)
            .paraMapa(),
        quebraDeLinha: '\n',
      );

      expect(novo, contains('PAR_HOST=192.168.0.12'));
      expect(novo, contains('PAR_PORT=5433'));
      expect(novo, contains('LAN_SYNC=true'));
      // O resto continua igual.
      expect(novo, contains('DB_NAME=exodo_db'));
      expect(novo, contains('SUPABASE_URL=https://exemplo.supabase.co'));
      // Linha comentada NÃO é descomentada nem trocada.
      expect(novo, contains('# PAR_HOST=nao_mexer_nisso'));
      // Chaves que não existiam foram acrescentadas.
      expect(novo, contains('PAR_NOME='));
      expect(novo, contains('LAN_DIAS_TOMBSTONE=30'));
    });

    test('preserva o CRLF do arquivo', () {
      final novo = RedeLocalService.aplicarValores(
        'DB_NAME=exodo_db\r\nPAR_HOST=\r\n',
        const ConfigRedeLocal(host: '10.0.0.7').paraMapa(),
      );
      expect(novo, contains('\r\n'));
      expect(novo.split('\r\n').where((l) => l.startsWith('PAR_HOST=')).toList(),
          ['PAR_HOST=10.0.0.7']);
    });

    test('não duplica a chave quando ela já existe', () {
      final novo = RedeLocalService.aplicarValores(
        'PAR_HOST=1.1.1.1\n',
        const ConfigRedeLocal(host: '2.2.2.2').paraMapa(),
        quebraDeLinha: '\n',
      );
      expect('PAR_HOST='.allMatches(novo).length, 1);
      expect(novo, contains('PAR_HOST=2.2.2.2'));
    });
  });

  group('salvar', () {
    test('grava no arquivo e o valor pode ser lido de volta', () async {
      final pasta = await Directory.systemTemp.createTemp('exodo_lan');
      final arquivo = File('${pasta.path}/.env');
      await arquivo.writeAsString(_envExemplo);

      final (ok, mensagem) = await RedeLocalService.salvar(
        const ConfigRedeLocal(
          ligado: true,
          host: '192.168.0.12',
          porta: 5432,
          nome: 'PC-CAIXA-2',
        ),
        arquivo: arquivo,
      );

      expect(ok, isTrue, reason: mensagem);
      expect(mensagem, contains('192.168.0.12'));

      final gravado = await arquivo.readAsString();
      // O que foi gravado é lido de volta do mesmo jeito que o app lê.
      final lido = ConfigRedeLocal.doMapa({
        for (final linha in gravado.split(RegExp(r'\r?\n')))
          if (linha.contains('=') && !linha.trimLeft().startsWith('#'))
            linha.split('=').first.trim(): linha.substring(linha.indexOf('=') + 1).trim(),
      });
      expect(lido.host, '192.168.0.12');
      expect(lido.nome, 'PC-CAIXA-2');
      expect(lido.ligado, isTrue);
      expect(lido.pronto, isTrue);
      // E as chaves da nuvem continuam lá.
      expect(gravado, contains('SUPABASE_URL='));

      await pasta.delete(recursive: true);
    });
  });

  group('leitura da configuração', () {
    test('mapa vazio usa os padrões', () {
      final cfg = ConfigRedeLocal.doMapa(const {});
      expect(cfg.ligado, isTrue);
      expect(cfg.host, '');
      expect(cfg.porta, 5432);
      expect(cfg.diasTombstone, 30);
      expect(cfg.inicialCompleto, isFalse);
      expect(cfg.pronto, isFalse); // sem host não há rede local
    });

    test('interpreta o que está no .env', () {
      final cfg = ConfigRedeLocal.doMapa(const {
        'LAN_SYNC': 'false',
        'PAR_HOST': ' 192.168.0.12 ',
        'PAR_PORT': '5433',
        'PAR_NOME': 'PC-CAIXA-2',
        'LAN_DIAS_TOMBSTONE': '90',
        'LAN_INICIAL_COMPLETO': 'true',
      });
      expect(cfg.ligado, isFalse);
      expect(cfg.host, '192.168.0.12');
      expect(cfg.porta, 5433);
      expect(cfg.nome, 'PC-CAIXA-2');
      expect(cfg.diasTombstone, 90);
      expect(cfg.inicialCompleto, isTrue);
      // Desligado NÃO sincroniza, mesmo com host preenchido.
      expect(cfg.pronto, isFalse);
    });
  });

  group('varredura da rede', () {
    test('mira a /24 deste PC, sem varrer a si mesmo', () {
      final hosts = RedeLocalService.hostsParaVarrer(const ['192.168.0.11']);
      // 192.168.0.1 ... 192.168.0.254, menos este PC.
      expect(hosts.length, 253);
      expect(hosts.first, '192.168.0.1');
      expect(hosts.last, '192.168.0.254');
      expect(hosts, isNot(contains('192.168.0.11')));
    });

    test('duas placas na mesma rede não varrem o mesmo IP duas vezes', () {
      final hosts = RedeLocalService.hostsParaVarrer(
          const ['192.168.0.11', '192.168.0.12']);
      expect(hosts.length, 252);
      expect(hosts.toSet().length, hosts.length);
    });

    test('mostra as redes procuradas', () {
      final redes = RedeLocalService.redesLocais(const ['192.168.0.11', '10.0.0.5']);
      expect(redes, containsAll(<String>['192.168.0.x', '10.0.0.x']));
    });

    test('sem endereços para varrer não tenta nada', () async {
      expect(await RedeLocalService.varrerPorta(const []), isEmpty);
    });
  });

  group('endereço do par: nome do computador', () {
    test('reconhece o que é nome e o que é IP', () {
      expect(const ConfigRedeLocal(host: 'PC-CAIXA-2').hostEhNome, isTrue);
      expect(
          const ConfigRedeLocal(host: 'DESKTOP-CM5TIL7.local').hostEhNome,
          isTrue);
      expect(const ConfigRedeLocal(host: '192.168.0.117').hostEhNome, isFalse);
      expect(const ConfigRedeLocal(host: '10.0.0.9').hostEhNome, isFalse);
      // Sem host não há o que classificar (LAN desligada).
      expect(const ConfigRedeLocal().hostEhNome, isFalse);
    });

    test('extrai o nome do computador do nbtstat pelo IP', () {
      // Cache do Windows: acha o nome daquele IP e ignora o WORKGROUP.
      expect(
        RedeLocalService.extrairNomeDoNbtstat(_nbtstatCache, '192.168.0.117'),
        'DESKTOP-CM5TIL7',
      );
      // Consulta direta: a linha não repete o IP, então vale o nome do bloco.
      expect(
        RedeLocalService.extrairNomeDoNbtstat(_nbtstatCache, '192.168.0.200'),
        'DESKTOP-CM5TIL7',
      );
      // Sem resposta nenhuma, não inventa nome.
      expect(
        RedeLocalService.extrairNomeDoNbtstat('host nao encontrado', '192.168.0.9'),
        isNull,
      );
    });
  });

  group('explicarFalha', () {
    test('traduz os erros comuns de conexão', () {
      expect(
        RedeLocalService.explicarFalha(
            Exception('connection refused: could not connect to server')),
        contains('Ninguém respondeu'),
      );
      // O Windows em português devolve "recusou a conexão" (errno 1225):
      // precisa cair na MESMA explicação da porta fechada.
      expect(
        RedeLocalService.explicarFalha(Exception(
            'SocketException: O computador remoto recusou a conexão de rede '
            '(OS Error: O computador remoto recusou a conexão de rede, '
            'errno = 1225)')),
        contains('Ninguém respondeu'),
      );
      expect(
        RedeLocalService.explicarFalha(
            Exception('password authentication failed for user "exodo_user"')),
        contains('usuário/senha'),
      );
      expect(
        RedeLocalService.explicarFalha(
            Exception('database "exodo_db" does not exist')),
        contains('não existe o banco'),
      );
    });

    test('explica nome de computador que não existe', () {
      // O erro clássico de configurar pelo nome: digitar o apelido em vez do
      // nome real da máquina. A mensagem precisa dizer isso, não "sem conexão".
      expect(
        RedeLocalService.explicarFalha(Exception(
            'SocketException: Failed host lookup: \'CAIXA2\' '
            '(OS Error: No address associated with hostname, errno = 11001)')),
        contains('Confira o NOME exato'),
      );
      expect(
        RedeLocalService.explicarFalha(
            Exception('getaddrinfo failed: Name or service not known')),
        contains('achei esse computador'),
      );
    });
  });

  group('tela de configuração', () {
    Future<void> abrir(
      WidgetTester tester, {
      required ConfigRedeLocal config,
      void Function(ConfigRedeLocal)? aoSalvar,
      ResultadoBuscaRede? busca,
      (bool, String)? teste,
      String? caminhoDoEnv,
    }) async {
      // A tela é uma lista longa: sem uma janela alta, o ListView nem monta os
      // cards de baixo (botões e faixa final) e o teste não os enxerga.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ConfiguracaoLanPage(
          configInicial: config,
          ipLocal: '192.168.0.11',
          nomeLocal: 'PC-CAIXA-1',
          lerLog: () async => const ['[LAN] Par PC-2: nada novo.'],
          buscar: (progresso) async {
            progresso('procurando', 254, 254);
            return busca ?? const ResultadoBuscaRede();
          },
          testar: (host, porta) async => teste ?? (false, 'sem teste'),
          salvar: (cfg) async {
            aoSalvar?.call(cfg);
            return (true, 'Salvo em teste.');
          },
          caminhoDoEnv: caminhoDoEnv,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra a configuração que já estava salva', (tester) async {
      await abrir(
        tester,
        config: const ConfigRedeLocal(
          ligado: true,
          host: '192.168.0.12',
          porta: 5432,
          nome: 'PC-2',
        ),
      );

      expect(find.text('Rede local entre os PCs'), findsOneWidget);
      // O campo pede o NOME do computador (o IP continua aceito, mas não é o
      // que a tela sugere) — era o pedido: configurar a LAN pelo nome.
      expect(find.text('Nome do outro computador (ou IP)'), findsOneWidget);
      expect(find.text('ex.: PC-CAIXA-2'), findsOneWidget);
      expect(find.text('192.168.0.12'), findsOneWidget);
      expect(find.textContaining('Rede local ATIVA com 192.168.0.12:5432'),
          findsOneWidget);
      // Informado por IP: a tela avisa que isso quebra quando o IP muda.
      expect(find.textContaining('informado pelo IP'), findsOneWidget);
      // E mostra o nome DESTE PC, que é o que o outro deve usar no campo
      // (o rótulo é um Text.rich: precisa do findRichText).
      expect(find.textContaining('PC-CAIXA-1', findRichText: true),
          findsOneWidget);
      // O log do sincronizador aparece na tela.
      expect(find.textContaining('[LAN] Par PC-2'), findsOneWidget);
    });

    testWidgets('sem par, avisa que a rede local está desligada',
        (tester) async {
      await abrir(tester, config: const ConfigRedeLocal(ligado: true));
      expect(find.textContaining('Ainda falta escolher o outro computador'),
          findsOneWidget);
      expect(find.textContaining('Rede local ATIVA'), findsNothing);
    });

    testWidgets('procurar na rede preenche o par encontrado e salvar guarda',
        (tester) async {
      ConfigRedeLocal? salvo;
      await abrir(
        tester,
        config: const ConfigRedeLocal(ligado: true),
        busca: const ResultadoBuscaRede(
          pares: [
            ParNaRede(
              host: '192.168.0.12',
              porta: 5432,
              aceitou: true,
              nome: 'PC-CAIXA-2',
              ip: '192.168.0.12',
              versao: '16.3',
              tabelas: 42,
              empresaAberta: 'BMJ PETSHOP',
            ),
          ],
          redes: ['192.168.0.x'],
        ),
        aoSalvar: (cfg) => salvo = cfg,
      );

      await tester.tap(find.text('Procurar PCs'));
      await tester.pumpAndSettle();

      // O PC encontrado é o escolhido sozinho (só tinha um) e o veredito
      // aparece logo no topo: quem já está liberado.
      expect(find.textContaining('1 de 1 já liberados'), findsOneWidget);
      expect(find.textContaining('JÁ LIBERADO'), findsOneWidget);
      expect(find.textContaining('empresa aberta: BMJ PETSHOP'), findsOneWidget);

      // O que vai para o campo é o NOME do PC, não o IP: é o nome que não muda
      // quando o DHCP troca o endereço.
      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.controller?.text, 'PC-CAIXA-2');
      expect(find.textContaining('IP agora: 192.168.0.12'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(salvo, isNotNull);
      expect(salvo!.host, 'PC-CAIXA-2');
      expect(salvo!.hostEhNome, isTrue);
      expect(salvo!.ligado, isTrue);
    });

    testWidgets('avisa quando ninguém é encontrado na rede', (tester) async {
      await abrir(
        tester,
        config: const ConfigRedeLocal(ligado: true),
        busca: const ResultadoBuscaRede(
          computadoresSemPostgres: ['192.168.0.12'],
          redes: ['192.168.0.x'],
        ),
      );

      await tester.tap(find.text('Procurar PCs'));
      await tester.pumpAndSettle();

      // Sem ninguém liberado, o topo conta isso e a máquina ganha o veredito.
      expect(find.textContaining('0 de 1 já liberados'), findsOneWidget);
      expect(find.textContaining('1 sem liberar'), findsOneWidget);
      expect(
        find.textContaining('AINDA FALTA LIBERAR'),
        findsOneWidget,
      );

      // Tocar no computador encontrado já o usa como par (sem digitar o IP).
      await tester.tap(find.text('192.168.0.12'));
      await tester.pumpAndSettle();
      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.controller?.text, '192.168.0.12');
    });

    testWidgets('mostra onde a configuração é gravada', (tester) async {
      await abrir(
        tester,
        config: const ConfigRedeLocal(ligado: true),
        caminhoDoEnv: r'C:\SistemaExodo\.env',
      );

      expect(find.textContaining('C:\\SistemaExodo\\.env'), findsOneWidget);
      // Caminho do sistema: sem alarme, o sincronizador lê este mesmo arquivo.
      expect(find.textContaining('SincronizadorNuvem INSTALADO lê o .env'),
          findsNothing);
    });

    testWidgets('avisa quando grava num .env que o sincronizador não lê',
        (tester) async {
      // É o caso real: app rodando de build de desenvolvimento gravou no .env
      // do PROJETO, enquanto o sincronizador instalado lê outro arquivo.
      await abrir(
        tester,
        config: const ConfigRedeLocal(ligado: true),
        caminhoDoEnv: r'C:\loja\build\windows\x64\runner\Debug\.env',
      );

      expect(find.textContaining('Esta configuração é gravada em'),
          findsOneWidget);
      expect(
          find.textContaining('SincronizadorNuvem INSTALADO lê o .env'),
          findsOneWidget);
    });

    testWidgets('mostrar o resultado do teste de conexão', (tester) async {
      await abrir(
        tester,
        config: const ConfigRedeLocal(ligado: true, host: '192.168.0.12'),
        teste: (true, 'Conectado no banco do outro PC (192.168.0.12:5432).'),
      );

      await tester.tap(find.text('Testar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Conectado no banco do outro PC'),
          findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Comando que pede Administrador para liberar o PC na rede
  // ─────────────────────────────────────────────────────────────────────────────
  // Aqui o erro só aparecia na hora de usar: o PowerShell recusava a linha e a
  // tela mostrava "Expressão ausente após ','" em vez do pedido de UAC.
  group('comando de preparação (PowerShell)', () {
    test('cita -PeerHost entre aspas, senão o PowerShell lê como operador', () {
      final linha = RedeLocalService.comandoDePreparacao(
        r'C:\SistemaExodo\scripts\configurar_lan_postgres.ps1',
        '192.168.0.12',
      );

      // Dentro de @(...) um item começando com '-' é OPERADOR: sem as aspas
      // simples o PowerShell aborta com "Expressão ausente após ','".
      expect(linha, contains("'-PeerHost'"));
      expect(linha, isNot(contains(',-PeerHost')));
      expect(linha, contains("'192.168.0.12'"));
      expect(linha, contains("-Verb RunAs"));
    });

    test('sem IP do par, libera a rede inteira (nenhum -PeerHost)', () {
      // É o caminho padrão para loja com vários PCs: uma execução por máquina,
      // sem cruzar IP a IP.
      final linha = RedeLocalService.comandoDePreparacao(
        r'C:\SistemaExodo\scripts\configurar_lan_postgres.ps1',
      );

      expect(linha, isNot(contains('PeerHost')));
      expect(linha, contains('-Verb RunAs'));
      expect(
        linha,
        contains(r'"C:\SistemaExodo\scripts\configurar_lan_postgres.ps1"'),
      );
    });

    test('põe o caminho do script entre aspas duplas', () {
      final linha = RedeLocalService.comandoDePreparacao(
        r'C:\Program Files\Exodo\scripts\configurar_lan_postgres.ps1',
        '10.0.0.9',
      );
      // As aspas duplas são para o PowerShell INTERNO: o Start-Process junta o
      // -ArgumentList apenas com espaços, então um caminho com espaço no meio
      // quebraria sem elas.
      expect(
        linha,
        contains(
            r'"C:\Program Files\Exodo\scripts\configurar_lan_postgres.ps1"'),
      );
    });
  });
}
