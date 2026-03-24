import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/nfce.dart';

/// Diálogo de sucesso premium para Cancelamento de NFC-e do sistema Exodo
/// Baseado no design do ExodoSuccessDialog mas adaptado para cancelamento
class ExodoCancelSuccessDialog extends StatelessWidget {
  final NFCe nfce;

  const ExodoCancelSuccessDialog({
    super.key,
    required this.nfce,
  });

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E), 
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 50,
              offset: const Offset(0, 25),
            ),
            BoxShadow(
              color: Colors.redAccent.withOpacity(0.05),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header com Gradiente Vermelho/Laranja para Cancelamento
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF5252), // Vermelho
                        const Color(0xFFD32F2F).withOpacity(0.9), // Vermelho Escuro
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      _AnimatedPulseIcon(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.cancel_rounded,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'NFC-e CANCELADA COM SUCESSO!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'CANCELAMENTO HOMOLOGADO',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 32),
                  child: Column(
                    children: [
                      // Resumo
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallDetailCard(
                              'NÚMERO',
                              nfce.numero ?? '---',
                              Icons.pin_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSmallDetailCard(
                              'SÉRIE',
                              nfce.serie ?? '---',
                              Icons.layers_rounded,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      _buildSmallDetailCard(
                        'VALOR TOTAL',
                        formatoMoeda.format(nfce.valorTotal),
                        Icons.payments_rounded,
                        isHighlight: true,
                      ),

                      const SizedBox(height: 32),
                      
                      // Botão Fechar
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text(
                            'CONCLUÍDO',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5252),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: Colors.redAccent.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallDetailCard(String label, String value, IconData icon, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isHighlight ? Colors.redAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: isHighlight ? Colors.redAccent : Colors.white54, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isHighlight ? Colors.redAccent.withOpacity(0.7) : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isHighlight ? 16 : 14,
                  fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void mostrar(BuildContext context, NFCe nfce) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) => ExodoCancelSuccessDialog(nfce: nfce),
    );
  }
}

class _AnimatedPulseIcon extends StatefulWidget {
  final Widget child;
  const _AnimatedPulseIcon({required this.child});

  @override
  State<_AnimatedPulseIcon> createState() => _AnimatedPulseIconState();
}

class _AnimatedPulseIconState extends State<_AnimatedPulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}
