import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/exodo_logo.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final sucesso = await authService.login(_emailController.text.trim(), _senhaController.text.trim());
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (sucesso) {
      final empresasDoUsuario = authService.getEmpresasDoUsuario();
      if (empresasDoUsuario.isNotEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SelecionarEmpresaPage()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomePage()));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário ou senha inválidos'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // 1. Fundo Gradiente Deep
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
            ),
          ),
          
          // 2. Orbes de Luz Aurora
          _buildOrb(top: -100, left: -50, color: Colors.blueAccent.withOpacity(0.2), size: 400),
          _buildOrb(bottom: -150, right: -100, color: Colors.orangeAccent.withOpacity(0.15), size: 500),

          // 3. Conteúdo
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    _buildLogoPremium(),
                    // CARD DE LOGIN GLASSMORPHISM
                    _buildGlassCard(),
                    
                    const SizedBox(height: 40),
                    
                    // VERSÃO E RODAPÉ DISCRETO
                    Text(
                      'SISTEMA ÊXODO V1.0.8',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedAurora() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A), // Deep Slate
            Color(0xFF1E293B), // Slate 800
            Color(0xFF0F172A),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingOrbs() {
    return Stack(
      children: [
        _buildOrb(top: -100, left: -50, color: Colors.blueAccent.withOpacity(0.2), size: 400),
        _buildOrb(bottom: -150, right: -100, color: Colors.orangeAccent.withOpacity(0.15), size: 500),
        _buildOrb(top: 200, right: -50, color: Colors.indigo.withOpacity(0.1), size: 300),
      ],
    );
  }

  Widget _buildOrb({double? top, double? left, double? right, double? bottom, required Color color, required double size}) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoPremium() {
    return Hero(
      tag: 'logo_exodo',
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 60, spreadRadius: 10),
                  ],
                ),
              ),
              const ExodoLogo(fontSize: 80, showSubtitle: false),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'GESTÃO INTELIGENTE',
            style: TextStyle(
              color: Colors.orange.shade300,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 4
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.1),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Acesso Administrativo',
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // INPUT USUÁRIO
                _buildModernInput(
                  controller: _emailController,
                  label: 'Usuário',
                  icon: Icons.alternate_email_rounded,
                ),

                // HISTÓRICO DE LOGINS
                Consumer<AuthService>(
                  builder: (context, auth, _) {
                    if (auth.historicoLogins.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: auth.historicoLogins.map((login) => ActionChip(
                          label: Text(login, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          backgroundColor: Colors.white.withOpacity(0.05),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          side: BorderSide(color: Colors.white.withOpacity(0.1)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _emailController.text = login;
                            FocusScope.of(context).nextFocus(); // Pula para senha
                          },
                        )).toList(),
                      ),
                    );
                  }
                ),
                
                const SizedBox(height: 20),
                
                // INPUT SENHA
                _buildModernInput(
                  controller: _senhaController,
                  label: 'Senha',
                  icon: Icons.lock_open_rounded,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _fazerLogin(),
                ),
                
                const SizedBox(height: 40),
                
                // BOTÃO ENTRAR
                _buildLoginButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputAction textInputAction = TextInputAction.next,
    Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.blueAccent, size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white24, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
            ),
            errorStyle: const TextStyle(color: Colors.redAccent),
          ),
          validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null,
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _fazerLogin,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading 
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('ACESSAR SISTEMA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ),
        ),
      ),
    );
  }
}
