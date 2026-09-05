import 'package:flutter/material.dart';

/// Widget do logo Êxodo Systems
/// Exibe o texto "êxodo" em estilo bold com acento circunflexo
class ExodoLogo extends StatefulWidget {
  final double? fontSize;
  final Color? color;
  final bool showSubtitle;
  final bool isVertical;
  final bool showPhoenix;
  
  const ExodoLogo({
    super.key,
    this.fontSize,
    this.color,
    this.showSubtitle = false,
    this.isVertical = true,
    this.showPhoenix = false,
  });

  @override
  State<ExodoLogo> createState() => _ExodoLogoState();
}

class _ExodoLogoState extends State<ExodoLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultColor = widget.color ?? const Color(0xFFFF9800);
    final defaultFontSize = widget.fontSize ?? 48.0;

    final bird = widget.showPhoenix ? AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: widget.isVertical ? const Offset(0, -12) : Offset.zero,
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                defaultColor.withOpacity(0.3),
                BlendMode.srcATop,
              ),
              child: Image.asset(
                'assets/images/phoenix.png',
                height: defaultFontSize * (widget.isVertical ? 1.9 : 1.8),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    ) : null;

    final logoText = Text(
      'êxodo',
      style: TextStyle(
        fontSize: defaultFontSize,
        fontWeight: FontWeight.w900,
        color: defaultColor,
        letterSpacing: 1.0,
        fontFamily: 'Roboto',
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    final subtitle = widget.showSubtitle ? Text(
      'systems',
      style: TextStyle(
        fontSize: (defaultFontSize * 0.3).clamp(10.0, 14.0),
        fontWeight: FontWeight.w400,
        color: Colors.white.withOpacity(0.4),
        letterSpacing: 5.0,
        fontFamily: 'Roboto',
      ),
    ) : null;

    if (!widget.isVertical) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (bird != null) ...[
            bird,
            const SizedBox(width: 8),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              logoText,
              if (subtitle != null) subtitle,
            ],
          ),
        ],
      );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bird != null) ...[
          bird,
          const SizedBox(height: 2),
        ],
        logoText,
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          subtitle,
        ],
      ],
    );

    if (widget.showPhoenix && widget.isVertical) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: column,
      );
    }

    return column;
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
        shadows: [
          Shadow(
            color: defaultColor.withOpacity(0.3),
            blurRadius: 8,
          ),
        ],
        fontFamily: 'Roboto',
      ),
    );
  }
}
