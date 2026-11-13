// Importação de PRODUTOS a partir do CSV do sistema antigo ("e o bicho").
//
// O export de lá sai em CSV: separador ";", UTF-8 com BOM, aspas nos campos e
// 17 colunas — formato que o importador antigo recusava (lia só Excel). Estes
// testes atravessam o caminho inteiro (ler → achar o cabeçalho → mapear as
// colunas → montar o produto com os impostos) SEM gravar nada no banco.
//
// Rodar: flutter test test/excel_import_service_csv_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/excel_import_service.dart';

/// Cabeçalho e linhas REAIS do export do sistema antigo (produtos..csv):
/// as 17 colunas na ordem original, acento no cabeçalho, "%" na alíquota e
/// aspas em alguns campos.
const String _csvReal =
    'Código;Nome do Produto;Unidade;Quantidade;Preço Custo;Preço Venda;'
    'TABELA 2;Total Preço Venda;Total Preço Custo;Código de Barras;NCM;CFOP;'
    'CST;CSOSN;Grupo;Descrição;Alíq. ICMS\r\n'
    '1475;1/2 Tubo Cristal/Verde;UN;1;0.00;1.00;-;1.00;0.00;;95072000;5102;60;'
    '500;AQUARISMO/PEIXES/REPTEIS;1/2 Tubo Cristal/Verde;18.00%\r\n'
    '1476;100 Ps Peito Seco;UN;0;0.00;15.16;-;0.00;0.00;;95072000;5102;60;500;'
    'AVES/ACESS/RACOES;100 Ps Peito Seco;18.00%\r\n'
    '6305;"AGULHA 20X5,5";UN;100;0.14;2.00;-;200.00;14.00;;90183219;5102;00;'
    '102;Medicamentos;;18.00%';

/// Lê um CSV como o importador de verdade, com o BOM que o Windows grava.
Future<Map<String, dynamic>> _planejarCsv(
  String csv, {
  List<Produto> existentes = const <Produto>[],
}) {
  final bytes = Uint8List.fromList(utf8.encode('\ufeff$csv'));
  return ExcelImportService.planejarProdutosDeBytes(
    bytes,
    existentes: existentes,
  );
}

