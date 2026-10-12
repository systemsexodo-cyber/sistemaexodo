import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import 'env_config.dart';
import 'process_utils.dart';
import 'sincronizador_manager_service.dart';

/// Configuração da REDE LOCAL (os dois PCs da mesma loja) — a mesma que o
/// sincronizador de bandeja lê no `.env`.
///
/// O `.env` é o canal entre o app e o sincronizador: a tela de configuração
/// grava aqui e o `SincronizadorNuvem` (processo separado) lê de lá. Por isso
/// toda a gravação passa por [RedeLocalService.aplicarValores], que mexe só nas
/// chaves da LAN e preserva o resto do arquivo (Supabase, banco, comentários).
class ConfigRedeLocal {
  const ConfigRedeLocal({
    this.ligado = false,
    this.host = '',
    this.porta = 5432,
    this.nome = '',
    this.diasTombstone = 30,
    this.inicialCompleto = false,
  });

  /// `LAN_SYNC`: liga/desliga sem apagar o `PAR_HOST`.
  final bool ligado;

  /// `PAR_HOST`: NOME (recomendado) ou IP do OUTRO computador.
  ///
  /// O nome é o jeito certo: o IP da loja vem por DHCP e muda de tempos em
  /// tempos, então configurar pelo IP quebra a LAN sozinho depois de um tempo.
  /// O nome do computador (ex.: `PC-CAIXA-2`) acompanha a máquina.
  /// Vazio = LAN desligada.
  final String host;

  /// `PAR_PORT`: porta do PostgreSQL do outro PC.
  final int porta;

  /// `PAR_NOME`: rótulo do par (aparece no log e no status).
  final String nome;

  /// `LAN_DIAS_TOMBSTONE`: por quantos dias guardar os apagados.
  final int diasTombstone;

  /// `LAN_INICIAL_COMPLETO`: no 1º contato puxa o histórico inteiro do par.
  final bool inicialCompleto;

  /// true quando dá para o sincronizador ligar a LAN com o que está aqui.
  bool get pronto => ligado && host.trim().isNotEmpty;

  /// O par foi informado por NOME do computador (e não por IP)?
  bool get hostEhNome => _ehNome(host);

  /// Lê do `.env` carregado pelo app.
  factory ConfigRedeLocal.ler() => ConfigRedeLocal.doMapa(EnvConfig.env);

  /// Lê de um mapa chave→valor qualquer (usado nos testes).
  factory ConfigRedeLocal.doMapa(Map<String, String> mapa) {
    return ConfigRedeLocal(
      ligado: _booleano(mapa['LAN_SYNC'], padrao: true),
      host: (mapa['PAR_HOST'] ?? '').trim(),
      porta: int.tryParse((mapa['PAR_PORT'] ?? '').trim()) ?? 5432,
      nome: (mapa['PAR_NOME'] ?? '').trim(),
      diasTombstone:
          int.tryParse((mapa['LAN_DIAS_TOMBSTONE'] ?? '').trim()) ?? 30,
      inicialCompleto: _booleano(mapa['LAN_INICIAL_COMPLETO'], padrao: false),
    );
  }

  /// Chaves do `.env` que esta tela controla.
  static const List<String> chaves = <String>[
    'LAN_SYNC',
    'PAR_HOST',
    'PAR_PORT',
    'PAR_NOME',
    'LAN_DIAS_TOMBSTONE',
    'LAN_INICIAL_COMPLETO',
  ];

  /// Texto do `.env` que a tela escreve (mesmas chaves do `.env.example`).
  Map<String, String> paraMapa() => <String, String>{
        'LAN_SYNC': ligado ? 'true' : 'false',
        'PAR_HOST': host.trim(),
        'PAR_PORT': '$porta',
        'PAR_NOME': nome.trim(),
        'LAN_DIAS_TOMBSTONE': '$diasTombstone',
        'LAN_INICIAL_COMPLETO': inicialCompleto ? 'true' : 'false',
      };

  ConfigRedeLocal copyWith({
    bool? ligado,
    String? host,
    int? porta,
    String? nome,
    int? diasTombstone,
    bool? inicialCompleto,
  }) {
    return ConfigRedeLocal(
      ligado: ligado ?? this.ligado,
      host: host ?? this.host,
      porta: porta ?? this.porta,
      nome: nome ?? this.nome,
      diasTombstone: diasTombstone ?? this.diasTombstone,
      inicialCompleto: inicialCompleto ?? this.inicialCompleto,
    );
  }

  static bool _booleano(String? valor, {required bool padrao}) {
    final texto = (valor ?? '').trim().toLowerCase();
    if (texto.isEmpty) return padrao;
    return const ['1', 'true', 'sim', 'yes', 'on'].contains(texto);
  }

