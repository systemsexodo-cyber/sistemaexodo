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
        // Logo principal "êxodo" com design moderno e minimalista
        Text(
          'êxodo',
          style: TextStyle(
            fontSize: defaultFontSize,
            fontWeight: FontWeight.w700,
            color: defaultColor,
            letterSpacing: 1.0,
            height: 1.0,
            fontFamily: 'Roboto',
            shadows: [
              Shadow(
                color: defaultColor.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        // Subtítulo "systems" (opcional) com design moderno
        if (showSubtitle) ...[
          const SizedBox(height: 8),
          Text(
            'systems',
            style: TextStyle(
              fontSize: (defaultFontSize * 0.35).clamp(12.0, 16.0),
              fontWeight: FontWeight.w300,
              color: Colors.white.withOpacity(0.6),
              letterSpacing: 4.0,
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
