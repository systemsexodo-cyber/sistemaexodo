import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/produto.dart';
import '../models/estoque_historico.dart';
import '../pages/html_helper_web.dart' if (dart.library.io) 'local_storage_service_stub.dart';

/// Serviço para exportar produtos para Excel e CSV
class ExcelExportService {
  /// Sanitiza texto para CSV
  static String _fix(String? text) {
    if (text == null) return '';
    return text.replaceAll('\n', ' ').replaceAll(';', ',').trim();
  }

  /// Exporta uma lista de produtos para um arquivo CSV (mais leve e compatível com E-commerces)
  static void exportarProdutosCSV(List<Produto> produtos) {
    debugPrint('>>> [CSVExport] Iniciando exportação de ${produtos.length} produtos...');
    
    try {
      // Cabeçalhos expandidos para E-commerce
      List<String> headers = [
        'Codigo', 'CodigoBarras', 'Nome', 'Descricao', 'Grupo_Categoria', 'Unidade', 
        'PrecoVenda', 'PrecoCusto', 'Estoque', 'EstoqueMinimo', 'NCM', 'CFOP', 
        'Peso_Gramas', 'Altura_Cm', 'Largura_Cm', 'Profundidade_Cm', 'Exibir_Loja', 'Em_Destaque',
        'URL_Foto_Principal', 'Origem', 'CSOSN', 'Fornecedor', 'ID'
      ];

      StringBuffer csv = StringBuffer();
      // Adicionar cabeçalho com ponto-e-vírgula (padrão Excel Brasil)
      csv.writeln(headers.join(';'));

      for (var p in produtos) {
        List<String> row = [
          _fix(p.codigo),
          _fix(p.codigoBarras),
          _fix(p.nome),
          _fix(p.descricao),
          _fix(p.grupo),
          _fix(p.unidade),
          p.preco.toString().replaceAll('.', ','),
          (p.precoCusto ?? 0.0).toString().replaceAll('.', ','),
          p.estoque.toString(),
          p.estoqueMinimo.toString(),
          _fix(p.ncm),
          _fix(p.cfop),
          (p.pesoGramas ?? 0).toString(),
          (p.alturaCm ?? 0.0).toString().replaceAll('.', ','),
          (p.larguraCm ?? 0.0).toString().replaceAll('.', ','),
          (p.profundidadeCm ?? 0.0).toString().replaceAll('.', ','),
          p.exibirNaLoja ? 'Sim' : 'Não',
          p.emDestaque ? 'Sim' : 'Não',
          _fix(p.fotoPrincipalUrl),
          _fix(p.origem),
          _fix(p.csosn),
          _fix(p.fornecedorNome),
          p.id
        ];
        csv.writeln(row.join(';'));
      }

      final bytes = Uint8List.fromList(csv.toString().codeUnits);
      if (kIsWeb) {
        downloadBytes(bytes, "produtos_ecommerce_full.csv", "text/csv;charset=utf-8");
        debugPrint('>>> [CSVExport] Download de CSV Full disparado!');
      }
    } catch (e) {
      debugPrint('>>> [CSVExport] ❌ ERRO: $e');
      rethrow;
    }
  }

  /// Exporta uma lista de produtos para um arquivo Excel (.xlsx)
  /// Exporta uma lista de produtos para um arquivo Excel (.xlsx)
  static void exportarProdutos(List<Produto> produtos) {
    debugPrint('>>> [ExcelExport] Iniciando exportação de ${produtos.length} produtos...');
    
    try {
      var excel = Excel.createExcel();
      String sheetName = excel.sheets.keys.first;
      
      List<String> headers = [
        'Código', 'Cód. Barras', 'Nome', 'Descrição', 'Grupo/Categoria', 'Unidade',
        'Preço Venda', 'Preço Custo', 'Estoque', 'Estoque Mínimo', 'NCM', 'CFOP',
        'Peso (g)', 'Alt (cm)', 'Larg (cm)', 'Prof (cm)', 'Na Loja', 'Destaque', 'Fornecedor', 'ID'
      ];

      // Escrever cabeçalhos
      for (int i = 0; i < headers.length; i++) {
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), headers[i]);
      }