  /// true quando o endereço é um NOME de computador (e não um IP).
  ///
  /// O `.local` (mDNS) também é nome: quem resolve é o Windows.
  static bool _ehNome(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return false;
    return !RegExp(r'^[0-9]{1,3}(\.[0-9]{1,3}){3}$').hasMatch(texto);
  }
}

/// Um endereço que respondeu na varredura, com o nome do computador (quando a
/// rede anuncia).
class HostEncontrado {
  const HostEncontrado({required this.host, this.nome});

  /// O endereço IP.
  final String host;

  /// Nome da máquina, quando descoberto (ex.: `PC-CAIXA-2`).
  final String? nome;
}

/// Um computador encontrado na rede local durante a procura.
class ParNaRede {
  const ParNaRede({
    required this.host,
    required this.porta,
    required this.aceitou,
    this.nome,
    this.ip,
    this.versao,
    this.tabelas = 0,
    this.empresaAberta,
    this.erro,
  });

  final String host;
  final int porta;

  /// Nome do computador (quando conhecido) — é o que deve ser gravado no `.env`.
  final String? nome;

  /// Endereço em que ele foi realmente encontrado (útil quando [host] é nome).
  final String? ip;

  /// true quando entrou no banco com as credenciais deste PC: é o outro PC da
  /// loja, com o banco do Êxodo aberto.
  final bool aceitou;

  final String? versao;
  final int tabelas;
  final String? empresaAberta;

  /// Por que não entrou (quando [aceitou] é false).
  final String? erro;
}

/// Resultado da procura de PCs na rede.
class ResultadoBuscaRede {
  const ResultadoBuscaRede({
    this.pares = const <ParNaRede>[],
    this.postgresSemAcesso = const <ParNaRede>[],
    this.computadoresSemPostgres = const <String>[],
    this.redes = const <String>[],
  });

  /// Bancos do Êxodo que aceitaram as credenciais deste PC.
  final List<ParNaRede> pares;

  /// Tinham PostgreSQL na rede, mas não aceitaram as credenciais (pode ser
  /// outro aparelho, ou o usuário/senha do banco difere entre os PCs).
  final List<ParNaRede> postgresSemAcesso;

  /// Computadores na rede que ainda NÃO liberaram o PostgreSQL — é o caso
  /// clássico: falta rodar a preparação naquele PC também.
  final List<String> computadoresSemPostgres;

  /// Redes (/24) varridas, para mostrar ao usuário o que foi procurado.
  final List<String> redes;
}

/// Configuração da rede local feita pelo próprio app (sem editar `.env` à mão
/// nem abrir o PowerShell).
///
/// O app faz quatro coisas aqui:
///   1. lê e grava as chaves da LAN no `.env` ([salvar]);
///   2. procura o outro PC varrendo a rede e testando as credenciais do banco
///      ([procurarPares]) — o usuário não precisa saber o IP;
///   3. testa a conexão com o par ([testarConexao]);
///   4. libera ESTE PC na rede ([prepararEstePc]), que é a única parte que
///      precisa de Administrador (o Windows pede a confirmação do UAC).
class RedeLocalService {
  RedeLocalService._();

  /// Script que ajusta `listen_addresses`, `pg_hba.conf` e o Firewall.
  static const String scriptPreparacao = 'scripts/configurar_lan_postgres.ps1';

  /// Arquivo onde o sincronizador grava o que fez na LAN.
  static const String arquivoLog = 'sincronizador.log';

  // ───────────────────────────────────────────────────────────────────────────
  // .env
  // ───────────────────────────────────────────────────────────────────────────

  /// Devolve o `.env` com as chaves da LAN atualizadas, preservando TODO o
  /// resto (outras chaves, comentários e a ordem das linhas).
  ///
  /// As linhas de comentário não são tocadas: uma linha `# PAR_HOST=...`
  /// continua comentada. Chave que não existe é acrescentada no fim.
  static String aplicarValores(
    String conteudo,
    Map<String, String> valores, {
    String? quebraDeLinha,
  }) {
    final quebra = quebraDeLinha ??
        (conteudo.contains('\r\n') ? '\r\n' : Platform.lineTerminator);
    var linhas = conteudo.split(RegExp(r'\r?\n'));

    valores.forEach((chave, valor) {
      final alvo = RegExp('^[ \\t]*${RegExp.escape(chave)}[ \\t]*=');
      var achou = false;
      for (var i = 0; i < linhas.length; i++) {
        if (!alvo.hasMatch(linhas[i])) continue;
        linhas[i] = '$chave=$valor';
        achou = true;
        break;
      }
      if (!achou) {
        // Tira linhas vazias do fim para não empilhar espaços em branco.
        while (linhas.isNotEmpty && linhas.last.trim().isEmpty) {
          linhas.removeLast();
        }
        linhas.add('$chave=$valor');
      }
    });

    return linhas.join(quebra);
  }

