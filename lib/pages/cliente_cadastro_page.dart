import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/cliente_auth_service.dart';
import 'cliente_login_page.dart';

/// Página de cadastro para clientes do e-commerce
class ClienteCadastroPage extends StatefulWidget {
  const ClienteCadastroPage({super.key});

  @override
  State<ClienteCadastroPage> createState() => _ClienteCadastroPageState();
}

class _ClienteCadastroPageState extends State<ClienteCadastroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cpfController = TextEditingController();
  final _cepController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _verificandoCpf = false;
  bool _verificandoTelefone = false;
  bool _verificandoEmail = false;
  String? _erroCpf;
  String? _erroTelefone;
  String? _erroEmail;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    _telefoneController.dispose();
    _cpfController.dispose();
    _cepController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    super.dispose();
  }

  Future<void> _buscarCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cep.length != 8) return;

    setState(() => _isLoading = true);
    try {
      // Usar ViaCEP para buscar endereço
      final response = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data.containsKey('erro')) {
          throw Exception('CEP não encontrado');
        }

        // Preencher campos automaticamente
        setState(() {
          _enderecoController.text = data['logradouro'] ?? '';
          _bairroController.text = data['bairro'] ?? '';
          _cidadeController.text = data['localidade'] ?? '';
          _estadoController.text = data['uf'] ?? '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CEP encontrado! Campos preenchidos automaticamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Erro ao buscar CEP');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao buscar CEP: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
      
      await clienteAuthService.cadastrar(
        nome: _nomeController.text.trim(),
        email: _emailController.text.trim(),
        senha: _senhaController.text.trim(),
        telefone: _telefoneController.text.trim(),
        cpf: _cpfController.text.trim().isNotEmpty ? _cpfController.text.trim() : null,
        endereco: _enderecoController.text.trim(),
        numero: _numeroController.text.trim(),
        complemento: _complementoController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        estado: _estadoController.text.trim(),
        cep: _cepController.text.trim(),
        context: context, // Passar contexto para usar Provider
      );

      if (!mounted) return;

      // Retornar true para indicar que o cadastro foi bem-sucedido
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verificarCpfUnico(String? value) async {
    if (value == null || value.isEmpty) {
      setState(() {
        _erroCpf = null;
        _verificandoCpf = false;
      });
      return;
    }
    
    final cpfLimpo = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cpfLimpo.length != 11) {
      setState(() {
        _erroCpf = 'CPF deve ter 11 dígitos';
        _verificandoCpf = false;
      });
      return;
    }

    setState(() => _verificandoCpf = true);
    try {
      final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
      final existe = await clienteAuthService.verificarCpfExistente(value, context);
      setState(() {
        _verificandoCpf = false;
        _erroCpf = existe ? 'Este CPF já está cadastrado' : null;
      });
    } catch (e) {
      setState(() {
        _verificandoCpf = false;
        _erroCpf = 'Erro ao verificar CPF';
      });
    }
  }

  Future<void> _verificarTelefoneUnico(String? value) async {
    if (value == null || value.isEmpty) {
      setState(() {
        _erroTelefone = 'Por favor, informe seu telefone';
        _verificandoTelefone = false;
      });
      return;
    }

    setState(() => _verificandoTelefone = true);
    try {
      final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
      final existe = await clienteAuthService.verificarTelefoneExistente(value, context);
      setState(() {
        _verificandoTelefone = false;
        _erroTelefone = existe ? 'Este telefone já está cadastrado' : null;
      });
    } catch (e) {
      setState(() {
        _verificandoTelefone = false;
        _erroTelefone = 'Erro ao verificar telefone';
      });
    }
  }

  Future<void> _verificarEmailUnico(String? value) async {
    if (value == null || value.isEmpty) {
      setState(() {
        _erroEmail = 'Por favor, informe seu email';
        _verificandoEmail = false;
      });
      return;
    }
    if (!value.contains('@')) {
      setState(() {
        _erroEmail = 'Email inválido';
        _verificandoEmail = false;
      });
      return;
    }

    setState(() => _verificandoEmail = true);
    try {
      final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
      final existe = await clienteAuthService.verificarEmailExistente(value, context);
      setState(() {
        _verificandoEmail = false;
        _erroEmail = existe ? 'Este email já está cadastrado' : null;
      });
    } catch (e) {
      setState(() {
        _verificandoEmail = false;
        _erroEmail = 'Erro ao verificar email';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Conta'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Crie sua conta',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Preencha os dados abaixo',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Dados pessoais
                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe seu nome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: const Icon(Icons.email),
                    suffixIcon: _verificandoEmail
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    errorText: _erroEmail,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe seu email';
                    }
                    if (!value.contains('@')) {
                      return 'Email inválido';
                    }
                    return _erroEmail;
                  },
                  onChanged: (value) {
                    if (_erroEmail != null) {
                      setState(() => _erroEmail = null);
                    }
                    if (value.isNotEmpty && value.contains('@')) {
                      _verificarEmailUnico(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _telefoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Telefone *',
                    prefixIcon: const Icon(Icons.phone),
                    suffixIcon: _verificandoTelefone
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    hintText: '(00) 00000-0000',
                    errorText: _erroTelefone,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe seu telefone';
                    }
                    return _erroTelefone;
                  },
                  onChanged: (value) {
                    if (_erroTelefone != null) {
                      setState(() => _erroTelefone = null);
                    }
                    if (value.length >= 10) {
                      _verificarTelefoneUnico(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cpfController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: InputDecoration(
                    labelText: 'CPF (opcional)',
                    prefixIcon: const Icon(Icons.badge),
                    suffixIcon: _verificandoCpf
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    hintText: '000.000.000-00',
                    errorText: _erroCpf,
                  ),
                  validator: (value) => _erroCpf,
                  onChanged: (value) {
                    if (_erroCpf != null) {
                      setState(() => _erroCpf = null);
                    }
                    if (value.length == 11) {
                      _verificarCpfUnico(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Senha *',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, informe sua senha';
                    }
                    if (value.length < 6) {
                      return 'Senha deve ter pelo menos 6 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmarSenhaController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirmar senha *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, confirme sua senha';
                    }
                    if (value != _senhaController.text) {
                      return 'As senhas não coincidem';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Endereço (opcional)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cepController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'CEP',
                          prefixIcon: Icon(Icons.location_on),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          if (value.length == 8) {
                            _buscarCep();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _enderecoController,
                        decoration: const InputDecoration(
                          labelText: 'Endereço',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _numeroController,
                        decoration: const InputDecoration(
                          labelText: 'Número',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _complementoController,
                        decoration: const InputDecoration(
                          labelText: 'Complemento',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bairroController,
                  decoration: const InputDecoration(
                    labelText: 'Bairro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Cidade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _estadoController,
                        decoration: const InputDecoration(
                          labelText: 'UF',
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 2,
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _cadastrar,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Criar Conta',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Já tem uma conta? '),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ClienteLoginPage(),
                          ),
                        );
                      },
                      child: const Text('Entrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

