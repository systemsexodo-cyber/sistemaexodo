import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../services/danfe_service.dart';

/// Diálogo de sucesso premium para NFC-e do sistema Exodo
/// Design moderno com gradientes vibrantes, efeitos de brilho e animações
class ExodoSuccessDialog extends StatelessWidget {
  final NFCe nfce;
  final Empresa? empresa;

  const ExodoSuccessDialog({
    super.key,
    required this.nfce,
    this.empresa,
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
          color: const Color(0xFF1E1E2E), // Fundo escuro premium
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.greenAccent.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 50,
              offset: const Offset(0, 25),
            ),
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.05),
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
                // Header com Gradiente e Ícone Animado
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00C853), // Verde Intenso
                        const Color(0xFF2E7D32).withOpacity(0.9), // Verde Escuro Suave
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
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'NFC-e EMITIDA COM SUCESSO!',
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
                          'AUTORIZADA PELO SEFAZ',
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
                      // Resumo da Nota em Cards Modernos
                      Row(
                        children: [
                          Expanded(
                            child: _buildSmallDetailCard(
                              'NÚMERO',
                              nfce.numero,
                              Icons.pin_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSmallDetailCard(
                              'SÉRIE',
                              nfce.serie,
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

                      const SizedBox(height: 24),

                      // QR Code com Container Estilizado
                      if (nfce.qrCode != null && nfce.qrCode!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              QrImageView(
                                data: nfce.qrCode!,
                                version: QrVersions.auto,
                                size: 180.0,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF1E1E2E),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF1E1E2E),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'ESCANEAR PARA CONSULTA',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF1E1E2E),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Infos Técnicas em Expansion Tiles
                      _buildTechnicalInfo(context),
                      
                      const SizedBox(height: 32),
                      
                      // Botões de Ação Final
                      Row(
                        children: [
                          if (empresa != null) ...[
                             Expanded(
                                child: _ActionButton(
                                  onPressed: () {
                                    DANFEService.imprimir(nfce: nfce, empresa: empresa!);
                                  },
                                  icon: Icons.print_rounded,
                                  label: 'IMPRIMIR',
                                  isPrimary: false,
                                ),
                              ),
                              const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: 2,
                            child: _ActionButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icons.check_circle_rounded,
                              label: 'FECHAR',
                              isPrimary: true,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Botão Secundário para Compartilhar
                      if (empresa != null)
                        TextButton.icon(
                          onPressed: () {
                            DANFEService.compartilharPDF(nfce: nfce, empresa: empresa!);
                          },
                          icon: Icon(Icons.share_rounded, color: Colors.white.withOpacity(0.5), size: 18),
                          label: Text(
                            'COMPARTILHAR PDF',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
        color: isHighlight ? Colors.greenAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight ? Colors.greenAccent.withOpacity(0.3) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: isHighlight ? Colors.greenAccent : Colors.white54, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isHighlight ? Colors.greenAccent.withOpacity(0.7) : Colors.white38,
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

  Widget _buildTechnicalInfo(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        title: Text(
          'EXIBIR DETALHES TÉCNICOS',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        children: [
          const SizedBox(height: 8),
          _InfoField(label: 'CHAVE DE ACESSO', value: nfce.chaveAcesso ?? '---'),
          const SizedBox(height: 10),
          _InfoField(label: 'PROTOCOLO DE AUTORIZAÇÃO', value: nfce.protocolo ?? '---'),
          const SizedBox(height: 10),
          _InfoField(label: 'DATA/HORA EMISSÃO', value: DateFormat('dd/MM/yyyy HH:mm:ss').format(nfce.dataEmissao)),
        ],
      ),
    );
  }

  static void mostrar(BuildContext context, NFCe nfce, {Empresa? empresa}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) => ExodoSuccessDialog(nfce: nfce, empresa: empresa),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;

  const _InfoField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.greenAccent.withOpacity(0.5),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF00C853) : Colors.white.withOpacity(0.08),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: isPrimary ? 8 : 0,
          shadowColor: isPrimary ? Colors.greenAccent.withOpacity(0.5) : Colors.transparent,
        ),
      ),
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
