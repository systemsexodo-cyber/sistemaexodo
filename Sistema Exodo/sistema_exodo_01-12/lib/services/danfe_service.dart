import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';

/// Serviço para geração do DANFE-NFC-e (Documento Auxiliar)
class DANFEService {
  /// Gera PDF do DANFE-NFC-e
  static Future<Uint8List> gerarPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(80 * 2.83465, 297 * 2.83465), // 80mm x 297mm (térmica) - 1mm = 2.83465 points
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildCabecalho(empresa),
                pw.SizedBox(height: 10),
                _buildDadosNFCe(nfce),
                pw.SizedBox(height: 10),
                _buildItens(nfce),
                pw.SizedBox(height: 10),
                _buildTotal(nfce),
                pw.SizedBox(height: 10),
                _buildPagamento(nfce),
                pw.SizedBox(height: 10),
                if (nfce.qrCode != null) _buildQRCode(nfce.qrCode!),
                pw.SizedBox(height: 10),
                _buildRodape(empresa),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar DANFE: $e');
    }
  }

  /// Constrói cabeçalho do DANFE
  static pw.Widget _buildCabecalho(Empresa empresa) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'DANFE NFC-e',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          empresa.nomeExibicao,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.cnpj != null)
          pw.Text(
            'CNPJ: ${_formatarCNPJ(empresa.cnpj!)}',
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
          if (empresa.enderecoCompleto.isNotEmpty && empresa.enderecoCompleto != '')
          pw.Text(
            empresa.enderecoCompleto,
            style: const pw.TextStyle(fontSize: 7),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  /// Constrói dados da NFC-e
  static pw.Widget _buildDadosNFCe(NFCe nfce) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NFC-e Nº ${nfce.numero}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Série: ${nfce.serie}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          if (nfce.chaveAcesso != null)
            pw.Text(
              'Chave: ${_formatarChaveAcesso(nfce.chaveAcesso!)}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Emissão: ${_formatarData(nfce.dataEmissao)}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          if (nfce.protocolo != null)
            pw.Text(
              'Protocolo: ${nfce.protocolo}',
              style: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    );
  }

  /// Constrói itens da NFC-e
  static pw.Widget _buildItens(NFCe nfce) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ITENS',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        ...nfce.itens.map((item) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.descricao,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${item.quantidade.toStringAsFixed(2)} ${item.unidade} x ${_formatarMoeda(item.valorUnitario)}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      _formatarMoeda(item.valorTotal),
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotal(NFCe nfce) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            _formatarMoeda(nfce.valorTotal),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Constrói formas de pagamento
  static pw.Widget _buildPagamento(NFCe nfce) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'FORMA DE PAGAMENTO',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        ...nfce.pagamentos.map((pag) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                pag.tipoDescricao,
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                _formatarMoeda(pag.valor),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          );
        }),
      ],
    );
  }

  /// Constrói QR Code
  static pw.Widget _buildQRCode(String qrCodeString) {
    // TODO: Implementar renderização do QR Code no PDF
    // Por enquanto, apenas texto
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'CONSULTE PELA CHAVE DE ACESSO',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            qrCodeString,
            style: const pw.TextStyle(fontSize: 6),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Constrói rodapé
  static pw.Widget _buildRodape(Empresa empresa) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(),
        pw.Text(
          'Documento Auxiliar da Nota Fiscal de Consumidor Eletrônica',
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Este documento não tem validade fiscal',
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// Formata CNPJ
  static String _formatarCNPJ(String cnpj) {
    final limpo = cnpj.replaceAll(RegExp(r'[^\d]'), '');
    if (limpo.length != 14) return cnpj;
    return '${limpo.substring(0, 2)}.${limpo.substring(2, 5)}.${limpo.substring(5, 8)}/${limpo.substring(8, 12)}-${limpo.substring(12)}';
  }

  /// Formata chave de acesso
  static String _formatarChaveAcesso(String chave) {
    if (chave.length != 44) return chave;
    return '${chave.substring(0, 4)} ${chave.substring(4, 8)} ${chave.substring(8, 12)} ${chave.substring(12, 16)} ${chave.substring(16, 20)} ${chave.substring(20, 24)} ${chave.substring(24, 28)} ${chave.substring(28, 32)} ${chave.substring(32, 36)} ${chave.substring(36, 40)} ${chave.substring(40, 44)}';
  }

  /// Formata data
  static String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  /// Formata moeda
  static String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Imprime DANFE
  static Future<void> imprimir({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir DANFE: $e');
    }
  }
}

