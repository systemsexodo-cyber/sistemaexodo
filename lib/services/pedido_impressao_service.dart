import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/empresa.dart';
import '../models/pedido.dart';
import 'auth_service.dart';
import 'data_service.dart';
import 'pedido_pdf_service.dart';

/// Ações de impressão de pedidos/serviços.
///
/// Reúne o menu de impressão usado na tela de Pedidos (via térmica, PDF A4,
/// pré-visualizações e romaneio) para que outras telas — como a de Serviços —
/// ofereçam exatamente as mesmas opções, sem duplicar a lógica.
class PedidoImpressaoService {
  /// Empresa atual (AuthService e, se necessário, DataService).
  static Empresa? _empresa(BuildContext context) {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa != null) return empresa;
    } catch (_) {
      // Provider indisponível — tenta o DataService abaixo
    }
    try {
      return Provider.of<DataService>(context, listen: false).empresaAtual;
    } catch (_) {
      return null;
    }
  }

  /// Menu com os tipos de impressão disponíveis para o pedido/serviço.
  static Future<void> mostrarMenuImpressao(
    BuildContext context,
    Pedido pedido, {
    bool incluirRomaneio = false,
  }) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Imprimir ${pedido.numero}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.receipt, color: Colors.orange, size: 32),
                title: const Text('Impressora Térmica (80mm)'),
                subtitle: const Text('Pedido para impressora térmica'),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                onTap: () {
                  Navigator.pop(dialogContext);
                  imprimirPedido(context, pedido, termico: true);
                },
              ),
              if (incluirRomaneio) ...[
                const Divider(),
                ListTile(
                  leading:
                      const Icon(Icons.receipt_long, color: Colors.purple, size: 32),
                  title: const Text('Romaneio / Separação (80mm)'),
                  subtitle: const Text('Apenas itens, sem valores financeiros'),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    imprimirRomaneio(context, pedido);
                  },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.blue, size: 32),
                title: const Text('PDF Normal (A4)'),
                subtitle: const Text('Pedido em formato PDF'),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                onTap: () {
                  Navigator.pop(dialogContext);
                  imprimirPedido(context, pedido, termico: false);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.visibility, color: Colors.teal, size: 32),
                title: const Text('Pré-visualizar PDF'),
                subtitle: const Text('Ver o pedido em PDF (A4) antes de imprimir'),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                onTap: () {
                  Navigator.pop(dialogContext);
                  imprimirPedido(context, pedido, termico: false, forcarPreview: true);
                },
              ),
              const Divider(),
              ListTile(
                leading:
                    const Icon(Icons.visibility, color: Colors.deepOrange, size: 32),
                title: const Text('Pré-visualizar Térmico (80mm)'),
                subtitle: const Text('Ver a via térmica antes de imprimir'),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                onTap: () {
                  Navigator.pop(dialogContext);
                  imprimirPedido(context, pedido, termico: true, forcarPreview: true);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  /// Gera e imprime o pedido (térmico ou A4), opcionalmente só pré-visualizando.
  static Future<void> imprimirPedido(
    BuildContext context,
    Pedido pedido, {
    required bool termico,
    bool forcarPreview = false,
  }) async {
    final empresa = _empresa(context);
    if (empresa == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa selecionada'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(termico ? 'Gerando Pedido (Térmico)...' : 'Gerando Pedido (PDF)...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (termico) {
        await PedidoPDFService.imprimirPDFTermico(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      } else {
        await PedidoPDFService.imprimirPDF(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      }
    } catch (e) {
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // O diálogo de carregamento já havia sido fechado
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Imprime o romaneio/separação (térmico, sem valores).
  static Future<void> imprimirRomaneio(BuildContext context, Pedido pedido) async {
    final empresa = _empresa(context);
    if (empresa == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa selecionada'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Gerando Romaneio Térmico...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final pdfBytes = await PedidoPDFService.gerarRomaneioPDFTermico(
        pedido: pedido,
        empresa: empresa,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (context.mounted) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Romaneio_${pedido.numero}',
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Romaneio térmico gerado com sucesso'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // O diálogo de carregamento já havia sido fechado
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar Romaneio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
