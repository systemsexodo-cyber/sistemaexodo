import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/empresa.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/database_service.dart';
import '../services/backup_restore_service.dart';
import '../services/env_config.dart';
import '../services/sincronizador_manager_service.dart';
import '../theme.dart';
import 'bloqueio_mensalidade_page.dart';
import 'conferencia_local_nuvem_page.dart';

/// Backup e Restauração — 4 ações claras:
/// 1. Backup Local (dump)
/// 2. Backup Nuvem (upload manual + automático)
/// 3. Restaurar (de dump local ou nuvem)
/// 4. Enviar Local → Nuvem (sincronizar dados via API)
/// Como restaurar um dump local: só a empresa selecionada (padrão), simular
/// (comparar sem alterar nada) ou o banco inteiro do computador (todas as
/// empresas).
enum _ModoRestauracaoDump { somenteEmpresa, simular, bancoInteiro }

/// O que fazer depois de uma restauração aplicada só no banco local.
enum _AcaoPosRestauracao { concluir, desfazer, enviar }

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  BackupRestoreService? _backupService;

  // Loading states
  bool _isLoading = true;
  bool _isGerandoDump = false;
  bool _isRestaurandoDump = false;
  bool _isRestaurandoSqlLocal = false;
  /// Simulação de restauração em andamento (não altera nada).
  bool _isSimulandoDump = false;
  /// Troca de empresa em andamento (a tela recarrega os backups da nova empresa
  /// sem sair daqui).
  bool _isTrocandoEmpresa = false;
  String _mensagemTrocaEmpresa = '';
  /// Passo atual da restauração (mostrado na tela enquanto ela roda).
  String _progressoRestauracao = '';

  /// Backups .sql POR EMPRESA que ficam em `C:\ExodoBackups\<empresaId>`
  /// (gerados no backup diário). A restauração deles é direta, sem base
  /// temporária, e mexe apenas nesta empresa.
  List<Map<String, dynamic>> _backupsSqlLocais = [];

  /// Quantos arquivos .sql da pasta são de OUTRAS empresas (não são listados).
  int _sqlLocaisDeOutrasEmpresas = 0;
  bool _mostrarTodosSqlLocais = false;

  /// Alguma restauração em andamento.
  bool get _restaurando => _isRestaurandoDump || _isRestaurandoSqlLocal;

  /// Tela ocupada (restaurando, simulando ou trocando de empresa): trava as ações.
  bool get _ocupado => _restaurando || _isSimulandoDump || _isTrocandoEmpresa;
  bool _isEnviandoNuvem = false;
  bool _isEnviandoLocalNuvem = false;
  bool _isSincronizandoCompleto = false;
  bool _isCriandoTabelas = false;
  /// Passo atual da comparação/criação de tabelas na nuvem.
  String _progressoTabelasNuvem = '';

  /// Retrato da ESTRUTURA dos dois bancos (tabelas/colunas), mostrado no painel
  /// "Saúde dos Bancos" — é assim que se acompanha o local e a nuvem.
  ConferenciaEsquema? _conferenciaEsquema;
  bool _isConferindoEsquema = false;
  String _progressoConferenciaEsquema = '';

  /// Criação, no banco LOCAL, das tabelas/colunas que só existem na nuvem.
  bool _isCriandoEstruturaLocal = false;
  String _progressoEstruturaLocal = '';

  /// Divergências detalhadas ficam escondidas até o usuário pedir (a lista pode
  /// ser longa numa instalação antiga).
  bool _verDivergenciasEsquema = false;
  bool _isCriandoBancoLocal = false;
  /// Passo atual da criação do banco local (exodo_db).
  String _progressoCriarBancoLocal = '';
  bool _isEnviandoBackupNuvem = false;
  bool _isRestaurandoBackupNuvem = false;
  bool _isBaixandoBackupNuvem = false;
  bool _isEnviandoBackupCompletoNuvem = false;
  bool _isBaixandoBackupCompletoNuvem = false;
  bool _isRestaurandoCompletoNaNuvem = false;
  String _mensagemProgressoBackupCompleto = '';

  /// Backup SÓ desta empresa tirado do banco DA NUVEM (o que existe hoje no
  /// Supabase — diferente do backup por empresa que é gerado do banco local).
  bool _isBaixandoSnapshotNuvem = false;
  bool _isRestaurandoSnapshotNaNuvem = false;
  String _progressoSnapshotNuvem = '';

  // Listas
  List<Map<String, dynamic>> _dumpsLocais = [];
  List<Map<String, dynamic>> _dumpsNuvem = [];

  /// Backups COMPLETOS do banco da nuvem guardados na própria nuvem
  /// (bucket 'dumps', pasta '_banco_completo' — todas as empresas).
  List<Map<String, dynamic>> _backupsCompletosNuvem = [];

  /// Fotos do banco DA NUVEM só desta empresa, salvas em
  /// `C:\ExodoBackups\nuvem\empresas\<empresaId>`.
  List<Map<String, dynamic>> _snapshotsNuvemEmpresa = [];

  /// Estados ANTERIORES guardados automaticamente antes de cada restauração
  /// (`C:\ExodoBackups\_antes_de_restaurar\<empresaId>`) — é a lista de desfazer.
  List<Map<String, dynamic>> _estadosAnteriores = [];
  bool _mostrarTodosEstadosAnteriores = false;

  /// Nome da empresa atual + ID curto (ex.: "É O BICHO PETSHOP (22ae2c16…)")
  String _nomeEmpresaComId() {
    final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
    if (empresa == null) return 'empresa';
    return '${empresa.nomeExibicao} (${empresa.idCurto})';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataService = Provider.of<DataService>(context, listen: false);
      _backupService = BackupRestoreService(dataService);
      _carregarDados();
    });
  }

  // ==================== TROCA DE EMPRESA ====================

  /// Empresas que este usuário pode acessar (mesma regra usada pelo login e
  /// pela tela de seleção de empresa), em ordem alfabética.
  List<Empresa> _empresasParaTroca() {
    final authService = Provider.of<AuthService>(context, listen: false);
    return authService.getEmpresasDoUsuario().toList()
      ..sort((a, b) => a.nomeExibicao.toLowerCase().compareTo(b.nomeExibicao.toLowerCase()));
  }

  /// Trocar de empresa é ação de master/suporte (como o botão da Home) e só faz
  /// sentido quando existe mais de uma empresa disponível.
  bool _podeTrocarEmpresa() {
    final usuario = Provider.of<AuthService>(context, listen: false).usuarioAtual;
    if (usuario == null) return false;
    final isMaster = usuario.isMaster || usuario.email.toLowerCase() == 'user';
    return isMaster && _empresasParaTroca().length > 1;
  }

  /// Bottom sheet para escolher a empresa — sem sair da tela de backup.
  Future<void> _abrirSeletorEmpresa() async {
    final atualId = Provider.of<DataService>(context, listen: false).currentEmpresaId;
    final empresas = _empresasParaTroca();
    if (empresas.length <= 1) return;

    final escolhida = await showModalBottomSheet<Empresa>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Trocar empresa',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text(
              'Os backups e as restaurações passam a ser da empresa escolhida — sem sair desta tela.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: empresas.length,
                itemBuilder: (ctx, i) {
                  final emp = empresas[i];
                  final selecionada = emp.id == atualId;
                  final documento = (emp.cnpj ?? '').trim();
                  return ListTile(
                    leading: Icon(
                      selecionada ? Icons.radio_button_checked : Icons.storefront_outlined,
                      color: selecionada ? Colors.cyanAccent : Colors.white54,
                      size: 20,
                    ),
                    title: Text(
                      emp.nomeExibicao,
                      style: TextStyle(
                        color: selecionada ? Colors.cyanAccent : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (selecionada) 'empresa atual',
                        'ID ${emp.idCurto}',
                        if (documento.isNotEmpty) 'CNPJ $documento',
                      ].join(' • '),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    onTap: selecionada ? null : () => Navigator.pop(ctx, emp),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (escolhida == null || escolhida.id == atualId) return;
    await _trocarEmpresa(escolhida);
  }

  /// Troca a empresa selecionada e RECARREGA os backups aqui mesmo.
  ///
  /// Usa a mesma sequência da tela de seleção de empresa (AuthService +
  /// DataService), senão o app continuaria trabalhando com os dados da empresa
  /// anterior.
  Future<void> _trocarEmpresa(Empresa nova) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    setState(() {
      _isTrocandoEmpresa = true;
      _mensagemTrocaEmpresa = 'Trocando para ${nova.nomeExibicao}...';
    });

    try {
      await authService.selecionarEmpresa(nova);
      final empAtualizada = authService.empresaAtual ?? nova;
      dataService.setEmpresaAtual(empAtualizada);
      await dataService.definirEmpresaAtual(empAtualizada.id);
      if (!mounted) return;

      setState(() {
        _mensagemTrocaEmpresa = 'Carregando os backups de ${empAtualizada.nomeExibicao}...';
        // A lista expandida era da empresa anterior.
        _mostrarTodosSqlLocais = false;
      });
      // Recarrega dumps locais, backups .sql, nuvem e backups completos da nova empresa
      await _carregarDados();
      if (!mounted) return;

      // Mesma regra da tela de seleção de empresa: se a empresa estiver bloqueada
      // (mensalidade/validação), o bloqueio é mostrado também aqui.
      final motivo = empAtualizada.verificarMotivoBloqueio(
        ultimaValidacaoOnline: dataService.ultimaValidacaoOnline,
        ultimaDataExecucao: dataService.ultimaDataExecucao,
        limiteDiasOffline: 5,
      );
      final usuario = authService.usuarioAtual;
      final isMaster = usuario?.isMaster == true || usuario?.email.toLowerCase() == 'user';
      final podeBypassar = isMaster && dataService.liberacaoProvisoriaAtiva;
      if (motivo != MotivoBloqueioEmpresa.nenhum && !podeBypassar) {
        if (!mounted) return;
        _mostrarSnackBar(
          '⚠️ ${empAtualizada.nomeExibicao} está bloqueada — o bloqueio foi aberto, volte para esta tela depois de resolvê-lo.',
          Colors.orange,
        );
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BloqueioMensalidadePage(
              configs: empAtualizada.configuracoes ?? {},
              motivoBloqueio: motivo,
            ),
          ),
        );
        if (!mounted) return;
        // Ao voltar do bloqueio, a empresa pode ter mudado (liberação) — recarrega.
        await _carregarDados();
        return;
      }

      _mostrarSnackBar(
        '✅ Agora você está em ${empAtualizada.nomeExibicao}: backups e restauração são desta empresa.',
        Colors.green,
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Não foi possível trocar de empresa: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isTrocandoEmpresa = false;
          _mensagemTrocaEmpresa = '';
        });
      }
    }
  }

  Future<void> _carregarDados() async {
    if (_backupService == null) return;
    setState(() => _isLoading = true);

    final dumpsLocais = await _carregarDumpsLocais();
    final (backupsSqlLocais, sqlDeOutras) = await _carregarBackupsSqlLocais();
    final dumpsNuvem = await _backupService!.listarDumpsNuvem();
    final backupsCompletos = await _backupService!.listarBackupsCompletosNuvem();
    final snapshotsNuvem = await _carregarSnapshotsNuvemEmpresa();
    final estadosAnteriores = await _carregarEstadosAnteriores();
    // Retrato da última conferência de estrutura (não reconecta em nada: lê o
    // arquivo salvo, para a tela não abrir em branco).
    final conferencia = await _backupService!.lerUltimaConferenciaEsquema();

    // Mais recente primeiro
    dumpsNuvem.sort((a, b) {
      final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    if (mounted) {
      setState(() {
        _dumpsLocais = dumpsLocais;
        _backupsSqlLocais = backupsSqlLocais;
        _sqlLocaisDeOutrasEmpresas = sqlDeOutras;
        _dumpsNuvem = dumpsNuvem;
        _backupsCompletosNuvem = backupsCompletos;
        _snapshotsNuvemEmpresa = snapshotsNuvem;
        _estadosAnteriores = estadosAnteriores;
        if (conferencia != null) _conferenciaEsquema = conferencia;
        _isLoading = false;
      });
    }
  }

  /// Lista os ESTADOS ANTERIORES guardados antes das restaurações desta empresa
  /// (`C:\ExodoBackups\_antes_de_restaurar\<empresaId>`), mais recentes primeiro.
  ///
  /// É a lista de desfazer: qualquer um destes arquivos pode voltar no banco
  /// local, porque é uma foto .sql da empresa feita no momento da restauração.
  Future<List<Map<String, dynamic>>> _carregarEstadosAnteriores() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaId = dataService.currentEmpresaId ?? '1';
    final dir = Directory(
        '${BackupRestoreService.pastaAntesDeRestaurar}${Platform.pathSeparator}$empresaId');
    if (!await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.sql'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final lista = <Map<String, dynamic>>[];
    for (final f in files) {
      final cabecalho = await _backupService!.lerCabecalhoScriptEmpresa(f);
      lista.add({
        'name': f.uri.pathSegments.last,
        'path': f.path,
        'size': f.lengthSync(),
        'date': f.lastModifiedSync().toIso8601String(),
        'registros': cabecalho.registros,
        'tabelas': cabecalho.tabelas,
      });
    }
    return lista;
  }

  /// Lista as fotos da NUVEM desta empresa (arquivos .sql em
  /// `C:\ExodoBackups\nuvem\empresas\<empresaId>`), mais recentes primeiro.
  Future<List<Map<String, dynamic>>> _carregarSnapshotsNuvemEmpresa() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaId = dataService.currentEmpresaId ?? '1';
    final dir = Directory(_backupService!.pastaBackupEmpresaNuvem(empresaId));
    if (!await dir.exists()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.sql'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final lista = <Map<String, dynamic>>[];
    for (final f in files) {
      final cabecalho = await _backupService!.lerCabecalhoScriptEmpresa(f);
      lista.add({
        'name': f.uri.pathSegments.last,
        'path': f.path,
        'size': f.lengthSync(),
        'modified': f.lastModifiedSync().toIso8601String(),
        'registros': cabecalho.registros,
        'tabelas': cabecalho.tabelas,
        'empresaId': cabecalho.empresaId,
      });
    }
    return lista;
  }

  Future<List<Map<String, dynamic>>> _carregarDumpsLocais() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaId = dataService.currentEmpresaId ?? '1';
    final dir = Directory('C:\\ExodoBackups\\$empresaId\\dumps');
    if (!await dir.exists()) return [];

    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dump')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    return files.map((f) => {
      'path': f.path,
      'name': f.uri.pathSegments.last,
      'size': f.lengthSync(),
      'date': f.lastModifiedSync().toIso8601String(),
    }).toList();
  }

  /// Lista os backups .sql POR EMPRESA de `C:\ExodoBackups\<empresaId>`.
  ///
  /// O nome do arquivo pode enganar (backups antigos saíam com o nome da empresa
  /// aberta na tela), então o filtro usa o `empresa_id` escrito no cabeçalho do
  /// arquivo: só entram os da empresa selecionada. Os das outras empresas são
  /// contados e ignorados — restaurá-los aqui trocaria os dados de outra
  /// empresa, que é exatamente o que se quer evitar.
  ///
  /// Retorna (backups da empresa, quantidade de arquivos de outras empresas).
  Future<(List<Map<String, dynamic>>, int)> _carregarBackupsSqlLocais() async {
    if (_backupService == null) return (<Map<String, dynamic>>[], 0);
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaId = dataService.currentEmpresaId ?? '1';
    final dir = Directory('C:\\ExodoBackups\\$empresaId');
    if (!await dir.exists()) return (<Map<String, dynamic>>[], 0);

    final arquivos = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.sql'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final daEmpresa = <Map<String, dynamic>>[];
    var deOutras = 0;

    for (final arquivo in arquivos) {
      final cabecalho = await _backupService!.lerCabecalhoScriptEmpresa(arquivo);
      if (cabecalho.empresaId == null) continue; // não é backup por empresa
      if (cabecalho.empresaId != empresaId) {
        deOutras++;
        continue;
      }
      daEmpresa.add({
        'path': arquivo.path,
        'name': arquivo.uri.pathSegments.last,
        'size': arquivo.lengthSync(),
        'date': arquivo.lastModifiedSync().toIso8601String(),
        'tabelas': cabecalho.tabelas,
        'registros': cabecalho.registros,
      });
    }
    return (daEmpresa, deOutras);
  }

  // ==================== AÇÕES ====================

  /// 1. Backup Local — gera dump PostgreSQL do banco local
  Future<void> _gerarDumpLocal() async {
    final confirmar = await _confirmar(
      'Gerar Backup Local',
      'Isso vai criar um arquivo .dump do banco de dados local. Continuar?',
    );
    if (!confirmar) return;

    setState(() => _isGerandoDump = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresaId = dataService.currentEmpresaId ?? '1';
      final dir = Directory('C:\\ExodoBackups\\$empresaId\\dumps');
      if (!await dir.exists()) await dir.create(recursive: true);

      final agora = DateTime.now();
      final nomeEmpresa = dataService.empresaAtual?.nomeExibicao ?? 'empresa';
      final nomeLimpo = nomeEmpresa.replaceAll(RegExp(r'[^a-zA-Z0-9À-ú]'), '_').replaceAll(RegExp(r'_+'), '_').trim();
      final nome = '${nomeLimpo}_dump_${agora.year}${agora.month.toString().padLeft(2, '0')}${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}.dump';
      final caminho = '${dir.path}\\$nome';

      final (ok, msg, _) = await _backupService!.criarBackupDumpLocal(destinoArquivo: caminho);
      if (mounted) {
        _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
        if (ok) _carregarDados();
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isGerandoDump = false);
    }
  }

  /// 2. Backup Nuvem — envia o dump local mais recente para o Supabase
  Future<void> _enviarDumpNuvem() async {
    if (_dumpsLocais.isEmpty) {
      _mostrarSnackBar('⚠️ Gere um backup local primeiro', Colors.orange);
      return;
    }

    final confirmar = await _confirmar(
      'Enviar para Nuvem',
      'Enviar o último dump local para a nuvem (Supabase Storage)?',
    );
    if (!confirmar) return;

    setState(() => _isEnviandoNuvem = true);
    try {
      final arquivo = File(_dumpsLocais.first['path']);
      final (ok, msg) = await _backupService!.uploadDumpNaNuvem(arquivo);
      if (mounted) {
        _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
        if (ok) _carregarDados();
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isEnviandoNuvem = false);
    }
  }

  /// 2b. Backup Nuvem por empresa — gera um .sql PostgreSQL APENAS desta empresa
  Future<void> _enviarBackupNuvemAgora() async {
    final confirmar = await _confirmar(
      'Backup PostgreSQL na Nuvem',
      'Gerar um backup .sql (PostgreSQL) SOMENTE dos dados da empresa atual e enviar para a nuvem?\n\nAs outras empresas não são afetadas.',
    );
    if (!confirmar) return;

    setState(() => _isEnviandoBackupNuvem = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final (ok, msg) = await dataService.fazerBackupNuvemAgora();
      if (mounted) {
        _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
        if (ok) _carregarDados();
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isEnviandoBackupNuvem = false);
    }
  }

  /// 2c. Restaurar o backup .sql da nuvem (apenas os dados desta empresa)
  /// Baixa um arquivo da nuvem para a pasta de baixados (não aplica nada).
  /// Devolve o caminho local, ou null (com o motivo no diálogo).
  Future<String?> _baixarBackupDaNuvem(String storagePath, String nome) async {
    _mostrarSnackBar('📥 Baixando "$nome" da nuvem...', Colors.blue);
    final (ok, msg, localPath) = await _backupService!.downloadDumpDaNuvem(
      storagePath,
      destino: BackupRestoreService.pastaNuvemBaixados,
    );
    if (!ok || localPath == null) {
      if (mounted) {
        await _mostrarErroRestauracao(
          'Não consegui baixar da nuvem',
          '$msg\n\nArquivo na nuvem: $storagePath\n\n'
              'Confira a internet e se o arquivo ainda existe no bucket (a lista é atualizada '
              'pelo botão de atualizar, no alto da tela).',
        );
      }
      return null;
    }
    return localPath;
  }

  /// ⬇ BAIXAR — só guarda o arquivo no computador. Não restaura nada.
  Future<void> _baixarBackupNuvemSomente(String storagePath, String nome) async {
    setState(() => _isBaixandoBackupNuvem = true);
    try {
      final localPath = await _baixarBackupDaNuvem(storagePath, nome);
      if (!mounted || localPath == null) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('⬇ Arquivo baixado (nada foi restaurado)',
              style: TextStyle(color: Colors.green, fontSize: 16)),
          content: Text(
            '"$nome" foi salvo em:\n\n$localPath\n\n'
            'Este arquivo é um backup .sql SÓ desta empresa. Para aplicar no banco local, use o '
            'botão ↺ (restaurar) — ou o ↺ na lista local, porque o arquivo já está no computador.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) await _mostrarErroRestauracao('Erro ao baixar da nuvem', '$e');
    } finally {
      if (mounted) setState(() => _isBaixandoBackupNuvem = false);
    }
  }

  /// ↺ RESTAURAR — o MESMO caminho da lista local: baixa, confere a integridade
  /// do arquivo, guarda o estado atual (desfazer), aplica SÓ esta empresa no
  /// banco local e pergunta no fim se quer enviar para a nuvem. A nuvem não é
  /// tocada em nenhum passo.
  Future<void> _restaurarBackupSqlNuvem(String storagePath, String nome) async {
    setState(() => _isRestaurandoBackupNuvem = true);
    try {
      final localPath = await _baixarBackupDaNuvem(storagePath, nome);
      if (!mounted || localPath == null) return;
      await _restaurarBackupSqlLocal(
        localPath,
        nome,
        origem: 'baixado da nuvem agora (fica salvo em $localPath)',
      );
    } catch (e) {
      if (mounted) await _mostrarErroRestauracao('Erro ao restaurar da nuvem', '$e');
    } finally {
      if (mounted) setState(() => _isRestaurandoBackupNuvem = false);
    }
  }

  /// 🔎 SIMULAR um arquivo da nuvem: baixa (sem aplicar) e mostra o que a
  /// restauração mudaria, tabela por tabela. Se o usuário mandar aplicar, o
  /// arquivo já está no computador — não baixa de novo.
  Future<void> _simularBackupNuvem(String storagePath, String nome) async {
    setState(() => _isBaixandoBackupNuvem = true);
    try {
      final localPath = await _baixarBackupDaNuvem(storagePath, nome);
      if (!mounted || localPath == null) return;

      if (localPath.toLowerCase().endsWith('.sql')) {
        await _simularRestauracaoSql(
          File(localPath),
          nome,
          aoAplicar: () => _restaurarBackupSqlLocal(
            localPath,
            nome,
            origem: 'baixado da nuvem agora (fica salvo em $localPath)',
          ),
        );
      } else {
        await _simularRestauracaoDump(
          localPath,
          nome,
          aoAplicar: () => _restaurarDumpSomenteEmpresa(localPath, nome),
        );
      }
    } catch (e) {
      if (mounted) await _mostrarErroRestauracao('Erro ao simular o backup da nuvem', '$e');
    } finally {
      if (mounted) setState(() => _isBaixandoBackupNuvem = false);
    }
  }

  /// ↺ RESTAURAR (dump `.dump` que está na nuvem): baixa e segue EXATAMENTE o
  /// mesmo caminho da lista local, inclusive o diálogo de escolha
  /// (🔎 simular / só esta empresa / banco inteiro).
  Future<void> _restaurarDumpNuvem(String storagePath, String nome) async {
    setState(() => _isRestaurandoBackupNuvem = true);
    try {
      final localPath = await _baixarBackupDaNuvem(storagePath, nome);
      if (!mounted || localPath == null) return;
      await _restaurarDumpLocal(localPath, nome);
    } catch (e) {
      if (mounted) await _mostrarErroRestauracao('Erro ao restaurar da nuvem', '$e');
    } finally {
      if (mounted) setState(() => _isRestaurandoBackupNuvem = false);
    }
  }

  /// 2c.2 Tira uma foto do banco DA NUVEM só desta empresa (não altera nada).
  ///
  /// É a rede de segurança que faltava: guarda o que existe HOJE no Supabase
  /// para esta empresa, independente do que está no banco local.
  Future<void> _baixarSnapshotNuvemEmpresa() async {
    final empresa = _nomeEmpresaComId();
    final confirmar = await _confirmar(
      'Backup SÓ desta empresa, tirado da NUVEM',
      'Baixar uma foto dos dados de $empresa que estão NA NUVEM (Supabase)?\n\n'
      '• Salva um .sql em C:\\ExodoBackups\\nuvem\\empresas — só desta empresa.\n'
      '• Não altera nada, nem aqui nem na nuvem.\n\n'
      'É diferente do "Backup PostgreSQL na Nuvem" (seção de cima): aquele é gerado do banco '
      'LOCAL e arquivado na nuvem, então não serve para reverter a nuvem se o local estiver '
      'errado ou desatualizado. Esta foto é do estado real do Supabase.',
    );
    if (!confirmar) return;

    setState(() {
      _isBaixandoSnapshotNuvem = true;
      _progressoSnapshotNuvem = 'Conectando ao banco da nuvem...';
    });
    try {
      final (ok, msg, _) = await _backupService!.criarBackupSqlDaEmpresaNaNuvem(
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoSnapshotNuvem = mensagem);
        },
      );
      if (!mounted) return;
      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      if (ok) _carregarDados();
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isBaixandoSnapshotNuvem = false;
          _progressoSnapshotNuvem = '';
        });
      }
    }
  }

  /// 2c.3 Aplica uma foto da nuvem DE VOLTA na nuvem — só a empresa atual.
  ///
  /// É a única ação desta tela que altera o Supabase para uma empresa só. Faz
  /// uma foto do estado atual antes (rede de segurança) e exige duas
  /// confirmações.
  Future<void> _restaurarSnapshotNaNuvem(String caminho, String nome) async {
    final empresa = _nomeEmpresaComId();
    final confirmar = await _confirmar(
      'Restaurar NA NUVEM (só esta empresa)',
      '⚠️ Isto ALTERA o banco da nuvem (Supabase): os dados de $empresa que estão lá serão '
      'substituídos pelo conteúdo de "$nome".\n\n'
      '• As OUTRAS empresas da nuvem não são tocadas.\n'
      '• Antes de aplicar, salvo automaticamente uma foto do estado atual da nuvem desta '
      'empresa (arquivo ANTES_DE_RESTAURAR_*.sql) — é por ela que você volta se o arquivo '
      'estiver errado.\n\n'
      'Restaurar aqui NÃO mexe no banco local. Use só para reverter a nuvem a um estado '
      'conhecido bom.',
    );
    if (!confirmar) return;

    final certeza = await _confirmar(
      'Última confirmação',
      'Aplicar "$nome" NA NUVEM agora, substituindo os dados de $empresa no Supabase?',
    );
    if (!certeza) return;

    setState(() {
      _isRestaurandoSnapshotNaNuvem = true;
      _progressoSnapshotNuvem = 'Preparando...';
    });
    try {
      final (ok, msg, caminhoFoto) = await _backupService!.restaurarBackupSqlDaEmpresaNaNuvem(
        File(caminho),
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoSnapshotNuvem = mensagem);
        },
      );
      if (!mounted) return;
      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      if (ok) {
        _carregarDados();
        if (caminhoFoto != null) {
          debugPrint('>>> [BackupRestore] Foto de segurança antes de restaurar na nuvem: $caminhoFoto');
        }
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isRestaurandoSnapshotNaNuvem = false;
          _progressoSnapshotNuvem = '';
        });
      }
    }
  }

  /// 2c.4 Abre uma foto da nuvem desta empresa como texto (conferência).
  void _previewSnapshotNuvem(String caminho, String nome) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(nome, style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 620,
          height: 380,
          child: FutureBuilder<String>(
            future: File(caminho).readAsString(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final linhas = snap.data!.split('\n').take(60).join('\n');
              return SingleChildScrollView(
                child: SelectableText(
                  linhas,
                  style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  /// 2d. Backup do banco INTEIRO da nuvem (Supabase) — todas as empresas
  Future<void> _baixarBackupBancoNuvem() async {
    final confirmar = await _confirmar(
      'Backup do banco da nuvem',
      'Vai baixar uma cópia COMPLETA do banco da nuvem (Supabase) — todos os dados de TODAS as empresas.\n\n'
      'O arquivo é salvo em C:\\ExodoBackups\\nuvem e pode demorar alguns minutos. Continuar?',
    );
    if (!confirmar) return;

    setState(() => _isBaixandoBackupNuvem = true);
    _mostrarSnackBar('☁️ Baixando backup do banco da nuvem... (pode demorar)', Colors.blue);
    try {
      final (ok, msg, caminho) = await _backupService!.criarBackupBancoNuvem();
      if (!mounted) return;

      if (ok && caminho != null) {
        _mostrarSnackBar('✅ $msg', Colors.green);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('✅ Backup da nuvem concluído', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  SelectableText(caminho,
                      style: const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      } else {
        _mostrarSnackBar('❌ Falha no backup da nuvem', Colors.red);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('⚠️ Backup da nuvem', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isBaixandoBackupNuvem = false);
    }
  }

  /// 2d.2 Salvar o backup COMPLETO da nuvem dentro da própria nuvem
  Future<void> _enviarBackupCompletoNuvem() async {
    final confirmar = await _confirmar(
      'Backup completo da nuvem → nuvem',
      'Vai gerar uma cópia COMPLETA do banco da nuvem (todas as tabelas de TODAS as empresas) '
      'e guardar o arquivo na própria nuvem, na pasta "_banco_completo" do bucket "dumps".\n\n'
      '• Não substitui nem apaga nada: é só uma cópia arquivada.\n'
      '• Pode demorar alguns minutos e consome dados de internet (subida).\n'
      '• São mantidos os 10 arquivos mais recentes; os mais antigos saem sozinhos.\n\n'
      'Continuar?',
    );
    if (!confirmar) return;

    setState(() {
      _isEnviandoBackupCompletoNuvem = true;
      _mensagemProgressoBackupCompleto = 'Iniciando...';
    });
    try {
      final (ok, msg, caminho) = await _backupService!.enviarBackupCompletoParaNuvem(
        onProgress: (msg) {
          if (mounted) setState(() => _mensagemProgressoBackupCompleto = msg);
        },
      );
      if (!mounted) return;

      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      await _carregarDados();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(ok ? '✅ Backup completo salvo na nuvem' : '⚠️ Backup completo',
              style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (ok) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Para recuperar este banco em qualquer máquina: baixe o arquivo na lista abaixo e '
                      'rode o .sql no Supabase (SQL Editor) ou use "Restaurar Dump" com o banco parado.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                  if (caminho != null) ...[
                    const SizedBox(height: 10),
                    SelectableText(caminho,
                        style: const TextStyle(
                            color: Colors.purpleAccent, fontSize: 11, fontFamily: 'monospace')),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() {
        _isEnviandoBackupCompletoNuvem = false;
        _mensagemProgressoBackupCompleto = '';
      });
    }
  }

  /// 2d.3 Baixar um backup COMPLETO da nuvem (não restaura nada)
  Future<void> _baixarBackupCompletoNuvem(String storagePath, String nome) async {
    setState(() => _isBaixandoBackupCompletoNuvem = true);
    _mostrarSnackBar('📥 Baixando "$nome"...', Colors.blue);
    try {
      final (ok, msg, destino) = await _backupService!.baixarBackupCompletoDaNuvem(storagePath);
      if (!mounted) return;
      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);

      if (ok && destino != null) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('✅ Backup baixado', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  SelectableText(destino,
                      style: const TextStyle(
                          color: Colors.purpleAccent, fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isBaixandoBackupCompletoNuvem = false);
    }
  }

  /// 2d.4 Restaurar um backup COMPLETO da nuvem → banco da nuvem
  Future<void> _restaurarBackupCompletoNaNuvem(String storagePath, String nome) async {
    final confirmar1 = await _confirmar(
      '⚠️ RESTAURAR BANCO DA NUVEM',
      'Isso vai SUBSTITUIR TODOS os dados do banco Supabase (todas as tabelas, '
      'de TODAS as empresas) pelo conteúdo do backup:\n\n$nome\n\n'
      'A restauração é IRREVERSÍVEL. Um novo backup completo (manual ou automático) '
      'é a única forma de recuperar o estado atual.\n\n'
      'Tem certeza ABSOLUTA?',
    );
    if (!confirmar1) return;

    // Segunda confirmação: digitar "RESTAURAR"
    final controller = TextEditingController();
    final confirmar2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Confirmação final', style: TextStyle(color: Colors.redAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Digite RESTAURAR para confirmar que todos os dados atuais '
              'do banco da nuvem serão substituídos:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'RESTAURAR',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.toUpperCase() == 'RESTAURAR'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('RESTAURAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar2 != true) return;

    setState(() => _isRestaurandoCompletoNaNuvem = true);
    _mostrarSnackBar('🔄 Restaurando backup completo na nuvem... (pode demorar)', Colors.blue);
    try {
      final (ok, msg, comparativo) =
          await _backupService!.restaurarBackupCompletoNaNuvem(storagePath);
      if (!mounted) return;

      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      await _carregarDados();

      if (!mounted) return;

      // Mostrar relatório de antes/depois
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(
            ok ? '✅ Restauração concluída' : '⚠️ Restauração',
            style: TextStyle(color: ok ? Colors.green : Colors.redAccent),
          ),
          content: SizedBox(
            width: 520,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (ok && comparativo != null) ...[
                  const SizedBox(height: 12),
                  const Text('Comparativo antes ↔ depois:',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._buildComparativoRestauracao(comparativo),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isRestaurandoCompletoNaNuvem = false);
    }
  }

  /// 2d.5 Remover um backup COMPLETO da nuvem
  Future<void> _removerBackupCompletoNuvem(String storagePath, String nome) async {
    final confirmar = await _confirmar(
      'Remover backup completo',
      'Apagar "$nome" da nuvem?\n\nÉ apenas uma cópia arquivada — o banco da nuvem NÃO é afetado. '
      'Não tem como desfazer.',
    );
    if (!confirmar) return;

    setState(() => _isBaixandoBackupCompletoNuvem = true);
    try {
      final ok = await _backupService!.removerBackupCompletoNuvem(storagePath);
      if (!mounted) return;
      _mostrarSnackBar(ok ? '🗑️ Backup completo removido da nuvem' : '❌ Não foi possível remover',
          ok ? Colors.green : Colors.red);
      if (ok) await _carregarDados();
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isBaixandoBackupCompletoNuvem = false);
    }
  }

  /// Diálogo que deixa a empresa selecionada em destaque antes de restaurar.
  Future<_ModoRestauracaoDump?> _escolherModoRestauracao(String nomeArquivo) async {
    final empresa = _nomeEmpresaComId();
    return showDialog<_ModoRestauracaoDump>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Restaurar backup', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: Colors.cyanAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Empresa selecionada: $empresa',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(nomeArquivo,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              const Text(
                'A restauração normal aplica o backup SOMENTE na empresa acima: ela apaga e recarrega os dados dessa '
                'empresa no banco local e as outras empresas do computador continuam intactas.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Text(
                'Use "Banco inteiro" apenas em caso de recuperação total — ele substitui os dados de TODAS as empresas.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ModoRestauracaoDump.simular),
            child: const Text('Simular antes', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ModoRestauracaoDump.bancoInteiro),
            child: const Text('Banco inteiro', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _ModoRestauracaoDump.somenteEmpresa),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            child: const Text('Restaurar só esta empresa', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  /// 3. Restaurar de dump local — por padrão SOMENTE na empresa selecionada.
  Future<void> _restaurarDumpLocal(String caminho, String nome) async {
    final modo = await _escolherModoRestauracao(nome);
    if (modo == null) return;
    switch (modo) {
      case _ModoRestauracaoDump.simular:
        await _simularRestauracaoDump(caminho, nome);
        break;
      case _ModoRestauracaoDump.bancoInteiro:
        await _restaurarBancoInteiroDoDump(caminho, nome);
        break;
      case _ModoRestauracaoDump.somenteEmpresa:
        await _restaurarDumpSomenteEmpresa(caminho, nome);
        break;
    }
  }

  /// 3.0 SIMULAÇÃO: compara o que o backup traria/perderia, sem alterar nada.
  ///
  /// Lê o dump numa base temporária e conta os registros da empresa em cada
  /// tabela hoje e como o backup deixaria — é o mesmo caminho da restauração de
  /// verdade, então o que aparece aqui é o que aconteceria de fato.
  Future<void> _simularRestauracaoDump(
    String caminho,
    String nome, {
    Future<void> Function()? aoAplicar,
  }) async {
    final empresa = _nomeEmpresaComId();
    setState(() {
      _isSimulandoDump = true;
      _progressoRestauracao = 'Preparando a simulação...';
    });
    _mostrarSnackBar('🔎 Simulando a restauração — nada será alterado.', Colors.blueAccent);

    try {
      final (ok, msg, comparativo) = await _backupService!.simularRestauracaoDumpSomenteEmpresa(
        dumpFile: File(caminho),
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoRestauracao = mensagem);
        },
      );
      if (!mounted) return;

      if (!ok || comparativo == null) {
        _mostrarSnackBar('❌ $msg', Colors.red);
        return;
      }

      await _mostrarResultadoSimulacao(
        empresa: empresa,
        mensagem: msg,
        comparativo: comparativo,
        caminho: caminho,
        nomeArquivo: nome,
        aoAplicar: aoAplicar,
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro na simulação: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isSimulandoDump = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// Relatório da simulação: o que muda tabela por tabela, com o botão para
  /// aplicar de verdade no final (é a decisão informada).
  Future<void> _mostrarResultadoSimulacao({
    required String empresa,
    required String mensagem,
    required Map<String, ({int antes, int depois, int delta})> comparativo,
    required String caminho,
    required String nomeArquivo,
    Future<void> Function()? aoAplicar,
  }) async {
    final perdem = comparativo.values.where((v) => v.delta < 0).length;
    final restauravel = comparativo.values.any((v) => v.depois > 0);

    final aplicar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('🔎 Simulação — NADA foi alterado', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 560,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: Colors.tealAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Empresa: $empresa',
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(nomeArquivo,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (perdem > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '⚠️ $perdem tabela(s) perderiam registros (linhas em vermelho) — veja se é isso mesmo antes de aplicar.',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(width: 200, child: Text('Tabela', style: TextStyle(color: Colors.white38, fontSize: 11))),
                  SizedBox(width: 80, child: Text('Hoje', textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 11))),
                  SizedBox(width: 28),
                  SizedBox(width: 80, child: Text('Depois', textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 11))),
                  SizedBox(width: 8),
                  SizedBox(width: 60, child: Text('Δ', textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 11))),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._buildComparativoRestauracao(comparativo, maiorPerdaPrimeiro: true),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          if (restauravel)
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.restore, size: 18, color: Colors.black),
              label: const Text('Restaurar de verdade', style: TextStyle(color: Colors.black)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            ),
        ],
      ),
    );

    if (aplicar == true && mounted) {
      // Cada lista tem a sua forma de aplicar: o dump (banco inteiro) passa pela
      // separação da empresa; o `.sql` por empresa aplica direto; e o arquivo que
      // veio da nuvem já está baixado.
      if (aoAplicar != null) {
        await aoAplicar();
      } else {
        await _restaurarDumpSomenteEmpresa(caminho, nomeArquivo);
      }
    }
  }

  /// 3a. Restaurar o dump SOMENTE na empresa selecionada.
  ///
  /// O dump é do banco inteiro, mas os dados das outras empresas são descartados
  /// antes de tocar no banco local (ver BackupRestoreService).
  Future<void> _restaurarDumpSomenteEmpresa(String caminho, String nome) async {
    final empresa = _nomeEmpresaComId();
    final confirmar = await _confirmar(
      'Restaurar só esta empresa',
      'Restaurar "$nome" no banco local SOMENTE para $empresa?\n\n'
      '• Os dados atuais desta empresa são substituídos pelos do backup.\n'
      '• As outras empresas deste computador NÃO são afetadas.\n'
      '• 🛡️ O estado ATUAL desta empresa é guardado automaticamente antes de aplicar '
      '(C:\\ExodoBackups\\_antes_de_restaurar) e fica um botão DESFAZER de um clique.\n'
      '• ✅ A NUVEM NÃO É TOCADA. Nada é apagado nem sobrescrito lá: a restauração roda '
      'com a fila de envio desligada e os envios pendentes desta empresa são guardados em '
      'auditoria e limpos antes, para o sincronizador não subir o conteúdo do backup depois.\n'
      '• Se falhar no meio, a transação é revertida inteira (a empresa não fica pela metade).\n'
      '• No fim eu pergunto o que fazer: desfazer, enviar para a nuvem ou concluir (padrão).'
      '${await _avisoSincronizador()}',
    );
    if (!confirmar) return;

    setState(() {
      _isRestaurandoDump = true;
      _progressoRestauracao = 'Preparando restauração...';
    });
    try {
      final (ok, msg) = await _backupService!.restaurarDumpSomenteEmpresa(
        dumpFile: File(caminho),
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoRestauracao = mensagem);
        },
      );
      if (!mounted) return;
      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);

      if (ok) {
        await _aposRestaurarLocal('Restauração de "$nome" concluída no banco local.');
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isRestaurandoDump = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// 🔎 SIMULAÇÃO de um backup `.sql` POR EMPRESA (o da pasta local ou o que
  /// está na nuvem) — lê o arquivo, compara com o banco local e NÃO altera nada.
  ///
  /// Diferente do dump `.dump`, aqui não precisa de base temporária: o arquivo
  /// já é filtrado por `empresa_id`, então a comparação é direta e rápida.
  Future<void> _simularRestauracaoSql(
    File arquivo,
    String nome, {
    Future<void> Function()? aoAplicar,
  }) async {
    final empresa = _nomeEmpresaComId();
    setState(() {
      _isSimulandoDump = true;
      _progressoRestauracao = 'Lendo o arquivo e comparando com o banco local...';
    });
    _mostrarSnackBar('🔎 Simulando a restauração — nada será alterado.', Colors.blueAccent);

    try {
      final (ok, msg, comparativo) =
          await _backupService!.simularRestauracaoBackupSqlDaEmpresa(arquivo);
      if (!mounted) return;

      if (!ok || comparativo == null) {
        await _mostrarErroRestauracao('Não deu para simular esta restauração', msg);
        return;
      }

      await _mostrarResultadoSimulacao(
        empresa: empresa,
        mensagem: msg,
        comparativo: comparativo,
        caminho: arquivo.path,
        nomeArquivo: nome,
        aoAplicar: aoAplicar,
      );
    } catch (e) {
      if (mounted) {
        await _mostrarErroRestauracao('Erro na simulação', '$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSimulandoDump = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// Erro de backup/restauração em diálogo (não só no aviso que passa rápido):
  /// aqui o usuário precisa poder ler o motivo — é o que faz a ação "não
  /// funcionar" deixar de ser um mistério.
  Future<void> _mostrarErroRestauracao(String titulo, String detalhe) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(titulo, style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              detalhe,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  /// 3b. Restaurar o banco local INTEIRO (todas as empresas) a partir do dump.
  /// Só é usada pelo botão "Banco inteiro" do diálogo de restauração.
  Future<void> _restaurarBancoInteiroDoDump(String caminho, String nome) async {
    final confirmar = await _confirmar(
      'Restaurar banco inteiro',
      '⚠️ Isso vai SUBSTITUIR o banco local INTEIRO — dados de TODAS as empresas deste computador — '
      'pelo conteúdo de "$nome".\n\nAs outras empresas perderão o que não estiver no dump.\n\n'
      '• 🛡️ Um dump COMPLETO do banco local atual é salvo automaticamente antes '
      '(C:\\ExodoBackups\\_antes_de_restaurar\\_banco_inteiro) — sem ele a restauração '
      'não roda — e fica um botão DESFAZER de um clique.\n'
      '• A NUVEM NÃO É TOCADA: a substituição roda com a fila de envio desligada e a fila '
      'inteira é limpa, então nada sobe para o Supabase por causa desta restauração.\n'
      '• O arquivo é validado antes (precisa ser legível e não estar vazio).\n\n'
      'Tem certeza?'
      '${await _avisoSincronizador()}',
    );
    if (!confirmar) return;

    setState(() {
      _isRestaurandoDump = true;
      _progressoRestauracao = 'Restaurando o banco inteiro...';
    });
    try {
      final arquivo = File(caminho);
      _mostrarSnackBar('🔄 Restaurando dump no banco local...', Colors.blue);
      final (ok, msg) = await _backupService!.restaurarDumpPostgres(arquivo);
      if (ok) {
        await _aposRestaurarLocal('Banco local INTEIRO restaurado a partir de "$nome".');
      } else if (mounted) {
        _mostrarSnackBar('❌ $msg', Colors.red);
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isRestaurandoDump = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// 3b.2 Restaurar um backup .sql da PRÓPRIA empresa (restauração direta).
  ///
  /// Esse arquivo já é filtrado por `empresa_id` (é o que o backup diário gera
  /// em `C:\ExodoBackups\<empresaId>`), então não precisa de base temporária: é
  /// a restauração mais rápida e também não encosta nas outras empresas.
  Future<void> _restaurarBackupSqlLocal(
    String caminho,
    String nome, {
    bool controleDeQualidade = false,
    String? origem,
  }) async {
    final empresa = _nomeEmpresaComId();

    // Pré-checagem: arquivo cortado/truncado é recusado AQUI, antes de apagar
    // qualquer linha da empresa.
    final integridade =
        await _backupService!.verificarIntegridadeScriptEmpresa(File(caminho));
    if (!integridade.ok) {
      await _backupService!.registrarAuditoria(
          '⛔ Restauração recusada na tela (arquivo inválido: $nome) — ${integridade.mensagem}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Arquivo recusado',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 17)),
          content: Text(
            'Este arquivo não passou na conferência e NADA foi alterado:\n\n'
            '${integridade.mensagem}\n\n'
            'Se ele foi copiado/baixado, tente de novo com o arquivo completo.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
      return;
    }

    final avisoSync = await _avisoSincronizador();
    final confirmar = await _confirmar(
      controleDeQualidade ? 'Voltar para este estado' : 'Restaurar backup da empresa',
      'Restaurar "$nome" no banco local SOMENTE para $empresa?\n\n'
      '• Conferência do arquivo: ✅ ${integridade.mensagem}\n'
      '• Restauração direta: rápida e sem base temporária.\n'
      '${origem != null ? '• Arquivo $origem\n' : ''}'
      '• Os dados atuais desta empresa são substituídos pelos do arquivo.\n'
      '• As outras empresas deste computador NÃO são afetadas.\n'
      '• 🛡️ O estado ATUAL é guardado automaticamente antes (em '
      'C:\\ExodoBackups\\_antes_de_restaurar) e vira um "Desfazer" de um clique.\n'
      '• ✅ A NUVEM NÃO É TOCADA. Nada é apagado nem sobrescrito lá: a restauração roda '
      'com a fila de envio desligada e os envios pendentes desta empresa são salvos em '
      'auditoria e limpos antes.\n'
      '• Se o arquivo falhar no meio do caminho, a transação é revertida inteira: a empresa '
      'nunca fica pela metade.'
      '$avisoSync',
    );
    if (!confirmar) return;

    setState(() {
      _isRestaurandoSqlLocal = true;
      _progressoRestauracao = 'Restaurando os dados de $empresa...';
    });
    try {
      _mostrarSnackBar('🔄 Restaurando backup da empresa...', Colors.blue);
      final (ok, msg) = await _backupService!.restaurarBackupSqlDaEmpresa(File(caminho));
      if (!mounted) return;
      _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);

      if (ok) {
        await _aposRestaurarLocal('Backup "$nome" restaurado no banco local.');
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isRestaurandoSqlLocal = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// 4. Enviar dados locais para a nuvem (via API REST)
  Future<void> _enviarLocalNuvem() async {
    final confirmar = await _confirmar(
      'Enviar Local → Nuvem',
      'Vai enviar TODOS os dados locais para a nuvem. A nuvem será substituída. Continuar?',
    );
    if (!confirmar) return;

    setState(() => _isEnviandoLocalNuvem = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final (ok, msg) = await dataService.enviarDadosLocalParaNuvem();
      if (mounted) {
        _mostrarSnackBar(ok ? '✅ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isEnviandoLocalNuvem = false);
    }
  }

  /// 4a. Sincronização completa (Local ↔ Nuvem) — unifica os dois bancos
  Future<void> _sincronizarCompleto() async {
    final confirmar = await _confirmar(
      'Sincronizar Completo',
      'Vai baixar os dados da nuvem, juntar com os dados locais e enviar de volta. Ideal para unificar 2 máquinas. Continuar?',
    );
    if (!confirmar) return;

    setState(() => _isSincronizandoCompleto = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final (ok, msg) = await dataService.sincronizacaoBidirecionalCompleta();
      if (mounted) {
        _mostrarSnackBar(ok ? '✅ $msg' : '⚠️ $msg', ok ? Colors.green : Colors.orange);
        if (ok) _carregarDados();
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSincronizandoCompleto = false);
    }
  }

  /// 4b. Compara o banco LOCAL com o da nuvem e cria lá o que falta
  /// (tabelas que só existem aqui e colunas faltantes nas de lá).
  ///
  /// Com [somenteComparar] só mostra o que falta e salva o SQL — nada é criado.
  Future<void> _criarTabelasNoSupabase({bool somenteComparar = false}) async {
    setState(() {
      _isCriandoTabelas = true;
      _progressoTabelasNuvem = 'Comparando o banco local com a nuvem...';
    });
    try {
      final (ok, logs) = await _backupService!.criarTabelasFaltantesNaNuvem(
        somenteComparar: somenteComparar,
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoTabelasNuvem = mensagem);
        },
      );
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(
            ok
                ? (somenteComparar ? '🔎 Comparação (nada foi criado)' : '✅ Nuvem atualizada')
                : '⚠️ Comparação concluída com avisos',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: SizedBox(
            width: 640,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comparação do banco LOCAL (a referência) com o banco da NUVEM. '
                  'Nada é apagado: só são criadas as tabelas e colunas que faltam lá.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 4),
                const Text(
                  'As tabelas valem para o banco inteiro (todas as empresas).',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        logs.join('\n'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isCriandoTabelas = false;
          _progressoTabelasNuvem = '';
        });
      }
    }
  }

  // ============ SAÚDE DOS BANCOS (LOCAL × NUVEM) ============

  /// Tabelas que existem na nuvem por serem recursos DELA (configuração do
  /// atualizador e acesso do portal do contador): criar uma cópia aqui é
  /// inofensivo, mas não serve para nada — por isso vêm desmarcadas na hora de
  /// igualar a estrutura.
  static const Set<String> _tabelasSoDaNuvem = {
    'bridge_config',
    'portal_contador_acessos',
  };

  /// Lê a estrutura dos DOIS bancos e mostra o retrato (só leitura: não cria,
  /// não altera e não sincroniza nada).
  Future<void> _conferirEsquemaBancos() async {
    setState(() {
      _isConferindoEsquema = true;
      _progressoConferenciaEsquema = 'Conferindo as duas estruturas...';
    });
    try {
      final resultado = await _backupService!.conferirEsquemaBancos(
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoConferenciaEsquema = mensagem);
        },
      );
      if (!mounted) return;
      setState(() {
        _conferenciaEsquema = resultado;
        _verDivergenciasEsquema = resultado.divergencias > 0;
      });
      _mostrarSnackBar(
        resultado.iguais
            ? '✅ Estruturas iguais: ${resultado.totalLocal} tabela(s) nos dois bancos.'
            : '🩺 ${resultado.resumo}',
        resultado.iguais ? Colors.green : Colors.orange,
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro ao conferir as estruturas: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isConferindoEsquema = false;
          _progressoConferenciaEsquema = '';
        });
      }
    }
  }

  /// Cria NO LOCAL as tabelas E as colunas que existem na nuvem e não aqui,
  /// depois de o usuário escolher quais. É o caminho inverso de "Criar Tabelas
  /// no Supabase".
  ///
  /// A conta é feita por [BackupRestoreService.trabalhosParaIgualarLocal], que
  /// junta as duas coisas: tabela que falta nascer inteira e tabela que já existe
  /// ganhar as colunas que faltam. Sem isso, o caso comum (0 tabelas faltando e
  /// dezenas de colunas faltando) fazia o botão dizer "nada a criar" e ficar
  /// parado — exatamente o que o painel mostrava como 100 colunas pendentes.
  Future<void> _criarEstruturaLocalFaltante() async {
    final conferencia = _conferenciaEsquema;
    if (conferencia == null) {
      _mostrarSnackBar(
        'Use "🔎 Conferir agora" primeiro: é a conferência que diz o que falta '
        'no local.',
        Colors.orangeAccent,
      );
      return;
    }

    final trabalho = BackupRestoreService.trabalhosParaIgualarLocal(conferencia);
    final faltando = <String>{
      ...trabalho.tabelasNovas,
      ...trabalho.colunasPorTabela.keys,
    }.toList()
      ..sort();

    // Colunas que exigem decisão (hoje só empresas.empresa_id): NÃO vêm marcadas
    // nem entram na conta automática, mas o usuário pode escolher criá-las no
    // mesmo diálogo — é o que deixa a estrutura 100% idêntica.
    final decisaoNoLocal = conferencia.decisaoFaltando;

    if (faltando.isEmpty && decisaoNoLocal.isEmpty) {
      final sensiveis = conferencia.sensiveisFaltando.length;
      _mostrarSnackBar(
        sensiveis == 0
            ? 'Nada a criar: a estrutura do local já está igual à da nuvem.'
            : 'Nada a criar: só sobrou ${sensiveis == 1 ? '1 coluna sensível' : "$sensiveis colunas sensíveis"} '
                '(senha) — essa o app não cria sozinho, de propósito.',
        Colors.green,
      );
      return;
    }

    final tabelasNovas = trabalho.tabelasNovas.toSet();
    final marcadas = <String>{
      for (final t in faltando)
        if (!(tabelasNovas.contains(t) && _tabelasSoDaNuvem.contains(t))) t,
    };

    /// Quantas colunas a seleção de agora vai criar.
    int colunasDaSelecao() => marcadas.fold<int>(
          0,
          (soma, t) => soma + (trabalho.colunasPorTabela[t]?.length ?? 0),
        );

    /// Quantas tabelas novas a seleção de agora vai criar.
    int tabelasNovasDaSelecao() =>
        marcadas.where(tabelasNovas.contains).length;

    // Ligada = cria também as colunas que precisam de decisão. Desligada por
    // padrão, porque elas só são seguras agora que o carregador não filtra mais
    // a leitura de `empresas`/`usuarios` por empresa_id.
    var criarDecisao = false;

    final escolha = await showDialog<({Set<String> tabelas, bool decisao})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void alternar(String t, bool? marcar) {
            setDialog(() {
              if (marcar == true) {
                marcadas.add(t);
              } else {
                marcadas.remove(t);
              }
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('⬇️ Igualar o LOCAL com a NUVEM',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: SizedBox(
              width: 600,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tudo o que falta aqui para ficar igual à nuvem: as tabelas que '
                    'não existem neste computador (criadas VAZIAS) e as COLUNAS que '
                    'faltam nas tabelas que já existem (criadas sem apagar nem '
                    'alterar o dado que já está na tabela).',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'A nuvem NÃO é tocada. Criar aqui uma tabela de recurso da nuvem '
                    '(bridge_config, portal do contador) não dá erro, mas também não '
                    'serve para nada — por isso vêm desmarcadas.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  Expanded(
                    child: ListView(
                      children: [
                        if (faltando.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Nada de tabela ou coluna comum pendente — só a(s) que '
                              'precisa(m) de decisão, na opção abaixo.',
                              style: TextStyle(color: Colors.white54, fontSize: 11.5),
                            ),
                          ),
                        for (final t in faltando)
                          CheckboxListTile(
                            dense: true,
                            value: marcadas.contains(t),
                            onChanged: (v) => alternar(t, v),
                            activeColor: Colors.cyanAccent,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(t,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            subtitle: Text(
                              tabelasNovas.contains(t)
                                  ? (_tabelasSoDaNuvem.contains(t)
                                      ? 'tabela NOVA — recurso da nuvem (aqui não é usada)'
                                      : 'tabela NOVA (nasce vazia, com todas as colunas da nuvem)')
                                  : '${trabalho.colunasPorTabela[t]!.length} coluna(s) nova(s): '
                                      '${trabalho.colunasPorTabela[t]!.take(6).join(', ')}'
                                      '${trabalho.colunasPorTabela[t]!.length > 6 ? '…' : ''}',
                              style: TextStyle(
                                color: tabelasNovas.contains(t)
                                    ? Colors.white38
                                    : Colors.cyanAccent.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  if (decisaoNoLocal.isNotEmpty)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: criarDecisao,
                      onChanged: (v) => setDialog(() => criarDecisao = v == true),
                      activeColor: Colors.deepOrangeAccent,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Criar também a(s) coluna(s) que precisam de decisão',
                        style: TextStyle(color: Colors.deepOrangeAccent, fontSize: 12.5),
                      ),
                      subtitle: Text(
                        '${decisaoNoLocal.join(', ')} — existe(m) na nuvem e falta(m) '
                        'aqui. O app não cria sozinho por padrão porque o banco passa a '
                        'poder FILTRAR a leitura desta tabela por essa coluna; agora que '
                        'essa filtragem foi bloqueada para empresas/usuarios, criar é '
                        'seguro. Marque para deixar a estrutura 100% igual.',
                        style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                      ),
                    ),
                  Text(
                    'Marcado agora: ${tabelasNovasDaSelecao()} tabela(s) nova(s) + '
                    '${colunasDaSelecao()} coluna(s) em ${marcadas.length - tabelasNovasDaSelecao()} tabela(s) '
                    'que já existem'
                    '${criarDecisao ? ' + ${decisaoNoLocal.length} coluna(s) que precisam de decisão' : ''}.',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: (marcadas.isEmpty && !criarDecisao)
                    ? null
                    : () => Navigator.pop(ctx, (
                          tabelas: {...marcadas},
                          decisao: criarDecisao,
                        )),
                child: Text(
                    'Aplicar (${tabelasNovasDaSelecao()} tabela(s) + ${colunasDaSelecao()} coluna(s)'
                    '${criarDecisao ? ' + ${decisaoNoLocal.length} a decidir' : ''})',
                    style: const TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          );
        },
      ),
    );

    if (escolha == null || (escolha.tabelas.isEmpty && !escolha.decisao)) return;

    setState(() {
      _isCriandoEstruturaLocal = true;
      _progressoEstruturaLocal = 'Preparando...';
    });
    try {
      final (ok, logs) = await _backupService!.criarEstruturaFaltanteNoLocal(
        // Com a decisão ligada, a tabela dona dessas colunas entra no conjunto —
        // mesmo que não estivesse marcada, senão elas não seriam criadas.
        tabelas: {
          ...escolha.tabelas,
          if (escolha.decisao)
            ...decisaoNoLocal.map((r) => r.split('.').first),
        },
        criarColunasAutorizadas: escolha.decisao,
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoEstruturaLocal = mensagem);
        },
      );
      if (!mounted) return;

      await _mostrarDialogoLogs(
        titulo: ok ? '✅ Estrutura do local igualada' : '⚠️ Concluído com avisos',
        intro: 'Só o banco LOCAL foi alterado (tabelas novas nascem vazias). '
            'Nada foi enviado para a nuvem.',
        logs: logs,
      );

      // Relê os dois lados para o painel já mostrar o estado novo.
      await _conferirEsquemaBancos();
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isCriandoEstruturaLocal = false;
          _progressoEstruturaLocal = '';
        });
      }
    }
  }

  /// Troca, SÓ no banco local, os nomes que aqui são TABELA e na nuvem são VIEW
  /// (a `vw_historico_recente`): é o que faz os dois bancos ficarem com o MESMO
  /// número de tabelas, sem tocar na nuvem e sem apagar dado — a tabela precisa
  /// estar VAZIA e nenhum objeto pode depender dela, senão nada é alterado.
  Future<void> _igualarTabelaViewNaNuvem() async {
    final objetos = _conferenciaEsquema?.objetoDiferenteNaNuvem ?? const <String>[];
    if (objetos.isEmpty) {
      _mostrarSnackBar(
        'Nada a igualar: nenhum nome é TABELA aqui e VIEW na nuvem.',
        Colors.green,
      );
      return;
    }

    final confirmar = await _confirmar(
      '🧩 Igualar TABELA × VIEW (${objetos.length})',
      'Estes nomes existem aqui como TABELA e na nuvem como VIEW: '
          '${objetos.join(', ')}.\n\n'
          'Como TABELA e VIEW contam de formas diferentes, é isso que deixa o banco '
          'local com 1 tabela a mais que a nuvem.\n\n'
          'Para ficar igual, o app vai:\n'
          '  1. guardar uma cópia do estado atual em C:\\ExodoBackups\\IGUALAR_VIEW_*.sql;\n'
          '  2. apagar a TABELA local — SOMENTE se ela estiver VAZIA e nada depender '
          'dela;\n'
          '  3. criar a VIEW com a MESMA definição da nuvem, numa única transação.\n\n'
          '✅ A nuvem NÃO é tocada e nenhum dado é apagado. Se a tabela tiver '
          'qualquer linha, a troca é recusada e nada muda.',
    );
    if (!confirmar) return;

    setState(() {
      _isCriandoEstruturaLocal = true;
      _progressoEstruturaLocal = 'Preparando...';
    });
    try {
      final (ok, logs) = await _backupService!.igualarTabelasQueSaoViewNaNuvem(
        objetos: objetos.toSet(),
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoEstruturaLocal = mensagem);
        },
      );
      if (!mounted) return;

      await _mostrarDialogoLogs(
        titulo: ok
            ? '✅ Igualado: agora é VIEW nos dois bancos'
            : '⚠️ Igualado com recusas — nada de risco foi alterado',
        intro: 'Só a estrutura deste computador mudou. A nuvem NÃO foi tocada e a '
            'cópia do estado anterior ficou em C:\\ExodoBackups (IGUALAR_VIEW_*.sql).',
        logs: logs,
      );

      // Relê os dois lados: o painel já mostra o número novo de cada um.
      await _conferirEsquemaBancos();
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isCriandoEstruturaLocal = false;
          _progressoEstruturaLocal = '';
        });
      }
    }
  }

  /// Converte, SÓ no banco local, as colunas que têm TIPO diferente do da nuvem
  /// (as 9 de `produtos`: `text` aqui × `numeric`/`integer` lá).
  ///
  /// O app não faz isso sozinho: mudar tipo de coluna com dado dentro pode dar
  /// prejuízo. Aqui o serviço confere TODOS os valores antes — o que não converte
  /// faz a coluna ser recusada — e grava a reversão em C:\ExodoBackups.
  Future<void> _igualarTiposDeColuna() async {
    final colunas = _conferenciaEsquema?.tiposDiferentes ?? const <String>[];
    if (colunas.isEmpty) {
      _mostrarSnackBar(
        'Nada a igualar: nenhuma coluna com tipo diferente.',
        Colors.green,
      );
      return;
    }

    final confirmar = await _confirmar(
      '🔧 Igualar TIPOS de coluna (${colunas.length})',
      'Estas colunas existem nos dois bancos com tipos diferentes:\n\n'
          '${colunas.map((t) => '  • $t').join('\n')}\n\n'
          'O tipo de cada uma será trocado pelo tipo EXATO da nuvem, só neste '
          'computador. Antes de alterar, o app CONFERE todos os valores da coluna: '
          'se algum não converter, aquela coluna é recusada e nada muda nela.\n\n'
          'O que for alterado deixa a reversão pronta (tipo antigo + valores) em '
          'C:\\ExodoBackups\\IGUALAR_TIPO_*.sql.\n\n'
          '✅ A nuvem NÃO é tocada.',
    );
    if (!confirmar) return;

    setState(() {
      _isCriandoEstruturaLocal = true;
      _progressoEstruturaLocal = 'Preparando...';
    });
    try {
      final (ok, logs) = await _backupService!.igualarTiposDeColunaNoLocal(
        colunas: colunas.toSet(),
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoEstruturaLocal = mensagem);
        },
      );
      if (!mounted) return;

      await _mostrarDialogoLogs(
        titulo: ok
            ? '✅ Tipos iguais aos da nuvem'
            : '⚠️ Igualado com recusas — nada de risco foi alterado',
        intro: 'Só a estrutura deste computador mudou. A nuvem NÃO foi tocada e a '
            'reversão ficou em C:\\ExodoBackups (IGUALAR_TIPO_*.sql).',
        logs: logs,
      );

      await _conferirEsquemaBancos();
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isCriandoEstruturaLocal = false;
          _progressoEstruturaLocal = '';
        });
      }
    }
  }

  /// Abre a tela de conferência de DADOS (linhas por tabela, empresa por
  /// empresa) — o complemento do painel de estrutura.
  void _abrirConferenciaDeDados() {
    final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConferenciaLocalNuvemPage(
          empresaAberta: empresa?.nomeExibicao,
          empresaAbertaId: empresa?.id,
        ),
      ),
    );
  }

  /// Diálogo único para mostrar o passo a passo de uma comparação/criação.
  Future<void> _mostrarDialogoLogs({
    required String titulo,
    required String intro,
    required List<String> logs,
    String? aviso,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: 660,
          height: 440,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intro,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              if (aviso != null) ...[
                const SizedBox(height: 4),
                Text(aviso,
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      logs.join('\n'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  /// Cria o banco local (`exodo_db`) e as tabelas, quando o banco tiver sido
  /// apagado (ou a instalação parou no meio).
  ///
  /// Chama a mesma rotina que o app roda sozinho quando não consegue conectar
  /// (`DatabaseService.criarBancoLocal`) e mostra o passo a passo na tela.
  /// Nada é apagado: só cria o que faltar. Os dados voltam depois pelo
  /// "Sincronizar Completo" (nuvem → local).
  Future<void> _criarBancoLocal() async {
    final confirmar = await _confirmar(
      'Criar banco local',
      'Vai conferir se o banco "${EnvConfig.dbName}" existe e, se não existir, '
          'criá-lo com todas as tabelas (scripts/init_db.sql). Nada é apagado. Continuar?',
    );
    if (!confirmar) return;

    setState(() {
      _isCriandoBancoLocal = true;
      _progressoCriarBancoLocal = 'Conferindo o banco local...';
    });
    try {
      final (ok, logs) = await DatabaseService().criarBancoLocal(
        onProgress: (mensagem) {
          if (mounted) setState(() => _progressoCriarBancoLocal = mensagem);
        },
      );
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(
            ok ? '✅ Banco local pronto' : '⚠️ Banco local: atenção',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: SizedBox(
            width: 640,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Banco local do app (PostgreSQL). Se ele tiver sido apagado, é aqui '
                  'que ele volta a existir, com as tabelas. Os dados são recarregados '
                  'depois pelo "Sincronizar Completo".',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        logs.join('\n'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isCriandoBancoLocal = false;
          _progressoCriarBancoLocal = '';
        });
      }
    }
  }

  // ==================== HELPERS ====================

  /// Depois de uma restauração que mexe SÓ no banco local.
  ///
  /// Recarrega a interface a partir do PostgreSQL local e pergunta, de forma
  /// explícita, se os dados desta empresa devem subir para a nuvem. O padrão é
  /// NÃO enviar: restaurar não deve sobrescrever a nuvem sem uma decisão clara.
  Future<void> _aposRestaurarLocal(String contexto) async {
    if (!mounted) return;
    final dataService = Provider.of<DataService>(context, listen: false);
    setState(() => _progressoRestauracao = 'Carregando os dados restaurados...');
    try {
      await dataService.recarregarSomenteBancoLocal();
    } catch (e) {
      if (mounted) {
        _mostrarSnackBar('⚠️ Restaurado, mas falhou ao recarregar a tela: $e', Colors.orange);
      }
    }
    await _carregarDados();
    if (!mounted) return;

    final acao = await _dialogoPosRestauracao(contexto);
    if (!mounted) return;

    if (acao == _AcaoPosRestauracao.desfazer) {
      await _desfazerRestauracao();
      return;
    }

    if (acao == _AcaoPosRestauracao.enviar) {
      setState(() => _progressoRestauracao = 'Enviando esta empresa para a nuvem...');
      _mostrarSnackBar('☁️ Enviando esta empresa para a nuvem...', Colors.blue);
      final (okSync, msgSync) = await dataService.enviarDadosLocalParaNuvem();
      if (mounted) {
        _mostrarSnackBar(okSync ? '✅ $msgSync' : '⚠️ $msgSync',
            okSync ? Colors.green : Colors.orange);
      }
      return;
    }

    _mostrarSnackBar(
      '✅ $contexto A nuvem segue intacta — nada foi sobrescrito nem apagado lá.',
      Colors.green,
    );
  }

  /// Volta o banco local ao estado guardado automaticamente antes da última
  /// restauração.
  ///
  /// Também passa pelo ciclo seguro: gera uma foto do estado ATUAL antes de
  /// aplicar, roda com a fila de envio desligada e não toca na nuvem.
  Future<void> _desfazerRestauracao() async {
    if (!mounted) return;
    final caminho = _backupService!.ultimoBackupAntesDeRestaurar;
    if (caminho == null || !await File(caminho).exists()) {
      _mostrarSnackBar('⚠️ Não achei o arquivo do estado anterior', Colors.orange);
      return;
    }

    final nome = caminho.split(RegExp(r'[\\/]')).last;
    final confirmar = await _confirmar(
      'Desfazer a restauração',
      'Voltar o banco LOCAL de ${_nomeEmpresaComId()} para o estado de antes ($nome)?\n\n'
      '• O estado ATUAL também é guardado antes de aplicar — nenhum passo se perde.\n'
      '• A nuvem não é tocada.',
    );
    if (!confirmar) return;

    // O estado de antes de uma restauração do banco INTEIRO é um .dump; o de
    // uma restauração por empresa é um .sql. O desfazer segue o mesmo tipo.
    final ehDump = caminho.toLowerCase().endsWith('.dump') ||
        caminho.toLowerCase().endsWith('.pg_dump') ||
        caminho.toLowerCase().endsWith('.bak');

    setState(() {
      _isRestaurandoSqlLocal = true;
      _progressoRestauracao = 'Voltando ao estado anterior...';
    });
    try {
      final (ok, msg) = ehDump
          ? await _backupService!.restaurarDumpPostgres(File(caminho))
          : await _backupService!
              .restaurarBackupSqlDaEmpresa(File(caminho), motivo: 'desfazer');
      if (!mounted) return;
      _mostrarSnackBar(ok ? '↩️ $msg' : '❌ $msg', ok ? Colors.green : Colors.red);
      if (ok) {
        await Provider.of<DataService>(context, listen: false)
            .recarregarSomenteBancoLocal();
        await _carregarDados();
      }
    } catch (e) {
      if (mounted) _mostrarSnackBar('❌ Erro ao desfazer: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isRestaurandoSqlLocal = false;
          _progressoRestauracao = '';
        });
      }
    }
  }

  /// Aviso (quando aplicável) de que o sincronizador de bandeja está rodando.
  ///
  /// Ele também escreve no banco local e pode estar baixando dados da nuvem
  /// justamente durante a restauração — o que embaralharia o resultado. A
  /// restauração continua permitida, mas com o aviso na letra.
  Future<String> _avisoSincronizador() async {
    try {
      if (await SincronizadorManagerService.isSincronizadorRunning()) {
        return '\n⚠️ O SincronizadorNuvem.exe está RODANDO agora. Ele também escreve no banco '
            'local e pode baixar dados da nuvem no meio da restauração. O ideal é sair do '
            'sincronizador (ícone na bandeja do sistema → Sair / Fechar) antes de restaurar e '
            'reabrir depois.\n';
      }
    } catch (_) {}
    return '';
  }

  /// O que fazer depois de uma restauração local: desfazer, enviar para a nuvem
  /// ou simplesmente concluir (padrão).
  Future<_AcaoPosRestauracao> _dialogoPosRestauracao(String contexto) async {
    final desfazer = _backupService!.ultimoBackupAntesDeRestaurar;
    final nomeDesfazer =
        desfazer == null ? null : desfazer.split(RegExp(r'[\\/]')).last;

    final resultado = await showDialog<_AcaoPosRestauracao>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Restaurado SÓ no banco local',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: SingleChildScrollView(
          child: Text(
            '$contexto\n\n'
            '✅ O banco LOCAL já está com os dados do arquivo.\n'
            '✅ A NUVEM não foi tocada: nada foi apagado nem sobrescrito lá.\n'
            '${nomeDesfazer == null ? '' : '🛡️ O estado de antes ficou guardado em $nomeDesfazer '
                '(aparece na seção "Estados anteriores desta empresa").\n'}'
            '\nO que você quer fazer agora?\n\n'
            '• CONCLUIR — fica como está, só no banco local. É o mais seguro: você confere com '
            'calma e, se quiser, envia depois em "Enviar Local → Nuvem".\n\n'
            '• DESFAZER — volta o banco local para o estado de antes desta restauração.\n\n'
            '• ENVIAR PARA A NUVEM — a nuvem passa a ter a versão restaurada (um registro que '
            'existir nos dois lados é sobrescrito; o que estiver mais novo lá se perde).',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
          ),
        ),
        actions: [
          if (desfazer != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, _AcaoPosRestauracao.desfazer),
              child: const Text('Desfazer', style: TextStyle(color: Colors.orangeAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AcaoPosRestauracao.enviar),
            child: const Text('Enviar para a nuvem',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _AcaoPosRestauracao.concluir),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreenAccent),
            child: const Text('Concluir', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    return resultado ?? _AcaoPosRestauracao.concluir;
  }

  Future<bool> _confirmar(String titulo, String mensagem) async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            child: const Text('Confirmar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  void _mostrarSnackBar(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor, duration: const Duration(seconds: 3)),
    );
  }

  String _formatarTamanho(int? bytes) {
    if (bytes == null) return '--';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatarData(String? iso) {
    if (iso == null || iso.isEmpty) return '--';
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  /// Gera a lista de widgets que mostra o comparativo antes ↔ depois de uma
  /// restauração. Extraído do dialog para não poluir o método.
  ///
  /// Com [maiorPerdaPrimeiro] (usado na simulação) as tabelas que mais perdem
  /// registros aparecem no topo — é o que interessa na hora de decidir.
  List<Widget> _buildComparativoRestauracao(
    Map<String, ({int antes, int depois, int delta})> comparativo, {
    bool maiorPerdaPrimeiro = false,
  }) {
    final ordenado = comparativo.entries.toList();
    if (maiorPerdaPrimeiro) {
      ordenado.sort((a, b) {
        final porDelta = a.value.delta.compareTo(b.value.delta);
        return porDelta != 0 ? porDelta : a.key.compareTo(b.key);
      });
    } else {
      ordenado.sort((a, b) => a.key.compareTo(b.key));
    }
    return [
      for (final entry in ordenado)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: Text(entry.key,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 80,
                child: Text('${entry.value.antes}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              const Text(' → ',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              SizedBox(
                width: 80,
                child: Text('${entry.value.depois}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  entry.value.delta == 0
                      ? '='
                      : entry.value.delta > 0
                          ? '+${entry.value.delta}'
                          : '${entry.value.delta}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: entry.value.delta == 0
                        ? Colors.white38
                        : entry.value.delta > 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          // A empresa aparece aqui E no banner: é o dado mais importante da tela,
          // porque todo backup/restauração é feito por empresa.
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Backup e Restauração'),
              Text(
                _nomeEmpresaComId(),
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          toolbarHeight: 68,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregarDados,
              tooltip: 'Atualizar',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _carregarDados,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBannerEmpresa(),
                    const SizedBox(height: 12),
                    _buildSecaoSaudeBancos(),
                    const SizedBox(height: 12),
                    _buildCaminhoSeguro(),
                    const SizedBox(height: 12),
                    _buildLegendaFluxo(),
                    const SizedBox(height: 16),
                    _buildSecaoBackupLocal(),
                    const SizedBox(height: 16),
                    _buildSecaoBackupNuvem(),
                    const SizedBox(height: 16),
                    _buildSecaoRestaurar(),
                    const SizedBox(height: 16),
                    _buildSecaoEnviarLocalNuvem(),
                    const SizedBox(height: 16),
                    _buildSecaoBackupBancoNuvem(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  /// Banner do topo: deixa explícito para qual empresa as ações desta tela
  /// valem (todo backup e restauração aqui é por empresa).
  Widget _buildBannerEmpresa() {
    final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
    final nome = empresa?.nomeExibicao ?? 'Nenhuma empresa selecionada';
    final documento = (empresa?.cnpj ?? '').trim();
    final detalhes = [
      if (empresa != null) 'ID ${empresa.idCurto}',
      if (documento.isNotEmpty) 'CNPJ $documento',
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.18),
            Colors.purpleAccent.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storefront_outlined, color: Colors.cyanAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMPRESA SELECIONADA',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nome,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (detalhes.isNotEmpty)
                  Text(detalhes, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                const Text(
                  'Backup e restauração desta tela valem SOMENTE para esta empresa. '
                  'As outras empresas deste computador não são afetadas.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (_isTrocandoEmpresa) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _mensagemTrocaEmpresa.isEmpty ? 'Trocando de empresa...' : _mensagemTrocaEmpresa,
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_podeTrocarEmpresa())
            TextButton.icon(
              onPressed: _ocupado ? null : _abrirSeletorEmpresa,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Trocar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                backgroundColor: Colors.cyanAccent.withOpacity(0.12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }

  /// Passo a passo seguro da restauração — a resposta curta para "como restauro
  /// sem risco de perder o que está na nuvem?".
  /// PAINEL DE ACOMPANHAMENTO: como estão a estrutura do banco LOCAL e a do
  /// banco da NUVEM — quantas tabelas cada um tem, o que falta de cada lado e
  /// quais são os botões para igualar (nos dois sentidos).
  Widget _buildSecaoSaudeBancos() {
    final c = _conferenciaEsquema;
    final cor = c == null
        ? Colors.blueGrey
        : !c.leuOsDois
            ? Colors.orangeAccent
            : c.iguais
                ? Colors.greenAccent
                : Colors.amberAccent;

    final faltamNoLocal = c?.somenteNaNuvem.length ?? 0;
    final faltamNaNuvem = c?.somenteNoLocal.length ?? 0;
    final colunasNoLocal = c?.colunasFaltandoNoLocal.length ?? 0;
    final colunasNaNuvem = c?.colunasFaltandoNaNuvem.length ?? 0;
    // Colunas sensíveis (ex.: usuarios.senha) aparecem no relatório, mas o app
    // não as cria sozinho — o SQL salvo em disco as leva comentadas.
    final sensiveisNoLocal = (c?.colunasFaltandoNoLocal ?? const [])
        .map((x) => x.rotulo)
        .where(BackupRestoreService.colunasSensiveis.contains)
        .toList();
    // Colunas que existem na nuvem mas que o app não cria sozinho porque a
    // leitura passaria a filtrar por elas (hoje só empresas.empresa_id).
    final decisaoNoLocal = (c?.colunasFaltandoNoLocal ?? const [])
        .map((x) => x.rotulo)
        .where(BackupRestoreService.colunasQueExigemDecisao.contains)
        .toList();
    final colunasNoLocalEfetivas =
        colunasNoLocal - sensiveisNoLocal.length - decisaoNoLocal.length;
    // Quantas tabelas que JÁ existem ganham coluna nova (o trabalho que o botão
    // "⬇️ Criar NO LOCAL" também faz, além de criar tabela nova).
    final tabelasComColunaNova = (c?.colunasFaltandoNoLocal ?? const [])
        .where((x) => !BackupRestoreService.naoCriarSozinho(x.rotulo))
        .map((x) => x.tabela)
        .toSet()
        .length;
    final pendentesLocal = faltamNoLocal + colunasNoLocalEfetivas;
    final pendentesNuvem = faltamNaNuvem + colunasNaNuvem;
    // Colunas que só entram com autorização explícita (senha e as que mudam a
    // leitura) — o diálogo do botão "⬇️ Criar NO LOCAL" tem a opção de criá-las.
    final pendentesDecisao = sensiveisNoLocal.length + decisaoNoLocal.length;
    final tiposDiferentes = c?.tiposDiferentes ?? const <String>[];

    // O selo do topo diz o que FALTA, não um total abstrato: antes ele dizia
    // "109 DIVERGÊNCIA(S)" e não dava para saber se era tabela, coluna ou tipo.
    final tituloStatus = c == null
        ? 'AINDA NÃO CONFERIDO'
        : !c.leuOsDois
            ? 'NÃO DEU PARA LER OS DOIS'
            : (pendentesLocal + pendentesNuvem) == 0
                ? (c.tiposDiferentes.isEmpty
                    ? 'IGUAIS'
                    : '${c.tiposDiferentes.length} TIPO(S) DIFERENTE(S)')
                : '${pendentesLocal + pendentesNuvem} ITEM(NS) A CRIAR'
                    '${c.tiposDiferentes.isNotEmpty ? ' + ${c.tiposDiferentes.length} TIPO(S)' : ''}';

    final rotuloStatus = '$tituloStatus'
        '${c != null && c.sensiveisFaltando.isNotEmpty ? ' + ${c.sensiveisFaltando.length} SENSÍVEL(IS)' : ''}'
        '${pendentesDecisao > 0 ? ' + $pendentesDecisao A DECIDIR' : ''}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withOpacity(0.14), Colors.white.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: cor, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SAÚDE DOS BANCOS — LOCAL × NUVEM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cor.withOpacity(0.5)),
                ),
                child: Text(
                  rotuloStatus,
                  style: TextStyle(
                      color: cor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Acompanhe a estrutura dos dois bancos: quantas tabelas cada um tem, o que '
            'existe só de um lado e o que dá para igualar — sem sair desta tela.',
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quadroBanco(
                  '🏠 LOCAL — este computador',
                  c?.totalLocal,
                  EnvConfig.dbName,
                  Colors.lightBlueAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quadroBanco(
                  '☁️ NUVEM — Supabase',
                  c?.totalNuvem,
                  EnvConfig.supabaseDbNameFinal,
                  Colors.purpleAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (c != null) ...[
            Text(
              'Faltam NO LOCAL: $faltamNoLocal tabela(s) e $colunasNoLocal coluna(s)'
              '${sensiveisNoLocal.isNotEmpty ? ' (${sensiveisNoLocal.length} sensível(is) não conta(m))' : ''}'
              '${decisaoNoLocal.isNotEmpty ? ' (${decisaoNoLocal.length} precisa(m) de decisão)' : ''}  •  '
              'Faltam NA NUVEM: $faltamNaNuvem tabela(s) e $colunasNaNuvem coluna(s)  •  '
              'Tipos diferentes: ${c.tiposDiferentes.length}'
              '${c.objetoDiferenteNaNuvem.isNotEmpty || c.objetoDiferenteNoLocal.isNotEmpty ? '  •  TABELA × VIEW: ${c.objetoDiferenteNaNuvem.length + c.objetoDiferenteNoLocal.length}' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 8),
            // A resposta que importa: QUEM está atrasado.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: c.divergenciasReais == 0
                    ? Colors.greenAccent.withOpacity(0.08)
                    : Colors.orangeAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: c.divergenciasReais == 0
                      ? Colors.greenAccent.withOpacity(0.3)
                      : Colors.orangeAccent.withOpacity(0.3),
                ),
              ),
              child: Text(
                c.divergenciasReais == 0 ? '✅ ${c.veredito}' : '🧭 ${c.veredito}',
                style: TextStyle(
                  color: c.divergenciasReais == 0
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ),
            if (pendentesDecisao > 0) ...[
              const SizedBox(height: 6),
              Text(
                (pendentesDecisao == 1
                    ? '🔒 1 coluna só entra com a sua autorização (o app não cria sozinho): '
                        '${[...sensiveisNoLocal, ...decisaoNoLocal].join(', ')}'
                    : '🔒 ${pendentesDecisao} colunas só entram com a sua autorização (o app '
                        'não cria sozinho): ${[...sensiveisNoLocal, ...decisaoNoLocal].join(', ')}'),
                style: const TextStyle(color: Colors.redAccent, fontSize: 10.5),
              ),
            ],
            if (c.objetoDiferenteNaNuvem.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'ℹ️ Mesmo nome com tipo diferente — NÃO é tabela faltando: '
                '${c.objetoDiferenteNaNuvem.join(', ')} é TABELA aqui e VIEW na nuvem.',
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
            ],
            if (c.objetoDiferenteNoLocal.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'ℹ️ Mesmo nome com tipo diferente: '
                '${c.objetoDiferenteNoLocal.join(', ')} é VIEW aqui e TABELA na nuvem.',
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
            ],
            if (c.privadasDoApp.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                'Fora da conta (só existem aqui, de propósito): ${c.privadasDoApp.join(', ')}',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Última conferência: ${DateFormat('dd/MM/yyyy HH:mm').format(c.quando)} '
              '(${_tempoRelativo(c.quando)})',
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
            if (!c.leuOsDois) ...[
              const SizedBox(height: 6),
              Text(
                '⚠️ ${c.resumo}',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
              ),
            ],
            if (c.divergencias > 0) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(
                    () => _verDivergenciasEsquema = !_verDivergenciasEsquema),
                child: Row(
                  children: [
                    Icon(
                      _verDivergenciasEsquema
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.cyanAccent,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _verDivergenciasEsquema
                          ? 'Esconder o detalhe das divergências'
                          : 'Ver o detalhe das ${c.divergencias} divergência(s)',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
            if (_verDivergenciasEsquema && c.divergencias > 0) ...[
              const SizedBox(height: 8),
              _detalheDivergencia('Tabelas que existem SÓ na nuvem (criar no local)',
                  c.somenteNaNuvem, Colors.purpleAccent),
              _detalheDivergencia('Tabelas que existem SÓ no local (criar na nuvem)',
                  c.somenteNoLocal, Colors.amberAccent),
              _detalheDivergencia(
                  'Colunas que faltam NO LOCAL (o botão “⬇️ Criar NO LOCAL” cria todas, '
                  'menos as anotadas abaixo)',
                  c.colunasFaltandoNoLocal
                      .map((x) => BackupRestoreService.colunasSensiveis.contains(x.rotulo)
                          ? '${x.rotulo}   (sensível — só com a sua autorização)'
                          : BackupRestoreService.colunasQueExigemDecisao.contains(x.rotulo)
                              ? '${x.rotulo}   (só com a sua autorização — criá-la mudaria como o app lê a tabela)'
                              : x.rotulo)
                      .toList(),
                  Colors.purpleAccent),
              _detalheDivergencia('Colunas que faltam NA NUVEM',
                  c.colunasFaltandoNaNuvem.map((x) => x.rotulo).toList(),
                  Colors.amberAccent),
              _detalheDivergencia('Colunas com tipo diferente (não são alteradas)',
                  c.tiposDiferentes, Colors.white54),
              _detalheDivergencia('Tabela aqui e VIEW na nuvem (nada a criar)',
                  c.objetoDiferenteNaNuvem, Colors.white38),
              _detalheDivergencia('View aqui e TABELA na nuvem (nada a criar)',
                  c.objetoDiferenteNoLocal, Colors.white38),
            ],
          ],
          const SizedBox(height: 12),
          _botao(
            icon: Icons.health_and_safety_outlined,
            label: _isConferindoEsquema ? 'Conferindo...' : '🔎 Conferir agora (só leitura)',
            desc: 'Lê a estrutura do banco local e a da nuvem e compara: não cria, não altera e não envia nada',
            cor: Colors.lightGreenAccent,
            loading: _isConferindoEsquema,
            onTap: _isConferindoEsquema || _isCriandoEstruturaLocal ? null : _conferirEsquemaBancos,
          ),
          if (_isConferindoEsquema)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.lightGreenAccent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _progressoConferenciaEsquema.isEmpty
                          ? 'Conferindo...'
                          : _progressoConferenciaEsquema,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _botao(
            icon: Icons.cloud_upload_outlined,
            label: _isCriandoTabelas
                ? 'Criando na nuvem...'
                : c == null
                    ? '⬆️ Criar NA NUVEM o que falta aqui (confira primeiro)'
                    : '⬆️ Criar NA NUVEM o que falta aqui ($faltamNaNuvem tabela(s) + '
                        '$colunasNaNuvem coluna(s))',
            desc: 'O que este computador tem e a nuvem não: cria tabela/coluna nova lá, '
                'sem apagar dado nenhum',
            cor: Colors.amberAccent,
            loading: _isCriandoTabelas,
            onTap: (_isCriandoTabelas || _isCriandoEstruturaLocal || _isConferindoEsquema)
                ? null
                : _criarTabelasNoSupabase,
          ),
          const SizedBox(height: 10),
          _botao(
            icon: Icons.download_for_offline_outlined,
            label: _isCriandoEstruturaLocal
                ? 'Criando no local...'
                : c == null
                    ? '⬇️ Criar NO LOCAL o que falta aqui (confira primeiro)'
                    : '⬇️ Criar NO LOCAL o que falta aqui ($faltamNoLocal tabela(s) + '
                        '$colunasNoLocalEfetivas coluna(s) em $tabelasComColunaNova tabela(s))',
            desc: 'O que a nuvem tem e este computador não: cria tabela vazia/coluna nova SÓ no banco local',
            cor: Colors.cyanAccent,
            loading: _isCriandoEstruturaLocal,
            onTap: (_isCriandoTabelas || _isCriandoEstruturaLocal || _isConferindoEsquema)
                ? null
                : _criarEstruturaLocalFaltante,
          ),
          if (_isCriandoEstruturaLocal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.cyanAccent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _progressoEstruturaLocal.isEmpty
                          ? 'Criando no banco local...'
                          : _progressoEstruturaLocal,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          if (c != null && c.objetoDiferenteNaNuvem.isNotEmpty) ...[
            const SizedBox(height: 10),
            _botao(
              icon: Icons.merge_type,
              label: '🧩 Igualar TABELA × VIEW '
                  '(${c.objetoDiferenteNaNuvem.length}: ${c.objetoDiferenteNaNuvem.join(', ')})',
              desc: 'Aqui é TABELA, na nuvem é VIEW — é o que deixa este banco com 1 tabela a '
                  'mais. Troca só no local (tabela vazia → VIEW igual à da nuvem), com cópia '
                  'do estado atual em C:\\ExodoBackups',
              cor: Colors.tealAccent,
              loading: false,
              onTap: (_isCriandoTabelas || _isCriandoEstruturaLocal || _isConferindoEsquema)
                  ? null
                  : _igualarTabelaViewNaNuvem,
            ),
          ],
          if (c != null && tiposDiferentes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _botao(
              icon: Icons.straighten,
              label: '🔧 Igualar TIPOS de coluna (${tiposDiferentes.length})',
              desc: 'Estas colunas existem nos dois bancos com tipos diferentes (ex.: text aqui × '
                  'numeric lá). Converte SÓ no local, conferindo cada valor antes: valor que '
                  'não converte faz a coluna ser recusada, e a cópia para voltar atrás fica em '
                  'C:\\ExodoBackups',
              cor: Colors.deepOrangeAccent,
              loading: false,
              onTap: (_isCriandoTabelas || _isCriandoEstruturaLocal || _isConferindoEsquema)
                  ? null
                  : _igualarTiposDeColuna,
            ),
          ],
          const SizedBox(height: 10),
          _botao(
            icon: Icons.fact_check_outlined,
            label: '📊 Conferir os DADOS (linhas por empresa)',
            desc: 'Abre a conferência de contagem: quantas linhas cada tabela tem no local e na nuvem (só leitura)',
            cor: Colors.lightBlueAccent,
            loading: false,
            onTap: _abrirConferenciaDeDados,
          ),
          const SizedBox(height: 12),
          _buildLegendaSaudeBancos(
              sensiveisNoLocal, decisaoNoLocal, tiposDiferentes),
        ],
      ),
    );
  }

  /// Um dos dois quadros do painel (tabelas de um lado).
  Widget _quadroBanco(String titulo, int? tabelas, String banco, Color cor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            tabelas == null ? '—' : '$tabelas tabela(s)',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(banco, style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
        ],
      ),
    );
  }

  /// Lista curta de divergências de um tipo (com o total, para não enganar
  /// quando a lista é longa).
  Widget _detalheDivergencia(String titulo, List<String> itens, Color cor) {
    if (itens.isEmpty) return const SizedBox.shrink();
    final mostrados = itens.take(12).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$titulo (${itens.length})',
              style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          for (final item in mostrados)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text('• $item',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11, fontFamily: 'monospace')),
            ),
          if (itens.length > mostrados.length)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('… e mais ${itens.length - mostrados.length}. Lista completa em '
                  'C:\\ExodoBackups\\esquema_local_x_nuvem.txt',
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
            ),
        ],
      ),
    );
  }

  /// Legenda do painel: o que cada número quer dizer e o que cada botão faz.
  Widget _buildLegendaSaudeBancos(
    List<String> sensiveisNoLocal, [
    List<String> decisaoNoLocal = const [],
    List<String> tiposDiferentes = const [],
  ]) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O QUE ESTES NÚMEROS QUEREM DIZER',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _linhaLegenda(Icons.storage, Colors.lightBlueAccent, 'LOCAL / NUVEM (n tabelas)',
              'quantas tabelas cada banco tem hoje. Diferença de número NÃO é erro '
              'por si: significa que um lado tem tabela que o outro não tem.'),
          _linhaLegenda(Icons.cloud_download_outlined, Colors.purpleAccent,
              'Tabelas/colunas que faltam NO LOCAL',
              'existem na nuvem e não neste computador. Costuma ser instalação mais antiga. '
              'O botão "⬇️ Criar NO LOCAL" cria aqui — VAZIAS, sem dados e sem tocar na nuvem.'),
          _linhaLegenda(Icons.cloud_upload_outlined, Colors.amberAccent,
              'Tabelas/colunas que faltam NA NUVEM',
              'existem neste computador e não no Supabase — é o caso que gera o erro '
              '"tabela não existe" no Supabase. O botão "⬆️ Criar NA NUVEM" cria lá.'),
          _linhaLegenda(Icons.explore_outlined, Colors.orangeAccent, 'A linha do veredito',
              'responde "onde está o problema?": o app compara os DOIS sentidos e diz se é o LOCAL que '
              'está atrás (criar aqui), se é a NUVEM (criar lá) ou se só há diferença de tipo. '
              'Ela conta apenas o que dá para resolver — coluna sensível e nome que é view do outro '
              'lado ficam de fora.'),
          _linhaLegenda(Icons.info_outline, Colors.white54, 'Tabela × VIEW',
              'o mesmo nome existindo como TABELA de um lado e VIEW do outro NÃO é tabela faltando: '
              'não dá para criar tabela com um nome que já existe como view. Só que essa '
              'diferença CONTA diferente de cada lado (a view não entra na conta de tabelas) — '
              'é ela que faz o local aparecer com 1 tabela a mais que a nuvem. Use o botão '
              '🧩 "Igualar TABELA × VIEW" para trocar a tabela vazia pela view igual à da '
              'nuvem e os dois números ficarem iguais.'),
          _linhaLegenda(Icons.storage, Colors.blueGrey, 'Contagem de tabelas',
              'as privadas do app (_exodo_sync_log, _sync_controle, cache_dados) ficam FORA da conta '
              'nos dois lugares (aqui e no diálogo "Criar Tabelas no Supabase"), por isso o número '
              'daqui pode ser menor que o total do banco.'),
          _linhaLegenda(Icons.tune, Colors.white54, 'Tipos diferentes',
              'a mesma coluna existe nos dois lados com tipos distintos. É só aviso: o app '
              'NÃO altera tipo de coluna, porque isso pode dar prejuízo em dado existente.'),
          if (sensiveisNoLocal.isNotEmpty)
            _linhaLegenda(Icons.lock_outline, Colors.redAccent,
                'Colunas sensíveis (${sensiveisNoLocal.length})',
                '${sensiveisNoLocal.join(', ')} — o app NÃO cria estas colunas sozinho, '
                'porque mexem no login/segredo do sistema. Elas saem comentadas no SQL salvo '
                'em C:\\ExodoBackups\\CRIAR_TABELAS_LOCAL_*.sql, para você decidir.'),
          if (decisaoNoLocal.isNotEmpty || sensiveisNoLocal.isNotEmpty)
            _linhaLegenda(Icons.vpn_key_outlined, Colors.redAccent,
                'Colunas que só entram com a SUA autorização '
                '(${sensiveisNoLocal.length + decisaoNoLocal.length})',
                '${[...sensiveisNoLocal, ...decisaoNoLocal].join(', ')} — o app não as cria '
                'sozinho porque mudam como ele lê a tabela ou como o usuário entra no '
                'sistema. No diálogo do botão "⬇️ Criar NO LOCAL" existe a opção de criá-las '
                '(vêm desmarcadas), e o SQL salvo em disco as deixa comentadas.'),
          if (tiposDiferentes.isNotEmpty)
            _linhaLegenda(Icons.straighten, Colors.deepOrangeAccent,
                '🔧 Igualar TIPOS de coluna (${tiposDiferentes.length})',
                'a mesma coluna existe aqui com um tipo e na nuvem com outro (ex.: '
                'produtos.altura_cm é text aqui e numeric lá). O app não muda isso sozinho '
                'porque tipo com dado dentro pode dar prejuízo — este botão confere TODOS os '
                'valores antes: se algum não converter, a coluna é recusada e nada é alterado. '
                'O que entrar fica com o tipo EXATO da nuvem, e a reversão vai para '
                'C:\\ExodoBackups\\IGUALAR_TIPO_*.sql.'),
          _linhaLegenda(Icons.health_and_safety_outlined, Colors.lightGreenAccent,
              '🔎 Conferir agora',
              'só lê e compara a estrutura dos dois bancos. Não cria, não altera e não envia '
              'nada. O resultado fica salvo e continua na tela na próxima vez que você abrir.'),
          _linhaLegenda(Icons.fact_check_outlined, Colors.lightBlueAccent, '📊 Conferir os DADOS',
              'abre a tela que conta LINHAS por tabela, empresa por empresa — para ver o que '
              'falta de conteúdo, não de estrutura.'),
          const SizedBox(height: 2),
          Text(
            'Criar tabela ou coluna nunca apaga nada: é sempre tabela nova (vazia) ou coluna '
            'nova. O relatório completo fica em C:\\ExodoBackups\\esquema_local_x_nuvem.txt.',
            style: TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// "há 5 min", "há 2 dias" — para o usuário saber se a conferência é de agora.
  String _tempoRelativo(DateTime quando) {
    final diferenca = DateTime.now().difference(quando);
    if (diferenca.inMinutes < 1) return 'agora';
    if (diferenca.inMinutes < 60) return 'há ${diferenca.inMinutes} min';
    if (diferenca.inHours < 24) return 'há ${diferenca.inHours} h';
    return 'há ${diferenca.inDays} dia(s)';
  }

  Widget _buildCaminhoSeguro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.tealAccent.withOpacity(0.10),
            Colors.cyanAccent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety, color: Colors.tealAccent, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RESTAURAR SEM RISCO — A NUVEM NÃO É TOCADA',
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _passoSeguro(1, 'Salve uma rede de segurança',
              'Antes de tudo, use "Salvar Backup Completo na Nuvem" (última seção). É a única forma '
              'de voltar com o banco da nuvem como está hoje.'),
          _passoSeguro(2, 'Confira a empresa do topo',
              'Tudo nesta tela vale só para a empresa do banner acima. Se for outra, clique em "Trocar".'),
          _passoSeguro(3, 'Use 🔎 Simular (nos dumps)',
              'Mostra quantos registros cada tabela ganharia ou perderia, sem alterar nada.'),
          _passoSeguro(4, 'Restaure (↻) sabendo que é só local',
              'O arquivo é conferido antes (cortado ou incompleto é recusado), o estado atual da '
              'empresa é salvo automaticamente e a restauração roda numa transação única: ou '
              'aplica tudo, ou não muda nada.'),
          _passoSeguro(5, 'Desfazer está sempre a um clique',
              'Depois de restaurar aparece o botão Desfazer (e a lista "Estados anteriores desta '
              'empresa"), que volta o banco local ao estado de antes — inclusive de restaurações '
              'mais antigas.'),
          _passoSeguro(6, 'Confira antes de enviar',
              'No fim o app pergunta se quer enviar para a nuvem. Só envie quando tiver certeza de que '
              'a versão restaurada é a correta — enviar sobrescreve o que estiver mais novo lá.'),
          const SizedBox(height: 4),
          Text(
            'A nuvem só é alterada por: "Enviar Local → Nuvem", "Sincronizar Completo", '
            'o envio confirmado no fim de uma restauração, "Restaurar esta empresa na nuvem" '
            '(seção roxa — foto da nuvem de UMA empresa) e "Restaurar backup na nuvem" '
            '(também roxa, o único que SUBSTITUI tudo, de TODAS as empresas).',
            style: TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _passoSeguro(int numero, String titulo, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.tealAccent.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                  color: Colors.tealAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.35),
                children: [
                  TextSpan(
                    text: '$titulo — ',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: texto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Legenda fixa do topo: responde de uma vez a dúvida mais comum desta tela
  /// — "isso mexe no banco local, na nuvem, ou nos dois?".
  Widget _buildLegendaFluxo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O QUE CADA AÇÃO FAZ',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          _linhaLegenda(Icons.save_alt, Colors.greenAccent,
              'Backup / Gerar / Baixar',
              'só cria ou guarda o arquivo — não altera nenhum dado.'),
          _linhaLegenda(Icons.restore, Colors.cyanAccent, 'Restaurar (↻)',
              'substitui os dados desta empresa SÓ no banco LOCAL. A nuvem não é tocada — enviar '
              'para lá é uma pergunta separada, com o padrão "não enviar".'),
          _linhaLegenda(Icons.cloud_download, Colors.purpleAccent,
              'Backup do Banco da Nuvem',
              'é o único que trata TODAS as empresas: baixar/arquivar não altera nada; restaurar substitui tudo.'),
          _linhaLegenda(Icons.insights, Colors.tealAccent, '🔎 Simular / ↺ Restaurar (nas listas)',
              'a simulação compara, tabela por tabela, os registros do arquivo com o banco local e não '
              'altera nada; o ↺ restaura SÓ no banco local — inclusive nos arquivos que estão na nuvem, '
              'que são baixados na hora. O ⬇ só baixa o arquivo.'),
          _linhaLegenda(Icons.table_chart, Colors.amberAccent, 'Criar tabelas / colunas',
              'estrutura, não dado: cria o que falta de um lado (na nuvem ou no local). Só cria — '
              'nunca apaga nem muda o tipo de coluna que já existe.'),
          _linhaLegenda(Icons.monitor_heart_outlined, Colors.lightBlueAccent,
              'Saúde dos Bancos / Conferir os Dados',
              'só leitura: mostram como estão os dois bancos hoje (estrutura no painel do topo, '
              'linhas por empresa na tela de conferência).'),
        ],
      ),
    );
  }

  Widget _linhaLegenda(
      IconData icone, Color cor, String titulo, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11, height: 1.35),
                children: [
                  TextSpan(
                    text: '$titulo — ',
                    style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: texto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// SEÇÃO 1: Backup Local
  Widget _buildSecaoBackupLocal() {
    return _buildCard(
      icon: Icons.save_alt,
      cor: Colors.greenAccent,
      titulo: 'Backup Local',
      subtitulo: 'Dump do banco local (.dump) e backups por empresa (.sql)',
      children: [
        _botao(
          icon: Icons.backup,
          label: _isGerandoDump ? 'Gerando...' : 'Gerar Backup Dump',
          desc: 'Cria um arquivo .dump do banco de dados local',
          cor: Colors.greenAccent,
          loading: _isGerandoDump,
          onTap: _isGerandoDump ? null : _gerarDumpLocal,
        ),
        if (_dumpsLocais.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Últimos backups locais (${_nomeEmpresaComId()}):',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          ..._dumpsLocais.take(3).map((d) => _buildDumpLocalItem(d)),
        ],
        if (_backupsSqlLocais.isNotEmpty || _sqlLocaisDeOutrasEmpresas > 0)
          ..._buildListaBackupsSqlLocais(),
        ..._buildListaEstadosAnteriores(),
      ],
    );
  }

  /// Lista dos ESTADOS ANTERIORES (fotos automáticas feitas antes de cada
  /// restauração) — é o "desfazer" desta tela.
  List<Widget> _buildListaEstadosAnteriores() {
    if (_estadosAnteriores.isEmpty) return const [];

    final visiveis = _mostrarTodosEstadosAnteriores
        ? _estadosAnteriores
        : _estadosAnteriores.take(3).toList();

    return [
      const SizedBox(height: 16),
      Row(
        children: [
          const Icon(Icons.health_and_safety, color: Colors.lightGreenAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estados anteriores desta empresa (${_estadosAnteriores.length}) — desfazer:',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Fotos tiradas AUTOMATICAMENTE antes de cada restauração (em '
        'C:\\ExodoBackups\\_antes_de_restaurar). Restaurar uma delas devolve o banco local ao '
        'estado de antes daquela restauração — e, como toda restauração, também guarda o estado '
        'atual antes de aplicar, então nunca se perde o presente para recuperar o passado.',
        style: TextStyle(color: Colors.white38, fontSize: 10),
      ),
      const SizedBox(height: 8),
      ...visiveis.map((b) => _buildEstadoAnteriorItem(b)),
      if (_estadosAnteriores.length > 3)
        TextButton.icon(
          onPressed: () => setState(
              () => _mostrarTodosEstadosAnteriores = !_mostrarTodosEstadosAnteriores),
          icon: Icon(_mostrarTodosEstadosAnteriores ? Icons.expand_less : Icons.expand_more,
              size: 16),
          label: Text(
            _mostrarTodosEstadosAnteriores
                ? 'Mostrar só os 3 mais recentes'
                : 'Ver todos os ${_estadosAnteriores.length} estados',
            style: const TextStyle(fontSize: 11),
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.lightGreenAccent),
        ),
    ];
  }

  Widget _buildEstadoAnteriorItem(Map<String, dynamic> estado) {
    final registros = estado['registros'];
    final tabelas = estado['tabelas'];
    final detalhe = [
      _formatarTamanho(estado['size'] as int?),
      _formatarData(estado['date']?.toString()),
      if (registros != null) '$registros registros',
      if (tabelas != null) '$tabelas tabelas',
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.lightGreenAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.lightGreenAccent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.lightGreenAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(estado['name']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                Text(detalhe, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                const Text('Estado de ANTES de uma restauração',
                    style: TextStyle(color: Colors.lightGreenAccent, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_backup_restore,
                color: Colors.lightGreenAccent, size: 18),
            tooltip: 'Voltar o banco LOCAL para este estado (a nuvem não é tocada)',
            onPressed: _ocupado
                ? null
                : () => _restaurarBackupSqlLocal(
                      estado['path'],
                      estado['name'],
                      controleDeQualidade: true,
                    ),
          ),
        ],
      ),
    );
  }

  /// Lista dos backups .sql POR EMPRESA (`C:\ExodoBackups\<empresaId>`).
  ///
  /// Diferente do dump `.dump`, esses arquivos já nascem filtrados pela empresa:
  /// a restauração é direta (sem base temporária) e leva segundos.
  List<Widget> _buildListaBackupsSqlLocais() {
    final visiveis =
        _mostrarTodosSqlLocais ? _backupsSqlLocais : _backupsSqlLocais.take(3).toList();

    return [
      const SizedBox(height: 16),
      Row(
        children: [
          const Icon(Icons.restore_page, color: Colors.tealAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Backups .sql desta empresa (restauração direta):',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Restauram na hora, sem base temporária, e mexem SÓ nesta empresa — os dados atuais dela são '
        'substituídos pelos do arquivo.  🔎 simula (compara e não altera)  ·  ↺ restaura.',
        style: TextStyle(color: Colors.white38, fontSize: 10),
      ),
      const SizedBox(height: 8),
      ...visiveis.map((b) => _buildBackupSqlLocalItem(b)),
      if (_backupsSqlLocais.length > 3)
        TextButton.icon(
          onPressed: () => setState(() => _mostrarTodosSqlLocais = !_mostrarTodosSqlLocais),
          icon: Icon(_mostrarTodosSqlLocais ? Icons.expand_less : Icons.expand_more, size: 16),
          label: Text(
            _mostrarTodosSqlLocais
                ? 'Mostrar só os 3 mais recentes'
                : 'Ver todos os ${_backupsSqlLocais.length} backups',
            style: const TextStyle(fontSize: 11),
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
        ),
      if (_sqlLocaisDeOutrasEmpresas > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$_sqlLocaisDeOutrasEmpresas arquivo(s) .sql de OUTRAS empresas estão nessa pasta e foram ignorados.',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
          ),
        ),
    ];
  }

  Widget _buildBackupSqlLocalItem(Map<String, dynamic> backup) {
    final registros = backup['registros'];
    final tabelas = backup['tabelas'];
    final detalhe = [
      _formatarTamanho(backup['size'] as int?),
      _formatarData(backup['date']?.toString()),
      if (registros != null) '$registros registros',
      if (tabelas != null) '$tabelas tabelas',
    ].join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.tealAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.file_present, color: Colors.tealAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(backup['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                Text(detalhe, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text('Empresa confirmada pelo cabeçalho do arquivo',
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 10)),
                Text(
                    '↻ Restaura SÓ ${_nomeEmpresaComId()} no banco LOCAL (a nuvem não é tocada)',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights, color: Colors.tealAccent, size: 18),
            tooltip: 'Simular a restauração — compara os registros com o banco local e NÃO altera nada',
            onPressed: _ocupado
                ? null
                : () => _simularRestauracaoSql(
                      File(backup['path']),
                      backup['name'],
                      aoAplicar: () => _restaurarBackupSqlLocal(
                        backup['path'],
                        backup['name'],
                      ),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.tealAccent, size: 18),
            tooltip: 'Restaurar direto (rápido) — SOMENTE ${_nomeEmpresaComId()}',
            onPressed: _ocupado
                ? null
                : () => _restaurarBackupSqlLocal(backup['path'], backup['name']),
          ),
        ],
      ),
    );
  }

  Widget _buildDumpLocalItem(Map<String, dynamic> dump) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.file_copy, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dump['name'], style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                Text('${_formatarTamanho(dump['size'])} • ${_formatarData(dump['date'])}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text(
                    '↻ Restaura SÓ ${_nomeEmpresaComId()} no banco local (a nuvem não é tocada) — '
                    'você escolhe simular, só esta empresa ou banco inteiro',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights, color: Colors.tealAccent, size: 18),
            tooltip: 'Simular a restauração — compara os registros e NÃO altera nada',
            onPressed:
                _ocupado ? null : () => _simularRestauracaoDump(dump['path'], dump['name']),
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.cyanAccent, size: 18),
            tooltip: 'Restaurar este dump SOMENTE em ${_nomeEmpresaComId()}',
            onPressed:
                _ocupado ? null : () => _restaurarDumpLocal(dump['path'], dump['name']),
          ),
        ],
      ),
    );
  }

  /// SEÇÃO 2: Backup Nuvem — PostgreSQL (.sql) SOMENTE desta empresa
  Widget _buildSecaoBackupNuvem() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final ultimo = dataService.ultimoBackupNuvem;

    return _buildCard(
      icon: Icons.cloud,
      cor: Colors.cyanAccent,
      titulo: 'Backup Nuvem (PostgreSQL)',
      subtitulo: 'Backup .sql SÓ desta empresa — automático a cada 24h',
      children: [
        _botao(
          icon: Icons.cloud_upload_outlined,
          label: _isEnviandoBackupNuvem ? 'Enviando...' : 'Fazer Backup da Empresa Agora',
          desc: 'Gera um .sql (PostgreSQL) só com os dados desta empresa e envia para a nuvem',
          cor: Colors.cyanAccent,
          loading: _isEnviandoBackupNuvem,
          onTap: (_isEnviandoBackupNuvem || _isRestaurandoBackupNuvem) ? null : _enviarBackupNuvemAgora,
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.cloud_upload,
          label: _isEnviandoNuvem ? 'Enviando...' : 'Enviar Dump Completo (banco inteiro)',
          desc: 'Envia o último dump local .dump — contém TODAS as empresas',
          cor: Colors.tealAccent,
          loading: _isEnviandoNuvem,
          onTap: (_isEnviandoNuvem || _dumpsLocais.isEmpty) ? null : _enviarDumpNuvem,
        ),
        if (_dumpsLocais.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('⚠️ Gere um backup local primeiro para enviar o dump completo', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ultimo == null
                      ? 'Backup automático: a cada 24h o backup PostgreSQL desta empresa é gerado e enviado para a nuvem.'
                      : 'Backup automático (a cada 24h) — último envio em ${DateFormat('dd/MM/yyyy HH:mm').format(ultimo)}.',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (_isRestaurandoBackupNuvem)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
                SizedBox(width: 10),
                Text('Restaurando backup da nuvem...', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        if (_dumpsNuvem.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Backups na nuvem (${_nomeEmpresaComId()}):',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          const Text(
            'MESMAS ações da lista local: 🔎 simular  ·  ↺ restaurar  ·  (⬇ baixar sem restaurar)  ·  🗑 remover.\n'
            'O ↺ daqui é o MESMO da pasta local: baixa o arquivo e segue o mesmo caminho — conferência '
            'de integridade, estado atual guardado (desfazer de um clique), aplicação SÓ no banco local '
            'e a pergunta final sobre enviar para a nuvem. Quando o arquivo é do banco inteiro (.dump), '
            'abre a mesma escolha da lista local: simular / só esta empresa / banco inteiro.',
            style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.3),
          ),
          const SizedBox(height: 8),
          ..._dumpsNuvem.map((d) => _buildDumpNuvemItem(d)),
        ],
      ],
    );
  }

  Widget _buildDumpNuvemItem(Map<String, dynamic> dump) {
    final name = dump['name']?.toString() ?? '';
    final path = dump['path']?.toString() ?? '';
    final size = (dump['size'] as num?)?.toInt();
    final data = dump['createdAt']?.toString();
    final empresaNome = _nomeEmpresaComId();

    // .sql  → backup PostgreSQL SÓ desta empresa (restaura sem afetar as outras)
    // .dump → banco inteiro (restaurar substitui os dados de todas as empresas)
    final ehSql = name.toLowerCase().endsWith('.sql');
    final ocupado = _isRestaurandoDump ||
        _isRestaurandoBackupNuvem ||
        _isBaixandoBackupNuvem ||
        _isRestaurandoSqlLocal;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(ehSql ? Icons.verified_user : Icons.warning_amber,
              color: ehSql ? Colors.cyanAccent : Colors.orangeAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                Text(
                  ehSql
                      ? 'PostgreSQL • SÓ esta empresa — $empresaNome'
                      : 'Dump do banco inteiro • restaura só $empresaNome',
                  style: TextStyle(
                    color: ehSql ? Colors.cyanAccent : Colors.orangeAccent,
                    fontSize: 10,
                  ),
                ),
                Text('${_formatarTamanho(size)} • ${_formatarData(data)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
                Text(
                    ehSql
                        ? '↻ Restaura SÓ ${_nomeEmpresaComId()} no banco LOCAL (a nuvem não é tocada)'
                        : '↻ Baixa e aplica SÓ ${_nomeEmpresaComId()} no banco local (o arquivo tem todas as empresas)',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights, color: Colors.tealAccent, size: 18),
            tooltip: 'Simular (baixa sem aplicar) — compara os registros e NÃO altera nada',
            onPressed: ocupado ? null : () => _simularBackupNuvem(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.cyanAccent, size: 18),
            tooltip: ehSql
                ? 'Restaurar no banco LOCAL — SOMENTE ${_nomeEmpresaComId()}'
                : 'Baixar e restaurar no banco local — SOMENTE ${_nomeEmpresaComId()}',
            onPressed: ocupado
                ? null
                : () => ehSql
                    ? _restaurarBackupSqlNuvem(path, name)
                    : _restaurarDumpNuvem(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.green, size: 18),
            tooltip: 'Baixar o arquivo (não restaura nada)',
            onPressed: ocupado ? null : () => _baixarBackupNuvemSomente(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
            tooltip: 'Remover',
            onPressed: () async {
              final ok = await _confirmar('Remover backup?', 'Remover "$name" da nuvem?');
              if (ok) {
                await _backupService!.removerDumpNuvem(path);
                _carregarDados();
              }
            },
          ),
        ],
      ),
    );
  }

  /// SEÇÃO 3: Restaurar
  Widget _buildSecaoRestaurar() {
    return _buildCard(
      icon: Icons.restore,
      cor: Colors.blueAccent,
      titulo: 'Restaurar',
      subtitulo: 'Restaura os backups SOMENTE na empresa selecionada',
      children: [
        if (_restaurando || _isSimulandoDump)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 12),
                  Text(
                    _progressoRestauracao.isNotEmpty
                        ? _progressoRestauracao
                        : (_isSimulandoDump
                            ? 'Simulando a restauração (nada é alterado)...'
                            : 'Restaurando... isso pode demorar.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Os dumps são do banco inteiro, mas a restauração aplica SOMENTE os dados de '
                    '${_nomeEmpresaComId()} — as outras empresas deste computador não são tocadas.\n\n'
                    'Atalho: os backups .sql por empresa restauram direto, na hora — tanto os da pasta '
                    'deste computador (card "Backup Local") quanto os que estão na nuvem (card "Backup '
                    'Nuvem"): lá tem 🔎 simular e ↺ restaurar SÓ no banco local (a nuvem não é tocada).',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orangeAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A restauração substitui os dados atuais desta empresa. Faça um backup antes!',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// SEÇÃO 4: Enviar Local → Nuvem
  Widget _buildSecaoEnviarLocalNuvem() {
    return _buildCard(
      icon: Icons.sync_alt,
      cor: Colors.tealAccent,
      titulo: 'Sincronizar com Nuvem',
      subtitulo: 'Enviar dados locais para o Supabase',
      children: [
        _botao(
          icon: Icons.sync,
          label: _isSincronizandoCompleto ? 'Sincronizando...' : 'Sincronizar Completo (Local ↔ Nuvem)',
          desc: 'Baixa da nuvem, junta com o local e envia de volta — unifica 2 máquinas',
          cor: Colors.tealAccent,
          loading: _isSincronizandoCompleto,
          onTap: _isSincronizandoCompleto ? null : _sincronizarCompleto,
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.cloud_upload,
          label: _isEnviandoLocalNuvem ? 'Enviando...' : 'Enviar Local → Nuvem',
          desc: 'Envia todas as tabelas locais para o Supabase',
          cor: Colors.orangeAccent,
          loading: _isEnviandoLocalNuvem,
          onTap: (_isEnviandoLocalNuvem || _isSincronizandoCompleto) ? null : _enviarLocalNuvem,
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.table_chart,
          label: _isCriandoTabelas ? 'Comparando...' : 'Criar Tabelas no Supabase',
          desc: 'Compara o banco local com a nuvem e cria as tabelas e colunas que faltam lá',
          cor: Colors.amberAccent,
          loading: _isCriandoTabelas,
          onTap: (_isCriandoTabelas || _isEnviandoLocalNuvem || _isSincronizandoCompleto || _isCriandoBancoLocal)
              ? null
              : _criarTabelasNoSupabase,
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.compare_arrows,
          label: 'Comparar Local × Nuvem (sem criar)',
          desc: 'Mostra o que falta na nuvem e salva o SQL em C:\\ExodoBackups — não altera nada',
          cor: Colors.lightGreenAccent,
          loading: false,
          onTap: (_isCriandoTabelas || _isEnviandoLocalNuvem || _isSincronizandoCompleto || _isCriandoBancoLocal)
              ? null
              : () => _criarTabelasNoSupabase(somenteComparar: true),
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.storage,
          label: _isCriandoBancoLocal ? 'Criando banco local...' : 'Criar Banco Local (se apagado)',
          desc: 'Confere se o banco "${EnvConfig.dbName}" existe e, se não existir, cria ele '
              'e as tabelas (init_db.sql) — não apaga nada',
          cor: Colors.blueAccent,
          loading: _isCriandoBancoLocal,
          onTap: (_isCriandoBancoLocal || _isCriandoTabelas || _isEnviandoLocalNuvem || _isSincronizandoCompleto)
              ? null
              : _criarBancoLocal,
        ),
        if (_isCriandoBancoLocal)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _progressoCriarBancoLocal.isEmpty
                        ? 'Criando o banco local...'
                        : _progressoCriarBancoLocal,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (_isCriandoTabelas)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _progressoTabelasNuvem.isEmpty ? 'Comparando...' : _progressoTabelasNuvem,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// SEÇÃO 5: Backup do banco inteiro da NUVEM (Supabase)
  Widget _buildSecaoBackupBancoNuvem() {
    final configurado = EnvConfig.backupBancoNuvemConfigurado;
    final intervaloHoras = EnvConfig.backupCompletoNuvemHoras;
    final ultimoCompleto =
        Provider.of<DataService>(context, listen: false).ultimoBackupCompletoNuvem;

    return _buildCard(
      icon: Icons.cloud_download,
      cor: Colors.purpleAccent,
      titulo: 'Backup do Banco da Nuvem',
      subtitulo: 'Cópia completa do Supabase (todas as empresas) + foto da nuvem por empresa',
      children: [
        _botao(
          icon: Icons.download_for_offline,
          label: _isBaixandoBackupNuvem ? 'Baixando...' : 'Baixar Backup Completo da Nuvem',
          desc: 'Gera um backup de TODO o banco da nuvem (.dump ou .sql) em C:\\ExodoBackups\\nuvem',
          cor: Colors.purpleAccent,
          loading: _isBaixandoBackupNuvem,
          onTap: _isBaixandoBackupNuvem ? null : _baixarBackupBancoNuvem,
        ),
        const SizedBox(height: 12),
        _botao(
          icon: Icons.cloud_upload_outlined,
          label: _isEnviandoBackupCompletoNuvem
              ? 'Enviando...'
              : 'Salvar Backup Completo na Nuvem',
          desc: 'Gera a cópia completa (todas as empresas) e arquiva na própria nuvem — '
              'bucket dumps/_banco_completo',
          cor: Colors.deepPurpleAccent,
          loading: _isEnviandoBackupCompletoNuvem,
          onTap: (_isEnviandoBackupCompletoNuvem || _isBaixandoBackupNuvem || !configurado)
              ? null
              : _enviarBackupCompletoNuvem,
        ),
        if (_isEnviandoBackupCompletoNuvem)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _mensagemProgressoBackupCompleto.isEmpty
                        ? 'Preparando...'
                        : _mensagemProgressoBackupCompleto,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.deepPurpleAccent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.deepPurpleAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  intervaloHoras == 0
                      ? 'Backup completo automático DESLIGADO. Ligue no .env com '
                          'BACKUP_COMPLETO_NUVEM_HORAS=24 (ou use o botão acima).'
                      : 'Automático a cada ${intervaloHoras}h'
                          '${ultimoCompleto != null ? ' — último em ${DateFormat('dd/MM/yyyy HH:mm').format(ultimoCompleto)}' : ' — nenhum envio ainda'}. '
                          'Intervalo configurável no .env: BACKUP_COMPLETO_NUVEM_HORAS.',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        if (_backupsCompletosNuvem.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Backups completos arquivados na nuvem (${_backupsCompletosNuvem.length} — todas as empresas, mantidos os 10 mais recentes):',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ..._backupsCompletosNuvem.map((b) => _buildBackupCompletoNuvemItem(b)),
        ],
        _buildSnapshotNuvemEmpresa(),
        if (!configurado)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orangeAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Para funcionar, preencha SUPABASE_POOLER_PASSWORD no arquivo .env com a senha do BANCO do '
                    'Supabase (painel → Project Settings → Database → Database password). As chaves de API '
                    '\"sb_secret_...\" não servem como senha.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Sub-seção: backup DA NUVEM de UMA empresa (a rede de segurança que faltava).
  Widget _buildSnapshotNuvemEmpresa() {
    final empresa = _nomeEmpresaComId();
    final configurado = EnvConfig.backupBancoNuvemConfigurado;
    final ocupado = _isBaixandoSnapshotNuvem || _isRestaurandoSnapshotNaNuvem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.photo_camera_back, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BACKUP SÓ DESTA EMPRESA, TIRADO DA NUVEM',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Lê o banco do SUPABASE e salva o que $empresa tem lá hoje. '
                'O "Backup PostgreSQL na Nuvem" da seção de cima é gerado do banco LOCAL e só '
                'depois arquivado — se o local estiver errado, ele não devolve a nuvem. '
                'Este aqui é a foto do estado real da nuvem: é a rede de segurança para reverter '
                'o Supabase sem depender deste computador.',
                style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 12),
              _botao(
                icon: Icons.download_for_offline,
                label: _isBaixandoSnapshotNuvem
                    ? 'Baixando da nuvem...'
                    : 'Baixar Backup Desta Empresa da Nuvem',
                desc: 'Salva um .sql com os dados desta empresa que estão no Supabase '
                    '(C:\\ExodoBackups\\nuvem\\empresas) — não altera nada',
                cor: Colors.orangeAccent,
                loading: _isBaixandoSnapshotNuvem,
                onTap: (_isBaixandoSnapshotNuvem || _isRestaurandoSnapshotNaNuvem || !configurado)
                    ? null
                    : _baixarSnapshotNuvemEmpresa,
              ),
            ],
          ),
        ),
        if (_isBaixandoSnapshotNuvem || _isRestaurandoSnapshotNaNuvem)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _progressoSnapshotNuvem.isEmpty ? 'Trabalhando...' : _progressoSnapshotNuvem,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (_snapshotsNuvemEmpresa.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Fotos da nuvem desta empresa (${_snapshotsNuvemEmpresa.length}, em '
            'C:\\ExodoBackups\\nuvem\\empresas):',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ..._snapshotsNuvemEmpresa
              .take(5)
              .map((b) => _buildSnapshotNuvemItem(b, ocupado)),
          if (_snapshotsNuvemEmpresa.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${_snapshotsNuvemEmpresa.length - 5} foto(s) mais antiga(s) — todas ficam em '
                'C:\\ExodoBackups\\nuvem\\empresas (nada é apagado automaticamente).',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Nenhuma foto da nuvem guardada ainda para $empresa. '
              'Baixe uma agora: é o único arquivo que consegue devolver a nuvem como ela está hoje.',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildSnapshotNuvemItem(Map<String, dynamic> backup, bool ocupado) {
    final name = backup['name']?.toString() ?? '';
    final path = backup['path']?.toString() ?? '';
    final size = (backup['size'] as num?)?.toInt();
    final data = backup['modified']?.toString();
    final registros = backup['registros'];
    final tabelas = backup['tabelas'];
    final ehSeguranca = name.startsWith('ANTES_DE_RESTAURAR_');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(
            ehSeguranca ? Icons.shield_outlined : Icons.photo_camera_back,
            color: Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                Text(
                  ehSeguranca
                      ? 'Foto automática do estado ANTERIOR da nuvem'
                      : 'Fotografia do Supabase • só esta empresa',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
                ),
                Text(
                  '${_formatarTamanho(size)} • ${_formatarData(data)}'
                  '${registros != null ? ' • $registros registro(s)' : ''}'
                  '${tabelas != null ? ' em $tabelas tabela(s)' : ''}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: Colors.white54, size: 18),
            tooltip: 'Conferir o cabeçalho do arquivo',
            onPressed: () => _previewSnapshotNuvem(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.cyanAccent, size: 18),
            tooltip: 'Restaurar esta foto no banco LOCAL (a nuvem não é tocada)',
            onPressed: ocupado ? null : () => _restaurarBackupSqlLocal(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.redAccent, size: 18),
            tooltip: 'RESTAURAR ESTA EMPRESA NA NUVEM (altera o Supabase — só esta empresa)',
            onPressed: ocupado ? null : () => _restaurarSnapshotNaNuvem(path, name),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCompletoNuvemItem(Map<String, dynamic> backup) {
    final name = backup['name']?.toString() ?? '';
    final path = backup['path']?.toString() ?? '';
    final size = (backup['size'] as num?)?.toInt();
    final data = backup['createdAt']?.toString();
    final ocupado = _isBaixandoBackupCompletoNuvem || _isEnviandoBackupCompletoNuvem || _isRestaurandoCompletoNaNuvem;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepPurpleAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.deepPurpleAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const Text('Banco inteiro • TODAS as empresas',
                    style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 10)),
                Text('${_formatarTamanho(size)} • ${_formatarData(data)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download, color: Colors.green, size: 18),
            tooltip: 'Baixar para C:\\ExodoBackups\\nuvem',
            onPressed: ocupado ? null : () => _baixarBackupCompletoNuvem(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.restore_page, color: Colors.orangeAccent, size: 18),
            tooltip: 'Restaurar este backup na nuvem (SUBSTITUI todos os dados)',
            onPressed: ocupado || _isRestaurandoCompletoNaNuvem
                ? null
                : () => _restaurarBackupCompletoNaNuvem(path, name),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            tooltip: 'Remover da nuvem',
            onPressed: ocupado ? null : () => _removerBackupCompletoNuvem(path, name),
          ),
        ],
      ),
    );
  }

  // ==================== WIDGETS BASE ====================

  Widget _buildCard({
    required IconData icon,
    required Color cor,
    required String titulo,
    required String subtitulo,
    required List<Widget> children,
  }) {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _botao({
    required IconData icon,
    required String label,
    required String desc,
    required Color cor,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              loading
                  ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: cor))
                  : Icon(icon, color: cor, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(desc, style: TextStyle(color: cor.withOpacity(0.6), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
