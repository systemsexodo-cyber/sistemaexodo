import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import 'local_storage_service.dart';
import 'firebase_service.dart';

/// Serviço de autenticação e gerenciamento de usuários
class AuthService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  final FirebaseService _firebaseService = FirebaseService.instance;
  
  Usuario? _usuarioAtual;
  Empresa? _empresaAtual;
  bool _isLoading = false;
  bool _isCarregandoDados = true; // Estado de carregamento inicial

  Usuario? get usuarioAtual => _usuarioAtual;
  Empresa? get empresaAtual => _empresaAtual;
  bool get isLoading => _isLoading;
  bool get isCarregandoDados => _isCarregandoDados;
  bool get isAuthenticated => _usuarioAtual != null;
  bool get temEmpresaSelecionada => _empresaAtual != null;

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
      
      // Carregar usuário e empresa atual selecionados
      try {
        final usuarioMap = await _storage.carregar('usuario_atual').timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (usuarioMap != null && usuarioMap is Map) {
          _usuarioAtual = Usuario.fromMap(Map<String, dynamic>.from(usuarioMap));
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
          debugPrint('>>> [AuthService] Carregando empresa do localStorage...');
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
    
    // VERIFICAÇÃO CRÍTICA: Se certificado não estiver presente, tentar recarregar do Firebase
    final temCertificado = (empresa.configuracoes?['certificadoDigitalBytes'] != null && 
                            (empresa.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty) ||
                           (empresa.certificadoDigitalUrl != null && empresa.certificadoDigitalUrl!.isNotEmpty) ||
                           (empresa.configuracoes?['certificadoWindowsThumbprint'] != null);
    
    if (!temCertificado) {
      debugPrint('>>> [AuthService] ⚠️ Certificado não encontrado na empresa local!');
      debugPrint('>>> [AuthService] Tentando recarregar do Firebase...');
      
      try {
        final empresasFirebase = await _firebaseService.carregarEmpresas();
        final empresaFirebase = empresasFirebase.firstWhere(
          (e) => e.id == empresa.id,
          orElse: () => empresa,
        );
        
        final temCertificadoFirebase = (empresaFirebase.configuracoes?['certificadoDigitalBytes'] != null && 
                                        (empresaFirebase.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty) ||
                                       (empresaFirebase.certificadoDigitalUrl != null && empresaFirebase.certificadoDigitalUrl!.isNotEmpty) ||
                                       (empresaFirebase.configuracoes?['certificadoWindowsThumbprint'] != null);
        
        if (temCertificadoFirebase) {
          debugPrint('>>> [AuthService] ✓✓✓ Certificado encontrado no Firebase!');
          debugPrint('>>> [AuthService] Usando empresa do Firebase com certificado...');
          _empresaAtual = empresaFirebase;
          
          // Atualizar na lista local também
          final index = _empresas.indexWhere((e) => e.id == empresa.id);
          if (index != -1) {
            _empresas[index] = empresaFirebase;
          }
          
          final empresaMap = empresaFirebase.toMap();
          await _storage.salvar('empresa_atual', empresaMap);
          debugPrint('>>> [AuthService] ✓ Empresa com certificado salva no localStorage');
          notifyListeners();
          return;
        } else {
          debugPrint('>>> [AuthService] ⚠️ Certificado também não encontrado no Firebase');
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao recarregar do Firebase: $e');
      }
    }
    
    _empresaAtual = empresa;
    final empresaMap = empresa.toMap();
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
    
    // TERCEIRO: Tentar Firebase (se disponível)
    try {
      debugPrint('>>> [AuthService] Tentando recarregar do Firebase...');
      final empresasFirebase = await _firebaseService.carregarEmpresas();
      final empresaFirebase = empresasFirebase
          .where((e) => e.id == empresaId)
          .firstOrNull ?? empresa;
      
      debugPrint('>>> [AuthService] Empresa encontrada no Firebase');
      debugPrint('>>> [AuthService] certificadoDigitalBytes Firebase: ${empresaFirebase.configuracoes?['certificadoDigitalBytes'] != null ? "presente (${(empresaFirebase.configuracoes!['certificadoDigitalBytes'] as String).length} chars)" : "NULL"}');
      
      // Se Firebase tem certificado e local não tem, usar Firebase
      final temCertificadoFirebase = (empresaFirebase.configuracoes?['certificadoDigitalBytes'] != null && 
                                      (empresaFirebase.configuracoes!['certificadoDigitalBytes'] as String).isNotEmpty);
      final temCertificadoLocal = (empresa.configuracoes?['certificadoDigitalBytes'] != null && 
                                   (empresa.configuracoes?['certificadoDigitalBytes'] as String).isNotEmpty);
      
      if (temCertificadoFirebase && !temCertificadoLocal) {
        debugPrint('>>> [AuthService] ✓✓✓ Certificado encontrado no Firebase! Usando...');
        empresa = empresaFirebase;
        
        // Atualizar na lista local
        final index = _empresas.indexWhere((e) => e.id == empresaId);
        if (index != -1) {
          _empresas[index] = empresa;
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao recarregar do Firebase: $e');
      debugPrint('>>> [AuthService] Continuando com empresa local/localStorage...');
    }
    
    await selecionarEmpresa(empresa);
  }

  /// Adiciona um novo usuário
  Future<void> adicionarUsuario(Usuario usuario) async {
    _usuarios.add(usuario);
    notifyListeners();
    await _salvarUsuarios();
  }

  /// Atualiza um usuário
  Future<void> atualizarUsuario(Usuario usuario) async {
    final index = _usuarios.indexWhere((u) => u.id == usuario.id);
    if (index != -1) {
      _usuarios[index] = usuario.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _salvarUsuarios();
    }
  }

  /// Remove um usuário
  Future<void> removerUsuario(String usuarioId) async {
    _usuarios.removeWhere((u) => u.id == usuarioId);
    notifyListeners();
    await _salvarUsuarios();
    // Remover do Firebase também
    try {
      await _firebaseService.removerUsuario(usuarioId);
    } catch (e) {
      debugPrint('Erro ao remover usuário do Firebase: $e');
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
    final slugLower = slug.toLowerCase().trim();
    
    debugPrint('>>> [AuthService] Buscando empresa para slug: "$slugLower" entre ${_empresas.length} empresas');
    
    // Primeiro tentar correspondência exata de slug ou ID (case-insensitive para ambos)
    try {
      final encontrada = _empresas.firstWhere(
        (e) => (e.slug.toLowerCase() == slugLower || e.id.toLowerCase() == slugLower) && e.ativo,
      );
      debugPrint('>>> [AuthService] ✅ Empresa encontrada por slug EXATO: ${encontrada.nomeExibicao} (ID: ${encontrada.id})');
      return encontrada;
    }
    catch (_) {
      // Se não achar pelo slug, tentar gerar slug do nome para comparação
      try {
        final encontrada = _empresas.firstWhere(
          (e) => Empresa.gerarSlug(e.nomeExibicao) == slugLower && e.ativo,
        );
        debugPrint('>>> [AuthService] ✅ Empresa encontrada por slug GERADO: ${encontrada.nomeExibicao} (ID: ${encontrada.id})');
        return encontrada;
      } catch (_) {
        debugPrint('>>> [AuthService] ❌ Nenhuma empresa encontrada locamente para: "$slugLower"');
        return null;
      }
    }
  }

  /// Busca uma empresa pelo slug, tentando Firebase se não encontrar localmente
  Future<Empresa?> buscarEmpresaPorSlugAsync(String slug) async {
    // 1. Tentar local
    final local = obterEmpresaPorSlug(slug);
    if (local != null) return local;

    // 2. Tentar Firebase
    debugPrint('>>> [AuthService] 🔍 Empresa não em memória, buscando no Firebase: $slug');
    final remota = await _firebaseService.buscarEmpresaPorSlug(slug);
    if (remota != null) {
      if (!_empresas.any((e) => e.id == remota.id)) {
        _empresas.add(remota);
        notifyListeners();
      }
      return remota;
    }

    return null;
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
    
    // Salvar no Firebase de forma não bloqueante
    Future.microtask(() async {
      try {
        await _firebaseService.salvarEmpresa(empresaAtualizada).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('>>> [AuthService] ⚠️ Timeout ao salvar empresa no Firebase (não bloqueante)');
          },
        );
        debugPrint('>>> [AuthService] ✓ Empresa salva no Firebase');
      } catch (e) {
        debugPrint('>>> [AuthService] ⚠️ Erro ao salvar empresa no Firebase: $e (não bloqueante)');
        // Não bloquear se o Firebase falhar
      }
    });
  }

  /// Remove uma empresa
  Future<void> removerEmpresa(String empresaId) async {
    _empresas.removeWhere((e) => e.id == empresaId);
    notifyListeners();
    await _salvarEmpresas();
    // Remover do Firebase também
    try {
      await _firebaseService.removerEmpresa(empresaId);
    } catch (e) {
      debugPrint('Erro ao remover empresa do Firebase: $e');
    }
  }

  /// Salva usuários no localStorage e Firebase
  Future<void> _salvarUsuarios() async {
    try {
      // Salvar no localStorage
      final usuariosMap = _usuarios.map((u) => u.toMap()).toList();
      await _storage.salvar('usuarios', usuariosMap);
      
      // Salvar no Firebase
      for (final usuario in _usuarios) {
        try {
          await _firebaseService.salvarUsuario(usuario);
        } catch (e) {
          debugPrint('Erro ao salvar usuário ${usuario.id} no Firebase: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar usuários: $e');
    }
  }

  /// Salva empresas no localStorage e Firebase
  Future<void> _salvarEmpresas() async {
    try {
      // Salvar no localStorage (sempre fazer primeiro - crítico)
      final empresasMap = _empresas.map((e) => e.toMap()).toList();
      await _storage.salvar('empresas', empresasMap);
      debugPrint('>>> [AuthService] ✓ Empresas salvas no localStorage');
      
      // Salvar no Firebase de forma assíncrona (não bloquear)
      // Executar em background para não impactar o carregamento
      Future.microtask(() async {
        for (final empresa in _empresas) {
          try {
            // Timeout reduzido para 5 segundos e não bloquear
            await _firebaseService.salvarEmpresa(empresa).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                // Apenas log, não propagar erro
                debugPrint('>>> [AuthService] ⚠️ Timeout ao salvar empresa ${empresa.id} no Firebase (não bloqueante)');
              },
            );
          } catch (e) {
            // Apenas log, não bloquear
            debugPrint('>>> [AuthService] ⚠️ Erro ao salvar empresa ${empresa.id} no Firebase: $e (não bloqueante)');
          }
        }
        debugPrint('>>> [AuthService] ✓ Processo de salvamento de empresas no Firebase concluído');
      });
      
      debugPrint('>>> [AuthService] ✓ Processo de salvamento de empresas concluído');
    } catch (e) {
      debugPrint('>>> [AuthService] ❌ Erro ao salvar empresas: $e');
      // Re-throw apenas se for erro crítico no localStorage
      // Se for erro do Firebase, não bloquear
      if (e.toString().contains('localStorage') || e.toString().contains('storage')) {
        rethrow;
      }
    }
  }

  
  /// Carrega usuários do localStorage e Firebase
  Future<void> carregarUsuarios() async {
    try {
      // Carregar do localStorage primeiro (rápido e confiável)
      try {
        final usuariosMap = await _storage.carregarLista('usuarios').timeout(
          const Duration(seconds: 2),
          onTimeout: () => <Map<String, dynamic>>[],
        );
        if (usuariosMap.isNotEmpty) {
          // Limpar usuários padrão e carregar os salvos
          _usuarios.clear();
          _usuarios.addAll(
            usuariosMap.map((map) => Usuario.fromMap(map)),
          );
          debugPrint('>>> ${_usuarios.length} usuários carregados do localStorage');
          notifyListeners();
          
          // Tentar sincronizar com Firebase em background (não bloqueante)
          Future.microtask(() async {
            try {
              final usuariosFirebase = await _firebaseService.carregarUsuarios().timeout(
                const Duration(seconds: 3),
                onTimeout: () {
                  debugPrint('>>> [AuthService] Timeout ao carregar usuários do Firebase (não bloqueante)');
                  return <Usuario>[];
                },
              );
              if (usuariosFirebase.isNotEmpty) {
                _usuarios.clear();
                _usuarios.addAll(usuariosFirebase);
                await _salvarUsuarios();
                notifyListeners();
                debugPrint('>>> ${_usuarios.length} usuários atualizados do Firebase');
              }
            } catch (e) {
              debugPrint('>>> [AuthService] Erro ao sincronizar usuários com Firebase: $e (não bloqueante)');
            }
          });
          
          return;
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuários do localStorage: $e');
      }

      // Se localStorage não tiver dados, tentar Firebase com timeout curto
      try {
        final usuariosFirebase = await _firebaseService.carregarUsuarios().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('>>> [AuthService] Timeout ao carregar usuários do Firebase - usando padrão');
            return <Usuario>[];
          },
        );
        if (usuariosFirebase.isNotEmpty) {
          _usuarios.clear();
          _usuarios.addAll(usuariosFirebase);
          debugPrint('>>> ${_usuarios.length} usuários carregados do Firebase');
          // Sincronizar com localStorage
          await _salvarUsuarios();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar usuários do Firebase: $e');
      }

      // Se não houver usuários salvos, manter apenas os padrão
      debugPrint('>>> Nenhum usuário salvo encontrado, mantendo usuários padrão');
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao carregar usuários: $e');
    }
  }

  /// Carrega empresas do localStorage e Firebase
  Future<void> carregarEmpresas() async {
    try {
      // Carregar do localStorage primeiro (rápido e confiável)
      final empresasMap = await _storage.carregarLista('empresas').timeout(
        const Duration(seconds: 2),
        onTimeout: () => <Map<String, dynamic>>[],
      );
      if (empresasMap.isNotEmpty) {
        // Limpar todas as empresas (incluindo padrão) e carregar as salvas
        _empresas.clear();
        _empresas.addAll(
          empresasMap.map((map) => Empresa.fromMap(map)),
        );
        debugPrint('>>> ${_empresas.length} empresas carregadas do localStorage');
        notifyListeners();
        
        // Tentar sincronizar com Firebase em background (não bloqueante)
        Future.microtask(() async {
          try {
            final empresasFirebase = await _firebaseService.carregarEmpresas().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('>>> [AuthService] Timeout ao carregar empresas do Firebase (não bloqueante)');
                return <Empresa>[];
              },
            );
            if (empresasFirebase.isNotEmpty) {
              // Atualizar com dados do Firebase se houver
              _empresas.clear();
              _empresas.addAll(empresasFirebase);
              await _salvarEmpresas();
              notifyListeners();
              debugPrint('>>> ${_empresas.length} empresas atualizadas do Firebase');
            }
          } catch (e) {
            debugPrint('>>> [AuthService] Erro ao carregar empresas do Firebase: $e (não bloqueante)');
          }
        });
        
        return;
      }
      
      // Se não há empresas no localStorage, tentar Firebase com timeout maior para evitar erro no primeiro acesso
      try {
        final empresasFirebase = await _firebaseService.carregarEmpresas().timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            debugPrint('>>> [AuthService] Timeout ao carregar empresas do Firebase - usando padrão');
            return <Empresa>[];
          },
        );
        if (empresasFirebase.isNotEmpty) {
          _empresas.clear();
          _empresas.addAll(empresasFirebase);
          debugPrint('>>> ${_empresas.length} empresas carregadas do Firebase');
          // Sincronizar com localStorage
          await _salvarEmpresas();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('>>> [AuthService] Erro ao carregar empresas do Firebase: $e');
      }

      // Se não houver empresas salvas, garantir que a empresa padrão existe
      if (!_empresas.any((e) => e.id == '1')) {
        _carregarEmpresasPadrao();
      }
      debugPrint('>>> Nenhuma empresa salva encontrada, mantendo empresas padrão');
      notifyListeners();
    } catch (e) {
      debugPrint('>>> [AuthService] Erro ao carregar empresas: $e');
      // Em caso de erro, garantir que a empresa padrão existe
      if (_empresas.isEmpty) {
        _carregarEmpresasPadrao();
      }
      notifyListeners();
    }
  }
}