      // Escrever dados
      for (int i = 0; i < produtos.length; i++) {
        final p = produtos[i];
        final r = i + 1;
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), _fix(p.codigo));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), _fix(p.codigoBarras));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), _fix(p.nome));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), _fix(p.descricao));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), _fix(p.grupo));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), _fix(p.unidade));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r), p.preco);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r), p.precoCusto ?? 0.0);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r), p.estoque);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r), p.estoqueMinimo);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r), _fix(p.ncm));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r), _fix(p.cfop));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: r), p.pesoGramas ?? 0);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r), p.alturaCm ?? 0.0);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r), p.larguraCm ?? 0.0);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: r), p.profundidadeCm ?? 0.0);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: r), p.exibirNaLoja ? 'Sim' : 'Não');
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: r), p.emDestaque ? 'Sim' : 'Não');
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: r), _fix(p.fornecedorNome));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: r), p.id);
      }

      final bytes = excel.encode();
      if (bytes != null && kIsWeb) {
        downloadBytes(bytes, "produtos_exodo.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
      }
    } catch (e) {
      debugPrint('>>> [ExcelExport] ❌ ERRO: $e');
      rethrow;
    }
  }

  /// Exporta o Inventário de Estoque para Contabilidade (xlsx)
  /// Contém: Código, Nome, Unidade, Quantidade, Valor Unitário (Custo), Valor Total
  static void exportarInventarioContabilidade(List<Produto> produtos) {
    debugPrint('>>> [InventoryExport] Gerando inventário contábil para ${produtos.length} produtos...');
    
    try {
      var excel = Excel.createExcel();
      String sheetName = excel.sheets.keys.first;
      
      final headers = [
        'CÓDIGO', 'DESCRIÇÃO', 'UNID', 'QUANTIDADE', 'CUSTO UNITÁRIO', 'CUSTO TOTAL'
      ];

      // Estilo para cabeçalho
      // Nota: A lib excel tem limitações de estilo em algumas versões, mas vamos tentar o básico
      for (int i = 0; i < headers.length; i++) {
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), headers[i]);
      }

      double somaTotal = 0;

      // Escrever dados
      for (int i = 0; i < produtos.length; i++) {
        final p = produtos[i];
        final r = i + 1;
        final qty = p.estoque.toDouble();
        if (qty <= 0) {
          // Pular ou zerar se o estoque for 0 ou negativo, conforme solicitado
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), _fix(p.codigo));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), _fix(p.nome));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), _fix(p.unidade));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), 0);
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), p.precoCusto ?? 0.0);
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), 0);
          continue; 
        }
        
        final custo = p.precoCusto ?? 0.0;
        final total = qty * custo;
        somaTotal += total;

        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), _fix(p.codigo));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), _fix(p.nome));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), _fix(p.unidade));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), qty);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), custo);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), total);
      }

      // Rodapé com total geral
      final footerRow = produtos.length + 2;
      excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: footerRow), 'TOTAL GERAL:');
      excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: footerRow), somaTotal);

      final bytes = excel.encode();
      if (bytes != null && kIsWeb) {
        final dataStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
        downloadBytes(bytes, "inventario_estoque_$dataStr.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
      }
    } catch (e) {
      debugPrint('>>> [InventoryExport] ❌ ERRO: $e');
      rethrow;
    }
  }

  /// Exporta o Inventário Retroativo
  /// Calcula o estoque na data desejada reconstruindo a partir dos movimentos
  static void exportarInventarioRetroativo(List<Produto> produtos, List<EstoqueHistorico> historico, DateTime dataAlvo) {
    debugPrint('>>> [InventoryExport] Gerando inventário retroativo (${DateFormat('dd/MM/yyyy').format(dataAlvo)}) para ${produtos.length} produtos...');
    
    try {
      var excel = Excel.createExcel();
      String sheetName = excel.sheets.keys.first;
      
      final headers = [
        'CÓDIGO', 'DESCRIÇÃO', 'UNID', 'QUANT. RETROATIVA', 'CUSTO UNITÁRIO', 'CUSTO TOTAL'
      ];

      for (int i = 0; i < headers.length; i++) {
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), headers[i]);
      }

      double somaTotal = 0;

      for (int i = 0; i < produtos.length; i++) {
        final p = produtos[i];
        final r = i + 1;
        
        // RECONSTRUÇÃO DO ESTOQUE
        // Estoque na data = Estoque Atual - (Entradas após data) + (Saídas após data)
        double qtyCalculada = p.estoque.toDouble();
        
        final movimentosDepois = historico.where((h) => h.produtoId == p.id && h.data.isAfter(dataAlvo));
        for (final m in movimentosDepois) {
          if (m.tipo == 'entrada') {
            qtyCalculada -= m.quantidade;
          } else if (m.tipo == 'saida' || m.tipo == 'venda') {
            qtyCalculada += m.quantidade;
          }
        }

        if (qtyCalculada <= 0) {
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), _fix(p.codigo));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), _fix(p.nome));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), _fix(p.unidade));
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), 0);
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), p.precoCusto ?? 0.0);
          excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), 0);
          continue; 
        }
        
        final custo = p.precoCusto ?? 0.0;
        final total = qtyCalculada * custo;
        somaTotal += total;

        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), _fix(p.codigo));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), _fix(p.nome));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), _fix(p.unidade));
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), qtyCalculada);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), custo);
        excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), total);
      }

      final footerRow = produtos.length + 2;
      excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: footerRow), 'INVENTÁRIO EM: ${DateFormat('dd/MM/yyyy').format(dataAlvo)}');
      excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: footerRow), 'TOTAL GERAL:');
      excel.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: footerRow), somaTotal);

      final bytes = excel.encode();
      if (bytes != null && kIsWeb) {
        final dataStr = DateFormat('yyyyMMdd').format(dataAlvo);
        downloadBytes(bytes, "inventario_estoque_retroativo_$dataStr.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
      }
    } catch (e) {
      debugPrint('>>> [InventoryExport] ❌ ERRO RETROATIVO: $e');
      rethrow;
    }
  }
}
