import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'env_config.dart';
import 'process_utils.dart';

/// Sobe o PostgreSQL LOCAL deste computador quando ele está DESLIGADO.
///
/// Por que existe: se o serviço para (PC desligado no meio, serviço parado,
/// instalação nova), a leitura do banco local devolve LISTA VAZIA — e o sistema
/// abre todas as telas sem dados, principalmente o Fluxo de Caixa, como se o
/// banco não tivesse nada. Antes disso a única saída era o usuário rodar o
/// `iniciar_postgres.bat` na mão. Agora o próprio app tenta ligar antes de
/// desistir do banco local.
///
/// Estratégia, na ordem (a mesma do `scripts/iniciar_postgres.bat` e do
/// `sincronizador_tray.py`):
///   1. Serviço do Windows `PostgreSQL_Exodo` (`sc start`);
///   2. Senão, o PostgreSQL embarcado: `postgresql\bin\pg_ctl.exe -D <pgdata>`;
///   3. Espera a porta voltar a aceitar conexão.
///
/// É conservador de propósito: só é chamado quando o erro foi CONEXÃO RECUSADA
/// (serviço parado). Senha errada, banco inexistente ou erro de SQL continuam
/// seguindo o caminho normal — não é papel deste serviço adivinhar esses casos.
class PostgresLocalStarter {
  PostgresLocalStarter._();

  /// Nome do serviço que o instalador registra (`scripts/setup_postgres.ps1`).
  static const String nomeServico = 'PostgreSQL_Exodo';

  /// Quanto tempo esperamos a porta voltar a responder depois do start.
  static const Duration esperaMaxima = Duration(seconds: 25);

  /// Intervalo mínimo entre duas tentativas automáticas de ligar o banco.
  ///
  /// Sem isto, cada leitura que falha dispararia um `sc start`/`pg_ctl` — numa
  /// abertura offline isso seriam dezenas de processos. Nunca atrapalha uma
  /// tentativa MANUAL (`respeitarIntervalo: false`).
  static const Duration intervaloMinimo = Duration(seconds: 60);

  /// Momento da última tentativa automática (null = nunca tentou).
  static DateTime? _ultimaTentativa;

  /// true enquanto uma tentativa está em andamento (evita duas simultâneas).
  static bool _emAndamento = false;

  /// Mensagem da última tentativa, para o log/status da tela.
  static String? ultimaMensagem;

  /// A tentativa automática pode rodar agora?
  static bool podeTentar(DateTime agora, {Duration? intervalo}) =>
      intervaloPassou(agora, _ultimaTentativa, intervalo: intervalo);

  /// Regra pura do intervalo (sem tocar em estado/processo) — é o que os
  /// testes usam.
  @visibleForTesting
  static bool intervaloPassou(
    DateTime agora,
    DateTime? ultima, {
    Duration? intervalo,
  }) {
    if (ultima == null) return true;
    return agora.difference(ultima) >= (intervalo ?? intervaloMinimo);
  }

  /// Só para os testes: finja que houve uma tentativa neste instante, sem
  /// executar nenhum processo.
  @visibleForTesting
  static void marcarTentativa(DateTime quando) {
    _ultimaTentativa = quando;
  }

  /// Zera o intervalo: a conexão com o banco local voltou, então uma nova queda
  /// merece uma nova tentativa na hora (e não 60s depois).
  static void registrarConexaoOk() {
    _ultimaTentativa = null;
  }

  /// Só para os testes: esquece o estado guardado entre casos.
  @visibleForTesting
  static void reiniciarParaTeste() {
    _ultimaTentativa = null;
    _emAndamento = false;
    ultimaMensagem = null;
  }

  /// Tenta ligar o PostgreSQL local.
  ///
  /// Devolve `(true, mensagem)` quando o servidor voltou a aceitar conexão na
  /// porta configurada. Devolve `(false, motivo)` quando não deu — a mensagem
  /// já vem em português, pronta para o log de sincronização.
  static Future<(bool, String)> tentarIniciar({
    bool respeitarIntervalo = true,
  }) async {
    if (!Platform.isWindows) {
      return (false, 'Ligar o banco local automaticamente só existe no Windows.');
    }
    if (_emAndamento) {
      return (false, 'Já existe uma tentativa de ligar o banco local em andamento.');
    }
    if (respeitarIntervalo && !podeTentar(DateTime.now())) {
      return (false, 'Aguardando o intervalo entre tentativas de ligar o banco local.');
    }

    _emAndamento = true;
    _ultimaTentativa = DateTime.now();
    try {
      final mensagem = await _passosDeInicio();
      ultimaMensagem = mensagem;
      final ok = await _esperarPorta(EnvConfig.dbPort);
      if (ok) {
        registrarConexaoOk();
        return (
          true,
          '✅ O PostgreSQL local foi ligado pelo sistema. Os dados do banco '
              'deste computador voltaram.'
        );
      }
      return (false, '$mensagem Mesmo assim, o banco local ainda não respondeu.');
    } catch (e) {
      final mensagem = 'Não foi possível ligar o PostgreSQL local: $e';
      ultimaMensagem = mensagem;
      debugPrint('>>> [PostgreSQL] ⚠️ $mensagem');
      return (false, mensagem);
    } finally {
      _emAndamento = false;
    }
  }

