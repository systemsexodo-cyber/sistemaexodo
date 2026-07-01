import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import 'local_storage_service.dart';
import 'supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço de autenticação e gerenciamento de usuários
class AuthService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  final SupabaseService _supabaseService = SupabaseService.instance;
  
  Usuario? _usuarioAtual;
  Empresa? _empresaAtual;
  bool _isLoading = false;
  bool _isCarregandoDados = true; // Estado de carregamento inicial
  bool _isProcessandoUsuarios = false;
  bool _isProcessandoEmpresas = false;

  Usuario? get usuarioAtual => _usuarioAtual;
  Empresa? get empresaAtual => _empresaAtual;
  bool get isLoading => _isLoading;
  bool get isCarregandoDados => _isCarregandoDados;
  bool get isAuthenticated => _usuarioAtual != null;
  bool get temEmpresaSelecionada => _empresaAtual != null;

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
  final List<Empresa> _empresas = [];

  List<Usuario> get usuarios => List.unmodifiable(_usuarios);
  List<Empresa> get empresas => List.unmodifiable(_empresas);

  AuthService() {
    // Iniciar carregamento
    _isCarregandoDados = true;
    notifyListeners();
    
    // Carrega dados salvos primeiro (isso carregará empresas e usuários salvos)
    // As empresas/usuários padrão só serão adicionados se não houver dados salvos
    _carregarDadosSalvos().then((_) {
      // Pequeno delay para garantir que o loading seja visível
      Future.delayed(const Duration(milliseconds: 300), () {
        _isCarregandoDados = false;
        notifyListeners();
        debugPrint('>>> [AuthService] Carregamento de dados inicial concluído');
      });
    }).catchError((e, stackTrace) {
      debugPrint('>>> [AuthService] Erro ao carregar dados iniciais: $e');
      debugPrint('>>> [AuthService] StackTrace: $stackTrace');
      // Garantir que sempre sai do estado de loading, mesmo em erro
      Future.delayed(const Duration(milliseconds: 300), () {
        _isCarregandoDados = false;
        notifyListeners();
        debugPrint('>>> [AuthService] Saindo do estado de loading após erro');
      });
    });
    
    // Timeout de segurança para garantir que sempre saia do loading
    Future.delayed(const Duration(seconds: 15), () {
      if (_isCarregandoDados) {
        debugPrint('>>> [AuthService] TIMEOUT no carregamento inicial (15s) - forçando saída do loading');
        _isCarregandoDados = false;
        notifyListeners();
      }
    });
  }

  /// Carrega dados salvos do localStorage
  Future<void> _carregarDadosSalvos() async {
    try {
      // Primeiro, carregar usuários padrão (se necessário)
      _carregarUsuariosPadrao();
      
      // Depois, carregar usuários salvos (substituem os padrão se existirem) com timeout
      try {
        await carregarUsuarios().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('>>> [AuthService] Timeout ao carregar usuários - usando padrão');
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuários: $e');
      }
      
      // Atualizar senha do usuário "user" se ainda tiver a senha antiga
      try {
        await _atualizarSenhaUsuarioUser().timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('>>> [AuthService] Timeout ao atualizar senha do usuário');
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao atualizar senha: $e');
      }
      
      // Primeiro, carregar empresas padrão (se necessário)
      _carregarEmpresasPadrao();
      
      // Depois, carregar empresas salvas (substituem as padrão se existirem) com timeout
      try {
        await carregarEmpresas().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('>>> [AuthService] Timeout ao carregar empresas - usando padrão');
          },
        );
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar empresas: $e');
      }
      
      // Carregar HISTÓRICO de logins
      try {
        final hist = await _storage.carregar('historico_logins');
        if (hist != null && hist is List) {
           _historicoLogins = hist.map((e) => e.toString()).toList();
           debugPrint('>>> [AuthService] Histórico carregado: ${_historicoLogins.length} perfis');
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar histórico: $e');
      }

      // SEGURANÇA: Se é uma nova sessão (navegador aberto agora), limpar login antigo
      if (!_storage.isSessaoAtiva()) {
        debugPrint('>>> [AuthService] 🔒 Nova sessão detectada! Limpando logins anteriores.');
        await _storage.remover('usuario_atual');
        await _storage.remover('empresa_atual');
      }

      // Carregar usuário e empresa atual selecionados de forma persistente
      try {
        final usuarioMap = await _storage.carregar('usuario_atual').timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (usuarioMap != null && usuarioMap is Map) {
          _usuarioAtual = Usuario.fromMap(Map<String, dynamic>.from(usuarioMap));
          debugPrint('>>> [AuthService] ✓ Usuário restaurado: ${_usuarioAtual?.nome}');
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuário atual: $e');
      }
      
      try {
        final empresaMap = await _storage.carregar('empresa_atual').timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (empresaMap != null && empresaMap is Map) {
          debugPrint('>>> [AuthService] ========================================');
          _empresaAtual = Empresa.fromMap(Map<String, dynamic>.from(empresaMap));
          debugPrint('>>> [AuthService] Empresa carregada: ${_empresaAtual?.razaoSocial ?? "null"}');
          debugPrint('>>> [AuthService] ========================================');
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
        debugPrint('>>> Senha do usuário "user" atualizada de "user" para "kP4#%vMJ"');
        await _salvarUsuarios(); // Salvar a atualização
        notifyListeners();
      }
    }
  }

  /// Carrega usuários padrão (apenas para desenvolvimento)
  void _carregarUsuariosPadrao() {
    if (_usuarios.isNotEmpty) {
      debugPrint('>>> Usuários já carregados: ${_usuarios.length}');
      return;
    }
    
    final agora = DateTime.now();
    final usuario = Usuario(
      id: '1',
      nome: 'Usuário',
      email: 'user',
      senha: 'kP4#%vMJ', // Senha alterada
      tipo: TipoUsuario.administrador,
      createdAt: agora,
      updatedAt: agora,
      ativo: true,
    );
    
    _usuarios.add(usuario);
    debugPrint('>>> Usuário padrão criado: email="${usuario.email}", senha="${usuario.senha}", ativo=${usuario.ativo}');
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

  /// Realiza login do usuário
  Future<bool> login(String email, String senha) async {
    _isLoading = true;
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
        debugPrint('>>>   - ${u.email} (senha: "${u.senha}", ativo: ${u.ativo})');
      }
      
      // Busca o usuário
      Usuario? usuarioEncontrado;
      for (var u in _usuarios) {
        final emailMatch = u.email.toLowerCase().trim() == emailLower;
        final senhaMatch = u.senha.trim() == senhaTrim;
        final ativo = u.ativo;
        
        debugPrint('>>> Comparando: emailMatch=$emailMatch (${u.email.toLowerCase().trim()} == $emailLower), senhaMatch=$senhaMatch (${u.senha.trim()} == $senhaTrim), ativo=$ativo');
        
        if (emailMatch && senhaMatch && ativo) {
          usuarioEncontrado = u;
          debugPrint('>>> Usuário encontrado: ${u.nome}');
          
          // Tentar autenticar no Supabase em paralelo para habilitar o Realtime
          // Supabase exige formato de email, então adicionamos um sufixo se for apenas usuário
          final supabaseEmail = emailLower.contains('@') ? emailLower : '$emailLower@sistemaexodo.com';
          
          try {
            debugPrint('>>> [Supabase] Tentando autenticação paralela para $supabaseEmail...');
            
            bool logadoComSucesso = false;
            String? senhaUsada;

            // 1. Tentar com a senha fornecida pelo usuário
            try {
              await _supabaseService.login(supabaseEmail, senhaTrim).timeout(
                const Duration(seconds: 5),
              );
              logadoComSucesso = true;
              senhaUsada = senhaTrim;
              debugPrint('>>> [Supabase] ✅ Autenticação realizada com a senha atual.');
            } catch (e) {
              debugPrint('>>> [Supabase] ⚠️ Senha atual falhou para Supabase. Tentando fallbacks...');
              
            // 2. Fallback: Tentar com senha antiga 'user'
            if (!logadoComSucesso) {
              try {
                debugPrint('>>> [Supabase] Tentando fallback 1: "user"...');
                await _supabaseService.login(supabaseEmail, 'user').timeout(
                  const Duration(seconds: 5),
                );
                logadoComSucesso = true;
                senhaUsada = 'user';
                debugPrint('>>> [Supabase] ✅ Autenticação realizada com fallback 1 ("user").');
              } catch (e) {
                debugPrint('>>> [Supabase] ⚠️ Fallback 1 falhou: $e');
              }
            }

            // 3. Fallback: Tentar com senha do arquivo 'hmrzbdKJB6Bc4Vcr'
            if (!logadoComSucesso) {
              try {
                debugPrint('>>> [Supabase] Tentando fallback 2: "hmrzbdKJB6Bc4Vcr"...');
                await _supabaseService.login(supabaseEmail, 'hmrzbdKJB6Bc4Vcr').timeout(
                  const Duration(seconds: 5),
                );
                logadoComSucesso = true;
                senhaUsada = 'hmrzbdKJB6Bc4Vcr';
                debugPrint('>>> [Supabase] ✅ Autenticação realizada com fallback 2 ("hmrzbdKJB6Bc4Vcr").');
              } catch (e) {
                debugPrint('>>> [Supabase] ⚠️ Fallback 2 falhou: $e');
              }
            }

            // 4. Fallback: Tentar com senha anterior conhecida 'ad1579036'
            if (!logadoComSucesso) {
              try {
                debugPrint('>>> [Supabase] Tentando fallback 3: "ad1579036"...');
                await _supabaseService.login(supabaseEmail, 'ad1579036').timeout(
                  const Duration(seconds: 5),
                );
                logadoComSucesso = true;
                senhaUsada = 'ad1579036';
                debugPrint('>>> [Supabase] ✅ Autenticação realizada com fallback 3 ("ad1579036").');
              } catch (e) {
                debugPrint('>>> [Supabase] ⚠️ Fallback 3 falhou: $e');
              }
            }
          }

            // Se logou com um fallback, sincronizar a senha do Supabase com a local para o próximo login
            if (logadoComSucesso && senhaUsada != senhaTrim) {
              debugPrint('>>> [Supabase] 🔄 Sincronizando senha do Supabase com a senha local...');
              try {
                // Supabase.client.auth.updateUser requer que o usuário esteja logado (o que já estamos após o fallback)
                await _supabaseService.client.auth.updateUser(
                  UserAttributes(password: senhaTrim),
                ).timeout(const Duration(seconds: 5));
                debugPrint('>>> [Supabase] ✅ Senha do Supabase sincronizada com o padrão local.');
              } catch (e) {
                debugPrint('>>> [Supabase] ⚠️ Erro ao sincronizar senha: $e');
              }
            }

            if (!logadoComSucesso) {
              throw Exception('Nenhuma das tentativas de autenticação no Supabase (incluindo fallbacks) funcionou.');
            }
            
            // ✅ Login no Supabase bem-sucedido!
            // Recarregar empresas agora que temos autenticação (RLS liberado)
            debugPrint('>>> [Supabase] 🔄 Recarregando empresas do Supabase (com autenticação)...');
            try {
              final empresasSupabase = await _supabaseService.carregarEmpresas().timeout(
                const Duration(seconds: 8),
                onTimeout: () => <Empresa>[],
              );
              if (empresasSupabase.isNotEmpty) {
                // Mesclar com empresas locais sem duplicar
                for (final emp in empresasSupabase) {
                  final idx = _empresas.indexWhere((e) => e.id == emp.id);
                  if (idx != -1) {
                    _empresas[idx] = emp; // Atualizar existente
                  } else {
                    _empresas.add(emp); // Adicionar nova
                  }
                }
                await _salvarEmpresas();
                debugPrint('>>> [Supabase] ✅ ${empresasSupabase.length} empresa(s) carregada(s) do Supabase após login.');
              }
            } catch (reloadErr) {
              debugPrint('>>> [Supabase] ⚠️ Erro ao recarregar empresas após login: $reloadErr');
            }

          } catch (e) {
            debugPrint('>>> [Supabase] ❌ Falha total na autenticação paralela (Realtime ficará off): $e');
            // Nota: Não lançamos erro aqui para não travar o login local/offline
          }
          
          break;
        }
      }
      
      if (usuarioEncontrado == null) {
        debugPrint('>>> ERRO: Nenhum usuário encontrado com essas credenciais');
        throw Exception('Usuário ou senha inválidos');
      }
      
      final usuario = usuarioEncontrado;

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
      _historicoLogins.removeWhere((l) => l.toLowerCase() == loginLower); // Remove se já existir
      _historicoLogins.insert(0, loginLower); // Insere no topo
      if (_historicoLogins.length > 5) _historicoLogins.removeLast(); // Limita a 5
      await _storage.salvar('historico_logins', _historicoLogins);
      
      // Se o usuário tem empresa associada, carrega ela
      if (_usuarioAtual!.empresaId != null) {
        await selecionarEmpresaPorId(_usuarioAtual!.empresaId!);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Erro no login: $e');
      return false;
    }
  }

  /// Realiza logout do usuário
  Future<void> logout() async {
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

  /// Seleciona uma empresa
  Future<void> selecionarEmpresa(Empresa empresa) async {
    // VALIDAÇÃO DE SEGURANÇA: Verificar se o usuário tem acesso a esta empresa
    if (_usuarioAtual != null) {
      final empresasPermitidas = getEmpresasDoUsuario();
      if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
        throw Exception('Você não tem permissão para acessar esta empresa');
      }
    }
    
    debugPrint('>>> [AuthService] ========================================');
    debugPrint('>>> [AuthService] Selecionando empresa: ${empresa.razaoSocial}');
    debugPrint('>>> [AuthService] ID: ${empresa.id}');
    debugPrint('>>> [AuthService] configuracoes: ${empresa.configuracoes != null ? "presente" : "null"}');
    if (empresa.configuracoes != null) {
      debugPrint('>>> [AuthService] configuracoes.keys: ${empresa.configuracoes!.keys.toList()}');
      final bytes = empresa.configuracoes!['certificadoDigitalBytes'];
      debugPrint('>>> [AuthService] certificadoDigitalBytes: ${bytes != null ? "presente (${(bytes as String).length} chars)" : "null"}');
      debugPrint('>>> [AuthService] certificadoWindowsThumbprint: ${empresa.configuracoes!['certificadoWindowsThumbprint'] ?? "null"}');
    }
    debugPrint('>>> [AuthService] certificadoDigitalUrl: ${empresa.certificadoDigitalUrl ?? "null"}');
    debugPrint('>>> [AuthService] senhaCertificado: ${empresa.senhaCertificado != null && empresa.senhaCertificado!.isNotEmpty ? "presente (${empresa.senhaCertificado!.length} chars)" : "AUSENTE"}');
    debugPrint('>>> [AuthService] ========================================');
    
    // VERIFICAÇÃO CRÍTICA: Se certificado não estiver presente, tentar recarregar do Supabase
    // VERIFICAÇÃO CRÍTICA: Se certificado não estiver presente, tentar recarregar do Supabase
    final temCertificado = (empresa.configuracoes?['certificadoDigitalBytes'] != null && 
                            (empresa.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty) ||
                           (empresa.certificadoDigitalUrl != null && empresa.certificadoDigitalUrl!.isNotEmpty) ||
                           (empresa.configuracoes?['certificadoWindowsThumbprint'] != null);
    
    if (!temCertificado) {
      debugPrint('>>> [AuthService] ⚠️ Certificado não encontrado na empresa local!');
      debugPrint('>>> [AuthService] Tentando recarregar do Supabase...');
      
      try {
        final empresaSupabase = await _supabaseService.buscarEmpresaPorSlug(empresa.slug);
        
        final temCertificadoSupabase = empresaSupabase != null && ((empresaSupabase.configuracoes?['certificadoDigitalBytes'] != null && 
                                         (empresaSupabase.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty) ||
                                        (empresaSupabase.certificadoDigitalUrl != null && empresaSupabase.certificadoDigitalUrl!.isNotEmpty) ||
                                        (empresaSupabase.configuracoes?['certificadoWindowsThumbprint'] != null));
        
        if (temCertificadoSupabase) {
          debugPrint('>>> [AuthService] ✓✓✓ Certificado encontrado no Supabase!');
          _empresaAtual = empresaSupabase;
          
          // Atualizar na lista local também
          final index = _empresas.indexWhere((e) => e.id == empresa.id);
          if (index != -1) {
            _empresas[index] = empresaSupabase;
          }
          
          final empresaMap = empresaSupabase.toMap();
          await _storage.salvar('empresa_atual', empresaMap);
          debugPrint('>>> [AuthService] ✓ Empresa com certificado salva no localStorage');
          notifyListeners();
          return;
        } else {
          debugPrint('>>> [AuthService] ⚠️ Certificado também não encontrado no Supabase');
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao recarregar do Supabase: $e');
      }
    }
    
    _empresaAtual = empresa;
    final empresaMap = empresa.toMap();
    
    // Sincronizar empresa_id com o metadado do usuário no Supabase para o RLS funcionar
    try {
      final supabaseUser = _supabaseService.client.auth.currentUser;
      if (supabaseUser != null) {
        debugPrint('>>> [AuthService] 🔄 Sincronizando empresa_id (${empresa.id}) com metadados do Supabase...');
        await _supabaseService.client.auth.updateUser(
          UserAttributes(
            data: {
              'empresa_id': empresa.id,
            },
          ),
        ).timeout(const Duration(seconds: 5));
        
        // Forçar atualização da sessão para renovar o JWT com o novo metadado
        await _supabaseService.client.auth.refreshSession();
        debugPrint('>>> [AuthService] ✅ Metadados e sessão do usuário atualizados no Supabase.');
      }
    } catch (e) {
      debugPrint('>>> [AuthService] ⚠️ Erro ao atualizar metadados no Supabase: $e');
    }

    debugPrint('>>> [AuthService] Salvando empresa no localStorage...');
    debugPrint('>>> [AuthService] empresaMap.keys: ${empresaMap.keys.toList()}');
    debugPrint('>>> [AuthService] empresaMap.configuracoes: ${empresaMap['configuracoes'] != null ? "presente" : "null"}');
    if (empresaMap['configuracoes'] != null) {
      final configMap = empresaMap['configuracoes'] as Map<String, dynamic>;
      debugPrint('>>> [AuthService] configMap.keys: ${configMap.keys.toList()}');
      final bytes = configMap['certificadoDigitalBytes'];
      debugPrint('>>> [AuthService] certificadoDigitalBytes no map: ${bytes != null ? "presente (${(bytes as String).length} chars)" : "null"}');
    }
    await _storage.salvar('empresa_atual', empresaMap);
    debugPrint('>>> [AuthService] ✓ Empresa salva no localStorage');
    notifyListeners();
  }

  /// Seleciona uma empresa por ID
  Future<void> selecionarEmpresaPorId(String empresaId) async {
    // VALIDAÇÃO DE SEGURANÇA: Verificar se o usuário tem acesso a esta empresa
    if (_usuarioAtual != null) {
      final empresasPermitidas = getEmpresasDoUsuario();
      if (!empresasPermitidas.any((e) => e.id == empresaId)) {
        debugPrint('>>> [AuthService] ⚠️ Usuário não tem permissão para acessar empresa $empresaId');
        return; // Silenciosamente retorna se não tiver permissão (evita erro no login)
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
    
    debugPrint('>>> [AuthService] Empresa encontrada localmente: ${empresa.razaoSocial}');
    debugPrint('>>> [AuthService] certificadoDigitalBytes local: ${empresa.configuracoes?['certificadoDigitalBytes'] != null ? "presente (${(empresa.configuracoes!['certificadoDigitalBytes'] as String).length} chars)" : "NULL"}');
    
    // SEGUNDO: Tentar recarregar do localStorage (mais confiável para local)
    try {
      debugPrint('>>> [AuthService] Tentando recarregar do localStorage...');
      final empresasMap = await _storage.carregarLista('empresas');
      if (empresasMap.isNotEmpty) {
        final empresaLocalStorage = empresasMap
            .map((map) => Empresa.fromMap(map))
            .where((e) => e.id == empresaId)
            .firstOrNull ?? empresa;
        
        debugPrint('>>> [AuthService] Empresa encontrada no localStorage');
        debugPrint('>>> [AuthService] certificadoDigitalBytes localStorage: ${empresaLocalStorage.configuracoes?['certificadoDigitalBytes'] != null ? "presente (${(empresaLocalStorage.configuracoes!['certificadoDigitalBytes'] as String).length} chars)" : "NULL"}');
        
        // Se localStorage tem certificado e local não tem, usar localStorage
        final temCertificadoLocalStorage = (empresaLocalStorage.configuracoes?['certificadoDigitalBytes'] != null && 
                                            (empresaLocalStorage.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty);
        final temCertificadoLocal = (empresa.configuracoes?['certificadoDigitalBytes'] != null && 
                                     (empresa.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty);
        
        if (temCertificadoLocalStorage && !temCertificadoLocal) {
          debugPrint('>>> [AuthService] ✓✓✓ Certificado encontrado no localStorage! Usando...');
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
    
    // TERCEIRO: Tentar Supabase (se disponível)
    try {
      debugPrint('>>> [AuthService] Tentando recarregar do Supabase...');
      final empresasSupabase = await _supabaseService.carregarEmpresas();
      final empresaSupabase = empresasSupabase
          .where((e) => e.id == empresaId)
          .firstOrNull ?? empresa;
      
      debugPrint('>>> [AuthService] Empresa encontrada no Supabase');
      
      // Se Supabase tem certificado e local não tem, usar Supabase
      final temCertificadoSupabase = (empresaSupabase.configuracoes?['certificadoDigitalBytes'] != null && 
                                      (empresaSupabase.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty);
      final temCertificadoLocal = (empresa.configuracoes?['certificadoDigitalBytes'] != null && 
                                   (empresa.configuracoes?['certificadoDigitalBytes'] as String).isNotEmpty);
      
      if (temCertificadoSupabase && !temCertificadoLocal) {
        debugPrint('>>> [AuthService] ✓✓✓ Certificado encontrado no Supabase! Usando...');
        empresa = empresaSupabase;
        
        // Atualizar na lista local
        final index = _empresas.indexWhere((e) => e.id == empresaId);
        if (index != -1) {
          _empresas[index] = empresa;
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao recarregar do Supabase: $e');
      debugPrint('>>> [AuthService] Continuando com empresa local/localStorage...');
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
      final supabaseEmail = emailLower.contains('@') ? emailLower : '$emailLower@sistemaexodo.com';
      
      debugPrint('>>> [Supabase] Criando conta de acesso para $supabaseEmail...');
      await _supabaseService.signUp(supabaseEmail, usuario.senha).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Timeout ao criar conta no Supabase'),
      );
      debugPrint('>>> [Supabase] ✅ Conta Auth criada com sucesso.');
    } catch (e) {
      // Se der erro (ex: usuário já existe), apenas logamos
      debugPrint('>>> [Supabase] ℹ️ Aviso ao criar conta Auth: $e');
    }
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
    
    debugPrint('>>> [AuthService] 🔍 Buscando empresa para slug normalizado: "$slugLower" (Original: "$slug")');
    debugPrint('>>> [AuthService] 🏢 Empresas em memória: ${_empresas.length}');
    
    // 1. Tentar correspondência exata de slug ou ID
    try {
      final encontrada = _empresas.firstWhere(
        (e) => (e.slug.toLowerCase() == slugLower || e.id.toLowerCase() == slugLower.toUpperCase() || e.id.toLowerCase() == slugLower) && e.ativo,
      );
      debugPrint('>>> [AuthService] ✅ Encontrada por Slug/ID: ${encontrada.nomeExibicao} (ID: ${encontrada.id})');
      return encontrada;
    } catch (_) {
      // 2. Tentar gerar slug do nome para comparação (fallback para empresas sem slug definido)
      try {
        final encontrada = _empresas.firstWhere(
          (e) => Empresa.gerarSlug(e.nomeExibicao) == slugLower && e.ativo,
        );
        debugPrint('>>> [AuthService] ✅ Encontrada por Nome Gerado: ${encontrada.nomeExibicao}');
        return encontrada;
      } catch (_) {
        // Log para ajudar no debug (sem expor muitos dados)
        if (_empresas.isNotEmpty) {
           debugPrint('>>> [AuthService] ❌ Falha na busca. Slugs disponíveis: ${_empresas.map((e) => e.slug).where((s) => s.isNotEmpty).join(", ")}');
        }
        return null;
      }
    }
  }
  

  /// Busca uma empresa pelo slug, tentando Supabase se não encontrar localmente
  Future<Empresa?> buscarEmpresaPorSlugAsync(String slug) async {
    // 1. Tentar Supabase primeiro para ter os dados mais frescos (importante para agendamento público)
    try {
      debugPrint('>>> [AuthService] 🔍 Buscando versão fresca da empresa no Supabase: $slug');
      final remota = await _supabaseService.buscarEmpresaPorSlug(slug).timeout(const Duration(seconds: 5));
      if (remota != null) {
        final index = _empresas.indexWhere((e) => e.id == remota.id);
        if (index != -1) {
          _empresas[index] = remota;
        } else {
          _empresas.add(remota);
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
    return _usuarios
        .where((u) => u.empresaId == empresaId && u.ativo)
        .toList();
  }

  /// Adiciona uma nova empresa (apenas usuário "user" pode criar)
  Future<void> adicionarEmpresa(Empresa empresa) async {
    if (!podeCriarEmpresa) {
      throw Exception('Apenas o usuário administrador pode criar empresas');
    }
    
    _empresas.add(empresa);
    notifyListeners();
    await _salvarEmpresas();
  }

  /// Atualiza uma empresa
  Future<void> atualizarEmpresa(Empresa empresa) async {
    debugPrint('>>> [AuthService] ========================================');
    debugPrint('>>> [AuthService] Atualizando empresa: ${empresa.razaoSocial}');
    debugPrint('>>> [AuthService] ID: ${empresa.id}');
    debugPrint('>>> [AuthService] configuracoes: ${empresa.configuracoes != null ? "presente" : "null"}');
    if (empresa.configuracoes != null) {
      debugPrint('>>> [AuthService] configuracoes.keys: ${empresa.configuracoes!.keys.toList()}');
      if (empresa.configuracoes!.containsKey('ecommerce')) {
        final ecommerce = empresa.configuracoes!['ecommerce'];
        debugPrint('>>> [AuthService] ecommerce config: ${ecommerce != null ? "presente" : "null"}');
        if (ecommerce != null) {
          debugPrint('>>> [AuthService] ecommerce keys: ${(ecommerce as Map).keys.toList()}');
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
      debugPrint('>>> [AuthService] ⚠️ Empresa não encontrada na lista, adicionando como nova...');
      _empresas.add(empresaAtualizada);
    }
    
    // Se a empresa atualizada é a empresa atual, atualizar também
    if (_empresaAtual?.id == empresa.id) {
      debugPrint('>>> [AuthService] Empresa atualizada é a empresa atual, atualizando...');
      _empresaAtual = empresaAtualizada;
      await _storage.salvar('empresa_atual', _empresaAtual!.toMap());
      debugPrint('>>> [AuthService] ✓ Empresa atual atualizada no localStorage');
      
      // Verificar se as configurações foram salvas corretamente
      final empresaSalva = await _storage.carregar('empresa_atual');
      if (empresaSalva != null && empresaSalva['configuracoes'] != null) {
        final configSalvas = empresaSalva['configuracoes'] as Map<String, dynamic>?;
        debugPrint('>>> [AuthService] Configurações salvas no localStorage: ${configSalvas?.keys.toList()}');
        if (configSalvas != null && configSalvas.containsKey('ecommerce')) {
          debugPrint('>>> [AuthService] ✓ Configurações de e-commerce salvas!');
        }
      }
    }
    
    notifyListeners();
    
    // Salvar no localStorage
    await _salvarEmpresas();
    
    // Salvar no Supabase de forma não bloqueante
    Future.microtask(() async {
      try {
        await _supabaseService.upsert(SupabaseService.tableEmpresas, empresaAtualizada.toMap()).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('>>> [AuthService] ⚠️ Timeout ao salvar empresa no Supabase (não bloqueante)');
          },
        );
        debugPrint('>>> [AuthService] ✓ Empresa salva no Supabase');
      } catch (e) {
        debugPrint('>>> [AuthService] ⚠️ Erro ao salvar empresa no Supabase: $e (não bloqueante)');
        // Não bloquear se o Supabase falhar
      }
    });
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

  Future<void> _salvarUsuarios() async {
    try {
      // Salvar no localStorage (Usando salvarLista para suporte nativo a SQLite)
      await _storage.salvarLista('usuarios', _usuarios);
      
      // Salvar no Supabase
      for (final usuario in _usuarios) {
        try {
          await _supabaseService.upsert(SupabaseService.tableUsuarios, usuario.toMap());
        } catch (e) {
          debugPrint('Erro ao salvar usuário ${usuario.id} no Supabase: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar usuários: $e');
    }
  }

  Future<void> _salvarEmpresas() async {
    try {
      // Salvar no localStorage (sempre fazer primeiro - crítico - Usando salvarLista para SQLite)
      await _storage.salvarLista('empresas', _empresas);
      debugPrint('>>> [AuthService] ✓ Empresas salvas no localStorage');
      
      // Salvar no Supabase de forma assíncrona (não bloquear)
      Future.microtask(() async {
        for (final empresa in _empresas) {
          try {
            await _supabaseService.upsert(SupabaseService.tableEmpresas, empresa.toMap()).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('>>> [AuthService] ⚠️ Timeout ao salvar empresa ${empresa.id} no Supabase (não bloqueante)');
              },
            );
          } catch (e) {
            // Apenas log, não bloquear
            debugPrint('>>> [AuthService] ⚠️ Erro ao salvar empresa ${empresa.id} no Supabase: $e (não bloqueante)');
          }
        }
        debugPrint('>>> [AuthService] ✓ Processo de salvamento de empresas no Supabase concluído');
      });
      
      debugPrint('>>> [AuthService] ✓ Processo de salvamento de empresas concluído');
    } catch (e) {
      debugPrint('>>> [AuthService] ❌ Erro ao salvar empresas: $e');
      // Re-throw apenas se for erro crítico no localStorage
      // Se for erro do Supabase, não bloquear
      if (e.toString().contains('localStorage') || e.toString().contains('storage')) {
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
        final usuariosMap = await _storage.carregarLista('usuarios').timeout(
          const Duration(seconds: 2),
          onTimeout: () => <Map<String, dynamic>>[],
        );
        if (usuariosMap.isNotEmpty) {
          _usuarios.clear();
          _usuarios.addAll(usuariosMap.map((map) => Usuario.fromMap(map)));
          debugPrint('>>> ${_usuarios.length} usuários carregados do localStorage');
          notifyListeners();
          
          if (SupabaseService.isAvailable) {
            Future.microtask(() async {
              try {
                final usuariosSupabase = await _supabaseService.carregarUsuarios().timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => <Usuario>[],
                );
                if (usuariosSupabase.isNotEmpty) {
                  _usuarios.clear();
                  _usuarios.addAll(usuariosSupabase);
                  await _salvarUsuarios();
                  notifyListeners();
                }
              } catch (_) {}
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuários do localStorage: $e');
      }

      // Se localStorage não tiver dados, tentar Supabase
      if (SupabaseService.isAvailable) {
        try {
          final usuariosSupabase = await _supabaseService.carregarUsuarios().timeout(
            const Duration(seconds: 3),
            onTimeout: () => <Usuario>[],
          );
          if (usuariosSupabase.isNotEmpty) {
            _usuarios.clear();
            _usuarios.addAll(usuariosSupabase);
            await _salvarUsuarios();
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('>>> [AuthService] Erro ao carregar usuários do Supabase: $e');
        }
      }

      debugPrint('>>> Nenhum usuário salvo encontrado, mantendo usuários padrão');
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
      final empresasMap = await _storage.carregarLista('empresas').timeout(
        const Duration(seconds: 2),
        onTimeout: () => <Map<String, dynamic>>[],
      );
      if (empresasMap.isNotEmpty) {
        _empresas.clear();
        _empresas.addAll(empresasMap.map((map) => Empresa.fromMap(map)));
        debugPrint('>>> ${_empresas.length} empresas carregadas do localStorage');
        notifyListeners();
        
        if (SupabaseService.isAvailable) {
          Future.microtask(() async {
            try {
              final empresasSupabase = await _supabaseService.carregarEmpresas().timeout(
                const Duration(seconds: 5),
                onTimeout: () => <Empresa>[],
              );
              if (empresasSupabase.isNotEmpty) {
                _empresas.clear();
                _empresas.addAll(empresasSupabase);
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
        final empresasSupabase = await _supabaseService.carregarEmpresas().timeout(
          const Duration(seconds: 12),
          onTimeout: () => <Empresa>[],
        );
          if (empresasSupabase.isNotEmpty) {
            _empresas.clear();
            _empresas.addAll(empresasSupabase);
            await _salvarEmpresas();
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('>>> [AuthService] Erro ao carregar empresas do Supabase: $e');
        }

      if (!_empresas.any((e) => e.id == '1')) {
        _carregarEmpresasPadrao();
      }
      notifyListeners();
    } finally {
      _isProcessandoEmpresas = false;
    }
  }
}
