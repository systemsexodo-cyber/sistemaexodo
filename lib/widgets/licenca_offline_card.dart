import 'package:flutter/material.dart';

/// Cartão da "Licença Offline" na tela de empresa (cadastro/edição).
///
/// Mostra o código de liberação que o suporte entrega ao cliente — o mesmo que
/// a tela de bloqueio compara quando o sistema passa do limite de dias sem
/// internet — e oferece copiar/gerar outro. É só apresentação: quem copia para
/// a área de transferência e quem gera o código novo é a tela (callbacks).
class LicencaOfflineCard extends StatelessWidget {
  /// Código atual da empresa (`''` enquanto não houver).
  final String codigo;

  /// Dias sem internet que a empresa tolera antes de o código ser exigido.
  final int limiteDiasOffline;

  /// Padrão do sistema, usado só para explicar de onde vem o limite.
  final int limitePadrao;

  final VoidCallback onCopiar;
  final VoidCallback onGerarNovo;

  const LicencaOfflineCard({
    super.key,
    required this.codigo,
    required this.limiteDiasOffline,
    required this.onCopiar,
    required this.onGerarNovo,
    this.limitePadrao = 7,
  });

  @override
  Widget build(BuildContext context) {
    final exibido = codigo.trim().isEmpty ? '—' : codigo.trim();
    final origem = limiteDiasOffline == limitePadrao
        ? 'padrão do sistema'
        : 'limite desta empresa';

    return Container(
      key: const Key('licenca-offline-card'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.vpn_key, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Licença Offline (liberação do cliente)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Código que o cliente digita na tela de bloqueio para voltar a usar '
            'o sistema sem internet. Gerar um novo invalida o anterior.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SelectableText(
            exibido,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Será exigido quando a empresa passar de $limiteDiasOffline dias '
            'sem internet ($origem).',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('licenca-offline-copiar'),
                onPressed: onCopiar,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar código'),
              ),
              OutlinedButton.icon(
                key: const Key('licenca-offline-gerar-novo'),
                onPressed: onGerarNovo,
                icon: const Icon(Icons.autorenew, size: 18),
                label: const Text('Gerar novo código'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
