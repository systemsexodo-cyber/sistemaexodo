import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import 'local_storage_service.dart';

/// Serviço de autenticação e gerenciamento de usuários
class AuthService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  
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
    // Carrega usuários e empresas padrão primeiro
    _carregarUsuariosPadrao();
    _carregarEmpresasPadrao();
    // Depois carrega dados salvos
    _carregarDadosSalvos();
  }

  /// Carrega dados salvos do localStorage
  Future<void> _carregarDadosSalvos() async {
    try {
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
      senha: 'user', // Em produção, deve ser hash
      tipo: TipoUsuario.administrador,
      createdAt: agora,
      updatedAt: agora,
      ativo: true,
    );
    
    _usuarios.add(usuario);
    debugPrint('>>> Usuário padrão criado: email="${usuario.email}", senha="${usuario.senha}", ativo=${usuario.ativo}');
  }

  /// Carrega empresas padrão (apenas para desenvolvimento)
  void _carregarEmpresasPadrao() {
    if (_empresas.isNotEmpty) return;
    
    final agora = DateTime.now();
    _empresas.addAll([
      Empresa(
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
      ),
    ]);
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
  }

  /// Adiciona uma nova empresa
  Future<void> adicionarEmpresa(Empresa empresa) async {
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
  }

  /// Salva usuários no localStorage
  Future<void> _salvarUsuarios() async {
    try {
      final usuariosMap = _usuarios.map((u) => u.toMap()).toList();
      await _storage.salvar('usuarios', usuariosMap);
    } catch (e) {
      debugPrint('Erro ao salvar usuários: $e');
    }
  }

  /// Salva empresas no localStorage
  Future<void> _salvarEmpresas() async {
    try {
      final empresasMap = _empresas.map((e) => e.toMap()).toList();
      await _storage.salvar('empresas', empresasMap);
    } catch (e) {
      debugPrint('Erro ao salvar empresas: $e');
    }
  }

  /// Carrega usuários do localStorage
  Future<void> carregarUsuarios() async {
    try {
      final usuariosMap = await _storage.carregarLista('usuarios');
      if (usuariosMap.isNotEmpty) {
        _usuarios.clear();
        _usuarios.addAll(
          usuariosMap.map((map) => Usuario.fromMap(map)),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao carregar usuários: $e');
    }
  }

  /// Carrega empresas do localStorage
  Future<void> carregarEmpresas() async {
    try {
      final empresasMap = await _storage.carregarLista('empresas');
      if (empresasMap.isNotEmpty) {
        _empresas.clear();
        _empresas.addAll(
          empresasMap.map((map) => Empresa.fromMap(map)),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao carregar empresas: $e');
    }
  }
}


