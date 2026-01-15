import 'package:flutter/material.dart';

/// Widget do logo Êxodo Systems
/// Exibe o texto "êxodo" em estilo bold com acento circunflexo
class ExodoLogo extends StatelessWidget {
  final double? fontSize;
  final Color? color;
  final bool showSubtitle;
  
  const ExodoLogo({
    super.key,
    this.fontSize,
    this.color,
    this.showSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = color ?? const Color(0xFFFF9800); // Laranja vibrante
    final defaultFontSize = fontSize ?? 48.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo principal "êxodo" com melhor tipografia
        Text(
          'êxodo',
          style: TextStyle(
            fontSize: defaultFontSize,
            fontWeight: FontWeight.w900, // Mais bold e impactante
            color: defaultColor,
            letterSpacing: -0.5,
            height: 1.1,
            fontFamily: 'Roboto',
            shadows: [
              Shadow(
                color: defaultColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
              Shadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        // Subtítulo "systems" (opcional)
        if (showSubtitle) ...[
          const SizedBox(height: 6),
          Text(
            'systems',
            style: TextStyle(
              fontSize: (defaultFontSize * 0.4).clamp(14.0, 18.0),
              fontWeight: FontWeight.w400,
              color: Colors.white.withOpacity(0.85),
              letterSpacing: 3.5,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ],
    );
  }
}

/// Widget compacto do logo para AppBar
class ExodoLogoCompact extends StatelessWidget {
  final double? fontSize;
  final Color? color;

  const ExodoLogoCompact({
    super.key,
    this.fontSize,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = color ?? const Color(0xFFFF9800);
    final defaultFontSize = fontSize ?? 24.0;

    return Text(
      'ê',
      style: TextStyle(
        fontSize: defaultFontSize,
        fontWeight: FontWeight.bold,
        color: defaultColor,
        fontFamily: 'Roboto',
      ),
    );
  }
}
