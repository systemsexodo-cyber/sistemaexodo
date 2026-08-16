import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

/// 📈 Gráfico de Linha - Tendência Diária de Faturamento
class DailyTrendLineChart extends StatelessWidget {
  final List<Map<String, dynamic>?> dados;
  final Color corDestaque;

  const DailyTrendLineChart({
    super.key,
    required this.dados,
    this.corDestaque = Colors.cyanAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (dados.isEmpty || dados.every((d) => d == null || (d!['total'] as double) == 0)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Sem dados para exibir no período',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final dadosValidos = dados.where((d) => d != null).cast<Map<String, dynamic>>().toList();
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    double maxY = 0;
    for (final d in dadosValidos) {
      final v = (d['total'] as double);
      if (v > maxY) maxY = v;
    }
    maxY = maxY * 1.3;
    if (maxY == 0) maxY = 100;

    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withOpacity(0.05),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 70,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      formato.format(value),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (dadosValidos.length / 5).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dadosValidos.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      dadosValidos[idx]['label'] ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 9,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (dadosValidos.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final label = idx >= 0 && idx < dadosValidos.length
                      ? dadosValidos[idx]['label'] ?? ''
                      : '';
                  return LineTooltipItem(
                    '$label\n${formato.format(spot.y)}',
                    TextStyle(
                      color: corDestaque,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(dadosValidos.length, (i) {
                return FlSpot(i.toDouble(), (dadosValidos[i]['total'] as double));
              }),
              isCurved: true,
              preventCurveOverShooting: true,
              color: corDestaque,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: const Color(0xFF0D0D1A),
                    strokeWidth: 2,
                    strokeColor: corDestaque,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    corDestaque.withOpacity(0.25),
                    corDestaque.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      ),
    );
  }
}

/// 🥧 Gráfico de Pizza - Distribuição de Receitas
class RevenuePieChart extends StatelessWidget {
  final List<Map<String, dynamic>> breakdown;
  final double total;

  const RevenuePieChart({
    super.key,
    required this.breakdown,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty || total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma receita no período',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: List.generate(breakdown.length, (i) {
                final item = breakdown[i];
                final valor = (item['valor'] as double);
                final percentage = total > 0 ? (valor / total) * 100 : 0.0;
                return PieChartSectionData(
                  color: (item['color'] as Color?) ?? Colors.blueAccent,
                  value: valor,
                  title: '${percentage.toStringAsFixed(1)}%',
                  radius: 55,
                  titleStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  badgeWidget: percentage > 8
                      ? Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item['icon'] as IconData? ?? Icons.circle,
                            color: (item['color'] as Color?) ?? Colors.blueAccent,
                            size: 14,
                          ),
                        )
                      : null,
                  badgePositionPercentageOffset: 1.3,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Legenda
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: List.generate(breakdown.length, (i) {
            final item = breakdown[i];
            final valor = (item['valor'] as double);
            final percentage = total > 0 ? (valor / total) * 100 : 0.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: (item['color'] as Color?) ?? Colors.blueAccent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item['label']} (${percentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// 📊 Gráfico de Barras - Top Produtos/Serviços
class TopItemsBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> itens;
  final Color corDestaque;
  final String? titulo;

  const TopItemsBarChart({
    super.key,
    required this.itens,
    this.corDestaque = Colors.greenAccent,
    this.titulo,
  });

  @override
  Widget build(BuildContext context) {
    if (itens.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum item vendido no período',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final top5 = itens.take(5).toList();
    final reversed = top5.reversed.toList();

    double maxValor = 0;
    for (final item in reversed) {
      final v = (item['total'] as double);
      if (v > maxValor) maxValor = v;
    }
    if (maxValor == 0) maxValor = 100;

    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxValor * 1.2,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final item = reversed[groupIndex];
                  return BarTooltipItem(
                    '${item['nome']}\n${formato.format(rod.toY)}',
                    TextStyle(
                      color: corDestaque,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    if (value == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        formato.format(value),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 8,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= reversed.length) {
                      return const SizedBox.shrink();
                    }
                    final nome = reversed[idx]['nome'] as String? ?? '';
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        nome.length > 12 ? '${nome.substring(0, 11)}…' : nome,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 9,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxValor / 4,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.white.withOpacity(0.05),
                strokeWidth: 1,
              ),
            ),
            barGroups: List.generate(reversed.length, (i) {
              final item = reversed[i];
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (item['total'] as double),
                    color: corDestaque.withOpacity(0.7 + (i / reversed.length) * 0.3),
                    width: 22,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }),
          ),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        ),
      ),
    );
  }
}

/// 📊 Gráfico de Barras Horizontais - Vendas por Operador
class SalesByOperatorChart extends StatelessWidget {
  final List<Map<String, dynamic>> operadores;
  final Color corDestaque;

  const SalesByOperatorChart({
    super.key,
    required this.operadores,
    this.corDestaque = Colors.orangeAccent,
  });

  @override
  Widget build(BuildContext context) {
    if (operadores.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhuma venda registrada',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final top5 = operadores.take(5).toList();

    double maxValor = 0;
    for (final op in top5) {
      final v = (op['total'] as double);
      if (v > maxValor) maxValor = v;
    }
    if (maxValor == 0) maxValor = 100;

    return Column(
      children: List.generate(top5.length, (i) {
        final op = top5[i];
        final valor = (op['total'] as double);
        final qtd = (op['quantidade'] as num).toInt();
        final pct = maxValor > 0 ? (valor / maxValor) : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${op['nome']}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${formato.format(valor)} · $qtd vendas',
                    style: TextStyle(
                      color: corDestaque.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    corDestaque.withOpacity(0.7 + (i / top5.length) * 0.3),
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// 🥧 Gráfico de Pizza - Despesas por Categoria
class ExpensesPieChart extends StatelessWidget {
  final List<Map<String, dynamic>> breakdown;
  final double total;

  const ExpensesPieChart({
    super.key,
    required this.breakdown,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty || total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma despesa no período',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 1,
              centerSpaceRadius: 40,
              sections: List.generate(breakdown.length, (i) {
                final item = breakdown[i];
                final valor = (item['valor'] as double);
                final percentage = total > 0 ? (valor / total) * 100 : 0.0;
                return PieChartSectionData(
                  color: (item['color'] as Color?) ?? Colors.redAccent,
                  value: valor,
                  title: '${percentage.toStringAsFixed(1)}%',
                  radius: i == 0 ? 50 : 45,
                  titleStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: List.generate(breakdown.length, (i) {
            final item = breakdown[i];
            final valor = (item['valor'] as double);
            final percentage = total > 0 ? (valor / total) * 100 : 0.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: (item['color'] as Color?) ?? Colors.redAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${item['label']} (${percentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// 📊 Indicador de Progresso Horizontal (KPIs)
class KpiProgressIndicator extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color color;
  final IconData? icon;

  const KpiProgressIndicator({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 📈 Sparkline Mini Gráfico (pequeno, para cartões)
class SparklineChart extends StatelessWidget {
  final List<double> valores;
  final Color cor;
  final double height;

  const SparklineChart({
    super.key,
    required this.valores,
    this.cor = Colors.cyanAccent,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (valores.isEmpty || valores.every((v) => v == 0)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Sem dados',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10),
          ),
        ),
      );
    }

    double maxV = valores.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) maxV = 1;

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _SparklinePainter(
          valores: valores,
          cor: cor,
          maxValor: maxV,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> valores;
  final Color cor;
  final double maxValor;

  _SparklinePainter({
    required this.valores,
    required this.cor,
    required this.maxValor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.length < 2) return;

    final paint = Paint()
      ..color = cor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [cor.withOpacity(0.2), cor.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (valores.length - 1);

    for (int i = 0; i < valores.length; i++) {
      final x = i * stepX;
      final y = size.height - (valores[i] / maxValor) * size.height * 0.9;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo((valores.length - 1) * stepX, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Último ponto destacado
    final lastX = (valores.length - 1) * stepX;
    final lastY = size.height - (valores.last / maxValor) * size.height * 0.9;
    canvas.drawCircle(
      Offset(lastX, lastY),
      3,
      Paint()..color = cor..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return valores != oldDelegate.valores || cor != oldDelegate.cor;
  }
}
