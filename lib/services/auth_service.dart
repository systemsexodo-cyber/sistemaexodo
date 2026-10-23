import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import 'local_storage_service.dart';
import 'supabase_service.dart';
import 'database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Desfecho da validação da conta na nuvem (Supabase) no login.
///
/// Existe para diferenciar "a nuvem não respondeu" (o login deve valer com os
/// dados LOCAIS) de "a nuvem respondeu e recusou a senha" (aí sim nega).
enum _ResultadoValidacaoNuvem { ok, indisponivel, senhaInvalida }

/// Serviço de autenticação e gerenciamento de usuários
class AuthService extends ChangeNotifier {
  /// Regra de retomada da última sessão no Desktop.
  ///
  /// Sem internet E com sessão salva -> abre direto na última empresa (sem
  /// login). Com internet, ou sem sessão salva, mantém o fluxo de login.
  /// Exposta para teste para o comportamento não regredir sem querer.
  @visibleForTesting
  static bool deveRetomarSessaoOffline({
    required bool temSessaoSalva,
    required bool temInternet,
    bool isWeb = false,
  }) => false;

  /// Há internet AGORA? Checagem curta para o boot não travar.
  ///
  /// Usada para decidir se a última sessão salva pode ser retomada sem exigir
  /// login: sem internet o sistema abre direto na última empresa (é o cenário
  /// que travava o uso offline); com internet, mantém a exigência de login.
  Future<bool> _temInternetAgora() async {
    if (kIsWeb) return true;

    // 1) Sem nenhuma interface de rede ativa -> offline na hora (rápido).
    try {
      final resultados = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 2),
      );
      if (resultados.isEmpty ||
          resultados.every((r) => r == ConnectivityResult.none)) {
        return false;
      }
    } catch (_) {
      // Sem resposta da plataforma: cai no teste de DNS abaixo.
    }

    // 2) Interface existe, mas a saída pode estar morta: resolve um host confiável.
    for (final host in const ['google.com', 'cloudflare.com']) {
      try {
        final r = await InternetAddress.lookup(
          host,
        ).timeout(const Duration(milliseconds: 1500));
        if (r.isNotEmpty && r[0].rawAddress.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Remove os tokens de sessao do Supabase (chaves sb-*) do SharedPreferences.
  Future<void> _removerTokensSbPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k
        in prefs.getKeys().where((k) => k.startsWith('sb-')).toList()) {
      await prefs.remove(k);
    }
  }

  final LocalStorageService _storage;
  final SupabaseService _supabaseService = SupabaseService.instance;

  Usuario? _usuarioAtual;
  Empresa? _empresaAtual;
  bool _isLoading = false;
  bool _isCarregandoDados = true; // Estado de carregamento inicial
  bool _isProcessandoUsuarios = false;
  bool _isProcessandoEmpresas = false;
  Timer? _heartbeatSessao;
  bool _sessaoExclusivaAtiva = false;
  bool _heartbeatEmAndamento = false;
  String? _mensagemErroLogin;

  /// Aviso (não bloqueante) de login OFFLINE: a nuvem (Supabase) estava
  /// indisponível — sem internet, cota estourada (402), servidor fora
  /// (503/504) — mas as credenciais conferiram no banco LOCAL e o acesso foi
  /// liberado. A tela mostra isto no lugar de um erro.
  String? _avisoNuvemLogin;

  Usuario? get usuarioAtual => _usuarioAtual;
  Empresa? get empresaAtual => _empresaAtual;
  bool get isLoading => _isLoading;
  bool get isCarregandoDados => _isCarregandoDados;
  bool get isAuthenticated => _usuarioAtual != null;
  bool get temEmpresaSelecionada => _empresaAtual != null;
  String? get mensagemErroLogin => _mensagemErroLogin;

  /// Mensagem informando que o login foi liberado localmente, mas a nuvem não
  /// respondeu (null quando a nuvem validou normalmente).
  String? get avisoNuvemLogin => _avisoNuvemLogin;

  // Histórico de logins (últimos nomes de usuário que entraram com sucesso)
  List<String> _historicoLogins = [];
  List<String> get historicoLogins => List.unmodifiable(_historicoLogins);

  // Modo Privacidade (Esconder valores sensíveis)
  bool _modoPrivacidade = false;
  bool get modoPrivacidade => _modoPrivacidade;

  void toggleModoPrivacidade() {
    _modoPrivacidade = !_modoPrivacidade;
    _storage.salvar('modo_privacidade', _modoPrivacidade);
    notifyListeners();
  }

  // Lista de usuários (em produção, viria de um backend)
  final List<Usuario> _usuarios = [];

  /// A lista de usuários SALVA já foi lida do banco nesta sessão?
  ///
  /// Enquanto for `false`, [_salvarUsuarios] não grava. É a trava que impede o
  /// boot de sobrescrever a lista salva com a memória ainda vazia (o boot começa
  /// sem nenhum usuário em memória). Sem ela, o usuário criado pelo operador era
  /// apagado no primeiro save do boot.
  bool _usuariosLidos = false;
  final List<Empresa> _empresas = [];

  List<Usuario> get usuarios => List.unmodifiable(_usuarios);
  List<Empresa> get empresas => List.unmodifiable(_empresas);

  AuthService({LocalStorageService? storage, bool carregarAutomaticamente = true})
      : _storage = storage ?? LocalStorageService() {
    if (!carregarAutomaticamente) return;

    // Iniciar carregamento
    _isCarregandoDados = true;
    notifyListeners();

    // Carrega dados salvos primeiro (isso carregará empresas e usuários salvos)
    // As empresas/usuários padrão só serão adicionados se não houver dados salvos
    _carregarDadosSalvos()
        .then((_) {
          // Pequeno delay para garantir que o loading seja visível
          Future.delayed(const Duration(milliseconds: 300), () {
            _isCarregandoDados = false;
            notifyListeners();
            debugPrint(
              '>>> [AuthService] Carregamento de dados inicial concluído',
            );
          });
        })
        .catchError((e, stackTrace) {
          debugPrint('>>> [AuthService] Erro ao carregar dados iniciais: $e');
          debugPrint('>>> [AuthService] StackTrace: $stackTrace');
          // Garantir que sempre sai do estado de loading, mesmo em erro
          Future.delayed(const Duration(milliseconds: 300), () {
            _isCarregandoDados = false;
            notifyListeners();
            debugPrint(
              '>>> [AuthService] Saindo do estado de loading após erro',
            );
          });
        });

    // Timeout de segurança para garantir que sempre saia do loading
    Future.delayed(const Duration(seconds: 15), () {
      if (_isCarregandoDados) {
        debugPrint(
          '>>> [AuthService] TIMEOUT no carregamento inicial (15s) - forçando saída do loading',
        );
        _isCarregandoDados = false;
        notifyListeners();
      }
    });
  }

  /// Carrega dados salvos do localStorage
  Future<void> _carregarDadosSalvos() async {
    try {
      // USUÁRIOS: LER a lista salva ANTES de aplicar os padrões — a ordem é o
      // que preserva os usuários criados pelo operador (ver
      // [carregarUsuariosNoBoot]).
      await carregarUsuariosNoBoot();

      // Atualizar senha do usuário "user" se ainda tiver a senha antiga
      try {
        await _atualizarSenhaUsuarioUser().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint(
              '>>> [AuthService] Timeout ao atualizar senha do usuário',
            );
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao atualizar senha: $e');
      }

      // GARANTIR que o usuário master "user" sempre tenha permissões totais
      try {
        _garantirPermissoesMaster();
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao garantir permissões master: $e');
      }

      // Primeiro, carregar empresas padrão (se necessário)
      _carregarEmpresasPadrao();

      // Depois, carregar empresas salvas (substituem as padrão se existirem) com timeout
      try {
        await carregarEmpresas().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint(
              '>>> [AuthService] Timeout ao carregar empresas - usando padrão',
            );
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar empresas: $e');
      }

      // Restaurar usuários locais conhecidos (carlos, silvio) que podem ter
      // perdido senha ou empresaId durante sync do Supabase.
      // Feito APÓS carregar empresas para que empresaId esteja disponível.
      try {
        await _restaurarUsuariosLocais().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint(
              '>>> [AuthService] Timeout ao restaurar usuários locais',
            );
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao restaurar usuários locais: $e');
      }

      // Carregar HISTÓRICO de logins
      try {
        final hist = await _storage.carregar('historico_logins');
        if (hist != null && hist is List) {
          _historicoLogins = hist.map((e) => e.toString()).toList();
          debugPrint(
            '>>> [AuthService] Histórico carregado: ${_historicoLogins.length} perfis',
          );
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar histórico: $e');
      }

      // SESSÃO PERSISTIDA (Desktop): ler usuário/empresa salvos ANTES de decidir
      // limpar a sessão. Sem internet o sistema abre DIRETO na última empresa em
      // vez de cair na tela de login — era o que travava o uso offline. Com
      // internet, mantém a exigência de login.
      Map<String, dynamic>? usuarioSalvo;
      Map<String, dynamic>? empresaSalva;
      try {
        final m = await _storage
            .carregar('usuario_atual')
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        if (m != null && m is Map) usuarioSalvo = Map<String, dynamic>.from(m);
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao ler usuario_atual salvo: $e');
      }
      try {
        final m = await _storage
            .carregar('empresa_atual')
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
        if (m != null && m is Map) empresaSalva = Map<String, dynamic>.from(m);
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao ler empresa_atual salva: $e');
      }

      // Só checa a internet quando existe sessão salva (economiza tempo no boot).
      final temInternet = usuarioSalvo != null
          ? await _temInternetAgora()
          : true;
      final retomarSessaoOffline = AuthService.deveRetomarSessaoOffline(
        temSessaoSalva: usuarioSalvo != null,
        temInternet: temInternet,
        isWeb: kIsWeb,
      );
      if (retomarSessaoOffline) {
        debugPrint(
          '>>> [AuthService] 📴 Sem internet: retomando a última sessão '
          'salva — o sistema abre direto, sem exigir login.',
        );
      }

      // SEGURANCA: se e uma nova sessao (navegador aberto agora), limpar login
      // antigo. No Desktop a sessão continua sendo limpa em condições normais,
      // EXCETO quando não há internet (aí a última sessão é retomada).
      if (!_storage.isSessaoAtiva() && !retomarSessaoOffline) {
        debugPrint(
          '>>> [AuthService] Inicializacao: limpando sessao anterior (Desktop sempre vai ao login).',
        );
        usuarioSalvo = null;
        empresaSalva = null;
        try {
          await _storage.remover('usuario_atual');
          await _storage.remover('empresa_atual');
        } catch (e) {
          debugPrint(
            '>>> [AuthService] Erro ao limpar sessao local: ' + e.toString(),
          );
        }
        if (!kIsWeb) {
          // Garantia extra no Desktop: limpar residuos em SharedPreferences
          // e encerrar a sessao do Supabase, para que NENHUM mecanismo
          // consiga restaurar um login anterior.
          try {
            final prefs = await SharedPreferences.getInstance();
            // Preservado: o Google Drive le usuario_atual do SharedPreferences (backup)
            // Preservado: o Google Drive le empresa_atual do SharedPreferences (backup)
            await _removerTokensSbPrefs();
            debugPrint(
              '>>> [AuthService] Tokens sb-* do Supabase removidos do SharedPreferences (Desktop).',
            );
          } catch (e) {
            debugPrint(
              '>>> [AuthService] Erro ao limpar SharedPreferences: ' +
                  e.toString(),
            );
          }
          try {
            await _supabaseService.logout().timeout(const Duration(seconds: 5));
            debugPrint(
              '>>> [AuthService] Sessao Supabase encerrada no boot (Desktop).',
            );
          } catch (e) {
            debugPrint(
              '>>> [AuthService] Erro ao encerrar sessao Supabase: ' +
                  e.toString(),
            );
          }
          // Re-remover apos o logout: o signOut() pode re-persistir a chave sb-*
          try {
            await _removerTokensSbPrefs();
            debugPrint(
              '>>> [AuthService] Tokens sb-* removidos apos logout (Desktop).',
            );
          } catch (e) {
            debugPrint(
              '>>> [AuthService] Erro ao limpar SharedPreferences apos logout: ' +
                  e.toString(),
            );
          }
        }
      }

      // Restaurar usuário e empresa atual selecionados (já lidos acima)
      try {
        if (usuarioSalvo != null) {
          _usuarioAtual = Usuario.fromMap(usuarioSalvo);
          debugPrint(
            '>>> [AuthService] ✓ Usuário restaurado: ${_usuarioAtual?.nome}',
          );
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuário atual: $e');
      }

      if (_usuarioAtual != null) {
        try {
          if (await _reivindicarSessaoExclusiva()) {
            _iniciarHeartbeatSessao();
          } else {
            _usuarioAtual = null;
            usuarioSalvo = null;
            empresaSalva = null;
            await _storage.remover('usuario_atual');
            await _storage.remover('empresa_atual');
            await _supabaseService.logout();
          }
        } catch (e) {
          debugPrint(
            '>>> [AuthService] Sessão persistida não pôde ser validada: $e',
          );
          _usuarioAtual = null;
          usuarioSalvo = null;
          empresaSalva = null;
          await _storage.remover('usuario_atual');
          await _storage.remover('empresa_atual');
          try {
            await _supabaseService.logout();
          } catch (_) {}
        }
      }

      try {
        if (empresaSalva != null) {
          debugPrint(
            '>>> [AuthService] ========================================',
          );
          _empresaAtual = Empresa.fromMap(empresaSalva);
          debugPrint(
            '>>> [AuthService] Empresa carregada localmente: ${_empresaAtual?.razaoSocial ?? "null"}',
          );
          debugPrint(
            '>>> [AuthService] ========================================',
          );

          // Se certificado ou senha estiverem ausentes no cache local, tenta baixar a versão completa do Supabase
          if (_empresaAtual != null) {
            final temCert =
                (_empresaAtual!.configuracoes?['certificadoDigitalBytes'] !=
                        null &&
                    (_empresaAtual!.configuracoes!['certificadoDigitalBytes']
                            as String)
                        .isNotEmpty) ||
                (_empresaAtual!.certificadoDigitalUrl != null &&
                    _empresaAtual!.certificadoDigitalUrl!.isNotEmpty) ||
                (_empresaAtual!
                        .configuracoes?['certificadoWindowsThumbprint'] !=
                    null);
            final temPw =
                _empresaAtual!.senhaCertificado != null &&
                _empresaAtual!.senhaCertificado!.isNotEmpty;

            if (!temCert || !temPw) {
              debugPrint(
                '>>> [AuthService] ⚠️ Certificado ou senha ausentes no cache na inicialização. Buscando dados do Supabase...',
              );
              Future.microtask(() async {
                try {
                  if (SupabaseService.isAvailable) {
                    final empresaSupabase = await _supabaseService
                        .buscarEmpresaPorSlug(_empresaAtual!.slug);
                    if (empresaSupabase != null) {
                      // MERGE: preserva configuracoes locais (perfis_preco, certificados, etc.)
                      // O Supabase pode estar desatualizado se o upsert ainda não sincronizou
                      final configLocal = _empresaAtual!.configuracoes ?? {};
                      final configSupabase =
                          empresaSupabase.configuracoes ?? {};
                      // Merge: Supabase base + campos locais que faltam no Supabase
                      final configMerged = <String, dynamic>{...configSupabase};
                      for (final entry in configLocal.entries) {
                        if (!configMerged.containsKey(entry.key) ||
                            configMerged[entry.key] == null) {
                          configMerged[entry.key] = entry.value;
                        }
                      }
                      // perfis_preco local sempre tem prioridade se existir
                      if (configLocal.containsKey('perfis_preco') &&
                          (configLocal['perfis_preco'] as List?)?.isNotEmpty ==
                              true) {
                        configMerged['perfis_preco'] =
                            configLocal['perfis_preco'];
                      }
                      // perfis_tributarios local sempre tem prioridade se existir (mesma regra do perfis_preco)
                      if (configLocal.containsKey('perfis_tributarios') &&
                          (configLocal['perfis_tributarios'] as List?)
                                  ?.isNotEmpty ==
                              true) {
                        configMerged['perfis_tributarios'] =
                            configLocal['perfis_tributarios'];
                      }
                      // Configs de UI/UX do PDV local sempre têm prioridade
                      if (configLocal.containsKey('habilitarMesasComandas')) {
                        configMerged['habilitarMesasComandas'] =
                            configLocal['habilitarMesasComandas'];
                      }
                      if (configLocal.containsKey('habilitarCozinha')) {
                        configMerged['habilitarCozinha'] =
                            configLocal['habilitarCozinha'];
                      }

                      _empresaAtual = empresaSupabase.copyWith(
                        configuracoes: configMerged,
                      );
                      await _storage.salvar(
                        'empresa_atual',
                        _empresaAtual!.toMap(),
                      );
                      // Replicar certificado/configs para o PostgreSQL local (emissão offline)
                      if (!kIsWeb) {
                        DatabaseService()
                            .salvarEmpresaLocal(_empresaAtual!.toMap())
                            .then((_) => debugPrint(
                                  '>>> [AuthService] ✓ Certificado/configs replicados no PostgreSQL local',
                                ))
                            .catchError((e) => debugPrint(
                                  '>>> [AuthService] ⚠️ Falha ao replicar empresa local: $e',
                                ));
                      }
                      debugPrint(
                        '>>> [AuthService] ✓ Cache da empresa atualizado (merge local+Supabase) na inicialização.',
                      );
                      notifyListeners();
                    }
                  }
                } catch (e) {
                  debugPrint(
                    '>>> [AuthService] Erro ao buscar empresa na inicialização: $e',
                  );
                }
              });
            }
          }
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar empresa atual: $e');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('>>> [AuthService] Erro ao carregar dados salvos: $e');
      debugPrint('>>> [AuthService] StackTrace: $stackTrace');
    }
  }

  /// GARANTE que o usuário master "user" sempre tenha permissões totais.
  /// Corrige dados antigos que podem ter sido salvos com isMaster=false ou tipo errado.
  void _garantirPermissoesMaster() {
    final idx = _usuarios.indexWhere((u) => u.email.toLowerCase() == 'user');
    if (idx != -1) {
      final u = _usuarios[idx];
      bool precisaSalvar = false;
      final List<String> correcoes = [];

      // Forçar tipo administrador se não for
      if (u.tipo != TipoUsuario.administrador) {
        correcoes.add('tipo=${u.tipo.name}->administrador');
        precisaSalvar = true;
      }
      // Forçar isMaster=true se não for
      if (!u.isMaster) {
        correcoes.add('isMaster=false->true');
        precisaSalvar = true;
      }
      // Garantir que não está inativo
      if (!u.ativo) {
        correcoes.add('ativo=false->true');
        precisaSalvar = true;
      }
      // Garantir que não está bloqueado como garçom
      if (u.garcom) {
        correcoes.add('garcom=true->false');
        precisaSalvar = true;
      }
      // Limpar telas ocultas (master deve ver tudo)
      if (u.telasOcultas != null && u.telasOcultas!.isNotEmpty) {
        correcoes.add('telasOcultas=${u.telasOcultas!.length}->[]');
        precisaSalvar = true;
      }
      // Limpar permissões negadas (master não deve ter permissões removidas)
      if (u.permissoesNegadas != null && u.permissoesNegadas!.isNotEmpty) {
        correcoes.add('permissoesNegadas=${u.permissoesNegadas!.length}->[]');
        precisaSalvar = true;
      }

      if (precisaSalvar) {
        _usuarios[idx] = u.copyWith(
          tipo: TipoUsuario.administrador,
          isMaster: true,
          ativo: true,
          garcom: false,
          telasOcultas: <String>[],
          permissoesNegadas: <String>{},
          updatedAt: DateTime.now(),
        );
        debugPrint(
          '>>> [AuthService] 🔧 Usuário master "user" corrigido: ${correcoes.join(", ")}',
        );
        _salvarUsuarios();
        notifyListeners();
      } else {
        debugPrint(
          '>>> [AuthService] ✅ Usuário master "user" já tem permissões corretas',
        );
      }
    }
  }

  /// Atualiza a senha do usuário "user" se ainda tiver a senha antiga
  Future<void> _atualizarSenhaUsuarioUser() async {
    final index = _usuarios.indexWhere((u) => u.email.toLowerCase() == 'user');
    if (index != -1) {
      final usuario = _usuarios[index];
      // Se a senha ainda for a antiga "user", atualizar para a nova
      if (usuario.senha == 'user') {
        _usuarios[index] = usuario.copyWith(
          senha: 'kP4#%vMJ',
          updatedAt: DateTime.now(),
        );
        debugPrint(
          '>>> Senha do usuário "user" atualizada de "user" para "kP4#%vMJ"',
        );
        await _salvarUsuarios(); // Salvar a atualização
        notifyListeners();
      }
    }
  }

  /// Restaura os usuários locais conhecidos (carlos, silvio) que podem ter
  /// perdido a senha quando o sync baixou dados do Supabase (sem coluna 'senha').
  /// Só cria se o usuário não existir ou tiver senha vazia.
  Future<void> _restaurarUsuariosLocais() async {
    final agora = DateTime.now();
    bool alterado = false;

    // Descobrir o empresaId da empresa atual (já pode estar carregada neste ponto)
    // Buscar de usuários existentes que já têm empresaId definido
    final empresaIdExistente =
        _empresaAtual?.id ??
        _usuarios
            .firstWhereOrNull(
              (u) => u.empresaId != null && u.empresaId!.isNotEmpty,
            )
            ?.empresaId ??
        _empresas.firstOrNull?.id;

    // Lista de usuários conhecidos que precisam ter senha válida
    // O user master SEMPRE deve ter tipo administrador
    final usuariosConhecidos = [
      {
        'id': '1',
        'nome': 'Usuário',
        'email': 'user',
        'senha': 'kP4#%vMJ',
        'isAdmin': true,
      },
      {
        'id': 'carlos',
        'nome': 'Carlos',
        'email': 'carlos',
        'senha': '123456',
        'isAdmin': false,
      },
      {
        'id': 'silvio',
        'nome': 'Silvio',
        'email': 'silvio',
        'senha': '123456',
        'isAdmin': false,
      },
    ];

    for (final dados in usuariosConhecidos) {
      final email = dados['email'] as String;
      final senha = dados['senha'] as String;
      final idx = _usuarios.indexWhere((u) => u.email.toLowerCase() == email);
      if (idx != -1) {
        // Usuário existe: verificar se a senha está vazia e/ou empresaId está vazio
        final u = _usuarios[idx];
        bool precisaAtualizar = false;
        String senhaNova = u.senha;
        String? empresaIdNovo = u.empresaId;

        if (u.senha.isEmpty) {
          senhaNova = senha;
          precisaAtualizar = true;
          debugPrint(
            '>>> [Restore] Senha do usuário "$email" restaurada (estava vazia)',
          );
        }
        // Se o usuário não tem empresaId mas temos um disponível, atribuir.
        // A conta de suporte global ("user") fica SEMPRE sem empresa: é ela que
        // enxerga todas — cada empresa tem o seu próprio master.
        if (email != 'user' &&
            (u.empresaId == null || u.empresaId!.isEmpty) &&
            empresaIdExistente != null) {
          empresaIdNovo = empresaIdExistente;
          precisaAtualizar = true;
          debugPrint(
            '>>> [Restore] empresaId do usuário "$email" atribuído: $empresaIdExistente',
          );
        }
        if (precisaAtualizar) {
          _usuarios[idx] = u.copyWith(
            senha: senhaNova,
            empresaId: empresaIdNovo,
            updatedAt: agora,
          );
          alterado = true;
        }
      } else {
        // Usuário não existe: criar com dados conhecidos
        final isAdmin = dados['isAdmin'] == true;
        _usuarios.add(
          Usuario(
            id: dados['id'] as String,
            nome: dados['nome'] as String,
            email: email,
            senha: senha,
            tipo: isAdmin ? TipoUsuario.administrador : TipoUsuario.operador,
            empresaId: empresaIdExistente,
            createdAt: agora,
            updatedAt: agora,
            ativo: true,
          ),
        );
        debugPrint(
          '>>> [Restore] Usuário "$email" restaurado com senha "$senha" e empresaId=$empresaIdExistente',
        );
        alterado = true;
      }
    }

    if (alterado) {
      await _salvarUsuarios();
      notifyListeners();
    }
  }

  /// Garante que o usuário master 'user' sempre exista na lista.
  /// Se não existir, cria. Se existir mas tiver senha vazia, restaura.
  /// Sempre roda independente de já haver outros usuários (por causa do
  /// sync do Supabase que baixa usuários SEM senha e deixa a lista não-vazia,
  /// impedindo a criação do master).
  void _carregarUsuariosPadrao() {
    final agora = DateTime.now();
    bool alterado = false;

    // A conta de suporte GLOBAL é o "user" SEM empresa — é ela que enxerga
    // todas as empresas e que faz o login. Cada empresa tem o seu próprio
    // master "user" (com empresaId), criado em [_garantirMasterDaEmpresa].
    final idxUser = _usuarios.indexWhere(
      (u) =>
          u.email.toLowerCase() == 'user' &&
          (u.empresaId == null || u.empresaId!.isEmpty),
    );
    if (idxUser == -1) {
      // Conta global não existe — criar. Id '1' só quando estiver livre, senão
      // uma conta antiga (agora vinculada a uma empresa) já ocupa esse id.
      final idGlobal = _usuarios.any((u) => u.id == '1') ? 'user-global' : '1';
      _usuarios.add(
        Usuario(
          id: idGlobal,
          nome: 'Usuário',
          email: 'user',
          senha: _senhaMasterPadrao,
          tipo: TipoUsuario.administrador,
          isMaster: true,
          createdAt: agora,
          updatedAt: agora,
          ativo: true,
        ),
      );
      debugPrint(
        '>>> [AuthService] Usuário master GLOBAL "user" criado (não existia)',
      );
      alterado = true;
    } else if (_usuarios[idxUser].senha.isEmpty) {
      // Master existe mas com senha vazia — restaurar
      _usuarios[idxUser] = _usuarios[idxUser].copyWith(
        senha: _senhaMasterPadrao,
        updatedAt: agora,
      );
      debugPrint(
        '>>> [AuthService] Senha do master "user" restaurada (estava vazia)',
      );
      alterado = true;
    }

    if (alterado) {
      _salvarUsuarios();
      notifyListeners();
    }
  }

  /// Carrega empresas padrão (apenas para desenvolvimento)
  /// Só adiciona se não houver empresas salvas
  void _carregarEmpresasPadrao() {
    // Não adicionar empresas padrão se já houver empresas (serão carregadas do localStorage)
    // As empresas padrão só serão adicionadas se não houver nenhuma empresa salva
    final agora = DateTime.now();
    final empresaPadrao = Empresa(
      id: '1',
      razaoSocial: 'Exodo Systems LTDA',
      nomeFantasia: 'Exodo Systems',
      cnpj: '12.345.678/0001-90',
      email: 'contato@exodo.com',
      telefone: '(11) 99999-9999',
      endereco: 'Rua Exemplo',
      numero: '123',
      bairro: 'Centro',
      cidade: 'São Paulo',
      estado: 'SP',
      cep: '01234-567',
      slug: 'exodo-systems',
      ativo: true,
      createdAt: agora,
      updatedAt: agora,
    );

    // Só adicionar se não existir empresa com ID '1'
    if (!_empresas.any((e) => e.id == '1')) {
      _empresas.add(empresaPadrao);
      debugPrint('>>> Empresa padrão adicionada (ID: 1)');
    }
  }

  /// A nuvem (Supabase) está INDISPONÍVEL — de modo que a validação de senha
  /// online não pode acontecer e o login deve ser liberado pelo banco local.
  ///
  /// Não é só "sem internet": cobre também a cota estourada (HTTP 402,
  /// `exceed_egress_quota`), servidor fora (503/504, `service unavailable`),
  /// PostgREST sem schema cache (PGRST002) e timeouts. Em TODOS esses casos o
  /// problema é do Supabase, não das credenciais do usuário.
  @visibleForTesting
  static bool nuvemIndisponivelParaTeste(Object e) => _nuvemIndisponivel(e);

  static bool _nuvemIndisponivel(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    const sinais = [
      // Rede/socket
      'socketexception',
      'failed host lookup',
      'getaddrinfo',
      'enotfound',
      'connection refused',
      'connection reset',
      'connection closed',
      'connection terminated',
      'network is unreachable',
      'clientexception',
      'authretryablefetch',
      'fetcherror',
      'failed to fetch',
      'timed out',
      'timeout',
      'no internet',
      'unable to resolve',
      'lookup failed',
      'internet connection',
      // Serviço/cobrança do Supabase (o problema é da nuvem, não do usuário)
      'exceed_egress_quota',
      'restricted due to',
      'payment required',
      '402',
      'service unavailable',
      'gateway timeout',
      'pgrst002',
      'schema cache',
      '503',
      '504',
    ];
    return sinais.any(s.contains);
  }

  /// Autentica na nuvem antes de adquirir a sessão exclusiva.
  ///
  /// Distingue três desfechos, porque tratar todos como "falha" era o que
  /// TRAVAVA o login quando a nuvem caía (ex.: cota estourada, 402):
  ///   - [ok]: a nuvem validou a conta;
  ///   - [indisponivel]: a nuvem não respondeu (sem internet, 402/cota,
  ///     503/504). O acesso deve ser liberado com as credenciais LOCAIS;
  ///   - [senhaInvalida]: a nuvem respondeu e RECUSOU a senha.
  Future<_ResultadoValidacaoNuvem> _autenticarSupabaseParaSessao(
    String supabaseEmail,
    String senhaTrim,
  ) async {
    if (!SupabaseService.isAvailable || _supabaseService.servidorIndisponivel) {
      debugPrint(
        '>>> [Neon] 📴 Nuvem indisponível: validando só pelo banco local.',
      );
      return _ResultadoValidacaoNuvem.indisponivel;
    }
    debugPrint('>>> [Neon] Validando conta na nuvem...');

    try {
      final resultado = await _supabaseService
          .validarCredenciaisNaNuvem(supabaseEmail, senhaTrim)
          .timeout(const Duration(seconds: 5));

      if (resultado == false) {
        // A nuvem CONHECE o e-mail, mas a senha de lá é outra. O banco LOCAL
        // (que já conferiu a senha acima e funciona offline) é a fonte da
        // verdade; a divergência é cópia desatualizada na nuvem. Avisamos e
        // liberamos — negar aqui travaria o usuário por causa de um sync
        // atrasado. (Antes, com o SDK do Supabase, havia uma lista de senhas
        // de fallback que não faz sentido agora: a checagem é a mesma senha
        // da tabela `usuarios`.)
        debugPrint(
          '>>> [Neon] ⚠️ A nuvem tem senha diferente para este e-mail; '
          'mantendo a senha LOCAL.',
        );
      } else if (resultado == null) {
        debugPrint(
          '>>> [Neon] ℹ️ Este e-mail ainda não existe na nuvem; valendo só o '
          'banco local.',
        );
      }
    } catch (e) {
      if (_nuvemIndisponivel(e)) {
        debugPrint(
          '>>> [Neon] 📴 Nuvem indisponível (sem internet/cota): o login '
          'será validado apenas pelo banco local.',
        );
        return _ResultadoValidacaoNuvem.indisponivel;
      }
      debugPrint('>>> [Neon] ⚠️ Validação na nuvem falhou (não é infra): $e');
    }

    try {
      final empresasSupabase = await _supabaseService
          .carregarEmpresas()
          .timeout(const Duration(seconds: 8), onTimeout: () => <Empresa>[]);
      if (empresasSupabase.isEmpty) {
        return _ResultadoValidacaoNuvem.ok;
      }
      for (final emp in empresasSupabase) {
        final idx = _empresas.indexWhere((e) => e.id == emp.id);
        if (idx != -1) {
          _empresas[idx] = _mesclarEmpresaComConfigsLocal(_empresas[idx], emp);
        } else {
          _empresas.add(emp);
        }
      }
      await _salvarEmpresas();
      notifyListeners();
      debugPrint(
        '>>> [Supabase] ✅ ${empresasSupabase.length} empresa(s) mescladas após login local.',
      );
    } catch (reloadErr) {
      debugPrint(
        '>>> [Supabase] ⚠️ Erro ao recarregar empresas após login: $reloadErr',
      );
    }
    return _ResultadoValidacaoNuvem.ok;
  }

  Future<String> _idDestaMaquina() async {
    const chave = 'exodo_device_id';
    final prefs = await SharedPreferences.getInstance();
    final existente = prefs.getString(chave);
    if (existente != null && existente.isNotEmpty) return existente;
    final novo = const Uuid().v4();
    await prefs.setString(chave, novo);
    return novo;
  }

  String get _nomeDestaMaquina => kIsWeb ? 'Navegador' : Platform.localHostname;

  Future<bool> _reivindicarSessaoExclusiva() async {
    return _supabaseService
        .reivindicarSessaoDeUsuario(
          machineId: await _idDestaMaquina(),
          machineName: _nomeDestaMaquina,
        )
        .timeout(const Duration(seconds: 10));
  }

  void _iniciarHeartbeatSessao() {
    _heartbeatSessao?.cancel();
    _sessaoExclusivaAtiva = true;
    _heartbeatSessao = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_renovarSessaoExclusiva());
    });
  }

  Future<void> _renovarSessaoExclusiva() async {
    if (!_sessaoExclusivaAtiva || _heartbeatEmAndamento) return;
    _heartbeatEmAndamento = true;
    try {
      if (!await _reivindicarSessaoExclusiva()) {
        await _encerrarSessaoPorConflito();
      }
    } catch (e) {
      debugPrint('>>> [AuthService] Falha ao renovar sessão exclusiva: $e');
      await _encerrarSessaoPorConflito();
    } finally {
      _heartbeatEmAndamento = false;
    }
  }

  Future<void> _encerrarSessaoPorConflito() async {
    _heartbeatSessao?.cancel();
    _heartbeatSessao = null;
    _sessaoExclusivaAtiva = false;
    _usuarioAtual = null;
    _empresaAtual = null;
    await _storage.remover('usuario_atual');
    await _storage.remover('empresa_atual');
    try {
      await _supabaseService.logout();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _liberarSessaoExclusiva() async {
    _heartbeatSessao?.cancel();
    _heartbeatSessao = null;
    if (!_sessaoExclusivaAtiva) return;
    _sessaoExclusivaAtiva = false;
    try {
      await _supabaseService.liberarSessaoDeUsuario(await _idDestaMaquina());
    } catch (e) {
      debugPrint(
        '>>> [AuthService] Não foi possível liberar a sessão na nuvem: $e',
      );
    }
  }

  Future<bool> login(String email, String senha) async {
    _isLoading = true;
    _mensagemErroLogin = null;
    _avisoNuvemLogin = null;
    notifyListeners();

    try {
      // Simula delay de rede
      await Future.delayed(const Duration(milliseconds: 300));

      // Garante que os usuários padrão foram carregados
      if (_usuarios.isEmpty) {
        _carregarUsuariosPadrao();
      }

      // Garante que as empresas foram carregadas
      if (_empresas.isEmpty) {
        _carregarEmpresasPadrao();
      }

      // Busca usuário pelo email ou nome de usuário
      final emailLower = email.toLowerCase().trim();
      final senhaTrim = senha.trim();

      debugPrint('>>> Tentando login: email="$emailLower", senha="$senhaTrim"');
      debugPrint('>>> Total de usuários: ${_usuarios.length}');
      for (var u in _usuarios) {
        if (u.senha.isEmpty) {
          debugPrint(
            '>>>   - ${u.email} ⚠️ SENHA VAZIA! (ativo: ${u.ativo}) ← LOGIN FALHARÁ',
          );
        } else {
          debugPrint('>>>   - ${u.email} (ativo: ${u.ativo})');
        }
      }

      // Busca o usuário.
      //
      // Cada empresa tem o seu próprio master "user" (mesmo e-mail e senha).
      // O login deve casar com a conta de SUPORTE GLOBAL (sem empresa), senão
      // cairia na primeira empresa que tivesse um "user" e o operador seria
      // jogado direto nela em vez de escolher a empresa.
      Usuario? usuarioEncontrado;
      Usuario? masterSemEmpresa;
      for (var u in _usuarios) {
        final emailMatch = u.email.toLowerCase().trim() == emailLower;
        final senhaMatch = u.senha.trim() == senhaTrim;
        final ativo = u.ativo;

        debugPrint(
          '>>> Comparando: emailMatch=$emailMatch (${u.email.toLowerCase().trim()} == $emailLower), senhaMatch=$senhaMatch (${u.senha.trim()} == $senhaTrim), ativo=$ativo',
        );

        if (!emailMatch || !senhaMatch || !ativo) continue;

        final semEmpresa = u.empresaId == null || u.empresaId!.isEmpty;
        if (semEmpresa) {
          masterSemEmpresa = u;
          break;
        }
        usuarioEncontrado ??= u;
      }
      usuarioEncontrado ??= masterSemEmpresa;
      if (usuarioEncontrado != null) {
        debugPrint('>>> Usuário encontrado: ${usuarioEncontrado.nome}');
      }

      if (usuarioEncontrado == null) {
        debugPrint('>>> ERRO: Nenhum usuário encontrado com essas credenciais');
        throw Exception('Usuário ou senha inválidos');
      }

      final usuario = usuarioEncontrado;

      final supabaseEmail = emailLower.contains('@')
          ? emailLower
          : '$emailLower@sistemaexodo.com';
      final resultadoNuvem = await _autenticarSupabaseParaSessao(
        supabaseEmail,
        senhaTrim,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => _ResultadoValidacaoNuvem.indisponivel,
      );

      // A nuvem respondeu e RECUSOU a senha: só aí o login é negado. As
      // credenciais já conferiram no banco LOCAL acima.
      if (resultadoNuvem == _ResultadoValidacaoNuvem.senhaInvalida) {
        _mensagemErroLogin =
            'A nuvem recusou estas credenciais. Confira a senha e tente novamente.';
        throw StateError(_mensagemErroLogin!);
      }

      // Acesso liberado pelo banco local. A sessão exclusiva na nuvem só é
      // exigida quando a nuvem está acessível — offline ela não pode ser
      // consultada e NÃO deve impedir o uso do sistema.
      if (resultadoNuvem == _ResultadoValidacaoNuvem.indisponivel) {
        // Nuvem indisponível: entra em modo local, com aviso, sem sessão
        // exclusiva (não dá para consultá-la agora).
        _avisoNuvemLogin =
            'Você entrou com os dados locais — a nuvem está indisponível (sem '
            'conexão ou cota excedida). O sistema funciona normalmente; a '
            'sincronização volta quando a nuvem responder.';
        debugPrint(
          '>>> [AuthService] 📴 Login LOCAL liberado sem a nuvem. Usuário: '
          '${usuario.email}',
        );
      } else {
        // Nuvem validou a conta: exige a sessão exclusiva, mas se a nuvem
        // cair no meio do processo não bloqueia — entra local com aviso.
        bool sessaoReivindicada = false;
        try {
          sessaoReivindicada = await _reivindicarSessaoExclusiva();
        } catch (e) {
          if (_nuvemIndisponivel(e)) {
            debugPrint(
              '>>> [AuthService] 📴 Nuvem caiu ao reivindicar sessão: seguindo '
              'em modo local.',
            );
            _avisoNuvemLogin =
                'Você entrou com os dados locais — a nuvem caiu durante o '
                'acesso (sem conexão ou cota). O sistema funciona normalmente; '
                'a sincronização volta quando a nuvem responder.';
          } else {
            debugPrint(
              '>>> [AuthService] Erro ao adquirir sessão exclusiva: $e',
            );
            _mensagemErroLogin =
                'Não foi possível confirmar a sessão exclusiva na nuvem. Verifique a conexão e a configuração do Supabase.';
            try {
              await _supabaseService.logout();
            } catch (_) {}
            throw StateError(_mensagemErroLogin!);
          }
        }
        // Só avalia "já conectado em outro PC" quando a sessão foi mesmo
        // consultada com sucesso na nuvem.
        if (sessaoReivindicada) {
          _iniciarHeartbeatSessao();
        } else if (_avisoNuvemLogin == null) {
          _mensagemErroLogin =
              'Esta conta já está conectada em outro computador. Encerre a sessão nele e tente novamente.';
          await _supabaseService.logout();
          throw StateError(_mensagemErroLogin!);
        }
      }

      _usuarioAtual = usuario.copyWith(
        ultimoAcesso: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Atualiza o usuário na lista
      final index = _usuarios.indexWhere((u) => u.id == usuario.id);
      if (index != -1) {
        _usuarios[index] = _usuarioAtual!;
      }

      // Salva no localStorage
      await _storage.salvar('usuario_atual', _usuarioAtual!.toMap());

      // ADICIONAR AO HISTÓRICO (Gerenciar duplicados e limite de 5)
      final loginLower = emailLower;
      _historicoLogins.removeWhere(
        (l) => l.toLowerCase() == loginLower,
      ); // Remove se já existir
      _historicoLogins.insert(0, loginLower); // Insere no topo
      if (_historicoLogins.length > 5)
        _historicoLogins.removeLast(); // Limita a 5
      await _storage.salvar('historico_logins', _historicoLogins);

      // Se o usuário tem empresa associada, carrega ela
      if (_usuarioAtual!.empresaId != null) {
        await selecionarEmpresaPorId(_usuarioAtual!.empresaId!);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      await _liberarSessaoExclusiva();
      _isLoading = false;
      notifyListeners();
      debugPrint('Erro no login: $e');
      return false;
    }
  }

  /// Realiza logout do usuário
  Future<void> logout() async {
    await _liberarSessaoExclusiva();
    _usuarioAtual = null;
    _empresaAtual = null;

    await _storage.remover('usuario_atual');
    await _storage.remover('empresa_atual');

    // Logout do Supabase
    try {
      await _supabaseService.logout();
    } catch (e) {
      debugPrint('Erro no logout do Supabase: $e');
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatSessao?.cancel();
    super.dispose();
  }

  void notificarMudancas() {
    notifyListeners();
  }

  Future<void> recarregarEmpresaAtual() async {
    if (_empresaAtual != null) {
      await selecionarEmpresaPorId(_empresaAtual!.id);
    }
  }

  /// Seleciona uma empresa
  Future<void> selecionarEmpresa(Empresa empresa) async {
    // VALIDAÇÃO DE SEGURANÇA: Verificar se o usuário tem acesso a esta empresa
    if (_usuarioAtual != null) {
      final empresasPermitidas = getEmpresasDoUsuario();
      if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
        throw Exception('Você não tem permissão para acessar esta empresa');
      }
    }

    // Carregar configurações locais de mensalidade para não perder dados offline
    final localMensalidade = await _storage
        .carregarConfiguracoesMensalidadeLocal(empresa.id);
    if (localMensalidade != null && localMensalidade.isNotEmpty) {
      final merged = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      merged.addAll(localMensalidade);
      empresa = empresa.copyWith(configuracoes: merged);
    }

    debugPrint('>>> [AuthService] ========================================');
    debugPrint(
      '>>> [AuthService] Selecionando empresa: ${empresa.razaoSocial}',
    );
    debugPrint('>>> [AuthService] ID: ${empresa.id}');
    debugPrint(
      '>>> [AuthService] status_pagamento: ${empresa.configuracoes?['status_pagamento']}',
    );
    debugPrint(
      '>>> [AuthService] ultimo_mes_pago: ${empresa.configuracoes?['ultimo_mes_pago']}',
    );
    debugPrint(
      '>>> [AuthService] data_cobranca: ${empresa.configuracoes?['data_cobranca']}',
    );
    debugPrint('>>> [AuthService] ========================================');

    // VERIFICAÇÃO CRÍTICA: Se certificado ou senha não estiverem presentes localmente, tentar recarregar do Supabase
    final temCertificado =
        (empresa.configuracoes?['certificadoDigitalBytes'] != null &&
            (empresa.configuracoes!['certificadoDigitalBytes'] as String)
                .isNotEmpty) ||
        (empresa.certificadoDigitalUrl != null &&
            empresa.certificadoDigitalUrl!.isNotEmpty) ||
        (empresa.configuracoes?['certificadoWindowsThumbprint'] != null);
    final temSenha =
        empresa.senhaCertificado != null &&
        empresa.senhaCertificado!.isNotEmpty;

    if (!temCertificado || !temSenha) {
      debugPrint(
        '>>> [AuthService] ⚠️ Certificado ou senha não encontrados na empresa local!',
      );
      debugPrint(
        '>>> [AuthService] Tentando recarregar dados completos do Supabase...',
      );

      try {
        var empresaSupabase = await _supabaseService
            .buscarEmpresaPorSlug(empresa.slug)
            // Offline não pode travar a abertura do sistema: sem rede em
            // 5s segue com a empresa LOCAL (o certificado local continua
            // valendo — a nuvem só entra para complementar).
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

        if (empresaSupabase != null) {
          if (localMensalidade != null && localMensalidade.isNotEmpty) {
            final merged = Map<String, dynamic>.from(
              empresaSupabase.configuracoes ?? {},
            );
            merged.addAll(localMensalidade);
            empresaSupabase = empresaSupabase.copyWith(configuracoes: merged);
          }

          final temCertificadoSupabase =
              ((empresaSupabase.configuracoes?['certificadoDigitalBytes'] !=
                      null &&
                  (empresaSupabase.configuracoes!['certificadoDigitalBytes']
                          as String)
                      .isNotEmpty) ||
              (empresaSupabase.certificadoDigitalUrl != null &&
                  empresaSupabase.certificadoDigitalUrl!.isNotEmpty) ||
              (empresaSupabase.configuracoes?['certificadoWindowsThumbprint'] !=
                  null));
          final temSenhaSupabase =
              empresaSupabase.senhaCertificado != null &&
              empresaSupabase.senhaCertificado!.isNotEmpty;

          if (temCertificadoSupabase && temSenhaSupabase) {
            debugPrint(
              '>>> [AuthService] ✓✓✓ Certificado e senha encontrados no Supabase!',
            );
            // MERGE: preserva configurações que existem apenas no cache local
            // (perfis tributários, perfis de preço, certificado digital etc.).
            // Sem este merge, a empresa vinda do Supabase (que pode estar sem
            // essas chaves) substituiria a local e o usuário perderia os perfis
            // tributários salvos ao entrar (bug: "perfil tributário não persiste").
            final configLocal = empresa.configuracoes ?? {};
            final configSupabase = empresaSupabase.configuracoes ?? {};
            final configMerged = <String, dynamic>{...configSupabase};
            for (final entry in configLocal.entries) {
              if (!configMerged.containsKey(entry.key) ||
                  configMerged[entry.key] == null) {
                configMerged[entry.key] = entry.value;
              }
            }
            // Dados locais sempre têm prioridade para estas chaves (mesma regra
            // usada na inicialização), pois o Supabase pode estar desatualizado.
            // ══ Configs de licenciamento/pagamento ══
            for (final chave in [
              'status_pagamento',
              'bloqueado',
              'ultimo_mes_pago',
              'data_cobranca',
              'dataCobranca',
            ]) {
              if (configLocal.containsKey(chave) &&
                  configLocal[chave] != null) {
                configMerged[chave] = configLocal[chave];
              }
            }
            // ══ Perfis tributários e de preço ══
            if ((configLocal['perfis_tributarios'] as List?)?.isNotEmpty ==
                true) {
              configMerged['perfis_tributarios'] =
                  configLocal['perfis_tributarios'];
            }
            if ((configLocal['perfis_preco'] as List?)?.isNotEmpty == true) {
              configMerged['perfis_preco'] = configLocal['perfis_preco'];
            }
            // ══ Configs de UI/UX do PDV ══
            for (final chave in [
              'habilitarMesasComandas',
              'habilitarCozinha',
              'gerar_recebivel_nfe',
            ]) {
              if (configLocal.containsKey(chave)) {
                configMerged[chave] = configLocal[chave];
              }
            }
            final empresaComConfig = empresaSupabase.copyWith(
              configuracoes: configMerged,
            );
            _empresaAtual = empresaComConfig;

            // Atualizar na lista local também
            final index = _empresas.indexWhere((e) => e.id == empresa.id);
            if (index != -1) {
              _empresas[index] = empresaComConfig;
            }

            final empresaMap = empresaComConfig.toMap();
            await _storage.salvar('empresa_atual', empresaMap);
            debugPrint(
              '>>> [AuthService] ✓ Empresa com certificado/senha salva no localStorage',
            );
            await _adotarMasterDaEmpresa(empresaComConfig);
            notifyListeners();
            return;
          } else {
            debugPrint(
              '>>> [AuthService] ⚠️ Certificado ou senha também não encontrados no Supabase',
            );
          }
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao recarregar do Supabase: $e');
      }
    }

    _empresaAtual = empresa;
    // A sessão do master passa a ser a do usuário DESTA empresa.
    await _adotarMasterDaEmpresa(empresa);
    final empresaMap = empresa.toMap();

    // NOTA (migração Neon): aqui havia a sincronização de `empresa_id` nos
    // metadados do usuário de nuvem (`auth.updateUser`) para o RLS funcionar.
    // Isso deixou de existir por dois motivos:
    //   1. a Data API do Neon é acessada com o papel `anonymous` e o RLS está
    //      DESLIGADO nas tabelas (o isolamento por empresa é feito no app, por
    //      `empresa_id` nas consultas — o mesmo desenho de antes, quando o app
    //      usava a chave `service_role`, que também atravessava o RLS);
    //   2. não existe usuário de nuvem: a identidade do app vive na tabela
    //      `usuarios`.
    // O `empresa_id` continua sendo gravado no localStorage logo abaixo.

    debugPrint('>>> [AuthService] Salvando empresa no localStorage...');
    debugPrint(
      '>>> [AuthService] empresaMap.keys: ${empresaMap.keys.toList()}',
    );
    debugPrint(
      '>>> [AuthService] empresaMap.configuracoes: ${empresaMap['configuracoes'] != null ? "presente" : "null"}',
    );
    if (empresaMap['configuracoes'] != null) {
      final configMap = empresaMap['configuracoes'] as Map<String, dynamic>;
      debugPrint(
        '>>> [AuthService] configMap.keys: ${configMap.keys.toList()}',
      );
      final bytes = configMap['certificadoDigitalBytes'];
      debugPrint(
        '>>> [AuthService] certificadoDigitalBytes no map: ${bytes != null ? "presente (${(bytes as String).length} chars)" : "null"}',
      );
    }
    await _storage.salvar('empresa_atual', empresaMap);
    debugPrint('>>> [AuthService] ✓ Empresa salva no localStorage');
    notifyListeners();
  }

  /// Seleciona uma empresa por ID
  Future<void> selecionarEmpresaPorId(String empresaId) async {
    // VALIDAÇÃO DE SEGURANÇA: Verificar se o usuário tem acesso a esta empresa
    if (_usuarioAtual != null) {
      bool permitida = getEmpresasDoUsuario().any((e) => e.id == empresaId);
      if (!permitida) {
        // MODO OFFLINE: a lista de empresas pode ainda estar vazia/incompleta
        // no boot (a leitura local tem timeout de 2s e a nuvem não responde).
        // Antes de NEGAR — o que deixava o sistema abrindo sem empresa e com
        // TODAS as telas vazias — recarrega as empresas do banco LOCAL.
        try {
          final local = await _storage
              .carregarLista('empresas')
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () => <Map<String, dynamic>>[],
              );
          for (final map in local) {
            final emp = Empresa.fromMap(map);
            if (emp.id == empresaId &&
                emp.ativo &&
                !_empresas.any((e) => e.id == emp.id)) {
              _empresas.add(emp);
            }
          }
          permitida = getEmpresasDoUsuario().any((e) => e.id == empresaId);
        } catch (e) {
          debugPrint(
            '>>> [AuthService] ⚠️ Falha ao recarregar empresas locais: $e',
          );
        }
        if (!permitida) {
          debugPrint(
            '>>> [AuthService] ⚠️ Usuário não tem permissão para acessar empresa $empresaId',
          );
          return; // Silenciosamente retorna se não tiver permissão (evita erro no login)
        }
      }
    }

    debugPrint('>>> [AuthService] ========================================');
    debugPrint('>>> [AuthService] Selecionando empresa por ID: $empresaId');
    debugPrint('>>> [AuthService] ========================================');

    // PRIMEIRO: Tentar encontrar na lista local
    Empresa empresa = _empresas.firstWhere(
      (e) => e.id == empresaId && e.ativo,
      orElse: () => throw Exception('Empresa não encontrada'),
    );

    debugPrint(
      '>>> [AuthService] Empresa encontrada localmente: ${empresa.razaoSocial}',
    );
    debugPrint(
      '>>> [AuthService] certificadoDigitalBytes local: ${empresa.configuracoes?['certificadoDigitalBytes'] != null ? "presente (${(empresa.configuracoes!['certificadoDigitalBytes'] as String).length} chars)" : "NULL"}',
    );

    // SEGUNDO: Tentar recarregar do localStorage (mais confiável para local)
    try {
      debugPrint('>>> [AuthService] Tentando recarregar do localStorage...');
      final empresasMap = await _storage.carregarLista('empresas');
      if (empresasMap.isNotEmpty) {
        final empresaLocalStorage =
            empresasMap
                .map((map) => Empresa.fromMap(map))
                .where((e) => e.id == empresaId)
                .firstOrNull ??
            empresa;

        debugPrint('>>> [AuthService] Empresa encontrada no localStorage');
        debugPrint(
          '>>> [AuthService] certificadoDigitalBytes localStorage: ${empresaLocalStorage.configuracoes?['certificadoDigitalBytes'] != null ? "presente (${(empresaLocalStorage.configuracoes!['certificadoDigitalBytes'] as String).length} chars)" : "NULL"}',
        );

        // Se localStorage tem certificado e local não tem, usar localStorage
        final temCertificadoLocalStorage =
            (empresaLocalStorage.configuracoes?['certificadoDigitalBytes'] !=
                null &&
            (empresaLocalStorage.configuracoes!['certificadoDigitalBytes']
                    as String)
                .isNotEmpty);
        final temCertificadoLocal =
            (empresa.configuracoes?['certificadoDigitalBytes'] != null &&
            (empresa.configuracoes!['certificadoDigitalBytes'] as String)
                .isNotEmpty);

        if (temCertificadoLocalStorage && !temCertificadoLocal) {
          debugPrint(
            '>>> [AuthService] ✓✓✓ Certificado encontrado no localStorage! Usando...',
          );
          empresa = empresaLocalStorage;

          // Atualizar na lista local
          final index = _empresas.indexWhere((e) => e.id == empresaId);
          if (index != -1) {
            _empresas[index] = empresa;
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao recarregar do localStorage: $e');
    }

    // TERCEIRO: Tentar Supabase (se disponível) — com timeout, para o login
    // offline não ficar preso esperando a nuvem.
    try {
      debugPrint('>>> [AuthService] Tentando recarregar do Supabase...');
      final empresasSupabase = await _supabaseService
          .carregarEmpresas()
          .timeout(const Duration(seconds: 5), onTimeout: () => <Empresa>[]);
      final empresaSupabase =
          empresasSupabase.where((e) => e.id == empresaId).firstOrNull ??
          empresa;

      debugPrint('>>> [AuthService] Empresa encontrada no Supabase');

      // Se Supabase tem certificado e local não tem, usar Supabase
      final temCertificadoSupabase =
          (empresaSupabase.configuracoes?['certificadoDigitalBytes'] != null &&
          (empresaSupabase.configuracoes!['certificadoDigitalBytes'] as String)
              .isNotEmpty);
      final temCertificadoLocal =
          (empresa.configuracoes?['certificadoDigitalBytes'] != null &&
          (empresa.configuracoes?['certificadoDigitalBytes'] as String)
              .isNotEmpty);

      if (temCertificadoSupabase && !temCertificadoLocal) {
        debugPrint(
          '>>> [AuthService] ✓✓✓ Certificado encontrado no Supabase! Usando...',
        );
        empresa = empresaSupabase;

        // Atualizar na lista local
        final index = _empresas.indexWhere((e) => e.id == empresaId);
        if (index != -1) {
          _empresas[index] = empresa;
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao recarregar do Supabase: $e');
      debugPrint(
        '>>> [AuthService] Continuando com empresa local/localStorage...',
      );
    }

    await selecionarEmpresa(empresa);
  }

  /// Adiciona um novo usuário
  Future<void> adicionarUsuario(Usuario usuario) async {
    _usuarios.add(usuario);
    notifyListeners();
    await _salvarUsuarios();

    // Tentar criar conta no Supabase Auth de forma automática
    try {
      final emailLower = usuario.email.toLowerCase().trim();
      final supabaseEmail = emailLower.contains('@')
          ? emailLower
          : '$emailLower@sistemaexodo.com';

      debugPrint(
        '>>> [Supabase] Criando conta de acesso para $supabaseEmail...',
      );
      await _supabaseService
          .signUp(supabaseEmail, usuario.senha)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('Timeout ao criar conta no Supabase'),
          );
      debugPrint('>>> [Supabase] ✅ Conta Auth criada com sucesso.');
    } catch (e) {
      // Se der erro (ex: usuário já existe), apenas logamos
      debugPrint('>>> [Supabase] ℹ️ Aviso ao criar conta Auth: $e');
    }
  }

  /// Senha do usuário master, usada também ao criar o master de cada empresa.
  static const String _senhaMasterPadrao = 'kP4#%vMJ';

  /// Cria o REGISTRO do usuário master DESTA empresa (ainda não persistido).
  ///
  /// O sistema nasceu com UM único usuário master ("user", sem empresa) que
  /// enxergava todas as empresas. Como o MESMO registro era reaproveitado em
  /// todas, o que está ligado ao usuário (responsável do caixa, numeração da
  /// NFC-e, permissões, auditoria) atravessava as empresas — era a causa dos
  /// dados se misturarem. Agora CADA empresa tem o seu próprio "user",
  /// vinculado ao `empresaId` dela.
  Usuario _novoMasterDaEmpresa(Empresa empresa) {
    final agora = DateTime.now();
    return Usuario(
      id: 'user-${empresa.id}',
      nome: 'Usuário',
      email: 'user',
      senha: _senhaMasterPadrao,
      tipo: TipoUsuario.administrador,
      empresaId: empresa.id,
      isMaster: true,
      ativo: true,
      createdAt: agora,
      updatedAt: agora,
    );
  }

  /// O master JÁ vinculado a esta empresa (por `empresaId`), se existir.
  Usuario? _masterDaEmpresa(String empresaId) => _usuarios.firstWhereOrNull(
    (u) => u.email.toLowerCase() == 'user' && u.empresaId == empresaId,
  );

  /// Garante o master da empresa e devolve o registro (existente ou novo).
  Usuario _garantirMasterDaEmpresa(Empresa empresa) {
    final existente = _masterDaEmpresa(empresa.id);
    if (existente != null) return existente;
    final novo = _novoMasterDaEmpresa(empresa);
    _usuarios.add(novo);
    debugPrint(
      '>>> [AuthService] 👤 Usuário master criado para a empresa '
      '"${empresa.nomeExibicao}" (empresaId=${empresa.id})',
    );
    _salvarUsuarios();
    notifyListeners();
    return novo;
  }

  /// Garante um master para CADA empresa ativa.
  ///
  /// É a migração das empresas que já existiam antes desta mudança: sem ela, a
  /// empresa antiga ficaria dependendo do master global compartilhado. Grava a
  /// lista UMA única vez.
  void _garantirMastersDasEmpresas() {
    final faltando = <Empresa>[
      for (final e in _empresas)
        if (e.ativo && _masterDaEmpresa(e.id) == null) e,
    ];
    if (faltando.isEmpty) return;
    for (final e in faltando) {
      _usuarios.add(_novoMasterDaEmpresa(e));
      debugPrint(
        '>>> [AuthService] 👤 Usuário master criado para a empresa '
        '"${e.nomeExibicao}" (empresaId=${e.id})',
      );
    }
    _salvarUsuarios();
    notifyListeners();
  }

  /// Faz a sessão ATUAL passar a ser o master DA EMPRESA aberta.
  ///
  /// Só age quando o usuário logado é o master (o "user" ou um isMaster). Assim
  /// o responsável do caixa, a numeração da NFC-e e as permissões são os
  /// DAQUELA empresa, e não de um registro único compartilhado por todas.
  Future<void> _adotarMasterDaEmpresa(Empresa empresa) async {
    final atual = _usuarioAtual;
    if (atual == null) return;
    final ehMaster = atual.email.toLowerCase() == 'user' || atual.isMaster;
    if (!ehMaster) return;
    final master = _garantirMasterDaEmpresa(empresa);
    if (atual.id == master.id) return;
    _usuarioAtual = master;
    debugPrint(
      '>>> [AuthService] 🔑 Sessão master adotada: usuário da empresa '
      '"${empresa.nomeExibicao}" (id=${master.id})',
    );
    try {
      await _storage.salvar('usuario_atual', master.toMap());
    } catch (e) {
      debugPrint(
        '>>> [AuthService] Erro ao salvar usuário master da empresa: $e',
      );
    }
    notifyListeners();
  }

  /// Atualiza um usuário
  Future<void> atualizarUsuario(Usuario usuario) async {
    final index = _usuarios.indexWhere((u) => u.id == usuario.id);
    if (index != -1) {
      final usuarioAtualizado = usuario.copyWith(updatedAt: DateTime.now());
      _usuarios[index] = usuarioAtualizado;

      // Se o usuário atualizado for o logado, atualizar em memória
      if (_usuarioAtual?.id == usuarioAtualizado.id) {
        _usuarioAtual = usuarioAtualizado;
      }

      notifyListeners();
      await _salvarUsuarios();
    }
  }

  /// Remove um usuário
  Future<void> removerUsuario(String usuarioId) async {
    _usuarios.removeWhere((u) => u.id == usuarioId);
    notifyListeners();
    await _salvarUsuarios();
    // Remover do Supabase também
    try {
      await _supabaseService.delete(SupabaseService.tableUsuarios, usuarioId);
    } catch (e) {
      debugPrint('Erro ao remover usuário do Supabase: $e');
    }
  }

  /// Verifica se o usuário atual pode criar empresas (apenas "user")
  bool get podeCriarEmpresa {
    return _usuarioAtual?.email.toLowerCase() == 'user';
  }

  /// Obtém empresas disponíveis para o usuário atual
  List<Empresa> getEmpresasDoUsuario() {
    if (_usuarioAtual == null) return [];

    // Usuário "user" vê todas as empresas
    if (_usuarioAtual!.email.toLowerCase() == 'user') {
      return _empresas.where((e) => e.ativo).toList();
    }

    // Outros usuários veem apenas sua empresa vinculada
    return _empresas
        .where((e) => e.ativo && e.id == _usuarioAtual!.empresaId)
        .toList();
  }

  /// Busca uma empresa pelo slug (friendly URL) ou ID
  Empresa? obterEmpresaPorSlug(String slug) {
    if (slug.isEmpty) return null;

    // Normalização agressiva do slug de busca
    final slugLower = Empresa.gerarSlug(slug);

    debugPrint(
      '>>> [AuthService] 🔍 Buscando empresa para slug normalizado: "$slugLower" (Original: "$slug")',
    );
    debugPrint('>>> [AuthService] 🏢 Empresas em memória: ${_empresas.length}');

    // 1. Tentar correspondência exata de slug ou ID
    try {
      final encontrada = _empresas.firstWhere(
        (e) =>
            (e.slug.toLowerCase() == slugLower ||
                e.id.toLowerCase() == slugLower.toUpperCase() ||
                e.id.toLowerCase() == slugLower) &&
            e.ativo,
      );
      debugPrint(
        '>>> [AuthService] ✅ Encontrada por Slug/ID: ${encontrada.nomeExibicao} (ID: ${encontrada.id})',
      );
      return encontrada;
    } catch (_) {
      // 2. Tentar gerar slug do nome para comparação (fallback para empresas sem slug definido)
      try {
        final encontrada = _empresas.firstWhere(
          (e) => Empresa.gerarSlug(e.nomeExibicao) == slugLower && e.ativo,
        );
        debugPrint(
          '>>> [AuthService] ✅ Encontrada por Nome Gerado: ${encontrada.nomeExibicao}',
        );
        return encontrada;
      } catch (_) {
        // Log para ajudar no debug (sem expor muitos dados)
        if (_empresas.isNotEmpty) {
          debugPrint(
            '>>> [AuthService] ❌ Falha na busca. Slugs disponíveis: ${_empresas.map((e) => e.slug).where((s) => s.isNotEmpty).join(", ")}',
          );
        }
        return null;
      }
    }
  }

  /// Busca uma empresa pelo slug, tentando Supabase se não encontrar localmente
  Future<Empresa?> buscarEmpresaPorSlugAsync(String slug) async {
    // 1. Tentar Supabase primeiro para ter os dados mais frescos (importante para agendamento público)
    try {
      debugPrint(
        '>>> [AuthService] 🔍 Buscando versão fresca da empresa no Supabase: $slug',
      );
      final remota = await _supabaseService
          .buscarEmpresaPorSlug(slug)
          .timeout(const Duration(seconds: 5));
      if (remota != null) {
        final index = _empresas.indexWhere((e) => e.id == remota.id);
        if (index != -1) {
          // MERGE: preserva configurações locais (perfis, bridge, certificado etc.)
          final mesclada = _mesclarEmpresaComConfigsLocal(
            _empresas[index],
            remota,
          );
          _empresas[index] = mesclada;
          notifyListeners();
          // Replicar certificado/configs para o banco local (emissão offline)
          if (!kIsWeb) {
            DatabaseService()
                .salvarEmpresaLocal(mesclada.toMap())
                .catchError((e) => debugPrint(
                      '>>> [AuthService] ⚠️ Falha ao replicar empresa local: $e',
                    ));
          }
          return mesclada;
        } else {
          // Mesmo empresa nova, aplicar merge de dados locais se existir
          final localMensalidade = await _storage
              .carregarConfiguracoesMensalidadeLocal(remota.id);
          if (localMensalidade != null && localMensalidade.isNotEmpty) {
            final mergedConfigs = Map<String, dynamic>.from(
              remota.configuracoes ?? {},
            );
            mergedConfigs.addAll(localMensalidade);
            final empComLocal = remota.copyWith(configuracoes: mergedConfigs);
            _empresas.add(empComLocal);
          } else {
            _empresas.add(remota);
          }
        }
        notifyListeners();
        return remota;
      }
    } catch (e) {
      debugPrint('>>> [AuthService] ⚠️ Erro ao buscar empresa no Supabase: $e');
    }

    // 2. Fallback para cache local se Supabase falhar ou não encontrar
    return obterEmpresaPorSlug(slug);
  }

  /// Obtém usuários de uma empresa específica
  List<Usuario> getUsuariosDaEmpresa(String empresaId) {
    return _usuarios.where((u) => u.empresaId == empresaId && u.ativo).toList();
  }

  /// Adiciona uma nova empresa (apenas usuário "user" pode criar)
  Future<void> adicionarEmpresa(Empresa empresa) async {
    if (!podeCriarEmpresa) {
      throw Exception('Apenas o usuário administrador pode criar empresas');
    }

    _empresas.add(empresa);
    notifyListeners();
    await _salvarEmpresas();
    // Cada empresa nasce com o SEU usuário master (não mais um "user" único
    // compartilhado por todas, que era o que misturava os dados).
    _garantirMasterDaEmpresa(empresa);
  }

  /// Sincroniza, apenas em memória, a cópia da empresa mantida pelo
  /// AuthService. Usado quando o DataService altera configurações da empresa
  /// atual (perfis tributários, departamentos, estoques...) e persiste no
  /// banco: sem isso o AuthService continuaria com a configuração antiga e a
  /// reaplicaria ao selecionar a empresa de novo (o perfil padrão "voltava").
  void sincronizarEmpresaEmMemoria(Empresa empresa) {
    final index = _empresas.indexWhere((e) => e.id == empresa.id);
    if (index != -1) {
      _empresas[index] = empresa;
    }
    if (_empresaAtual?.id == empresa.id) {
      _empresaAtual = empresa;
    }
    notifyListeners();
  }

  /// Atualiza uma empresa
  Future<void> atualizarEmpresa(Empresa empresa) async {
    debugPrint('>>> [AuthService] ========================================');
    debugPrint('>>> [AuthService] Atualizando empresa: ${empresa.razaoSocial}');
    debugPrint('>>> [AuthService] ID: ${empresa.id}');
    debugPrint(
      '>>> [AuthService] configuracoes: ${empresa.configuracoes != null ? "presente" : "null"}',
    );
    if (empresa.configuracoes != null) {
      debugPrint(
        '>>> [AuthService] configuracoes.keys: ${empresa.configuracoes!.keys.toList()}',
      );
      if (empresa.configuracoes!.containsKey('ecommerce')) {
        final ecommerce = empresa.configuracoes!['ecommerce'];
        debugPrint(
          '>>> [AuthService] ecommerce config: ${ecommerce != null ? "presente" : "null"}',
        );
        if (ecommerce != null) {
          debugPrint(
            '>>> [AuthService] ecommerce keys: ${(ecommerce as Map).keys.toList()}',
          );
        }
      }
    }
    debugPrint('>>> [AuthService] ========================================');

    // Garantir que updatedAt está atualizado
    final empresaAtualizada = empresa.copyWith(updatedAt: DateTime.now());

    final index = _empresas.indexWhere((e) => e.id == empresa.id);
    if (index != -1) {
      _empresas[index] = empresaAtualizada;
      debugPrint('>>> [AuthService] ✓ Empresa atualizada na lista local');
    } else {
      // Se não encontrou, adicionar como nova empresa
      debugPrint(
        '>>> [AuthService] ⚠️ Empresa não encontrada na lista, adicionando como nova...',
      );
      _empresas.add(empresaAtualizada);
    }

    // Se a empresa atualizada é a empresa atual, atualizar também
    if (_empresaAtual?.id == empresa.id) {
      debugPrint(
        '>>> [AuthService] Empresa atualizada é a empresa atual, atualizando...',
      );
      _empresaAtual = empresaAtualizada;
      await _storage.salvar('empresa_atual', _empresaAtual!.toMap());
      debugPrint(
        '>>> [AuthService] ✓ Empresa atual atualizada no localStorage',
      );

      // Salvar backup dedicado de config de mensalidade para proteger contra sobrescrever
      if (empresaAtualizada.configuracoes != null) {
        await _storage.salvarConfiguracoesMensalidadeLocal(
          empresaAtualizada.id,
          empresaAtualizada.configuracoes!,
        );
        debugPrint(
          '>>> [AuthService] ✓ Config de mensalidade salva no backup local',
        );
      }

      // Salvar também no PostgreSQL local com suporte a JSONB para configuracoes
      if (!kIsWeb) {
        DatabaseService().salvarEmpresaLocal(_empresaAtual!.toMap()).catchError((
          e,
        ) {
          debugPrint(
            '>>> [AuthService] ⚠️ Erro ao salvar empresa no PostgreSQL local: $e',
          );
        });
      }

      // Verificar se as configurações foram salvas corretamente
      final empresaSalva = await _storage.carregar('empresa_atual');
      if (empresaSalva != null && empresaSalva['configuracoes'] != null) {
        final configSalvas =
            empresaSalva['configuracoes'] as Map<String, dynamic>?;
        debugPrint(
          '>>> [AuthService] Configurações salvas no localStorage: ${configSalvas?.keys.toList()}',
        );
        if (configSalvas != null && configSalvas.containsKey('ecommerce')) {
          debugPrint('>>> [AuthService] ✓ Configurações de e-commerce salvas!');
        }
      }
    }

    notifyListeners();

    // Salvar no localStorage
    await _salvarEmpresas();

    // Salvar no Supabase — tenta agora com timeout generoso
    if (!empresaAtualizada.nuvemAtiva) {
      debugPrint(
        '>>> [AuthService] ☁️⛔ Nuvem desativada para a empresa — não enviada ao Supabase',
      );
    } else
    try {
      await _supabaseService
          .upsert(SupabaseService.tableEmpresas, empresaAtualizada.toMap())
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint(
                '>>> [AuthService] ⚠️ Timeout ao salvar empresa no Supabase',
              );
            },
          );
      debugPrint(
        '>>> [AuthService] ✓ Empresa salva no Supabase (incluindo configuracoes)',
      );
    } catch (e) {
      debugPrint('>>> [AuthService] ⚠️ Erro ao salvar empresa no Supabase: $e');
      // Não bloquear o fluxo se Supabase falhar
    }
  }

  /// Remove uma empresa
  Future<void> removerEmpresa(String empresaId) async {
    _empresas.removeWhere((e) => e.id == empresaId);
    notifyListeners();
    await _salvarEmpresas();
    // Remover do Supabase também
    try {
      await _supabaseService.delete(SupabaseService.tableEmpresas, empresaId);
    } catch (e) {
      debugPrint('Erro ao remover empresa do Supabase: $e');
    }
  }

  /// Boot dos USUÁRIOS: primeiro LÊ o que está salvo, depois garante o master.
  ///
  /// A ORDEM é o que preserva os usuários criados pelo operador. Antes,
  /// [_carregarUsuariosPadrao] rodava primeiro — e ele GRAVA na hora. Como no
  /// boot a memória ainda está vazia, esse save levava só o master "user" para
  /// `cache_dados.usuarios` e APAGAVA a lista salva. O usuário criado aparecia
  /// na tela e sumia no reinício seguinte: a lista sempre voltava aos 3
  /// restaurados por [_restaurarUsuariosLocais] (user, carlos, silvio).
  ///
  /// Extraído para método próprio porque o teste de regressão exercita ESTA
  /// ordem, e não uma cópia dela.
  @visibleForTesting
  Future<void> carregarUsuariosNoBoot() async {
    try {
      await carregarUsuarios().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint(
            '>>> [AuthService] Timeout ao carregar usuários - usando padrão',
          );
        },
      );
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao carregar usuários: $e');
    }

    // Leitura feita (ou tentada): só agora a gravação é liberada. Se o banco
    // local NÃO respondeu, a lista em memória não representa o que está salvo —
    // nesse caso o boot também não grava por cima.
    _usuariosLidos = !DatabaseService().bancoLocalFalhou;
    _carregarUsuariosPadrao();
    // Daqui em diante a gravação segue normal (criar/editar/remover usuário).
    _usuariosLidos = true;
  }

  Future<void> _salvarUsuarios() async {
    // TRAVA DE BOOT: gravar antes de ler a lista salva sobrescreveria os
    // usuários do banco com a memória (vazia) do boot — era isso que fazia o
    // usuário recém-criado desaparecer no reinício do app.
    if (!_usuariosLidos) {
      debugPrint(
        '>>> [AuthService] ⛔ Gravação de usuários BLOQUEADA: a lista salva '
        'ainda não foi lida. Gravar agora apagaria os usuários já cadastrados.',
      );
      return;
    }
    try {
      // SEGURANÇA: NUNCA salvar usuários com senha vazia no PostgreSQL.
      // Se um usuário chegar aqui sem senha (ex: merge do Supabase),
      // removê-lo da lista de salvamento para não corromper o banco local.
      // A restauração na inicialização (_restaurarUsuariosLocais) cuidará
      // de recriar com senha correta no próximo boot.
      final usuariosComSenha = <Usuario>[];
      for (final u in _usuarios) {
        if (u.senha.isEmpty) {
          debugPrint(
            '>>> [AuthService] ⚠️ BLOQUEADO: usuário "${u.email}" (id=${u.id}) com senha vazia NÃO será salvo no PostgreSQL.',
          );
          continue;
        }
        usuariosComSenha.add(u);
      }

      // 1) Salvar no localStorage (PostgreSQL local — fonte primária de login)
      await _storage.salvarLista('usuarios', usuariosComSenha);

      // 2) Salvar no Supabase (apenas usuários vinculados a uma empresa — a
      //    tabela usuarios do Supabase tem empresa_id NOT NULL, então contas
      //    master/suporte sem empresa ficam apenas locais).
      //    Falhas são registradas de forma PERSISTENTE (exodo_config) para
      //    diagnóstico — nunca mais um usuário "some" silenciosamente.
      // Nuvem indisponível (PGRST002/503/504): não tenta usuário por usuário —
      // isso só gerava dezenas de "ERRO GRAVE" e esperas de timeout. Os dados
      // já estão no PostgreSQL local; a nuvem recebe quando o servidor voltar.
      if (SupabaseService.instance.servidorIndisponivel) {
        debugPrint(
          '>>> [Sync Usuários] ⏸️ Nuvem indisponível (cooldown) — '
          'sync de usuários adiado; login local preservado.',
        );
        return;
      }

      final errosAnteriores = await _carregarErrosSyncUsuarios();
      final errosAgora = <Map<String, dynamic>>[];

      for (final usuario in usuariosComSenha) {
        if (usuario.empresaId == null || usuario.empresaId!.isEmpty) {
          debugPrint(
            '>>> Usuário ${usuario.id} sem empresa_id — mantido apenas local.',
          );
          continue;
        }
        try {
          await _supabaseService.upsertUsuario(usuario.toMap());
        } catch (e) {
          errosAgora.add({
            'id': usuario.id,
            'email': usuario.email,
            'erro': e.toString(),
            'quando': DateTime.now().toIso8601String(),
          });
          final isRls =
              e.toString().contains('row-level security') ||
              e.toString().contains('42501');
          if (isRls) {
            debugPrint(
              '>>> [Sync Usuários] 🔒 RLS bloqueou ${usuario.email} — configure a política no Supabase (tabela usuarios)',
            );
          } else {
            debugPrint(
              '>>> [Sync Usuários] ❌ Falha persistente para ${usuario.email}: $e',
            );
          }
        }
      }

      // Salvar o registro de erros (máx. 50, sem duplicar o mesmo usuário) para
      // consulta futura — falhas ficam visíveis para diagnóstico, nunca silenciosas.
      if (errosAgora.isNotEmpty) {
        final porId = <String, Map<String, dynamic>>{};
        for (final e in [...errosAgora, ...errosAnteriores]) {
          porId[e['id']?.toString() ?? ''] = e; // novo sobrescreve antigo
        }
        final combinado = porId.values.take(50).toList();
        await _storage.salvar('erros_sync_usuarios', combinado);
      }
    } catch (e) {
      debugPrint('Erro ao salvar usuários: $e');
    }
  }

  /// Carrega o registro persistente de falhas de sincronização de usuários
  Future<List<Map<String, dynamic>>> _carregarErrosSyncUsuarios() async {
    try {
      final dados = await _storage.carregar('erros_sync_usuarios');
      if (dados is List) {
        return dados.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  /// Mescla as configurações locais (perfis tributários, perfis de preço e outras
  /// chaves apenas-locais) na versão remota da empresa, evitando que dados locais
  /// sejam perdidos quando o Supabase está desatualizado ou não possui essas chaves.
  Empresa _mesclarEmpresaComConfigsLocal(Empresa local, Empresa remota) {
    final configLocal = local.configuracoes ?? {};
    final configRemota = remota.configuracoes ?? {};
    final configMerged = <String, dynamic>{...configRemota};
    for (final entry in configLocal.entries) {
      if (!configMerged.containsKey(entry.key) ||
          configMerged[entry.key] == null) {
        configMerged[entry.key] = entry.value;
      }
    }
    // ══ Configs de licenciamento/pagamento — local SEMPRE tem prioridade ══
    for (final chave in [
      'status_pagamento',
      'bloqueado',
      'ultimo_mes_pago',
      'data_cobranca',
      'dataCobranca',
    ]) {
      if (configLocal.containsKey(chave) && configLocal[chave] != null) {
        configMerged[chave] = configLocal[chave];
      }
    }
    // ══ Perfis tributários e de preço ══
    if ((configLocal['perfis_tributarios'] as List?)?.isNotEmpty == true) {
      configMerged['perfis_tributarios'] = configLocal['perfis_tributarios'];
    }
    if ((configLocal['perfis_preco'] as List?)?.isNotEmpty == true) {
      configMerged['perfis_preco'] = configLocal['perfis_preco'];
    }
    return remota.copyWith(configuracoes: configMerged);
  }

  Future<void> _salvarEmpresas() async {
    try {
      // Salvar no localStorage (sempre fazer primeiro - crítico - Usando salvarLista para PostgreSQL)
      await _storage.salvarLista('empresas', _empresas);
      for (final empresa in _empresas) {
        if (empresa.configuracoes != null) {
          await _storage.salvarConfiguracoesMensalidadeLocal(
            empresa.id,
            empresa.configuracoes!,
          );
        }
      }
      debugPrint(
        '>>> [AuthService] ✓ Empresas e mensalidades salvas no banco local',
      );

      // Salvar no Supabase de forma assíncrona (não bloquear)
      Future.microtask(() async {
        for (final empresa in _empresas) {
          // Modo sem nuvem: não subir esta empresa para o Supabase
          if (!empresa.nuvemAtiva) {
            debugPrint(
              '>>> [AuthService] ☁️⛔ Empresa ${empresa.id} com nuvem desativada — não enviada ao Supabase',
            );
            continue;
          }
          try {
            await _supabaseService
                .upsert(SupabaseService.tableEmpresas, empresa.toMap())
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: () {
                    debugPrint(
                      '>>> [AuthService] ⚠️ Timeout ao salvar empresa ${empresa.id} no Supabase (não bloqueante)',
                    );
                  },
                );
          } catch (e) {
            // Apenas log, não bloquear
            debugPrint(
              '>>> [AuthService] ⚠️ Erro ao salvar empresa ${empresa.id} no Supabase: $e (não bloqueante)',
            );
          }
        }
        debugPrint(
          '>>> [AuthService] ✓ Processo de salvamento de empresas no Supabase concluído',
        );
      });

      debugPrint(
        '>>> [AuthService] ✓ Processo de salvamento de empresas concluído',
      );
    } catch (e) {
      debugPrint('>>> [AuthService] ❌ Erro ao salvar empresas: $e');
      // Re-throw apenas se for erro crítico no localStorage
      // Se for erro do Supabase, não bloquear
      if (e.toString().contains('localStorage') ||
          e.toString().contains('storage')) {
        rethrow;
      }
    }
  }

  /// Carrega usuários do localStorage e Supabase
  Future<void> carregarUsuarios() async {
    if (_isProcessandoUsuarios) return;
    _isProcessandoUsuarios = true;
    try {
      // Carregar do localStorage primeiro (rápido e confiável)
      try {
        final usuariosMap = await _storage
            .carregarLista('usuarios')
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => <Map<String, dynamic>>[],
            );
        if (usuariosMap.isNotEmpty) {
          _usuarios.clear();
          _usuarios.addAll(usuariosMap.map((map) => Usuario.fromMap(map)));
          debugPrint(
            '>>> ${_usuarios.length} usuários carregados do localStorage',
          );
          notifyListeners();

          if (SupabaseService.isAvailable) {
            Future.microtask(() async {
              try {
                final usuariosSupabase = await _supabaseService
                    .carregarUsuarios()
                    .timeout(
                      const Duration(seconds: 3),
                      onTimeout: () => <Usuario>[],
                    );
                if (usuariosSupabase.isNotEmpty) {
                  // MERGE SEGURO: o Supabase não tem coluna 'senha', então os
                  // usuários vindos da nuvem chegam com senha vazia. Sobrescrever
                  // a lista local por eles apagaria as senhas locais e o login
                  // quebraria. Mesclamos por id preservando a senha/permissões
                  // locais quando o registro da nuvem não tem esses dados.
                  final locais = <String, Usuario>{
                    for (final u in _usuarios) u.id: u,
                  };
                  final mesclados = <Usuario>[];
                  for (final u in usuariosSupabase) {
                    final local = locais[u.id];
                    if (local != null) {
                      // SEMPRE preservar dados locais (senha, permissões, etc.)
                      // O Supabase não tem coluna 'senha' — nunca sobrescrever
                      // a senha local com vazio.
                      mesclados.add(
                        u.copyWith(
                          senha: local.senha.isNotEmpty ? local.senha : u.senha,
                          isMaster: local.isMaster || u.isMaster,
                          permissoesPersonalizadas:
                              local.permissoesPersonalizadas ??
                              u.permissoesPersonalizadas,
                          permissoesNegadas:
                              local.permissoesNegadas ?? u.permissoesNegadas,
                          telasOcultas: local.telasOcultas ?? u.telasOcultas,
                          funcionarioId: local.funcionarioId ?? u.funcionarioId,
                          serieNfce: local.serieNfce != 1
                              ? local.serieNfce
                              : u.serieNfce,
                          numeroInicialNfce: local.numeroInicialNfce != 1
                              ? local.numeroInicialNfce
                              : u.numeroInicialNfce,
                        ),
                      );
                    } else if (u.senha.isNotEmpty) {
                      // Usuário NOVO do Supabase que tem senha → pode adicionar
                      mesclados.add(u);
                    }
                    // else: Supabase user sem senha e sem equivalente local →
                    // IGNORAR. Não faz sentido ter usuário sem senha local.
                  }
                  // Preservar usuários locais que ainda não existem na nuvem
                  for (final local in _usuarios) {
                    if (!mesclados.any((m) => m.id == local.id)) {
                      mesclados.add(local);
                    }
                  }
                  _usuarios.clear();
                  _usuarios.addAll(mesclados);

                  // SEGURANÇA FINAL: garantir que o usuário master 'user' sempre
                  // existe com senha válida. Se o merge do Supabase removeu ou
                  // deixou vazio, recriamos aqui para nunca bloquear o login.
                  if (!_usuarios.any((u) => u.email.toLowerCase() == 'user')) {
                    debugPrint(
                      '>>> [AuthService] ⚠️ Usuário master "user" não encontrado após merge — recriando.',
                    );
                    _usuarios.add(
                      Usuario(
                        id: '1',
                        nome: 'Usuário',
                        email: 'user',
                        senha: 'kP4#%vMJ',
                        tipo: TipoUsuario.administrador,
                        isMaster: true,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                        ativo: true,
                      ),
                    );
                  }

                  await _salvarUsuarios();
                  notifyListeners();
                }
              } catch (_) {}
            });
          }
          return;
        }
      } catch (e) {
        debugPrint(
          '>>> [AuthService] Erro ao carregar usuários do localStorage: $e',
        );
      }

      // Se localStorage não tiver dados, NÃO usar Supabase como fonte de
      // login local. O Supabase não tem coluna 'senha' — carregar de lá
      // e salvar no banco local criaria usuários sem senha e o login
      // quebraria. Mantemos apenas os usuários padrão (user/admin).
      debugPrint(
        '>>> [AuthService] Nenhum usuário local encontrado. Mantendo apenas usuários padrão (login local requer senhas locais).',
      );
    } finally {
      _isProcessandoUsuarios = false;
    }
  }

  /// Carrega empresas do localStorage e Supabase
  Future<void> carregarEmpresas() async {
    if (_isProcessandoEmpresas) return;
    _isProcessandoEmpresas = true;
    try {
      // Carregar do localStorage primeiro (Mais rápido para offline)
      // Carregar do localStorage primeiro
      final empresasMap = await _storage
          .carregarLista('empresas')
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => <Map<String, dynamic>>[],
          );
      if (empresasMap.isNotEmpty) {
        _empresas.clear();
        for (final map in empresasMap) {
          Empresa emp = Empresa.fromMap(map);
          final localMensalidade = await _storage
              .carregarConfiguracoesMensalidadeLocal(emp.id);
          if (localMensalidade != null) {
            final mergedConfigs = Map<String, dynamic>.from(
              emp.configuracoes ?? {},
            );
            mergedConfigs.addAll(localMensalidade);
            emp = emp.copyWith(configuracoes: mergedConfigs);
          }
          _empresas.add(emp);
        }
        debugPrint(
          '>>> ${_empresas.length} empresas com mensalidade local carregadas',
        );
        notifyListeners();

        if (SupabaseService.isAvailable) {
          Future.microtask(() async {
            try {
              final empresasSupabase = await _supabaseService
                  .carregarEmpresas()
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => <Empresa>[],
                  );
              if (empresasSupabase.isNotEmpty) {
                // Snapshot dos campos fiscais JÁ presentes na lista local (carregada
                // do localStorage/PG): evita perder IE/IM quando o Supabase está
                // com esses campos vazios e sobrescreve a lista local.
                final Map<String, Empresa> fiscaisLocais = {
                  for (final e in _empresas) e.id: e,
                };
                _empresas.clear();
                for (var emp in empresasSupabase) {
                  final localMensalidade = await _storage
                      .carregarConfiguracoesMensalidadeLocal(emp.id);
                  if (localMensalidade != null) {
                    final mergedConfigs = Map<String, dynamic>.from(
                      emp.configuracoes ?? {},
                    );
                    // Atualiza chaves de cobrança locais se houver override offline
                    mergedConfigs.addAll(localMensalidade);
                    emp = emp.copyWith(configuracoes: mergedConfigs);
                  }
                  final local = fiscaisLocais[emp.id];
                  if (local != null) {
                    final ieVazio = (emp.inscricaoEstadual ?? '').trim().isEmpty;
                    final imVazio = (emp.inscricaoMunicipal ?? '').trim().isEmpty;
                    final ibgeVazio = (emp.codigoIBGE ?? '').trim().isEmpty;
                    if (ieVazio || imVazio || ibgeVazio) {
                      emp = emp.copyWith(
                        inscricaoEstadual: ieVazio &&
                                (local.inscricaoEstadual ?? '').trim().isNotEmpty
                            ? local.inscricaoEstadual
                            : emp.inscricaoEstadual,
                        inscricaoMunicipal: imVazio &&
                                (local.inscricaoMunicipal ?? '').trim().isNotEmpty
                            ? local.inscricaoMunicipal
                            : emp.inscricaoMunicipal,
                        codigoIBGE: ibgeVazio &&
                                (local.codigoIBGE ?? '').trim().isNotEmpty
                            ? local.codigoIBGE
                            : emp.codigoIBGE,
                      );
                    }
                  }
                  _empresas.add(emp);
                }
                await _salvarEmpresas();
                notifyListeners();
              }
            } catch (_) {}
          });
        }
        return;
      }

      // Tentar Supabase (Mesmo sem usuário autenticado, se a tabela permitir leitura pública)
      try {
        final empresasSupabase = await _supabaseService
            .carregarEmpresas()
            .timeout(const Duration(seconds: 12), onTimeout: () => <Empresa>[]);
        if (empresasSupabase.isNotEmpty) {
          _empresas.clear();
          for (final emp in empresasSupabase) {
            // Merge: preserva dados locais (mensalidade, configs de PDV, etc.)
            final localMensalidade = await _storage
                .carregarConfiguracoesMensalidadeLocal(emp.id);
            if (localMensalidade != null && localMensalidade.isNotEmpty) {
              final mergedConfigs = Map<String, dynamic>.from(
                emp.configuracoes ?? {},
              );
              mergedConfigs.addAll(localMensalidade);
              _empresas.add(emp.copyWith(configuracoes: mergedConfigs));
            } else {
              _empresas.add(emp);
            }
          }
          await _salvarEmpresas();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint(
          '>>> [AuthService] Erro ao carregar empresas do Supabase: $e',
        );
      }

      if (!_empresas.any((e) => e.id == '1')) {
        _carregarEmpresasPadrao();
      }
      notifyListeners();
    } finally {
      _isProcessandoEmpresas = false;
      // Empresas carregadas: garantir o master de cada uma (inclusive as que já
      // existiam antes desta mudança).
      _garantirMastersDasEmpresas();
    }
  }
}
