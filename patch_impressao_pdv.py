# -*- coding: utf-8 -*-
"""Patch: melhorias de impressao no PDV (Sistema Exodo).
1) adicionar_empresa_page.dart: config 'mostrarEnderecoCupom'
2) venda_pdf_service.dart: destacar endereco de entrega (A4 + termico), respeitar config
3) historico_vendas_page.dart: botao REIMPRIMIR CUPOM NAO FISCAL
"""
import sys

BASE = 'C:/Users/charles/.antigravity/sistema_exodo_15-04-2026/'

REPLACEMENTS = [
    # ============ adicionar_empresa_page.dart ============
    (BASE + 'lib/pages/adicionar_empresa_page.dart',
     "  final _comandaFonteStatusController = TextEditingController(text: '8.0');\n"
     "  bool _comandaNegrito = true;",
     "  final _comandaFonteStatusController = TextEditingController(text: '8.0');\n"
     "  bool _comandaNegrito = true;\n"
     "  bool _mostrarEnderecoCupom = true; // Exibir endereco de entrega no cupom nao fiscal"),

    (BASE + 'lib/pages/adicionar_empresa_page.dart',
     "    _comandaNegrito = empresa.configuracoes?['comandaNegrito'] ?? true;",
     "    _comandaNegrito = empresa.configuracoes?['comandaNegrito'] ?? true;\n"
     "    _mostrarEnderecoCupom = empresa.configuracoes?['mostrarEnderecoCupom'] ?? true;"),

    (BASE + 'lib/pages/adicionar_empresa_page.dart',
     "        'comandaNegrito': _comandaNegrito,",
     "        'comandaNegrito': _comandaNegrito,\n"
     "        'mostrarEnderecoCupom': _mostrarEnderecoCupom,"),

    (BASE + 'lib/pages/adicionar_empresa_page.dart',
     """              SwitchListTile(
                title: const Text('Usar Negrito nos Textos Principais', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Melhora a leitura em algumas impressoras térmicas', style: TextStyle(color: Colors.white60, fontSize: 11)),
                value: _comandaNegrito,
                onChanged: (value) => setState(() => _comandaNegrito = value),
                activeColor: Colors.purple,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),""",
     """              SwitchListTile(
                title: const Text('Usar Negrito nos Textos Principais', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Melhora a leitura em algumas impressoras térmicas', style: TextStyle(color: Colors.white60, fontSize: 11)),
                value: _comandaNegrito,
                onChanged: (value) => setState(() => _comandaNegrito = value),
                activeColor: Colors.purple,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Mostrar Endereço de Entrega no Cupom', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Quando a venda for DELIVERY, exibe o endereço de entrega destacado no cupom não fiscal', style: TextStyle(color: Colors.white60, fontSize: 11)),
                value: _mostrarEnderecoCupom,
                onChanged: (value) => setState(() => _mostrarEnderecoCupom = value),
                activeColor: Colors.orange,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),"""),

    # ============ venda_pdf_service.dart ============
    (BASE + 'lib/services/venda_pdf_service.dart',
     "      final formatoData = DateFormat('dd/MM/yyyy HH:mm');\n\n"
     "      pdf.addPage(",
     "      final formatoData = DateFormat('dd/MM/yyyy HH:mm');\n"
     "      final mostrarEnderecoCupom = empresa.configuracoes?['mostrarEnderecoCupom'] != false;\n\n"
     "      pdf.addPage("),

    (BASE + 'lib/services/venda_pdf_service.dart',
     "                  _buildDelivery(venda),",
     "                  _buildDelivery(venda, mostrarEndereco: mostrarEnderecoCupom),"),

    (BASE + 'lib/services/venda_pdf_service.dart',
     "  static pw.Widget _buildDelivery(VendaBalcao venda) {",
     "  static pw.Widget _buildDelivery(VendaBalcao venda, {bool mostrarEndereco = true}) {"),

    (BASE + 'lib/services/venda_pdf_service.dart',
     """          pw.SizedBox(height: 8),
          pw.Text(
            'Endereço: ${info.logradouro}, ${info.numero}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Bairro: ${info.bairro}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Cidade/UF: ${info.cidade} - ${info.uf}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          if (info.cep != null && info.cep!.isNotEmpty)
            pw.Text(
              'CEP: ${info.cep}',
              style: const pw.TextStyle(fontSize: 10),
            ),""",
     """          pw.SizedBox(height: 8),
          if (mostrarEndereco) ...[
            pw.Text(
              'Endereço: ${info.logradouro}, ${info.numero}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Bairro: ${info.bairro}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Cidade/UF: ${info.cidade} - ${info.uf}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            if (info.cep != null && info.cep!.isNotEmpty)
              pw.Text(
                'CEP: ${info.cep}',
                style: const pw.TextStyle(fontSize: 10),
              ),
          ],"""),

    (BASE + 'lib/services/venda_pdf_service.dart',
     "      final bool usarNegrito = config['comandaNegrito'] ?? true;",
     "      final bool usarNegrito = config['comandaNegrito'] ?? true;\n"
     "      final bool mostrarEnderecoCupom = config['mostrarEnderecoCupom'] != false;"),

    (BASE + 'lib/services/venda_pdf_service.dart',
     "                  _buildDeliveryTermico(venda, fontSizeCorpo),",
     "                  _buildDeliveryTermico(venda, fontSizeCorpo, mostrarEndereco: mostrarEnderecoCupom),"),

    (BASE + 'lib/services/venda_pdf_service.dart',
     "  static pw.Widget _buildDeliveryTermico(VendaBalcao venda, double fontSizeCorpo) {",
     "  static pw.Widget _buildDeliveryTermico(VendaBalcao venda, double fontSizeCorpo, {bool mostrarEndereco = true}) {"),

    (BASE + 'lib/services/venda_pdf_service.dart',
     """        pw.SizedBox(height: 4),
        pw.Text(
          'Endereço: ${info.logradouro}, ${info.numero}',
          style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Bairro: ${info.bairro}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        pw.Text(
          'Cidade/UF: ${info.cidade} - ${info.uf}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),""",
     """        pw.SizedBox(height: 4),
        if (mostrarEndereco) ...[
          pw.Container(
            padding: pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ENDEREÇO DE ENTREGA',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '${info.logradouro}, ${info.numero}',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Bairro: ${info.bairro}',
                  style: pw.TextStyle(fontSize: fontSizeCorpo + 1),
                ),
                pw.Text(
                  '${info.cidade} - ${info.uf}',
                  style: pw.TextStyle(fontSize: fontSizeCorpo + 1),
                ),
                if (info.observacoes != null && info.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Obs.: ${info.observacoes}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ],"""),

    # ============ historico_vendas_page.dart ============
    (BASE + 'lib/pages/historico_vendas_page.dart',
     "import '../services/auth_service.dart';\n"
     "import '../services/caixa_pdf_service.dart';",
     "import '../services/auth_service.dart';\n"
     "import '../services/caixa_pdf_service.dart';\n"
     "import '../services/venda_pdf_service.dart';\n"
     "import '../services/pedido_pdf_service.dart';"),

    (BASE + 'lib/pages/historico_vendas_page.dart',
     """                const SizedBox(height: 12),
              ],
              // Botão de Cancelamento (Apenas se não estiver cancelado e for venda/pedido)""",
     """                const SizedBox(height: 12),
              ],
              // Botão de Reimpressão do Cupom Não Fiscal
              if (!item.isCancelada &&
                  (item.vendaBalcao != null || item.pedido != null) &&
                  !item.isSangria &&
                  !item.isSuprimento &&
                  item.fechamentoCaixa == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _reimprimirCupomNaoFiscal(item),
                    icon: const Icon(Icons.print, color: Colors.cyanAccent),
                    label: const Text(
                      'REIMPRIMIR CUPOM NÃO FISCAL',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.cyanAccent),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Botão de Cancelamento (Apenas se não estiver cancelado e for venda/pedido)"""),

    (BASE + 'lib/pages/historico_vendas_page.dart',
     """  void _confirmarCancelamento(ItemHistorico item) {
    final dataService = Provider.of<DataService>(context, listen: false);""",
     """  Future<void> _reimprimirCupomNaoFiscal(ItemHistorico item) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final emp = authService.empresaAtual;
      if (emp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa selecionada para imprimir o cupom'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      if (item.vendaBalcao != null) {
        await VendaPDFService.imprimirPDFTermico(
          venda: item.vendaBalcao!,
          empresa: emp,
          context: context,
        );
      } else if (item.pedido != null) {
        await PedidoPDFService.imprimirPDFTermico(
          pedido: item.pedido!,
          empresa: emp,
          context: context,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reimprimir cupom: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _confirmarCancelamento(ItemHistorico item) {
    final dataService = Provider.of<DataService>(context, listen: false);"""),
]


def apply(path, old, new):
    with open(path, 'rb') as f:
        raw = f.read()
    had_bom = raw.startswith(b'\xef\xbb\xbf')
    text = raw.decode('utf-8-sig')
    crlf = '\r\n' in text
    text = text.replace('\r\n', '\n')
    count = text.count(old)
    if count != 1:
        print('FALHA: %s\n  ocorrencias de %r = %d (esperado 1)\n  inicio do trecho: %r' % (path, old[:60], count, old[:80]))
        return False
    text = text.replace(old, new, 1)
    out = text.replace('\n', '\r\n') if crlf else text
    data = (b'\xef\xbb\xbf' + out.encode('utf-8')) if had_bom else out.encode('utf-8')
    with open(path, 'wb') as f:
        f.write(data)
    print('OK  %s  -> %r' % (path.split('/')[-1], old[:50]))
    return True


def main():
    ok = True
    for path, old, new in REPLACEMENTS:
        if not apply(path, old, new):
            ok = False
    print('RESULTADO:', 'SUCESSO' if ok else 'FALHAS ENCONTRADAS')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
