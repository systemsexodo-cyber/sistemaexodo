import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import 'local_storage_service.dart';
import 'firebase_service.dart';

/// Serviço de autenticação e gerenciamento de usuários
class AuthService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  final FirebaseService _firebaseService = FirebaseService();
  
  Usuario? _usuarioAtual;
  Empresa? _empresaAtual;
  bool _isLoading = false;

  Usuario? get usuarioAtual => _usuarioAtual;
  Empresa? get empresaAtual => _empresaAtual;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _usuarioAtual != null;
  bool get temEmpresaSelecionada => _empresaAtual != null;

  // Lista de usuários (em produção, viria de um backend)
  final List<Usuario> _usuarios = [];
  final List<Empresa> _empresas = [];

  List<Usuario> get usuarios => List.unmodifiable(_usuarios);
  List<Empresa> get empresas => List.unmodifiable(_empresas);

  AuthService() {
    // Carrega dados salvos primeiro (isso carregará empresas e usuários salvos)
    // As empresas/usuários padrão só serão adicionados se não houver dados salvos
    _carregarDadosSalvos();
  }

  /// Carrega dados salvos do localStorage
  Future<void> _carregarDadosSalvos() async {
    try {
      // Primeiro, carregar usuários padrão (se necessário)
      _carregarUsuariosPadrao();
      
      // Depois, carregar usuários salvos (substituem os padrão se existirem)
      await carregarUsuarios();
      
      // Atualizar senha do usuário "user" se ainda tiver a senha antiga
      await _atualizarSenhaUsuarioUser();
      
      // Primeiro, carregar empresas padrão (se necessário)
      _carregarEmpresasPadrao();
      
      // Depois, carregar empresas salvas (substituem as padrão se existirem)
      await carregarEmpresas();
      
      // Carregar usuário e empresa atual selecionados
      final usuarioMap = await _storage.carregar('usuario_atual');
      final empresaMap = await _storage.carregar('empresa_atual');
      
      if (usuarioMap != null && usuarioMap is Map) {
        _usuarioAtual = Usuario.fromMap(Map<String, dynamic>.from(usuarioMap));
      }
      
      if (empresaMap != null && empresaMap is Map) {
        _empresaAtual = Empresa.fromMap(Map<String, dynamic>.from(empresaMap));
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar dados salvos: $e');
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
    _empresaAtual = empresa;
    await _storage.salvar('empresa_atual', empresa.toMap());
    notifyListeners();
  }

  /// Seleciona uma empresa por ID
  Future<void> selecionarEmpresaPorId(String empresaId) async {
    final empresa = _empresas.firstWhere(
      (e) => e.id == empresaId && e.ativo,
      orElse: () => throw Exception('Empresa não encontrada'),
    );
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
    final index = _empresas.indexWhere((e) => e.id == empresa.id);
    if (index != -1) {
      _empresas[index] = empresa.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _salvarEmpresas();
    }
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
      // Salvar no localStorage
      final empresasMap = _empresas.map((e) => e.toMap()).toList();
      await _storage.salvar('empresas', empresasMap);
      
      // Salvar no Firebase
      for (final empresa in _empresas) {
        try {
          await _firebaseService.salvarEmpresa(empresa);
        } catch (e) {
          debugPrint('Erro ao salvar empresa ${empresa.id} no Firebase: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar empresas: $e');
    }
  }

  
  /// Carrega usuários do localStorage e Firebase
  Future<void> carregarUsuarios() async {
    try {
      // Primeiro, tentar carregar do Firebase
      try {
        final usuariosFirebase = await _firebaseService.carregarUsuarios();
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
        debugPrint('>>> Erro ao carregar usuários do Firebase: $e');
      }

      // Se Firebase não tiver dados, carregar do localStorage
      final usuariosMap = await _storage.carregarLista('usuarios');
      if (usuariosMap.isNotEmpty) {
        // Limpar usuários padrão e carregar os salvos
        _usuarios.clear();
        _usuarios.addAll(
          usuariosMap.map((map) => Usuario.fromMap(map)),
        );
        debugPrint('>>> ${_usuarios.length} usuários carregados do localStorage');
        // Sincronizar com Firebase
        for (final usuario in _usuarios) {
          try {
            await _firebaseService.salvarUsuario(usuario);
          } catch (e) {
            debugPrint('>>> Erro ao sincronizar usuário ${usuario.id} com Firebase: $e');
          }
        }
        notifyListeners();
      } else {
        // Se não houver usuários salvos, manter apenas os padrão
        debugPrint('>>> Nenhum usuário salvo encontrado, mantendo usuários padrão');
      }
    } catch (e) {
      debugPrint('Erro ao carregar usuários: $e');
    }
  }

  /// Carrega empresas do localStorage e Firebase
  Future<void> carregarEmpresas() async {
    try {
      // Primeiro, tentar carregar do Firebase
      try {
        final empresasFirebase = await _firebaseService.carregarEmpresas();
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
        debugPrint('>>> Erro ao carregar empresas do Firebase: $e');
      }

      // Se Firebase não tiver dados, carregar do localStorage
      final empresasMap = await _storage.carregarLista('empresas');
      if (empresasMap.isNotEmpty) {
        // Limpar todas as empresas (incluindo padrão) e carregar as salvas
        _empresas.clear();
        _empresas.addAll(
          empresasMap.map((map) => Empresa.fromMap(map)),
        );
        debugPrint('>>> ${_empresas.length} empresas carregadas do localStorage');
        // Sincronizar com Firebase
        for (final empresa in _empresas) {
          try {
            await _firebaseService.salvarEmpresa(empresa);
          } catch (e) {
            debugPrint('>>> Erro ao sincronizar empresa ${empresa.id} com Firebase: $e');
          }
        }
        notifyListeners();
      } else {
        // Se não houver empresas salvas, garantir que a empresa padrão existe
        if (!_empresas.any((e) => e.id == '1')) {
          _carregarEmpresasPadrao();
        }
        debugPrint('>>> Nenhuma empresa salva encontrada, mantendo empresas padrão');
      }
    } catch (e) {
      debugPrint('Erro ao carregar empresas: $e');
      // Em caso de erro, garantir que a empresa padrão existe
      if (_empresas.isEmpty) {
        _carregarEmpresasPadrao();
      }
    }
  }
}