  /// Grava a configuração da LAN no `.env` e recarrega o que o app enxerga.
  ///
  /// Devolve (deu certo, mensagem).
  static Future<(bool, String)> salvar(
    ConfigRedeLocal cfg, {
    File? arquivo,
  }) async {
    try {
      final destino = arquivo ?? EnvConfig.arquivoEnv;
      if (destino == null) {
        return (
          false,
          'Não achei o arquivo .env deste computador. Ele fica na pasta do '
              'sistema (junto do executável).'
        );
      }

      var conteudo = '';
      if (await destino.exists()) {
        conteudo = await destino.readAsString();
      }
      final novo = aplicarValores(conteudo, cfg.paraMapa());
      await destino.writeAsString(novo, flush: true);
      EnvConfig.recarregar();

      final limpo = cfg.host.trim();
      if (limpo.isEmpty) {
        return (true, 'Salvo: rede local DESLIGADA (nenhum PC par informado).');
      }
      // Nome de computador: confirma AGORA que este PC consegue achar o outro.
      // Sem isso o erro só apareceria como "sem conexão" no log, sem dizer que
      // o problema é o nome — que é o erro mais fácil de cometer (digitar o
      // apelido em vez do nome real da máquina).
      if (ConfigRedeLocal._ehNome(limpo)) {
        final ip = await resolverNome(limpo);
        if (ip == null) {
          return (
            true,
            'Salvo, mas ATENÇÃO: este PC não conseguiu achar o computador '
                '"$limpo" na rede. Confira o nome EXATO (abre Propriedades do '
                'Sistema no outro PC) ou use "Procurar PCs".',
          );
        }
        return (
          true,
          'Salvo: o nome "$limpo" foi encontrado em $ip:${cfg.porta}. '
              'Se o IP mudar, a rede se ajusta sozinha.',
        );
      }
      return (
        true,
        'Salvo: este PC vai procurar o outro em $limpo:${cfg.porta}.',
      );
    } catch (e) {
      debugPrint('>>> [RedeLocal] Erro ao gravar no .env: $e');
      return (false, 'Não consegui gravar no .env: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Descoberta do outro PC
  // ───────────────────────────────────────────────────────────────────────────

  /// Traduz o NOME do outro computador para o IPv4 dele na rede local.
  ///
  /// Devolve `null` quando o nome não é encontrado. Usa o mesmo resolvedor do
  /// Windows (`InternetAddress.lookup`), que entende o mDNS (`PC.local`,
  /// anunciado pelo próprio Windows) e, em rede com servidor de nomes, o DNS
  /// local.
  ///
  /// Preferir o nome ao IP é o que torna a LAN estável: o IP do outro PC vem
  /// por DHCP e muda sozinho — o nome acompanha a máquina.
  static Future<String?> resolverNome(String nome) async {
    final limpo = nome.trim();
    if (limpo.isEmpty) return null;
    try {
      final enderecos = await InternetAddress.lookup(limpo)
          .timeout(const Duration(seconds: 4));
      for (final endereco in enderecos) {
        if (endereco.type == InternetAddressType.IPv4) {
          return endereco.address;
        }
      }
      // Sem IPv4 explícito: vale um endereço qualquer resolvido.
      return enderecos.isEmpty ? null : enderecos.first.address;
    } catch (e) {
      debugPrint('>>> [RedeLocal] Não resolvi o nome "$limpo": $e');
      return null;
    }
  }

  /// Nome deste computador (o que o OUTRO PC deve informar como `PAR_HOST`).
  static String nomeDestePc() {
    try {
      if (!Platform.isWindows) return '';
      return Platform.localHostname.trim();
    } catch (_) {
      return '';
    }
  }

  /// Endereços IPv4 deste computador (fora loopback e link-local).
  static Future<List<String>> ipsLocais() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final endereco in interface.addresses) {
          final ip = endereco.address;
          if (ip.startsWith('169.254.')) continue;
          if (!ips.contains(ip)) ips.add(ip);
        }
      }
    } catch (e) {
      debugPrint('>>> [RedeLocal] Não consegui listar as interfaces: $e');
    }
    return ips;
  }

  /// Endereços a varrer: a rede /24 de cada IP deste PC, sem os próprios IPs.
  ///
  /// A rede da loja é sempre uma /24 (192.168.0.x, 10.0.0.x...). Varrer a /24
  /// inteira custa menos de 1 segundo e dispensa o usuário saber o IP do outro.
  static List<String> hostsParaVarrer(List<String> ipsLocais) {
    final meus = ipsLocais.toSet();
    final vistos = <String>{};
    final hosts = <String>[];
    for (final ip in ipsLocais) {
      final partes = ip.split('.');
      if (partes.length != 4) continue;
      final base = '${partes[0]}.${partes[1]}.${partes[2]}.';
      for (var n = 1; n <= 254; n++) {
        final candidato = '$base$n';
        if (meus.contains(candidato)) continue;
        if (vistos.add(candidato)) hosts.add(candidato);
      }
    }
    return hosts;
  }

  /// Nomes das redes que serão varridas (ex.: `192.168.0.x`).
  static List<String> redesLocais(List<String> ipsLocais) {
    final redes = <String>{};
    for (final ip in ipsLocais) {
      final partes = ip.split('.');
      if (partes.length != 4) continue;
      redes.add('${partes[0]}.${partes[1]}.${partes[2]}.x');
    }
    return redes.toList();
  }

  /// Testa a porta TCP de vários endereços ao mesmo tempo e devolve os que
  /// responderam, com o NOME de cada um (quando a rede anuncia).
  ///
  /// A varredura é por IP (é o único jeito de descobrir quem está na rede),
  /// mas o nome é resolvido em paralelo e devolvido junto: é por ele que o
  /// usuário reconhece a máquina e é ele que a tela grava no `.env`.
  static Future<List<HostEncontrado>> varrerPortaDetalhado(
    List<String> hosts, {
    int porta = 5432,
    Duration tempoLimite = const Duration(milliseconds: 400),
    int simultaneos = 64,
    void Function(int feitos, int total)? progresso,
  }) async {
    if (hosts.isEmpty) return const <HostEncontrado>[];
    final abertos = <HostEncontrado>[];
    var proximo = 0;
    var feitos = 0;

    Future<void> trabalhador() async {
      while (true) {
        final i = proximo++;
        if (i >= hosts.length) return;
        final host = hosts[i];
        try {
          final socket = await Socket.connect(host, porta, timeout: tempoLimite);
          // Fecha sem falar nada: só queremos saber se a porta está aberta.
          socket.destroy();
          final nome = await nomeDeIp(host);
          abertos.add(HostEncontrado(host: host, nome: nome));
        } catch (_) {
          // Host sem ninguém (ou porta fechada): é o caso comum, ignora.
        }
        feitos++;
        progresso?.call(feitos, hosts.length);
      }
    }

    final quantos = simultaneos.clamp(1, hosts.length);
    await Future.wait(List<Future<void>>.generate(quantos, (_) => trabalhador()));
    return abertos;
  }

  /// Igual a [varrerPortaDetalhado], mas devolve só os endereços.
  static Future<List<String>> varrerPorta(
    List<String> hosts, {
    int porta = 5432,
    Duration tempoLimite = const Duration(milliseconds: 400),
    int simultaneos = 64,
    void Function(int feitos, int total)? progresso,
  }) async {
    final achados = await varrerPortaDetalhado(
      hosts,
      porta: porta,
      tempoLimite: tempoLimite,
      simultaneos: simultaneos,
      progresso: progresso,
    );
    return achados.map((a) => a.host).toList();
  }

  /// Nome do computador que está naquele IP (best-effort, nunca demora).
  ///
  /// O Windows não oferece isso de forma direta: tenta o cache de nomes do
  /// Windows (`nbtstat -c`, que o próprio Windows preenche quando um PC usa o
  /// nome) e, se não achar, uma consulta NetBIOS ao endereço. Quando nada
  /// responde, devolve `null` — a tela então mostra só o IP.
  static Future<String?> nomeDeIp(String ip) async {
    if (!Platform.isWindows) return null;
    try {
      final cache = await _nbtstat(['-c']);
      final doCache = extrairNomeDoNbtstat(cache, ip);
      if (doCache != null) return doCache;
      final direto = await _nbtstat(['-A', ip]);
      return extrairNomeDoNbtstat(direto, ip);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _nbtstat(List<String> argumentos) async {
    try {
      final resultado = await runProcessHidden(
        'nbtstat',
        argumentos,
        timeout: const Duration(seconds: 3),
      );
      return '${resultado.stdout}\n${resultado.stderr}';
    } catch (_) {
      return '';
    }
  }

  /// Extrai o nome da máquina do texto do `nbtstat` para o IP informado.
  ///
  /// O formato é uma linha `NOME<00>  EXCLUSIVO  192.168.0.117` (cache) ou um
  /// bloco de tabela (consulta direta, sem o IP repetido). `<00>` é o nome da
  /// estação; `<20>` é o serviço de compartilhamento. O grupo WORKGROUP fica de
  /// fora.
  @visibleForTesting
  static String? extrairNomeDoNbtstat(String texto, String ip) {
    if (texto.trim().isEmpty) return null;
    String? primeiroDoIp;
    String? primeiroQualquer;
    for (final linha in texto.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s*(\S+)<00>\s+EXCLUSIVO\s+(\S*)').firstMatch(linha);
      if (match == null) continue;
      final nome = match.group(1)!.trim();
      if (nome.isEmpty || nome.toUpperCase() == 'WORKGROUP') continue;
      primeiroQualquer ??= nome;
      final endereco = (match.group(2) ?? '').trim();
      if (endereco == ip) {
        primeiroDoIp ??= nome;
      }
    }
    return primeiroDoIp ?? primeiroQualquer;
  }

  /// Entra no banco do endereço informado com as credenciais DESTE PC.
  ///
  /// Nunca levanta exceção: devolve [ParNaRede] com `aceitou = false` e o
  /// motivo quando não conseguir.
  static Future<ParNaRede> inspecionar(String host, {int? porta}) async {
    final portaAlvo = porta ?? EnvConfig.dbPort;
    Connection? conexao;
    try {
      conexao = await Connection.open(
        Endpoint(
          host: host,
          port: portaAlvo,
          database: EnvConfig.dbName,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(
          sslMode: SslMode.disable,
          connectTimeout: Duration(seconds: 5),
        ),
      ).timeout(const Duration(seconds: 8));

      // Com o par informado por NOME, guarda em que IP ele foi achado desta
      // vez: é o que prova, na tela e no log, que a LAN se ajustou sozinha
      // depois de o DHCP trocar o endereço.
      final ehNome = ConfigRedeLocal._ehNome(host);
      final resolvido = ehNome ? await resolverNome(host) : host;

      final versao = await _texto(conexao, 'SELECT version()');
      final tabelas = await _inteiro(
        conexao,
        "SELECT COUNT(*) FROM information_schema.tables "
        "WHERE table_schema = 'public'",
      );
      final empresa = await _texto(
        conexao,
        "SELECT valor FROM cache_dados WHERE chave = 'exodo_empresa_ativa' "
        'LIMIT 1',
      );

      return ParNaRede(
        host: host,
        porta: portaAlvo,
        aceitou: true,
        versao: _resumoVersao(versao),
        tabelas: tabelas,
        empresaAberta: empresa,
        ip: resolvido,
      );
    } catch (e) {
      return ParNaRede(
        host: host,
        porta: portaAlvo,
        aceitou: false,
        erro: explicarFalha(e),
      );
    } finally {
      try {
        await conexao?.close();
      } catch (_) {}
    }
  }

  /// Procura o outro PC da loja na rede local.
  ///
  /// Faz em duas etapas: varre a porta do PostgreSQL e, nos que responderam,
  /// tenta entrar com as credenciais deste PC. Quem aceitar é o outro PC do
  /// Êxodo. Se ninguém aceitar, procura computadores ligados na rede (porta de
  /// compartilhamento do Windows) para avisar que falta liberar o PostgreSQL
  /// naquele PC.
  static Future<ResultadoBuscaRede> procurarPares({
    int? porta,
    Duration tempoLimite = const Duration(milliseconds: 400),
    void Function(String etapa, int feitos, int total)? progresso,
  }) async {
    final portaAlvo = porta ?? EnvConfig.dbPort;
    final ips = await ipsLocais();
    final hosts = hostsParaVarrer(ips);
    final redes = redesLocais(ips);

    if (hosts.isEmpty) return ResultadoBuscaRede(redes: redes);

    final comPostgres = await varrerPortaDetalhado(
      hosts,
      porta: portaAlvo,
      tempoLimite: tempoLimite,
      progresso: (feitos, total) => progresso?.call('procurando', feitos, total),
    );

    final pares = <ParNaRede>[];
    final semAcesso = <ParNaRede>[];
    for (var i = 0; i < comPostgres.length; i++) {
      progresso?.call('testando', i + 1, comPostgres.length);
      final achado = await inspecionar(comPostgres[i].host, porta: portaAlvo);
      final comNome = ParNaRede(
        host: achado.host,
        porta: achado.porta,
        aceitou: achado.aceitou,
        nome: achado.nome ?? comPostgres[i].nome,
        ip: achado.ip ?? comPostgres[i].host,
        versao: achado.versao,
        tabelas: achado.tabelas,
        empresaAberta: achado.empresaAberta,
        erro: achado.erro,
      );
      (achado.aceitou ? pares : semAcesso).add(comNome);
    }

    var computadores = <String>[];
    if (pares.isEmpty) {
      final comPostgresIps =
          comPostgres.map((a) => a.host).toSet();
      final restantes =
          hosts.where((h) => !comPostgresIps.contains(h)).toList();
      computadores = await varrerPorta(
        restantes,
        porta: 445, // compartilhamento do Windows: PC ligado e acessível
        tempoLimite: tempoLimite,
        progresso: (feitos, total) =>
            progresso?.call('procurando_pcs', feitos, total),
      );
    }

    return ResultadoBuscaRede(
      pares: pares,
      postgresSemAcesso: semAcesso,
      computadoresSemPostgres: computadores,
      redes: redes,
    );
  }

  /// Traduz o erro de conexão para algo que o dono da loja entenda.
  static String explicarFalha(Object erro) {
    final texto = erro.toString();
    final minusculo = texto.toLowerCase();

    if (minusculo.contains('password') || texto.contains('28P01')) {
      return 'O banco respondeu, mas o usuário/senha do banco não conferem '
          'com os deste computador.';
    }
    if (minusculo.contains('does not exist') || texto.contains('3D000')) {
      return 'O banco respondeu, mas não existe o banco '
          '"${EnvConfig.dbName}" nele.';
    }
    // O Windows em português devolve "recusou a conexão" e o errno 1225; em
    // inglês, ``refused`` e 10061. Os dois casos são a porta fechada.
    if (minusculo.contains('refused') ||
        minusculo.contains('recusou') ||
        minusculo.contains('1225') ||
        minusculo.contains('timed out')) {
      return 'Ninguém respondeu nesse endereço. Confira se o outro PC está '
          'ligado e se ele já foi preparado ("Liberar este PC na rede").';
    }
    if (minusculo.contains('host lookup') ||
        minusculo.contains('name or service not known') ||
        minusculo.contains('getaddrinfo')) {
      return 'Não achei esse computador na rede. Confira o NOME exato (no outro '
          'PC: Configurações > Sistema > Sobre) ou toque em "Procurar PCs".';
    }
    if (minusculo.contains('timeout')) {
      return 'A conexão demorou demais. Confira a rede e o preparo no outro PC.';
    }
    return 'Não consegui conectar: $texto';
  }

  /// Testa a conexão com o par informado. Devolve (deu certo, mensagem).
  ///
  /// Aceita NOME do computador ou IP: nome é o recomendado, porque o IP da loja
  /// muda. Quando o nome é resolvido, a mensagem mostra o IP em que ele foi
  /// encontrado — é o que prova que a LAN continua funcionando após a troca.
  static Future<(bool, String)> testarConexao(String host, int porta) async {
    final limpo = host.trim();
    if (limpo.isEmpty) {
      return (false, 'Informe o nome (ou o IP) do outro computador.');
    }
    if (!Platform.isWindows && limpo == 'localhost') {
      return (false, 'Endereço inválido.');
    }

    final ehNome = ConfigRedeLocal._ehNome(limpo);
    final ip = ehNome ? await resolverNome(limpo) : null;
    if (ehNome && ip == null) {
      return (
        false,
        'Não achei o computador "$limpo" na rede. Confira o nome EXATO (no '
            'outro PC: Configurações > Sistema > Sobre) ou toque em "Procurar '
            'PCs".'
      );
    }

    final achado = await inspecionar(limpo, porta: porta);
    if (!achado.aceitou) {
      return (false, achado.erro ?? 'Não consegui conectar.');
    }
    final onde = ehNome ? '$limpo ($ip:$porta)' : '$limpo:$porta';
    final partes = <String>[
      'Conectado no banco do outro PC ($onde).',
      '${achado.tabelas} tabela(s) encontradas.',
      if (achado.versao != null && achado.versao!.isNotEmpty)
        'PostgreSQL ${achado.versao}.',
      if (achado.empresaAberta != null && achado.empresaAberta!.isNotEmpty)
        'Empresa aberta lá: ${achado.empresaAberta}.',
    ];
    return (true, partes.join(' '));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Preparar ESTE PC (a única parte que precisa de Administrador)
  // ───────────────────────────────────────────────────────────────────────────

  /// Caminho do script que libera o PostgreSQL na rede.
  static Future<String?> caminhoDoScript() async {
    for (final candidato in _candidatos(scriptPreparacao)) {
      try {
        if (await File(candidato).exists()) return candidato;
      } catch (_) {}
    }
    return null;
  }

  /// Comando do PowerShell que abre o script de preparação COMO ADMINISTRADOR.
  ///
  /// Extraído de [prepararEstePc] para poder ser testado: o PowerShell é
  /// sensível à forma da linha, e um detalhe errado aqui só aparece na hora de
  /// usar (o usuário vê um erro de sintaxe em vez do UAC).
  ///
  /// Regras que a linha precisa respeitar:
  ///  - `'-PeerHost'` entre aspas simples: dentro de `@(...)`, um item que
  ///    começa com `-` é lido como OPERADOR (erro "Expressão ausente após
  ///    ','");
  ///  - o caminho do script entre aspas duplas para o PowerShell INTERNO,
  ///    porque o `Start-Process` junta o `-ArgumentList` apenas com espaços —
  ///    sem as aspas, um caminho com espaço no meio quebraria.
  ///
  /// `alvo` vazio = **sem** `-PeerHost`: o script libera a rede local inteira
  /// (a sub-rede /24 deste PC). É o caminho que faz sentido numa loja com
  /// vários caixas — roda uma vez em cada PC e todos se enxergam.
  @visibleForTesting
  static String comandoDePreparacao(String script, [String alvo = '']) {
    String aspas(String valor) => "'${valor.replaceAll("'", "''")}'";
    final limpo = alvo.trim();
    final extra =
        limpo.isEmpty ? '' : ",'-PeerHost',${aspas(limpo)}";
    return "Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait "
        "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"
        "${aspas('"$script"')}$extra);";
  }

  /// Libera ESTE computador para os outros acessarem o banco local.
  ///
  /// Roda o script em `scripts/` pedindo permissão de Administrador (o Windows
  /// mostra o UAC). É o que faz o `listen_addresses`, o `pg_hba.conf` e a regra
  /// do Firewall — e no fim reinicia o PostgreSQL. Devolve (deu certo, mensagem).
  ///
  /// Com [hostDoOutroPc] vazio libera a **rede local inteira** (padrão, o certo
  /// para loja com vários PCs). Informando um IP, libera só aquele PC; um
  /// endereço com `/` (ex.: `192.168.0.0/24`) libera aquela rede.
  static Future<(bool, String)> prepararEstePc(
      [String hostDoOutroPc = '']) async {
    if (!Platform.isWindows) {
      return (false, 'Isso só funciona no Windows.');
    }
    var alvo = hostDoOutroPc.trim();

    // Nome do computador não serve para o `pg_hba.conf` (que trabalha com
    // endereço). Traduz para o IP de hoje; se o par trocar de IP, basta rodar a
    // liberação de novo — o caminho recomendado é liberar a rede inteira
    // (campo vazio), que não depende de endereço nenhum.
    if (ConfigRedeLocal._ehNome(alvo)) {
      final ip = await resolverNome(alvo);
      if (ip == null) {
        return (
          false,
          'Não achei o computador "$alvo" na rede para liberar o acesso dele. '
              'Confira o nome, ou deixe o campo vazio para liberar a rede '
              'inteira (não depende de IP).'
        );
      }
      alvo = ip;
    }

    final script = await caminhoDoScript();
    if (script == null) {
      return (
        false,
        'Não achei $scriptPreparacao na pasta do sistema. Reinstale/atualize '
            'o sistema para ter esse arquivo.'
      );
    }

    final linha = comandoDePreparacao(script, alvo);

    try {
      final resultado = await runProcessHidden(
        'powershell',
        ['-NoProfile', '-Command', linha],
        timeout: const Duration(minutes: 5),
      );
      final saida = '${resultado.stdout}${resultado.stderr}'.trim();
      final minusculo = saida.toLowerCase();
      if (minusculo.contains('canceled') || minusculo.contains('cancelado')) {
        return (false, 'Você cancelou o pedido de Administrador do Windows.');
      }
      if (resultado.exitCode != 0) {
        return (false, 'A preparação falhou: $saida');
      }
      // Quando há um par informado, o script grava PAR_HOST no .env.
      EnvConfig.recarregar();
      return (
        true,
        alvo.isEmpty
            ? 'Pronto neste PC: o PostgreSQL agora ouve na rede local e aceita '
                'os PCs da sua rede (sempre com usuário e senha). Faça o MESMO '
                'nos outros computadores da loja — em nenhum deles é preciso '
                'informar IP.'
            : 'Pronto neste PC: o PostgreSQL foi reiniciado e agora aceita '
                'conexão de $alvo. Para uma loja com vários PCs, o ideal é '
                'liberar a rede inteira (deixe o campo vazio).'
      );
    } catch (e) {
      final minusculo = e.toString().toLowerCase();
      if (minusculo.contains('canceled') || minusculo.contains('1223')) {
        return (false, 'Você cancelou o pedido de Administrador do Windows.');
      }
      return (false, 'Não consegui chamar o Windows: $e');
    }
  }

  /// IP deste computador que o outro PC deve informar no preparo dele.
  /// Nome deste computador, do jeito que o outro PC deve informá-lo.
  static String nomeProvavel() => nomeDestePc();

  static Future<String> ipProvavel() async {
    final ips = await ipsLocais();
    if (ips.isEmpty) return '';
    // Prefere endereço de rede privada (a rede da loja).
    for (final ip in ips) {
      if (ip.startsWith('192.168.') ||
          ip.startsWith('10.') ||
          ip.startsWith('172.')) {
        return ip;
      }
    }
    return ips.first;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sincronizador de bandeja
  // ───────────────────────────────────────────────────────────────────────────

  /// Fecha e reabre o sincronizador para ele reler o `.env`.
  ///
  /// Ele lê a configuração da LAN quando abre — sem reiniciar, a mudança só
  /// valeria no próximo boot do computador.
  static Future<bool> reiniciarSincronizador() async {
    if (!Platform.isWindows) return false;
    try {
      await runProcessHidden(
        'taskkill',
        ['/F', '/IM', 'SincronizadorNuvem.exe'],
      );
      await runProcessHidden(
        'taskkill',
        ['/F', '/IM', 'SincronizadorNuvemConsole.exe'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return SincronizadorManagerService.startSincronizador();
    } catch (e) {
      debugPrint('>>> [RedeLocal] Falha ao reiniciar o sincronizador: $e');
      return false;
    }
  }

  /// Últimas linhas `[LAN]` do log do sincronizador (mais recentes primeiro).
  ///
  /// Lê só o fim do arquivo: o log pode ter centenas de milhares de linhas.
  static Future<List<String>> ultimasLinhasLan({int max = 8}) async {
    for (final caminho in _candidatos(arquivoLog)) {
      final arquivo = File(caminho);
      RandomAccessFile? leitor;
      try {
        if (!await arquivo.exists()) continue;
        leitor = await arquivo.open();
        final tamanho = await leitor.length();
        const janela = 64 * 1024;
        final inicio = tamanho > janela ? tamanho - janela : 0;
        await leitor.setPosition(inicio);
        final bytes = await leitor.read(tamanho - inicio);
        final texto = utf8.decode(bytes, allowMalformed: true);
        final linhas = texto
            .split(RegExp(r'\r?\n'))
            .where((l) => l.contains('[LAN]'))
            .toList();
        if (linhas.isEmpty) return const <String>[];
        final recorte = linhas.length <= max
            ? linhas
            : linhas.sublist(linhas.length - max);
        return recorte.reversed.toList();
      } catch (_) {
        // Log em uso/ilegível: segue para o próximo candidato.
      } finally {
        try {
          await leitor?.close();
        } catch (_) {}
      }
    }
    return const <String>[];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Caminhos prováveis de um arquivo do sistema (pasta atual, pasta do
  /// executável e os pais — o app roda de `build\windows\...\Release`).
  static List<String> _candidatos(String nome) {
    final bases = <String>[];
    try {
      bases.add(Directory.current.path);
    } catch (_) {}
    try {
      bases.add(File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}

    final caminhos = <String>[];
    for (final base in bases) {
      var dir = Directory(base);
      for (var nivel = 0; nivel < 6; nivel++) {
        final caminho = p.join(dir.path, nome);
        if (!caminhos.contains(caminho)) caminhos.add(caminho);
        final pai = dir.parent;
        if (pai.path == dir.path) break;
        dir = pai;
      }
    }
    return caminhos;
  }

  static Future<String?> _texto(Connection conn, String sql) async {
    try {
      final resultado = await conn.execute(sql);
      if (resultado.isEmpty) return null;
      final linha = resultado.first;
      if (linha.isEmpty) return null;
      return linha[0]?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<int> _inteiro(Connection conn, String sql) async {
    final texto = await _texto(conn, sql);
    return int.tryParse(texto ?? '') ?? 0;
  }

  /// `PostgreSQL 16.4` a partir do texto completo do `version()`.
  static String _resumoVersao(String? version) {
    if (version == null || version.isEmpty) return '';
    final match = RegExp(r'PostgreSQL\s+([0-9][^\s,]*)').firstMatch(version);
    return match?.group(1) ?? '';
  }
}
