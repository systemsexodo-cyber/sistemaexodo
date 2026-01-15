import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import 'local_storage_service.dart';
import 'firebase_service.dart';
import 'data_service.dart';

/// Serviço de autenticação para clientes do e-commerce
class ClienteAuthService extends ChangeNotifier {
  final LocalStorageService _storage = LocalStorageService();
  
  Cliente? _clienteAtual;
  bool _isLoading = false;
  bool _isCarregandoDados = true;

  Cliente? get clienteAtual => _clienteAtual;
  bool get isLoading => _isLoading;
  bool get isCarregandoDados => _isCarregandoDados;
  bool get isAuthenticated => _clienteAtual != null;

  ClienteAuthService() {
    _isCarregandoDados = true;
    notifyListeners();
    _carregarClienteSalvo().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _isCarregandoDados = false;
        notifyListeners();
        debugPrint('>>> [ClienteAuthService] Carregamento concluído');
      });
    }).catchError((e) {
      debugPrint('>>> [ClienteAuthService] Erro ao carregar: $e');
      _isCarregandoDados = false;
      notifyListeners();
    });
  }

  /// Carrega cliente salvo do localStorage
  Future<void> _carregarClienteSalvo() async {
    try {
      final clienteMap = await _storage.carregar('cliente_ecommerce_atual');
      if (clienteMap != null && clienteMap is Map) {
        _clienteAtual = Cliente.fromMap(Map<String, dynamic>.from(clienteMap));
        debugPrint('>>> [ClienteAuthService] Cliente carregado: ${_clienteAtual?.nome}');
      }
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao carregar cliente: $e');
    }
  }

  /// Obtém o DataService (singleton ou via Provider se disponível)
  DataService _obterDataService([BuildContext? context]) {
    // Se tiver contexto, tentar usar Provider
    if (context != null) {
      try {
        return Provider.of<DataService>(context, listen: false);
      } catch (e) {
        debugPrint('>>> [ClienteAuthService] Erro ao obter DataService via Provider: $e');
      }
    }
    // Fallback: criar nova instância (não ideal, mas funciona)
    return DataService();
  }

  /// Verifica se CPF já está cadastrado
  Future<bool> verificarCpfExistente(String cpf, [BuildContext? context]) async {
    try {
      final dataService = _obterDataService(context);
      final clientes = dataService.clientes;
      
      // Remove caracteres não numéricos do CPF
      final cpfLimpo = cpf.replaceAll(RegExp(r'[^\d]'), '');
      
      // Verifica se já existe cliente com este CPF
      final existe = clientes.any((c) {
        final cpfCliente = c.cpfCnpj?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
        return cpfCliente == cpfLimpo;
      });
      
      return existe;
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao verificar CPF: $e');
      return false;
    }
  }

  /// Verifica se telefone já está cadastrado
  Future<bool> verificarTelefoneExistente(String telefone, [BuildContext? context]) async {
    try {
      final dataService = _obterDataService(context);
      final clientes = dataService.clientes;
      
      // Remove caracteres não numéricos do telefone
      final telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');
      
      // Verifica se já existe cliente com este telefone
      final existe = clientes.any((c) {
        final telCliente = c.telefone.replaceAll(RegExp(r'[^\d]'), '');
        return telCliente == telefoneLimpo;
      });
      
      return existe;
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao verificar telefone: $e');
      return false;
    }
  }

  /// Verifica se email já está cadastrado
  Future<bool> verificarEmailExistente(String email, [BuildContext? context]) async {
    try {
      final dataService = _obterDataService(context);
      final clientes = dataService.clientes;
      
      final emailLower = email.toLowerCase().trim();
      
      // Verifica se já existe cliente com este email
      final existe = clientes.any((c) {
        final emailCliente = c.email?.toLowerCase().trim() ?? '';
        return emailCliente == emailLower;
      });
      
      return existe;
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao verificar email: $e');
      return false;
    }
  }

  /// Cadastra um novo cliente
  Future<bool> cadastrar({
    required String nome,
    required String email,
    required String senha,
    required String telefone,
    String? cpf,
    String? endereco,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? cep,
    BuildContext? context,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Verificar se email já existe
      if (await verificarEmailExistente(email, context)) {
        throw Exception('Este email já está cadastrado');
      }

      // Verificar se telefone já existe
      if (await verificarTelefoneExistente(telefone, context)) {
        throw Exception('Este telefone já está cadastrado');
      }

      // Verificar se CPF já existe (se fornecido)
      if (cpf != null && cpf.isNotEmpty) {
        if (await verificarCpfExistente(cpf, context)) {
          throw Exception('Este CPF já está cadastrado');
        }
      }

      final dataService = _obterDataService(context);
      
      // Criar novo cliente
      final novoCliente = Cliente(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nome: nome,
        email: email,
        telefone: telefone,
        cpfCnpj: cpf,
        endereco: endereco,
        numero: numero,
        complemento: complemento,
        bairro: bairro,
        cidade: cidade,
        estado: estado,
        cep: cep,
        senha: senha, // Armazenar senha (em produção, usar hash)
        emailLogin: email, // Email usado para login
        ativo: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Adicionar cliente
      await dataService.addCliente(novoCliente);

      // Fazer login automático após cadastro
      final loginSucesso = await login(email, senha, context: context);
      if (!loginSucesso) {
        throw Exception('Erro ao fazer login após cadastro');
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('>>> [ClienteAuthService] Erro ao cadastrar: $e');
      rethrow;
    }
  }

  /// Realiza login do cliente
  Future<bool> login(String email, String senha, {BuildContext? context}) async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final dataService = _obterDataService(context);
      final clientes = dataService.clientes;

      final emailLower = email.toLowerCase().trim();
      final senhaTrim = senha.trim();

      // Buscar cliente pelo email ou emailLogin
      Cliente? clienteEncontrado;
      for (final c in clientes) {
        if (!c.ativo) continue;
        
        final emailCliente = c.email?.toLowerCase().trim() ?? '';
        final emailLoginCliente = c.emailLogin?.toLowerCase().trim() ?? '';
        
        if ((emailCliente == emailLower || emailLoginCliente == emailLower)) {
          clienteEncontrado = c;
          break;
        }
      }
      
      if (clienteEncontrado == null) {
        throw Exception('Email ou senha inválidos');
      }

      // Verificar senha
      // O modelo Cliente já tem campo senha e emailLogin
      final emailLoginCliente = clienteEncontrado.emailLogin?.toLowerCase().trim() ?? clienteEncontrado.email?.toLowerCase().trim() ?? '';
      final senhaCliente = clienteEncontrado.senha ?? '';
      
      if (emailLoginCliente != emailLower || senhaCliente != senhaTrim) {
        throw Exception('Email ou senha inválidos');
      }

      _clienteAtual = clienteEncontrado.copyWith(
        updatedAt: DateTime.now(),
      );

      // Salvar no localStorage
      await _storage.salvar('cliente_ecommerce_atual', _clienteAtual!.toMap());

      // Tentar salvar no Firebase (não bloqueante)
      _salvarClienteNoFirebase(_clienteAtual!).catchError((e) {
        debugPrint('>>> [ClienteAuthService] Erro ao salvar no Firebase: $e');
      });

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('>>> [ClienteAuthService] Erro ao fazer login: $e');
      rethrow;
    }
  }

  /// Salva cliente no Firebase (não bloqueante)
  Future<void> _salvarClienteNoFirebase(Cliente cliente) async {
    try {
      if (!FirebaseService.isAvailable) return;

      // Salvar cliente via FirebaseService
      await FirebaseService.instance.salvarCliente('ecommerce', cliente);
      
      debugPrint('>>> [ClienteAuthService] Cliente salvo no Firebase');
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao salvar no Firebase: $e');
    }
  }

  /// Realiza logout do cliente
  Future<void> logout() async {
    _clienteAtual = null;
    await _storage.remover('cliente_ecommerce_atual');
    notifyListeners();
    debugPrint('>>> [ClienteAuthService] Cliente deslogado');
  }

  /// Atualiza dados do cliente logado
  Future<void> atualizarCliente(Cliente clienteAtualizado, {BuildContext? context}) async {
    try {
      final dataService = _obterDataService(context);
      dataService.updateCliente(clienteAtualizado);

      _clienteAtual = clienteAtualizado;
      await _storage.salvar('cliente_ecommerce_atual', clienteAtualizado.toMap());

      // Tentar salvar no Firebase
      _salvarClienteNoFirebase(clienteAtualizado).catchError((e) {
        debugPrint('>>> [ClienteAuthService] Erro ao atualizar no Firebase: $e');
      });

      notifyListeners();
    } catch (e) {
      debugPrint('>>> [ClienteAuthService] Erro ao atualizar cliente: $e');
      rethrow;
    }
  }
}

