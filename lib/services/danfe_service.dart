import 'dart:typed_data';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
          pageFormat: const PdfPageFormat(80 * 2.83465, 400 * 2.83465), // 80mm x 400mm (térmica)
          margin: const pw.EdgeInsets.all(5),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _buildCabecalho(empresa),
                _divider(),
                pw.Text(
                  'DETALHE DA VENDA',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                _buildCabecalhoItens(),
                _buildItens(nfce),
                _divider(),
                _buildTotalGeral(nfce),
                _divider(),
                _buildPagamentos(nfce),
                _divider(),
                _buildConsulta(nfce),
                _divider(),
                _buildConsumidor(nfce),
                _divider(),
                _buildDadosEmissao(nfce),
                _divider(),
                if (nfce.qrCode != null && nfce.qrCode!.isNotEmpty) ...[
                  pw.Text(
                    'Consulta via leitor de QR Code',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(height: 5),
                  _buildQRCode(nfce.qrCode!),
                ],
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

  static pw.Widget _divider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        '------------------------------------------------------------',
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  /// Constrói cabeçalho do DANFE
  static pw.Widget _buildCabecalho(Empresa empresa) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          empresa.nomeExibicao.toUpperCase(),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.cnpj != null)
          pw.Text(
            'CNPJ: ${_formatarCNPJ(empresa.cnpj!)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
        if (empresa.inscricaoEstadual != null)
          pw.Text(
             'I.E.: ${empresa.inscricaoEstadual}',
             style: const pw.TextStyle(fontSize: 8),
          ),
        if (empresa.enderecoCompleto.isNotEmpty)
          pw.Text(
            empresa.enderecoCompleto,
            style: const pw.TextStyle(fontSize: 7),
            textAlign: pw.TextAlign.center,
          ),
        if (empresa.telefone != null && empresa.telefone != '')
          pw.Text(
            'Fone: ${empresa.telefone}',
            style: const pw.TextStyle(fontSize: 8),
          ),
      ],
    );
  }

  static pw.Widget _buildCabecalhoItens() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text('CÓDIGO DESCRIÇÃO', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Text('QTD', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          ),
          pw.Expanded(
            child: pw.Text('UN', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          ),
          pw.Expanded(
            child: pw.Text('V.UN', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text('V.TOT', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// Constrói itens da NFC-e
  static pw.Widget _buildItens(NFCe nfce) {
    return pw.Column(
      children: nfce.itens.map((item) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${item.codigo} ${item.descricao}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: pw.SizedBox()),
                pw.Expanded(
                  child: pw.Text(item.quantidade.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                ),
                pw.Expanded(
                  child: pw.Text(item.unidade, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                ),
                pw.Expanded(
                  child: pw.Text(item.valorUnitario.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.right),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(item.valorTotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right),
                ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotalGeral(NFCe nfce) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('QTD. TOTAL DE ITENS', style: const pw.TextStyle(fontSize: 8)),
            pw.Text(nfce.itens.length.toString(), style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('VALOR DOS PRODUTOS', style: const pw.TextStyle(fontSize: 8)),
            pw.Text(_formatarMoeda(nfce.valorTotal), style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('VALOR TOTAL R\$', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(_formatarMoeda(nfce.valorTotal), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  /// Constrói formas de pagamento
  static pw.Widget _buildPagamentos(NFCe nfce) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('FORMA DE PAGAMENTO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Text('VALOR PAGO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        ...nfce.pagamentos.map((pag) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(pag.tipoDescricao.toUpperCase(), style: const pw.TextStyle(fontSize: 8)),
              pw.Text(_formatarMoeda(pag.valor), style: const pw.TextStyle(fontSize: 8)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildConsulta(NFCe nfce) {
    return pw.Column(
      children: [
        pw.Text('CONSULTA PELA CHAVE DE ACESSO:', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text('www.nfe.fazenda.sp.gov.br', style: const pw.TextStyle(fontSize: 7)),
        pw.SizedBox(height: 2),
        pw.Text('CHAVE DE ACESSO', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          _formatarChaveAcesso(nfce.chaveAcesso ?? '0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000'),
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static pw.Widget _buildConsumidor(NFCe nfce) {
    return pw.Column(
      children: [
        pw.Text('CONSUMIDOR', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          nfce.cpfCnpjConsumidor != null 
            ? 'CNPJ/CPF: ${nfce.cpfCnpjConsumidor}' 
            : 'NOME: ${nfce.nomeConsumidor ?? "NÃO IDENTIFICADO"}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  static pw.Widget _buildDadosEmissao(NFCe nfce) {
    return pw.Column(
      children: [
        pw.Text(
          'Nº  Série ${nfce.serie}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${_formatarData(nfce.dataEmissao)} - Via Consumidor',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 2),
        pw.Text('PROTOCOLO DE AUTORIZAÇÃO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text(
          '${nfce.protocolo ?? "Aguardando..."} - ${_formatarData(nfce.dataEmissao)}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  /// Constrói QR Code
  static pw.Widget _buildQRCode(String qrCodeString) {
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: qrCodeString,
        width: 100,
        height: 100,
      ),
    );
  }

  /// Constrói rodapé
  static pw.Widget _buildRodape(Empresa empresa) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Não permite aproveitamento de crédito de ICMS',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Documento Auxiliar da Nota Fiscal de Consumidor Eletrônica',
          style: const pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Esta nota foi emitida pelo Sistema Exodo',
          style: const pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
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

  /// Salva PDF do DANFE em arquivo
  static Future<String> salvarPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      
      if (kIsWeb) {
        // Em web, não podemos salvar arquivo diretamente
        // Retornar dados base64 para download
        throw Exception('Salvamento de arquivo não suportado em web. Use visualizarPDF() ou downloadPDF().');
      }
      
      // Obter diretório de documentos
      final directory = await getApplicationDocumentsDirectory();
      final nfceDir = Directory('${directory.path}/nfce_pdfs');
      if (!await nfceDir.exists()) {
        await nfceDir.create(recursive: true);
      }
      
      // Nome do arquivo: NFCe_NUMERO_SERIE_DATA.pdf
      final dataFormatada = '${nfce.dataEmissao.year}${nfce.dataEmissao.month.toString().padLeft(2, '0')}${nfce.dataEmissao.day.toString().padLeft(2, '0')}';
      final nomeArquivo = 'NFCe_${nfce.numero}_${nfce.serie}_$dataFormatada.pdf';
      final arquivo = File('${nfceDir.path}/$nomeArquivo');
      
      await arquivo.writeAsBytes(pdfBytes);
      
      return arquivo.path;
    } catch (e) {
      throw Exception('Erro ao salvar PDF do DANFE: $e');
    }
  }

  /// Visualiza PDF do DANFE
  static Future<void> visualizarPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      throw Exception('Erro ao visualizar PDF do DANFE: $e');
    }
  }

  /// Faz download do PDF (web) ou salva (desktop/mobile)
  static Future<String?> downloadPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      
      if (kIsWeb) {
        // Em web, usar Printing para download
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
        return null;
      } else {
        // Em desktop/mobile, salvar arquivo
        final caminho = await salvarPDF(nfce: nfce, empresa: empresa);
        return caminho;
      }
    } catch (e) {
      throw Exception('Erro ao fazer download do PDF: $e');
    }
  }

  /// Compartilha PDF via WhatsApp, Email, etc.
  static Future<void> compartilharPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      
      // Criar arquivo temporário para compartilhamento
      if (kIsWeb) {
        // Em web, usar XFile com bytes
        final xFile = XFile.fromData(
          pdfBytes,
          name: 'NFCe_${nfce.numero}_${nfce.serie}.pdf',
          mimeType: 'application/pdf',
        );
        await Share.shareXFiles([xFile], text: 'DANFE NFC-e ${nfce.numero}');
      } else {
        // Em desktop/mobile, salvar temporariamente e compartilhar
        final directory = await getTemporaryDirectory();
        final arquivo = File('${directory.path}/NFCe_${nfce.numero}_${nfce.serie}.pdf');
        await arquivo.writeAsBytes(pdfBytes);
        
        final xFile = XFile(arquivo.path);
        await Share.shareXFiles(
          [xFile],
          text: 'DANFE NFC-e Nº ${nfce.numero} - ${empresa.nomeExibicao}',
        );
      }
    } catch (e) {
      throw Exception('Erro ao compartilhar PDF: $e');
    }
  }

  /// Envia PDF por email usando mailto
  static Future<void> enviarPorEmail({
    required NFCe nfce,
    required Empresa empresa,
    String? emailDestinatario,
  }) async {
    try {
      // Salvar PDF primeiro
      final caminhoPDF = await salvarPDF(nfce: nfce, empresa: empresa);
      
      // Montar assunto e corpo do email
      final assunto = 'DANFE NFC-e Nº ${nfce.numero} - ${empresa.nomeExibicao}';
      final corpo = '''
Olá,

Segue em anexo o DANFE da NFC-e emitida.

Dados da NFC-e:
- Número: ${nfce.numero}
- Série: ${nfce.serie}
- Data de Emissão: ${_formatarData(nfce.dataEmissao)}
- Valor Total: ${_formatarMoeda(nfce.valorTotal)}
${nfce.chaveAcesso != null ? '- Chave de Acesso: ${_formatarChaveAcesso(nfce.chaveAcesso!)}' : ''}

Este é um email automático do sistema ${empresa.nomeExibicao}.

Atenciosamente,
Sistema Exodo
      ''';
      
      // Criar URL mailto
      final emailUri = Uri(
        scheme: 'mailto',
        path: emailDestinatario ?? empresa.email ?? '',
        queryParameters: {
          'subject': assunto,
          'body': corpo,
        },
      );
      
      // Abrir cliente de email
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        throw Exception('Não foi possível abrir o cliente de email. Verifique se há um aplicativo de email configurado.');
      }
      
      // Nota: Em algumas plataformas, o anexo pode não funcionar via mailto
      // Para anexo real, seria necessário usar um serviço de email (SMTP) ou API
    } catch (e) {
      throw Exception('Erro ao enviar PDF por email: $e');
    }
  }

  /// Faz backup do PDF no Firebase Storage
  static Future<String> fazerBackupFirebase({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      
      // Criar referência no Firebase Storage
      final storage = FirebaseStorage.instance;
      final dataFormatada = '${nfce.dataEmissao.year}${nfce.dataEmissao.month.toString().padLeft(2, '0')}${nfce.dataEmissao.day.toString().padLeft(2, '0')}';
      final nomeArquivo = 'NFCe_${nfce.numero}_${nfce.serie}_$dataFormatada.pdf';
      final caminhoStorage = 'nfce_pdfs/${empresa.id}/$nomeArquivo';
      
      final ref = storage.ref().child(caminhoStorage);
      
      // Upload do PDF
      final uploadTask = ref.putData(
        pdfBytes,
        SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'numero': nfce.numero,
            'serie': nfce.serie,
            'empresa_id': empresa.id,
            'data_emissao': nfce.dataEmissao.toIso8601String(),
            'valor_total': nfce.valorTotal.toString(),
            'chave_acesso': nfce.chaveAcesso ?? '',
          },
        ),
      );
      
      // Aguardar conclusão do upload
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      throw Exception('Erro ao fazer backup no Firebase: $e');
    }
  }
}

