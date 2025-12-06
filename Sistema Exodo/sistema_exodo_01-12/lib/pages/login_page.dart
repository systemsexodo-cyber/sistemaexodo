import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/exodo_logo.dart';
import '../theme.dart';
import 'home_page.dart';
import 'selecionar_empresa_page.dart';

/// Página de login do sistema
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _fazerLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final authService = Provider.of<AuthService>(context, listen: false);
    final sucesso = await authService.login(
      _emailController.text.trim(),
      _senhaController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (sucesso) {
      // Sempre mostra seleção de empresa após login bem-sucedido
      // Se houver empresas disponíveis para o usuário, mostra a tela de seleção
      final empresasDoUsuario = authService.getEmpresasDoUsuario();
      if (empresasDoUsuario.isNotEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const SelecionarEmpresaPage(),
          ),
        );
      } else {
        // Se não tem empresas cadastradas, vai direto para home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const HomePage(),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuário ou senha inválidos'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 420,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      // Logo com efeito brilhante
                      _buildLogoBrilhante(),
                      const SizedBox(height: 50),
                      // Campo de usuário
                      TextFormField(
                        controller: _emailController,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Usuário',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Digite seu usuário',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.person, color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Colors.blueAccent,
                              width: 2.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Por favor, insira seu usuário';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      // Campo de senha
                      TextFormField(
                        controller: _senhaController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _fazerLogin(),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Digite sua senha',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Colors.blueAccent,
                              width: 2.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Por favor, insira sua senha';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 36),
                      // Botão de login
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              Colors.blueAccent,
                              Colors.blue.shade600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 0,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : _fazerLogin,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              alignment: Alignment.center,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Entrar',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoBrilhante() {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Efeito de brilho pulsante
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 3),
            curve: Curves.easeInOut,
            onEnd: () {
              if (mounted) {
                setState(() {});
              }
            },
            builder: (context, value, child) {
              return Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.orange.withOpacity(0.4 * (0.5 + 0.5 * value)),
                      Colors.orange.withOpacity(0.1 * (0.5 + 0.5 * value)),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),
          // Brilho externo
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.6),
                  blurRadius: 50,
                  spreadRadius: 10,
                ),
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 80,
                  spreadRadius: 20,
                ),
              ],
            ),
          ),
          // Logo
          const ExodoLogo(
            fontSize: 72,
            showSubtitle: true,
          ),
        ],
      ),
    );
  }
}