  /// Dispara o start pelo serviço do Windows e, se não houver serviço, pelo
  /// PostgreSQL embarcado. Devolve um resumo do que foi tentado.
  static Future<String> _passosDeInicio() async {
    final bases = basesCandidatos();
    final pgCtl = localizarPgCtl(bases);
    final dataDir = localizarDataDir(bases);

    // 1) Serviço do Windows (o instalador registra como 'PostgreSQL_Exodo').
    final servico = await _tentarServico();
    if (servico.sucesso) return servico.mensagem;

    // 2) PostgreSQL embarcado (instalação portátil, sem serviço registrado ou
    //    com o serviço sem permissão de start).
    if (pgCtl == null || dataDir == null) {
      debugPrint('>>> [PostgreSQL] ⚠️ pg_ctl/data não encontrados. Bases '
          'procuradas: ${bases.join(' | ')}');
      return '${servico.mensagem} E o PostgreSQL embarcado '
          '(postgresql\\bin\\pg_ctl.exe + pgdata) não foi encontrado.';
    }

    await _removerPostmasterPidOrfao(dataDir);
    // Log ao lado do próprio pgdata — assim independe da pasta de trabalho.
    final logPath = _prepararLog(p.dirname(dataDir));
    debugPrint('>>> [PostgreSQL] ▶️ Iniciando pelo pg_ctl ($dataDir)...');
    final resultado = await runProcessHidden(
      pgCtl,
      ['-D', dataDir, '-l', logPath, 'start', '-w', '-t', '30'],
      timeout: const Duration(seconds: 40),
    );
    if (resultado.exitCode == 0) {
      debugPrint('>>> [PostgreSQL] ✅ pg_ctl start concluído.');
      return 'Pg_ctl iniciou o PostgreSQL local.';
    }
    final erro = '${resultado.stdout} ${resultado.stderr}'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    debugPrint('>>> [PostgreSQL] ❌ pg_ctl start falhou: $erro');
    return 'Falha ao iniciar pelo pg_ctl: '
        '${erro.isEmpty ? 'código ${resultado.exitCode}' : erro}. '
        '(${servico.mensagem})';
  }

  /// `sc start PostgreSQL_Exodo`.
  ///
  /// `sucesso: false` quando o serviço não existe OU quando o start não foi
  /// aceito — nos dois casos a vez é do PostgreSQL embarcado (pg_ctl), por isso
  /// a mensagem de falha é devolvida em vez de abortar o caminho 2.
  static Future<({bool sucesso, String mensagem})> _tentarServico() async {
    try {
      final existe = await runProcessHidden(
        'sc',
        ['query', nomeServico],
        timeout: const Duration(seconds: 10),
      );
      // A saída do `sc` é TRADUZIDA no Windows em português, então o texto não
      // serve de sinal — quem manda é o exit code (1060 = serviço não existe;
      // outros códigos = sem permissão de consulta).
      if (existe.exitCode != 0) {
        debugPrint('>>> [PostgreSQL] ℹ️ sc query $nomeServico devolveu '
            'código ${existe.exitCode} — tentando o PostgreSQL embarcado.');
        return (
          sucesso: false,
          mensagem: 'O serviço "$nomeServico" não está instalado '
              '(sc query: ${existe.exitCode}).',
        );
      }
      final saida = '${existe.stdout}'.toUpperCase();
      if (saida.contains('RUNNING')) {
        debugPrint('>>> [PostgreSQL] ℹ️ O serviço $nomeServico já está rodando.');
        return (
          sucesso: true,
          mensagem: 'O serviço do PostgreSQL local já estava em execução.',
        );
      }

      debugPrint('>>> [PostgreSQL] ▶️ Solicitando start do serviço $nomeServico...');
      final start = await runProcessHidden(
        'sc',
        ['start', nomeServico],
        timeout: const Duration(seconds: 30),
      );
      final texto = '${start.stdout} ${start.stderr}'.trim();
      if (start.exitCode == 0 || texto.contains('1056')) {
        // 1056 = "O serviço já está em execução".
        return (
          sucesso: true,
          mensagem: 'Serviço "$nomeServico" iniciado.',
        );
      }
      debugPrint('>>> [PostgreSQL] ⚠️ sc start: $texto');
      return (
        sucesso: false,
        mensagem: 'Não consegui iniciar o serviço "$nomeServico": $texto',
      );
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ⚠️ Erro ao consultar o serviço: $e');
      return (
        sucesso: false,
        mensagem: 'Erro ao consultar o serviço "$nomeServico": $e',
      );
    }
  }

