import 'dart:async';
import 'package:flutter/material.dart';
import 'exodo_logo.dart';

/// Widget de loading com logo do Exodo
/// Exibe o logo com animação de rotação e texto de carregamento
class ExodoLoading extends StatefulWidget {
  final String? mensagem;
  final Color? corLoading;

  /// Ação do botão de escape exibido quando o carregamento demora.
  /// Quando informado (ex.: carga inicial da nuvem), o botão aparece com o
  /// texto [textoPular] e libera a tela sem interromper a sincronização.
  /// Sem ele, mantém o comportamento antigo ("Cancelar e Voltar").
  final VoidCallback? onPular;
  final String textoPular;
  final String textoAjudaPular;

  /// Segundos até exibir o botão de escape.
  final int segundosParaMostrarPular;

  const ExodoLoading({
    super.key,
    this.mensagem,
    this.corLoading,
    this.onPular,
    this.textoPular = 'Continuar sem esperar',
    this.textoAjudaPular = 'A sincronização continua em segundo plano.',
    this.segundosParaMostrarPular = 15,
  });

  @override
  State<ExodoLoading> createState() => _ExodoLoadingState();
}

class _ExodoLoadingState extends State<ExodoLoading>
    with SingleTickerProviderStateMixin {
  bool _mostrarCancelar = false;
  Timer? _timerCancelar;
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

    // Mostrar botão de escape após alguns segundos
    _timerCancelar = Timer(
      Duration(seconds: widget.segundosParaMostrarPular),
      () {
        if (mounted) {
          setState(() => _mostrarCancelar = true);
        }
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _timerCancelar?.cancel();
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
            // Mensagem de carregamento animada
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                widget.mensagem ?? 'Preparando ambiente...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ajustando os últimos detalhes para você',
              style: TextStyle(
                color: corLoading.withOpacity(0.8),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            if (_mostrarCancelar) ...[
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: widget.onPular ?? () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  widget.onPular != null ? Icons.skip_next : Icons.close,
                  size: 20,
                ),
                label: Text(widget.onPular != null ? widget.textoPular : 'Cancelar e Voltar'),
              ),
              const SizedBox(height: 12),
              Text(
                widget.onPular != null
                    ? widget.textoAjudaPular
                    : 'O processo parece estar demorando mais que o normal.',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

