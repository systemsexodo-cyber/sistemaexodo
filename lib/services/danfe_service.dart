import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Adicionado para formatacao de valores monetarios
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../services/impressao_service.dart';


/// Serviço para geração do DANFE-NFC-e (Documento Auxiliar)
class DANFEService {
  /// Gera PDF do DANFE-NFC-e
  static Future<Uint8List> gerarPDF({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      if (_isNfeModelo55(nfce)) {
        return _gerarDanfeNfe(nfce: nfce, empresa: empresa);
      }

      final double margemEsq =
          (double.tryParse(
                empresa.configuracoes?['nfceMargemEsquerda']?.toString() ??
                    '5.0',
              ) ??
              5.0) *
          2.83465;
      final double margemDir =
          (double.tryParse(
                empresa.configuracoes?['nfceMargemDireita']?.toString() ??
                    '15.0',
              ) ??
              15.0) *
          2.83465;
      final double escalaFonte =
          double.tryParse(
            empresa.configuracoes?['nfceFonteEscala']?.toString() ?? '1.0',
          ) ??
          1.0;
      final double larguraBobina =
          double.tryParse(
            empresa.configuracoes?['nfceLarguraBobina']?.toString() ?? '80.0',
          ) ??
          80.0;

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            larguraBobina * 2.83465,
            double.infinity,
            marginAll: 0,
          ), // Altura infinita ajustável
          margin: pw.EdgeInsets.only(
            left: margemEsq,
            right: margemDir,
            top: 0,
            bottom: 0,
          ),
          build: (pw.Context context) {
            return pw.Align(
              alignment: pw.Alignment.topCenter,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisSize: pw.MainAxisSize.min, // Impede a coluna de esticar
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 5),
                  _buildCabecalho(empresa, escalaFonte),
                  _divider(),
                  pw.Text(
                    'DETALHE DA VENDA',
                    style: pw.TextStyle(
                      fontSize: 7.5 * escalaFonte,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  _buildCabecalhoItens(escalaFonte),
                  _buildItens(nfce, escalaFonte),
                  _divider(),
                  _buildTotalGeral(nfce, escalaFonte),
                  _divider(),
                  _buildPagamentos(nfce, escalaFonte),
                  _divider(),
                  _buildConsulta(nfce, escalaFonte),
                  _divider(),
                  _buildConsumidor(nfce, escalaFonte),
                  _divider(),
                  _buildDadosEmissao(nfce, escalaFonte),
                  _divider(),
                  if (nfce.qrCode != null && nfce.qrCode!.isNotEmpty) ...[
                    pw.Text(
                      'Consulta via leitor de QR Code',
                      style: pw.TextStyle(fontSize: 6.5 * escalaFonte),
                    ),
                    pw.SizedBox(height: 2),
                    _buildQRCode(nfce.qrCode!, escalaFonte),
                  ],
                  pw.SizedBox(height: 3),
                  _buildRodape(empresa, escalaFonte),
                ],
              ), // end Column
            ); // end Align
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar DANFE: $e');
    }
  }

  /// O campo modelo ocupa as posições 21 e 22 da chave de acesso.
  /// A entidade armazenada ainda se chama NFCe por compatibilidade, portanto
  /// a chave é a fonte segura para selecionar o layout correto do documento.
  static bool _isNfeModelo55(NFCe nota) {
    final chave = (nota.chaveAcesso ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return chave.length >= 22 && chave.substring(20, 22) == '55';
  }

  /// Gera DANFE A4 rico para NF-e modelo 55, seguindo o padrão oficial da SEFAZ
  static Future<Uint8List> _gerarDanfeNfe({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    final pdf = pw.Document();
    final chave = (nfce.chaveAcesso ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final destinatario = nfce.nomeConsumidor?.trim().isNotEmpty == true
        ? nfce.nomeConsumidor!.trim()
        : 'CONSUMIDOR FINAL';
    final documento = nfce.cpfCnpjConsumidor?.trim().isNotEmpty == true
        ? nfce.cpfCnpjConsumidor!.trim()
        : 'NÃO INFORMADO';

    // Formatar data de emissão para exibição
    final dataEmissaoStr = _formatarData(nfce.dataEmissao);
    
    // Buscar ou simular dados de endereço do destinatário
    String destEnd = 'NÃO INFORMADO';
    String destBairro = 'NÃO INFORMADO';
    String destCEP = 'NÃO INFORMADO';
    String destCid = 'NÃO INFORMADO';
    String destUF = 'SP';
    String destFone = 'NÃO INFORMADO';
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
        build: (context) => [
          // ─── 1. CANHOTO DE RECEBIMENTO ───
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.8),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 8,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'RECEBEMOS DE ${empresa.nomeExibicao.toUpperCase()} OS PRODUTOS/SERVIÇOS CONSTANTES NA NOTA FISCAL INDICADA AO LADO',
                          style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: _danfeSubCampo('DATA DE RECEBIMENTO', ''),
                            ),
                            pw.Expanded(
                              flex: 6,
                              child: _danfeSubCampo('IDENTIFICAÇÃO E ASSINATURA DO RECEBEDOR', ''),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Container(
                  width: 1,
                  height: 40,
                  color: PdfColors.black,
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'NF-e',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Nº: ${nfce.numero}',
                          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'SÉRIE: ${nfce.serie}',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Picotado / Linha divisória do Canhoto
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: List.generate(
                45,
                (index) => pw.Text('-', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
              ),
            ),
          ),

          // ─── 2. CABEÇALHO / LOGO / DADOS EMITENTE / QUADRO DANFE ───
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Identificação do Emitente
              pw.Expanded(
                flex: 5,
                child: pw.Container(
                  height: 100,
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        empresa.nomeExibicao.toUpperCase(),
                        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                        maxLines: 2,
                        overflow: pw.TextOverflow.clip,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        empresa.enderecoCompleto,
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      if (empresa.telefone != null && empresa.telefone!.isNotEmpty)
                        pw.Text(
                          'TEL/FAX: ${empresa.telefone}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      if (empresa.email != null && empresa.email!.isNotEmpty)
                        pw.Text(
                          'E-MAIL: ${empresa.email}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 4),
              // Bloco DANFE
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  height: 100,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'DANFE',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'DOCUMENTO AUXILIAR DA\nNOTA FISCAL ELETRÔNICA',
                        style: const pw.TextStyle(fontSize: 5.5, lineSpacing: 1.1),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            '0 - ENTRADA\n1 - SAÍDA',
                            style: const pw.TextStyle(fontSize: 6),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: PdfColors.black, width: 1),
                            ),
                            child: pw.Text(
                              '1',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Nº ${nfce.numero}\nSÉRIE ${nfce.serie}',
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 4),
              // Código de Barras e Chave de Acesso
              pw.Expanded(
                flex: 5,
                child: pw.Container(
                  height: 100,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: chave.isEmpty ? '00000000000000000000000000000000000000000000' : chave,
                        height: 28,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'CHAVE DE ACESSO',
                        style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        _formatarChaveAcesso(chave),
                        style: const pw.TextStyle(fontSize: 7.2),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Consulta de autenticidade no portal nacional da NF-e\nwww.nfe.fazenda.gov.br/portal ou no site da Sefaz Autorizadora',
                        style: const pw.TextStyle(fontSize: 5),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // ─── 3. CADASTRO / NATUREZA DA OPERAÇÃO ───
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 6,
                child: _danfeRetanguloField('NATUREZA DA OPERAÇÃO', 'VENDA DE MERCADORIA'),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 4,
                child: _danfeRetanguloField('PROTOCOLO DE AUTORIZAÇÃO DE USO', nfce.protocolo ?? 'Aguardando autorização da SEFAZ'),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                child: _danfeRetanguloField('INSCRIÇÃO ESTADUAL', empresa.inscricaoEstadual ?? 'ISENTO'),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: _danfeRetanguloField('INSCRIÇÃO ESTADUAL DO SUBST. TRIBUT.', ''),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: _danfeRetanguloField('CNPJ', empresa.cnpj != null ? _formatarCNPJ(empresa.cnpj!) : ''),
              ),
            ],
          ),

          // ─── 4. DESTINATÁRIO / REMETENTE ───
          pw.SizedBox(height: 6),
          _danfeDividerTitle('DESTINATÁRIO / REMETENTE'),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 6,
                child: _danfeRetanguloField('NOME / RAZÃO SOCIAL', destinatario),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 3,
                child: _danfeRetanguloField('CNPJ / CPF', documento),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 2,
                child: _danfeRetanguloField('DATA DA EMISSÃO', dataEmissaoStr),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 6,
                child: _danfeRetanguloField('ENDEREÇO', destEnd),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 3,
                child: _danfeRetanguloField('BAIRRO / DISTRITO', destBairro),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 2,
                child: _danfeRetanguloField('CEP', destCEP),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 5,
                child: _danfeRetanguloField('MUNICÍPIO', destCid),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 2,
                child: _danfeRetanguloField('FONE / FAX', destFone),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 1,
                child: _danfeRetanguloField('UF', destUF),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 3,
                child: _danfeRetanguloField('INSCRIÇÃO ESTADUAL', 'ISENTO'),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 2,
                child: _danfeRetanguloField('HORA DA SAÍDA', ''),
              ),
            ],
          ),

          // ─── 5. CÁLCULO DO IMPOSTO ───
          pw.SizedBox(height: 6),
          _danfeDividerTitle('CÁLCULO DO IMPOSTO'),
          pw.Row(
            children: [
              pw.Expanded(child: _danfeRetanguloField('BASE DE CÁLCULO DO ICMS', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR DO ICMS', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('BASE DE CÁLC. ICMS S.T.', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR DO ICMS SUBST.', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR APROX. TRIBUTOS', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR TOTAL DOS PRODUTOS', _formatarMoeda(nfce.valorTotal))),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: _danfeRetanguloField('VALOR DO FRETE', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR DO SEGURO', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('DESCONTO', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('OUTRAS DESP. ACESSÓRIAS', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('VALOR DO IPI', 'R\$ 0,00')),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('VALOR TOTAL DA NOTA', style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold)),
                      pw.Align(
                        alignment: pw.Alignment.bottomRight,
                        child: pw.Text(_formatarMoeda(nfce.valorTotal), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ─── 6. TRANSPORTADOR / VOLUMES TRANSPORTADOS ───
          pw.SizedBox(height: 6),
          _danfeDividerTitle('TRANSPORTADOR / VOLUMES TRANSPORTADOS'),
          pw.Row(
            children: [
              pw.Expanded(flex: 5, child: _danfeRetanguloField('NOME / RAZÃO SOCIAL', 'SEM FRETE')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 2, child: _danfeRetanguloField('FRETE POR CONTA', '9 - Sem Frete')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 2, child: _danfeRetanguloField('CÓDIGO ANTT', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 2, child: _danfeRetanguloField('PLACA DO VEÍC.', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 1, child: _danfeRetanguloField('UF', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 3, child: _danfeRetanguloField('CNPJ / CPF', '')),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(flex: 6, child: _danfeRetanguloField('ENDEREÇO', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 4, child: _danfeRetanguloField('MUNICÍPIO', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 1, child: _danfeRetanguloField('UF', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(flex: 3, child: _danfeRetanguloField('INSCRIÇÃO ESTADUAL', '')),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: _danfeRetanguloField('QUANTIDADE', '0')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('ESPÉCIE', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('MARCA', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('NUMERAÇÃO', '')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('PESO BRUTO', '0,000 kg')),
              pw.SizedBox(width: 4),
              pw.Expanded(child: _danfeRetanguloField('PESO LÍQUIDO', '0,000 kg')),
            ],
          ),

          // ─── 7. DADOS DOS PRODUTOS / SERVIÇOS ───
          pw.SizedBox(height: 6),
          _danfeDividerTitle('DADOS DOS PRODUTOS / SERVIÇOS'),
          pw.TableHelper.fromTextArray(
            headers: const [
              'CÓD. PROD.',
              'DESCRIÇÃO DO PRODUTO / SERVIÇO',
              'NCM/SH',
              'CST',
              'CFOP',
              'UNID.',
              'QUANT.',
              'VALOR UNIT.',
              'VALOR TOTAL',
              'B. CALC. ICMS',
              'VALOR ICMS',
              'VALOR IPI',
              'ALÍQ. ICMS %',
              'ALÍQ. IPI %',
            ],
            data: nfce.itens
                .map(
                  (item) => [
                    item.codigo,
                    item.descricao.toUpperCase(),
                    item.ncm,
                    '0400', // Simula o CSOSN/CST do Simples
                    item.cfop,
                    item.unidade,
                    item.quantidade.toStringAsFixed(2),
                    _formatarMoedaSemSimbolo(item.valorUnitario),
                    _formatarMoedaSemSimbolo(item.valorTotal),
                    '0,00',
                    '0,00',
                    '0,00',
                    '0,00',
                    '0,00',
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 4.8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 4.8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
              11: pw.Alignment.centerRight,
              12: pw.Alignment.centerRight,
              13: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8), // Cod
              1: const pw.FlexColumnWidth(2.8), // Descrição
              2: const pw.FlexColumnWidth(0.7), // NCM
              3: const pw.FlexColumnWidth(0.4), // CST
              4: const pw.FlexColumnWidth(0.4), // CFOP
              5: const pw.FlexColumnWidth(0.4), // Unid
              6: const pw.FlexColumnWidth(0.6), // Qtd
              7: const pw.FlexColumnWidth(0.8), // VUnit
              8: const pw.FlexColumnWidth(0.8), // VTotal
              9: const pw.FlexColumnWidth(0.8), // BC ICMS
              10: const pw.FlexColumnWidth(0.7), // VIcms
              11: const pw.FlexColumnWidth(0.6), // VIpi
              12: const pw.FlexColumnWidth(0.6), // Aliq Icms
              13: const pw.FlexColumnWidth(0.6), // Aliq Ipi
            },
          ),

          // ─── 8. DADOS ADICIONAIS / INFORMAÇÕES COMPLEMENTARES ───
          pw.SizedBox(height: 6),
          _danfeDividerTitle('DADOS ADICIONAIS'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 7,
                child: _danfeRetanguloField(
                  'INFORMAÇÕES COMPLEMENTARES',
                  'DOCUMENTO EMITIDO POR ME/EPP OPTANTE PELO SIMPLES NACIONAL. NÃO GERA DIREITO A CRÉDITO FISCAL DE IPI.\n'
                  'NF-e EMITIDA EM AMBIENTE DE HOMOLOGAÇÃO - SEM VALOR FISCAL.\n'
                  'Informações de interesse do emissor: Venda registrada no PDV Êxodo. Obrigado pela preferência!',
                  altura: 70,
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                flex: 3,
                child: _danfeRetanguloField(
                  'RESERVADO AO FISCO',
                  '',
                  altura: 70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // --- MÉTODOS DE RENDERIZAÇÃO ESTILIZADOS PARA A4 (DESIGN OFICIAL) ---
  
  static pw.Widget _danfeDividerTitle(String titulo) {
    return pw.Container(
      width: double.infinity,
      color: PdfColors.white,
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(
        titulo,
        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _danfeRetanguloField(String rotulo, String valor, {double? altura}) {
    return pw.Container(
      height: altura ?? 26,
      width: double.infinity,
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            rotulo,
            style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
          pw.SizedBox(height: 1),
          pw.Expanded(
            child: pw.Text(
              valor,
              style: const pw.TextStyle(fontSize: 7.2),
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _danfeSubCampo(String rotulo, String valor) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          rotulo,
          style: const pw.TextStyle(fontSize: 5),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          valor,
          style: const pw.TextStyle(fontSize: 7),
        ),
      ],
    );
  }

  static String _formatarMoedaSemSimbolo(double valor) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: '').format(valor).trim();
  }


  static pw.Widget _danfeBox(pw.Widget child) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: .6),
    ),
    child: child,
  );

  static pw.Widget _danfeTitulo(String titulo) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    color: PdfColors.grey300,
    child: pw.Text(
      titulo,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _danfeCampo(String rotulo, String valor) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(rotulo, style: const pw.TextStyle(fontSize: 6)),
        pw.Text(valor, style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  );

  static pw.Widget _danfeResumo(
    String rotulo,
    double valor, {
    bool destaque = false,
  }) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        rotulo,
        style: pw.TextStyle(
          fontSize: destaque ? 9 : 8,
          fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
      pw.Text(
        _formatarMoeda(valor),
        style: pw.TextStyle(
          fontSize: destaque ? 9 : 8,
          fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ],
  );

  static pw.Widget _divider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Divider(
        color: PdfColors.grey700,
        thickness: 0.5,
        borderStyle: pw.BorderStyle.dashed,
      ),
    );
  }

  /// Constrói cabeçalho do DANFE
  static pw.Widget _buildCabecalho(Empresa empresa, double escala) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          empresa.nomeExibicao.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 9.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.cnpj != null)
          pw.Text(
            'CNPJ: ${_formatarCNPJ(empresa.cnpj!)}',
            style: pw.TextStyle(
              fontSize: 5.5 * escala,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
        if (empresa.inscricaoEstadual != null)
          pw.Text(
            'I.E.: ${empresa.inscricaoEstadual}',
            style: pw.TextStyle(fontSize: 6.5 * escala),
          ),
        if (empresa.enderecoCompleto.isNotEmpty)
          pw.Text(
            empresa.enderecoCompleto,
            style: pw.TextStyle(fontSize: 5.5 * escala),
            textAlign: pw.TextAlign.center,
          ),
        if (empresa.telefone != null && empresa.telefone != '')
          pw.Text(
            'Fone: ${empresa.telefone}',
            style: pw.TextStyle(fontSize: 6.5 * escala),
          ),
      ],
    );
  }

  static pw.Widget _buildCabecalhoItens(double escala) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              'CÓDIGO DESCRIÇÃO',
              style: pw.TextStyle(
                fontSize: 5.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              'QTD',
              style: pw.TextStyle(
                fontSize: 5.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              'UN',
              style: pw.TextStyle(
                fontSize: 5.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              'V.UN',
              style: pw.TextStyle(
                fontSize: 5.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'V.TOT',
              style: pw.TextStyle(
                fontSize: 5.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói itens da NFC-e
  static pw.Widget _buildItens(NFCe nfce, double escala) {
    return pw.Column(
      children: nfce.itens.map((item) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${item.codigo} ${item.descricao}',
              style: pw.TextStyle(fontSize: 6.5 * escala),
            ),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: pw.SizedBox()),
                pw.Expanded(
                  child: pw.Text(
                    item.quantidade.toStringAsFixed(2),
                    style: pw.TextStyle(fontSize: 5.5 * escala),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    item.unidade,
                    style: pw.TextStyle(fontSize: 5.5 * escala),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    item.valorUnitario.toStringAsFixed(2),
                    style: pw.TextStyle(fontSize: 5.5 * escala),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    item.valorTotal.toStringAsFixed(2),
                    style: pw.TextStyle(fontSize: 6.5 * escala),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotalGeral(NFCe nfce, double escala) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'QTD. TOTAL DE ITENS',
              style: pw.TextStyle(fontSize: 6.5 * escala),
            ),
            pw.Text(
              nfce.itens.length.toString(),
              style: pw.TextStyle(fontSize: 6.5 * escala),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'VALOR DOS PRODUTOS',
              style: pw.TextStyle(fontSize: 6.5 * escala),
            ),
            pw.Text(
              _formatarMoeda(nfce.valorTotal),
              style: pw.TextStyle(fontSize: 6.5 * escala),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'VALOR TOTAL R\$',
              style: pw.TextStyle(
                fontSize: 7.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              _formatarMoeda(nfce.valorTotal),
              style: pw.TextStyle(
                fontSize: 7.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Constrói formas de pagamento
  static pw.Widget _buildPagamentos(NFCe nfce, double escala) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'FORMA DE PAGAMENTO',
              style: pw.TextStyle(
                fontSize: 6.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'VALOR PAGO',
              style: pw.TextStyle(
                fontSize: 6.5 * escala,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        ...nfce.pagamentos.map((pag) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                pag.tipoDescricao.toUpperCase(),
                style: pw.TextStyle(fontSize: 6.5 * escala),
              ),
              pw.Text(
                _formatarMoeda(pag.valor),
                style: pw.TextStyle(fontSize: 6.5 * escala),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildConsulta(NFCe nfce, double escala) {
    return pw.Column(
      children: [
        pw.Text(
          'CONSULTA PELA CHAVE DE ACESSO:',
          style: pw.TextStyle(
            fontSize: 5.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          'www.nfe.fazenda.sp.gov.br',
          style: pw.TextStyle(fontSize: 5.5 * escala),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'CHAVE DE ACESSO',
          style: pw.TextStyle(
            fontSize: 5.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          _formatarChaveAcesso(
            nfce.chaveAcesso ??
                '0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000',
          ),
          style: pw.TextStyle(fontSize: 5.5 * escala),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static pw.Widget _buildConsumidor(NFCe nfce, double escala) {
    return pw.Column(
      children: [
        pw.Text(
          'CONSUMIDOR',
          style: pw.TextStyle(
            fontSize: 6.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          nfce.cpfCnpjConsumidor != null
              ? 'CNPJ/CPF: ${nfce.cpfCnpjConsumidor}'
              : 'NOME: ${nfce.nomeConsumidor ?? "NÃO IDENTIFICADO"}',
          style: pw.TextStyle(fontSize: 6.5 * escala),
        ),
      ],
    );
  }

  static pw.Widget _buildDadosEmissao(NFCe nfce, double escala) {
    final bool isContingencia = nfce.status == 'contingencia';
    return pw.Column(
      children: [
        if (isContingencia) ...[
          pw.Text(
            'EMITIDA EM CONTINGÊNCIA',
            style: pw.TextStyle(
              fontSize: 8.5 * escala,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Pendente de autorização',
            style: pw.TextStyle(
              fontSize: 7.0 * escala,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.Text(
          'Nº ${nfce.numero}  Série ${nfce.serie}',
          style: pw.TextStyle(
            fontSize: 7.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          '${_formatarData(nfce.dataEmissao)} - Via Consumidor',
          style: pw.TextStyle(fontSize: 6.5 * escala),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          isContingencia
              ? 'EMISSÃO EM CONTINGÊNCIA'
              : 'PROTOCOLO DE AUTORIZAÇÃO',
          style: pw.TextStyle(
            fontSize: 6.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Text(
          isContingencia
              ? 'Aguardando transmissão'
              : '${nfce.protocolo ?? "Aguardando..."} - ${_formatarData(nfce.dataEmissao)}',
          style: pw.TextStyle(fontSize: 6.5 * escala),
        ),
      ],
    );
  }

  /// Constrói QR Code
  static pw.Widget _buildQRCode(String qrCodeString, double escala) {
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
  static pw.Widget _buildRodape(Empresa empresa, double escala) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'Não permite aproveitamento de crédito de ICMS',
          style: pw.TextStyle(
            fontSize: 6.5 * escala,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Documento Auxiliar da Nota Fiscal de Consumidor Eletrônica',
          style: pw.TextStyle(fontSize: 5.5 * escala),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Esta nota foi emitida pelo Sistema Exodo',
          style: pw.TextStyle(
            fontSize: 5.5 * escala,
            fontStyle: pw.FontStyle.italic,
          ),
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
    BuildContext? context,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
      await ImpressaoService.imprimirPdf(
        bytes: pdfBytes,
        empresa: empresa,
        name: 'DANFE_${nfce.numero}',
        termico: true,
        context: context,
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
        throw Exception(
          'Salvamento de arquivo não suportado em web. Use visualizarPDF() ou downloadPDF().',
        );
      }

      // Obter diretório de documentos
      final directory = await getApplicationDocumentsDirectory();
      final nfceDir = Directory('${directory.path}/nfce_pdfs');
      if (!await nfceDir.exists()) {
        await nfceDir.create(recursive: true);
      }

      // Nome do arquivo: NFCe_NUMERO_SERIE_DATA.pdf
      final dataFormatada =
          '${nfce.dataEmissao.year}${nfce.dataEmissao.month.toString().padLeft(2, '0')}${nfce.dataEmissao.day.toString().padLeft(2, '0')}';
      final nomeArquivo =
          'NFCe_${nfce.numero}_${nfce.serie}_$dataFormatada.pdf';
      final arquivo = File('${nfceDir.path}/$nomeArquivo');

      await arquivo.writeAsBytes(pdfBytes);

      return arquivo.path;
    } catch (e) {
      throw Exception('Erro ao salvar PDF do DANFE: $e');
    }
  }

  /// Visualiza PDF do DANFE de forma interativa
  static Future<void> visualizarPDF({
    BuildContext? context,
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      if (context != null) {
        // Abre uma página com visualização interativa do PDF (DANFE)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(
                  _isNfeModelo55(nfce)
                      ? 'Visualizar DANFE NF-e (Modelo 55)'
                      : 'Visualizar DANFE NFC-e (Modelo 65)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: const Color(0xFF1E1E2E),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    tooltip: 'Compartilhar',
                    onPressed: () => compartilharPDF(nfce: nfce, empresa: empresa),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    tooltip: 'Download',
                    onPressed: () async {
                      final path = await downloadPDF(nfce: nfce, empresa: empresa);
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ PDF salvo em: $path'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              body: Container(
                color: const Color(0xFF13131A),
                child: PdfPreview(
                  build: (format) => gerarPDF(nfce: nfce, empresa: empresa),
                  allowPrinting: true,
                  allowSharing: true,
                  canChangePageFormat: false,
                  initialPageFormat: _isNfeModelo55(nfce) ? PdfPageFormat.a4 : PdfPageFormat.roll80,
                  pdfFileName: 'DANFE_${nfce.numero}.pdf',
                  loadingWidget: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.blueAccent,
                    ),
                  ),
                  actions: const [],
                ),
              ),
            ),
          ),
        );
      } else {
        final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
      }
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
        final arquivo = File(
          '${directory.path}/NFCe_${nfce.numero}_${nfce.serie}.pdf',
        );
        await arquivo.writeAsBytes(pdfBytes);

        final xFile = XFile(arquivo.path);
        await Share.shareXFiles([
          xFile,
        ], text: 'DANFE NFC-e Nº ${nfce.numero} - ${empresa.nomeExibicao}');
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
      final corpo =
          '''
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
        queryParameters: {'subject': assunto, 'body': corpo},
      );

      // Abrir cliente de email
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        throw Exception(
          'Não foi possível abrir o cliente de email. Verifique se há um aplicativo de email configurado.',
        );
      }

      // Nota: Em algumas plataformas, o anexo pode não funcionar via mailto
      // Para anexo real, seria necessário usar um serviço de email (SMTP) ou API
    } catch (e) {
      throw Exception('Erro ao enviar PDF por email: $e');
    }
  }

  /// Faz backup do PDF no Supabase Storage
  static Future<String> fazerBackupSupabase({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(nfce: nfce, empresa: empresa);

      final dataFormatada =
          '${nfce.dataEmissao.year}${nfce.dataEmissao.month.toString().padLeft(2, '0')}${nfce.dataEmissao.day.toString().padLeft(2, '0')}';
      final nomeArquivo =
          'NFCe_${nfce.numero}_${nfce.serie}_$dataFormatada.pdf';
      final caminhoStorage = '${empresa.id}/$nomeArquivo';

      final publicUrl = await SupabaseService.instance.uploadFile(
        'nfces', // Bucket específico para NFC-e
        caminhoStorage,
        pdfBytes,
        contentType: 'application/pdf',
      );

      if (publicUrl == null)
        throw Exception('Falha ao obter URL pública do PDF');

      return publicUrl;
    } catch (e) {
      throw Exception('Erro ao fazer backup no Supabase: $e');
    }
  }
}
