import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/horarios_pico.dart';

/// Card do dashboard com os HORÁRIOS QUE MAIS VENDEM (horário de pico).
///
/// Recebe o resultado já calculado ([ResumoHorarios]) e só desenha: o cálculo
/// mora em `utils/horarios_pico.dart` (com teste próprio) e a busca dos dados
/// fica na tela. Assim dá para testar o card com números feitos à mão.
class HorariosPicoCard extends StatelessWidget {
  final ResumoHorarios resumo;

  /// Quem não pode ver totais vê o pico por QUANTIDADE (sem valores).
  final bool podeVerTotais;

  /// "do Dia", "da Semana", "do Mês"...
  final String rotuloPeriodo;

  /// Chamado ao trocar entre valor e quantidade. Nulo esconde o seletor.
  final VoidCallback? onTrocarMetrica;

  const HorariosPicoCard({
    super.key,
    required this.resumo,
    this.podeVerTotais = true,
    this.rotuloPeriodo = '',
    this.onTrocarMetrica,
  });

  @override
  Widget build(BuildContext context) {
    final formato = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final porQuantidade = resumo.metrica == MetricaPico.quantidade;
    final horaDoPico = resumo.horaDoPico;

    String texto(double peso, int quantidade) => porQuantidade
        ? '$quantidade venda${quantidade == 1 ? '' : 's'}'
        : formato.format(peso);

    var maiorPeso = 0.0;
    for (final hora in resumo.porHora) {
      if (hora.total > maiorPeso) maiorPeso = hora.total;
    }

    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.schedule, color: Colors.amber, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Horários que mais vendem $rotuloPeriodo',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (podeVerTotais && onTrocarMetrica != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Ver pico por:',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 10),
                  _BotaoMetrica(
                    texto: 'Valor',
                    ativo: !porQuantidade,
                    onTap: porQuantidade ? onTrocarMetrica! : null,
                  ),
                  const SizedBox(width: 8),
                  _BotaoMetrica(
                    texto: 'Quantidade',
                    ativo: porQuantidade,
                    onTap: porQuantidade ? null : onTrocarMetrica!,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (resumo.vazio)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Nenhuma venda no período para calcular o horário de pico',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              )
            else ...[
              _buildDestaque(porQuantidade, horaDoPico, texto),
              const SizedBox(height: 20),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: resumo.porHora.map((hora) {
                    final altura = maiorPeso <= 0
                        ? 0.0
                        : (hora.total / maiorPeso) * 110;
                    final naFaixa = resumo.janelaDePico.contains(hora.hora);
                    final cor = hora.hora == resumo.horaDePico
                        ? Colors.amber
                        : naFaixa
                            ? Colors.orange.withOpacity(0.8)
                            : hora.total > 0
                                ? Colors.blueGrey.shade400
                                : Colors.white10;
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            height: altura <= 0 ? 2 : altura,
                            decoration: BoxDecoration(
                              color: cor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(3),
                                topRight: Radius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hora.hora % 3 == 0 ? hora.rotulo : '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 8),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Horas com mais movimento:',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: resumo.melhoresHoras.take(4).map((hora) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${hora.rotulo} · ${texto(hora.total, hora.quantidade)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
              if (resumo.porDia.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Dias que mais vendem:',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                ...resumo.porDia.take(3).map((dia) {
                  final rotuloPico = dia.horaDePico >= 0
                      ? ' · pico ${dia.horaDePico.toString().padLeft(2, '0')}h'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            dia.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${texto(dia.total, dia.quantidade)}$rotuloPico',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDestaque(
    bool porQuantidade,
    HoraDePico? horaDoPico,
    String Function(double, int) texto,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Pico: ${resumo.rotuloJanela}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${(resumo.parteNaJanela * 100).toStringAsFixed(0)}% '
            '${porQuantidade ? 'das vendas' : 'do faturamento'} do período '
            '(${texto(resumo.total, resumo.quantidade)})',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (horaDoPico != null)
            Text(
              'Melhor hora: ${horaDoPico.rotulo} — '
              '${texto(horaDoPico.total, horaDoPico.quantidade)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _BotaoMetrica extends StatelessWidget {
  final String texto;
  final bool ativo;
  final VoidCallback? onTap;

  const _BotaoMetrica({
    required this.texto,
    required this.ativo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo
              ? Colors.amber.withOpacity(0.2)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? Colors.amber : Colors.white12),
        ),
        child: Text(
          texto,
          style: TextStyle(
            color: ativo ? Colors.amber : Colors.white54,
            fontSize: 12,
            fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
