import 'package:flutter/material.dart';
import 'central_nuvem_frame_stub.dart'
    if (dart.library.html) 'central_nuvem_frame_web.dart'
    as central_frame;

/// Central visual da nuvem. O painel operacional continua no servidor central;
/// esta tela o incorpora ao portal sem expor credenciais no aplicativo.
class CentralNuvemPage extends StatefulWidget {
  const CentralNuvemPage({super.key});

  @override
  State<CentralNuvemPage> createState() => _CentralNuvemPageState();
}

class _CentralNuvemPageState extends State<CentralNuvemPage> {
  static const String _painelUrl =
      'https://exodosystems.tail9b4943.ts.net/central-nuvem/';
  int _versaoPainel = 0;

  void _atualizarAgora() {
    setState(() => _versaoPainel++);
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 760;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.cloud_done_rounded, color: Color(0xFFFFA726)),
            SizedBox(width: 10),
            Text(
              'Central da Nuvem Êxodo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar agora',
            onPressed: _atualizarAgora,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(compacto ? 10 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF202B3B), Color(0xFF151D2A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF34445B)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.autorenew_rounded,
                          color: Color(0xFF4ADE80),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monitoramento automático',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'O serviço vigia e tenta recuperar o sincronizador',
                              style: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Text(
                      'Indicadores atualizados automaticamente',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      border: Border.all(color: const Color(0xFF293548)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: central_frame.buildCentralNuvemFrame(
                      _painelUrl,
                      key: ValueKey(_versaoPainel),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'O painel atualiza os indicadores automaticamente a cada 15 segundos. '
                'Use o botão de atualizar somente se quiser recarregar a página.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
