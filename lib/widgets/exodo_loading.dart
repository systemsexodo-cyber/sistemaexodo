import 'package:flutter/material.dart';
import 'exodo_logo.dart';

/// Widget de loading com logo do Exodo
/// Exibe o logo com animação de rotação e texto de carregamento
class ExodoLoading extends StatefulWidget {
  final String? mensagem;
  final Color? corLoading;
  
  const ExodoLoading({
    super.key,
    this.mensagem,
    this.corLoading,
  });

  @override
  State<ExodoLoading> createState() => _ExodoLoadingState();
}

class _ExodoLoadingState extends State<ExodoLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final corLoading = widget.corLoading ?? const Color(0xFFFF9800);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo com animação de fade pulsante
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      corLoading.withOpacity(0.15),
                      corLoading.withOpacity(0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: const ExodoLogo(
                  fontSize: 64,
                  showSubtitle: true,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Indicador de loading
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(corLoading),
                backgroundColor: corLoading.withOpacity(0.2),
              ),
            ),
            const SizedBox(height: 24),
            // Mensagem de carregamento
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                widget.mensagem ?? 'Carregando...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Aguarde alguns instantes',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