void main() {
  test('CSV do sistema antigo: as 17 colunas viram produto com impostos', () async {
    final resultado = await _planejarCsv(_csvReal);

    expect(resultado['erros'], 0, reason: resultado['mensagens'].toString());
    expect(resultado['duplicados'], 0);
    expect(resultado['sucesso'], 3);

    final novos = resultado['novos'] as List<Produto>;
    expect(novos, hasLength(3));

    final tubo = novos.firstWhere((p) => p.nome == '1/2 Tubo Cristal/Verde');

    // Cadastro básico
    expect(tubo.codigo, 'COD-1475');
    expect(tubo.unidade, 'UN');
    expect(tubo.estoque, 1.0);
    expect(tubo.grupo, 'AQUARISMO/PEIXES/REPTEIS');
    expect(tubo.descricao, '1/2 Tubo Cristal/Verde');
    expect(tubo.codigoBarras, isNull, reason: 'coluna de barras vazia no arquivo');

    // Preços (as colunas de TOTAL não podem sequestrar o preço unitário)
    expect(tubo.preco, closeTo(1.0, 0.0001));
    expect(tubo.precoCusto, closeTo(0.0, 0.0001));

    // Fiscais
    expect(tubo.ncm, '95072000');
    expect(tubo.cfop, '5102');
    expect(tubo.icmsCst, '60', reason: 'coluna "CST" pura tem que virar icmsCst');
    expect(tubo.csosn, '500');
    expect(tubo.icmsAliquota, closeTo(18.0, 0.0001), reason: '"18.00%" → 18.0');

    // Segunda linha: preço com centavos e estoque zerado
    final peito = novos.firstWhere((p) => p.codigo == 'COD-1476');
    expect(peito.preco, closeTo(15.16, 0.0001));
    expect(peito.precoCusto, closeTo(0.0, 0.0001));
    expect(peito.estoque, 0.0);
  });

  test('campo entre aspas com vírgula e coluna de descrição vazia', () async {
    final resultado = await _planejarCsv(_csvReal);

    final agulha =
        (resultado['novos'] as List<Produto>).firstWhere((p) => p.codigo == 'COD-6305');

    expect(agulha.nome, 'AGULHA 20X5,5', reason: 'a vírgula fica dentro do nome');
    expect(agulha.descricao, isNull, reason: 'coluna Descrição veio vazia');
    expect(agulha.grupo, 'Medicamentos');
    expect(agulha.estoque, 100.0);
    expect(agulha.preco, closeTo(2.0, 0.0001));
    expect(agulha.precoCusto, closeTo(0.14, 0.0001));
    expect(agulha.ncm, '90183219');
    expect(agulha.icmsCst, '00');
    expect(agulha.csosn, '102');
    expect(agulha.icmsAliquota, closeTo(18.0, 0.0001));
  });

  test('ponto e vírgula DENTRO de aspas não quebra a linha', () async {
    const csv =
        'Código;Nome;Preço Venda;Preço Custo;Descrição\r\n'
        '1;"PANO DE PRATO; VERMELHO";3,50;1,20;"Teclado ; mouse ; cabo"';

    final resultado = await _planejarCsv(csv);

    expect(resultado['erros'], 0, reason: resultado['mensagens'].toString());
    final produto = (resultado['novos'] as List<Produto>).single;
    expect(produto.nome, 'PANO DE PRATO; VERMELHO');
    expect(produto.descricao, 'Teclado ; mouse ; cabo');
    expect(produto.preco, closeTo(3.5, 0.0001));
    expect(produto.precoCusto, closeTo(1.2, 0.0001));
  });

  test('"Total Preço Venda/Custo" não sequestra o preço unitário', () async {
    // Mesmo relatório, só que com as colunas de TOTAL antes das unitárias.
    const csv =
        'Codigo;Nome;Total Preço Venda;Total Preço Custo;Preço Venda;Preço Custo\r\n'
        '10;PRODUTO TESTE;500,00;300,00;50,00;30,00';

    final resultado = await _planejarCsv(csv);

    expect(resultado['erros'], 0, reason: resultado['mensagens'].toString());
    final produto = (resultado['novos'] as List<Produto>).single;
    expect(produto.preco, closeTo(50.0, 0.0001),
        reason: 'tem que pegar o preço unitário, não a soma da quantidade');
    expect(produto.precoCusto, closeTo(30.0, 0.0001));
  });

  test('CSV salvo em ANSI (pt-BR sem BOM) também é lido', () async {
    const csv = 'Código;Nome;Preço Venda\r\n1;AÇÃO DE GRÃOS;10,50';
    // Latin1/Windows-1252: é o que o "Salvar como" antigo do Windows gera.
    final bytes = Uint8List.fromList(latin1.encode(csv));

    final resultado = await ExcelImportService.planejarProdutosDeBytes(bytes);

    expect(resultado['erros'], 0, reason: resultado['mensagens'].toString());
    final produto = (resultado['novos'] as List<Produto>).single;
    expect(produto.nome, 'AÇÃO DE GRÃOS');
    expect(produto.preco, closeTo(10.5, 0.0001));
  });

  test('planilha Excel continua sendo lida (regressão do refactor)', () async {
    final excel = Excel.createExcel();
    final sheetName = excel.sheets.keys.first;
    final linhas = [
      ['Código', 'Nome', 'Preço', 'Custo', 'Estoque', 'NCM'],
      ['77', 'PRODUTO EXCEL', 9.9, 4.5, 12, '12345678'],
    ];
    for (var r = 0; r < linhas.length; r++) {
      for (var c = 0; c < linhas[r].length; c++) {
        excel.updateCell(
          sheetName,
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          linhas[r][c],
        );
      }
    }
    final bytes = Uint8List.fromList(excel.encode()!);

    final resultado = await ExcelImportService.planejarProdutosDeBytes(bytes);

    expect(resultado['erros'], 0, reason: resultado['mensagens'].toString());
    final produto = (resultado['novos'] as List<Produto>).single;
    expect(produto.codigo, 'COD-77');
    expect(produto.nome, 'PRODUTO EXCEL');
    expect(produto.preco, closeTo(9.9, 0.0001));
    expect(produto.precoCusto, closeTo(4.5, 0.0001));
    expect(produto.estoque, 12.0);
    expect(produto.ncm, '12345678');
  });
}