  /// Espera a porta do PostgreSQL voltar a aceitar TCP (o servidor pode levar
  /// alguns segundos depois do start).
  static Future<bool> _esperarPorta(int porta) async {
    final host = EnvConfig.dbHost.toLowerCase() == 'localhost'
        ? '127.0.0.1'
        : EnvConfig.dbHost;
    final limite = DateTime.now().add(esperaMaxima);
    while (DateTime.now().isBefore(limite)) {
      if (await portaAberta(host, porta)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// true quando dá para abrir um TCP na porta (o servidor está escutando).
  @visibleForTesting
  static Future<bool> portaAberta(
    String host,
    int porta, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, porta, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Pastas onde procura o PostgreSQL embarcado: a pasta atual, a do executável
  /// e alguns níveis ACIMA das duas.
  ///
  /// Subir os pais é essencial: o app compilado roda de
  /// `build\windows\x64\runner\Debug`, então o `postgresql\bin` (na raiz da
  /// instalação) só aparece lá em cima.
  @visibleForTesting
  static List<String> basesCandidatos({String? cwd, String? exeDir}) {
    final bases = <String>[];
    void adicionarComPais(String caminho) {
      if (caminho.trim().isEmpty) return;
      var dir = Directory(caminho);
      for (var nivel = 0; nivel < 6; nivel++) {
        if (!bases.contains(dir.path)) bases.add(dir.path);
        final pai = dir.parent;
        if (pai.path == dir.path) break;
        dir = pai;
      }
    }

    adicionarComPais(cwd ?? Directory.current.path);
    try {
      adicionarComPais(exeDir ?? File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}
    return bases;
  }

  /// Primeiro `pg_ctl.exe` encontrado nas bases candidatas (null = nenhum).
  @visibleForTesting
  static String? localizarPgCtl(List<String> bases) {
    for (final base in bases) {
      for (final partes in const [
        ['postgresql', 'bin', 'pg_ctl.exe'],
        ['postgresql', 'pgsql', 'bin', 'pg_ctl.exe'],
      ]) {
        try {
          final caminho = p.joinAll([base, ...partes]);
          if (File(caminho).existsSync()) return caminho;
        } catch (_) {}
      }
    }
    return null;
  }

  /// Primeira pasta de dados válida (`pgdata` ou `data`) nas bases candidatas.
  ///
  /// Exigir `postgresql.conf` é o que impede confundir a pasta `data` do pacote
  /// do Flutter (com flutter_assets/app.so) com o cluster do PostgreSQL — o
  /// `setup_postgres.ps1` tem exatamente essa mesma trava.
  @visibleForTesting
  static String? localizarDataDir(List<String> bases) {
    for (final base in bases) {
      for (final relativo in const ['pgdata', 'data']) {
        try {
          final dir = Directory(p.join(base, relativo));
          if (File(p.join(dir.path, 'postgresql.conf')).existsSync()) {
            return dir.path;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Remove um `postmaster.pid` órfão (o PC desligou com o banco aberto, o pid
  /// sobrou e o `pg_ctl start` se recusa a subir). Só remove se NENHUM
  /// `postgres.exe` estiver rodando, como no sincronizador da bandeja.
  static Future<void> _removerPostmasterPidOrfao(String dataDir) async {
    try {
      final pidFile = File(p.join(dataDir, 'postmaster.pid'));
      if (!pidFile.existsSync()) return;
      final tasklist = await runProcessHidden(
        'tasklist',
        ['/FI', 'IMAGENAME eq postgres.exe'],
        timeout: const Duration(seconds: 15),
      );
      if ('${tasklist.stdout}'.contains('postgres.exe')) return;
      debugPrint('>>> [PostgreSQL] 🧹 Removendo postmaster.pid órfão.');
      pidFile.deleteSync();
    } catch (_) {}
  }

  /// Garante `logs\postgresql.log` (instalações antigas podem não ter a pasta).
  static String _prepararLog(String base) {
    final logDir = p.join(base, 'logs');
    try {
      Directory(logDir).createSync(recursive: true);
    } catch (_) {}
    return p.join(logDir, 'postgresql.log');
  }
}
