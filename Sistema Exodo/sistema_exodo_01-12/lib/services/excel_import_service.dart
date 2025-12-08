import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../services/codigo_service.dart';

/// Serviço para importar produtos de arquivos Excel
/// 
/// Importação inteligente que:
/// - Detecta automaticamente a estrutura da planilha
/// - Trata diferentes formatos de dados (vírgula, ponto, texto, número)
/// - Importa estoque quando disponível
/// - Evita erros e duplicações
class ExcelImportService {
  /// Mapa de índices de colunas detectados automaticamente
  static Map<String, int?> _detectarColunas(List<dynamic> cabecalho) {
    final indices = <String, int?>{};
    
    debugPrint('>>> [Excel Import] Detectando colunas do cabeçalho (${cabecalho.length} colunas)...');
    
    // Log de todas as células do cabeçalho para debug
    debugPrint('>>> [Excel Import] Valores RAW do cabeçalho:');
    for (int i = 0; i < cabecalho.length; i++) {
      final valorRaw = cabecalho[i];
      final valorLido = _lerCelula(cabecalho, i);
      final valorLower = (valorLido ?? '').toLowerCase().trim();
      final podeSerGrupo = valorLower.contains('grupo') || valorLower.contains('gurpo') || 
                          valorLower.contains('categoria') || valorLower == 'grupo' || valorLower == 'gurpo';
      final marcacao = podeSerGrupo ? ' ← PODE SER GRUPO!' : '';
      debugPrint('  [Célula $i] RAW: $valorRaw → Lido: "$valorLido"$marcacao');
    }
    
    for (int i = 0; i < cabecalho.length; i++) {
      final valor = _lerCelula(cabecalho, i);
      if (valor == null) continue;
      
      final valorLower = valor.toLowerCase().trim();
      debugPrint('>>> [Excel Import] Coluna $i: "$valor" (lowercase: "$valorLower")');
      
      // Detectar códigos de coluna
      // ORDEM IMPORTANTE: Padrões mais específicos primeiro!
      
      // 1. Código
      if (indices['codigo'] == null) {
        if (valorLower.contains('código') || valorLower.contains('codigo') || 
            valorLower == 'cod' || valorLower == 'cód') {
          // Não pode ser código de barras
          if (!valorLower.contains('barras') && !valorLower.contains('ean') && 
              !valorLower.contains('gtin')) {
            indices['codigo'] = i;
            continue;
          }
        }
      }
      
      // 2. Preço de Venda (padrão específico - verificar ANTES de preço genérico)
      if (indices['preco'] == null) {
        // Normalizar removendo espaços extras para comparação
        final valorNormalizado = valorLower.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Padrões mais específicos primeiro - verificar igualdade exata
        if (valorNormalizado == 'preço de venda' || valorNormalizado == 'preco de venda' ||
            valorNormalizado == 'preço venda' || valorNormalizado == 'preco venda' ||
            valorNormalizado == 'preco de venda' || valorNormalizado == 'preço de venda') {
          // Garantir que não é preço de custo
          if (!valorNormalizado.contains('custo')) {
            indices['preco'] = i;
            debugPrint('>>> [Excel Import] ✅ Coluna "preco" detectada no índice $i: "$valor" (normalizado: "$valorNormalizado")');
            continue; // IMPORTANTE: não verificar descrição para esta coluna
          }
        }
        // Fallback: verificar contains (caso tenha espaços extras ou variações)
        else if ((valorLower.contains('preco') || valorLower.contains('preço')) && 
                 valorLower.contains('venda') &&
                 !valorLower.contains('custo')) {
          indices['preco'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "preco" detectada no índice $i (via contains): "$valor"');
          continue;
        }
      }
      
      // 3. Preço de Custo (padrão específico - verificar ANTES de preço genérico)
      if (indices['precoCusto'] == null) {
        // Normalizar removendo espaços extras para comparação
        final valorNormalizado = valorLower.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Padrões mais específicos primeiro - verificar igualdade exata
        if (valorNormalizado == 'preço de custo' || valorNormalizado == 'preco de custo' ||
            valorNormalizado == 'preço custo' || valorNormalizado == 'preco custo') {
          indices['precoCusto'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "precoCusto" detectada no índice $i: "$valor" (normalizado: "$valorNormalizado")');
          continue;
        }
        // Fallback: verificar contains
        else if ((valorLower.contains('preco') || valorLower.contains('preço')) && 
                 valorLower.contains('custo')) {
          indices['precoCusto'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "precoCusto" detectada no índice $i (via contains): "$valor"');
          continue;
        }
      }
      
      // 4. Preço genérico (apenas se não foi detectado como preço de venda)
      if (indices['preco'] == null) {
        if (valorLower.contains('preço') || valorLower.contains('preco') ||
            valorLower == 'pre' || valorLower == 'vlr') {
          // Não pode ser preço de custo
          if (!valorLower.contains('custo')) {
            indices['preco'] = i;
            continue;
          }
        }
      }
      
      // 5. Nome/Produto
      if (indices['nome'] == null) {
        if (valorLower.contains('nome') || valorLower.contains('produto') ||
            valorLower.contains('descrição curta') || valorLower == 'prod') {
          indices['nome'] = i;
          continue;
        }
      }
      
      // 6. Descrição (não pode ser preço de venda!)
      if (indices['descricao'] == null) {
        // Normalizar removendo espaços extras
        final valorNormalizado = valorLower.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Padrões mais específicos primeiro - verificar igualdade exata
        if (valorNormalizado == 'descrição' || valorNormalizado == 'descricao' ||
            valorNormalizado == 'desc') {
          // GARANTIR que não é preço de venda ou preço de custo
          if (!valorLower.contains('preço') && !valorLower.contains('preco') &&
              !valorLower.contains('venda') && !valorLower.contains('custo')) {
            indices['descricao'] = i;
            debugPrint('>>> [Excel Import] ✅ Coluna "descricao" detectada no índice $i: "$valor" (normalizado: "$valorNormalizado")');
            // Se não encontrou nome, usar descrição como nome também
            if (indices['nome'] == null) {
              indices['nome'] = i;
            }
            continue;
          }
        }
        // Fallback: verificar contains
        else if ((valorLower.contains('descrição') || valorLower.contains('descricao') ||
                 valorLower.contains('detalhe')) &&
                 !valorLower.contains('preço') && !valorLower.contains('preco') &&
                 !valorLower.contains('venda') && !valorLower.contains('custo')) {
          indices['descricao'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "descricao" detectada no índice $i (via contains): "$valor"');
          if (indices['nome'] == null) {
            indices['nome'] = i;
          }
          continue;
        }
      }
      
      // 7. Unidade
      if (indices['unidade'] == null) {
        if (valorLower.contains('unidade') || valorLower.contains('un') ||
            valorLower.contains('medida') || valorLower == 'und') {
          indices['unidade'] = i;
          continue;
        }
      }
      
      // 8. Grupo
      if (indices['grupo'] == null) {
        // Normalizar removendo espaços extras
        final valorNormalizado = valorLower.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Padrões mais específicos primeiro - verificar igualdade exata
        if (valorNormalizado == 'grupo' || valorNormalizado == 'gurpo' || // "gurpo" é erro comum de digitação
            valorNormalizado == 'categoria' || valorNormalizado == 'categ' || 
            valorNormalizado == 'cat') {
          indices['grupo'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "grupo" detectada no índice $i: "$valor" (normalizado: "$valorNormalizado")');
          continue;
        }
        // Fallback: verificar contains com tolerância a erros de digitação
        // Aceita "grupo", "gurpo" (erro comum), "categoria", etc.
        else if (valorLower.contains('grupo') || valorLower.contains('gurpo') || // Aceita "gurpo" como variação
                 valorLower.contains('categoria') || valorLower.contains('categ') || 
                 valorLower.contains('cat')) {
          indices['grupo'] = i;
          debugPrint('>>> [Excel Import] ✅ Coluna "grupo" detectada no índice $i (via contains): "$valor"');
          continue;
        }
      }
      
      // 9. Valor genérico (pode ser preço se não foi detectado ainda)
      if (indices['preco'] == null) {
        if (valorLower == 'valor' || valorLower == 'vlr') {
          indices['preco'] = i;
          continue;
        }
      }
      
      // 10. Custo genérico (sem "preço")
      if (indices['precoCusto'] == null) {
        if ((valorLower.contains('custo') || valorLower.contains('compra') ||
            valorLower == 'cust') && !valorLower.contains('preço') && !valorLower.contains('preco')) {
          indices['precoCusto'] = i;
          continue;
        }
      }
      
      // 11. Venda genérico (pode ser preço se não foi detectado ainda)
      if (indices['preco'] == null) {
        if (valorLower == 'venda' && !valorLower.contains('preço') && !valorLower.contains('preco')) {
          indices['preco'] = i;
          continue;
        }
      }
      
      if (indices['estoque'] == null) {
        if (valorLower.contains('estoque') || valorLower.contains('quantidade') ||
            valorLower.contains('qtd') || valorLower.contains('qtde') ||
            valorLower == 'est' || valorLower == 'qty') {
          indices['estoque'] = i;
          continue;
        }
      }
      
      if (indices['codigoBarras'] == null) {
        if (valorLower.contains('código de barras') || valorLower.contains('codigo de barras') ||
            valorLower.contains('ean') || valorLower.contains('barras') ||
            valorLower == 'ean13' || valorLower == 'gtin') {
          indices['codigoBarras'] = i;
          continue;
        }
      }
    }
    
    // Log final das colunas detectadas
    debugPrint('>>> [Excel Import] Resumo da detecção de colunas:');
    indices.forEach((key, value) {
      if (value != null) {
        final nomeColuna = _lerCelula(cabecalho, value);
        debugPrint('  ✓ $key: índice $value ("$nomeColuna")');
      } else {
        debugPrint('  ✗ $key: não detectado');
      }
    });
    
    return indices;
  }

  /// Importa produtos de um arquivo Excel
  /// 
  /// Formato esperado (flexível):
  /// - Detecta automaticamente as colunas pelo cabeçalho
  /// - Se não houver cabeçalho, usa ordem padrão: Código, Nome, Descrição, Unidade, Grupo, Preço, Preço Custo, Estoque, Código de Barras
  /// 
  /// Retorna um mapa com estatísticas da importação
  /// Importa produtos de um arquivo Excel (aceita File ou bytes)
  static Future<Map<String, dynamic>> importarProdutos(
    File arquivo,
    DataService dataService,
  ) async {
    final bytes = await arquivo.readAsBytes();
    return importarProdutosDeBytes(bytes, dataService);
  }

  /// Importa produtos usando bytes do arquivo (funciona em web e outras plataformas)
  static Future<Map<String, dynamic>> importarProdutosDeBytes(
    Uint8List bytes,
    DataService dataService, {
    void Function(int processados, int total, String etapa)? onProgress,
  }) async {
    final resultado = {
      'sucesso': 0,
      'erros': 0,
      'duplicados': 0,
      'atualizados': 0,
      'mensagens': <String>[],
    };

    try {
      // Ler arquivo Excel
      final excel = Excel.decodeBytes(Uint8List.fromList(bytes));

      // Pegar primeira planilha
      if (excel.tables.isEmpty) {
        (resultado['mensagens'] as List<String>).add('❌ Arquivo Excel vazio ou inválido');
        return resultado;
      }

      final sheet = excel.tables[excel.tables.keys.first]!;
      if (sheet.rows.isEmpty) {
        (resultado['mensagens'] as List<String>).add('❌ Planilha vazia');
        return resultado;
      }

      // Detectar índices de colunas
      final primeiraLinha = sheet.rows[0];
      Map<String, int?> indicesColunas = {};
      
      // Tentar detectar se a primeira linha é cabeçalho
      // Verificar TODAS as colunas, não apenas as 5 primeiras
      bool pareceCabecalho = false;
      int palavrasCabecalhoEncontradas = 0;
      
      for (int i = 0; i < primeiraLinha.length; i++) {
        final valor = _lerCelula(primeiraLinha, i);
        if (valor != null && valor.trim().isNotEmpty) {
          final valorLower = valor.toLowerCase().trim();
          
          // Palavras-chave que indicam cabeçalho
          if (              valorLower.contains('código') || valorLower.contains('codigo') ||
              valorLower.contains('nome') || valorLower.contains('produto') ||
              valorLower.contains('preço') || valorLower.contains('preco') ||
              valorLower.contains('venda') || valorLower.contains('custo') ||
              valorLower.contains('descrição') || valorLower.contains('descricao') ||
              valorLower.contains('estoque') || valorLower.contains('quantidade') ||
              valorLower.contains('unidade') || valorLower.contains('grupo') ||
              valorLower.contains('categoria') || valorLower.contains('categ')) {
            palavrasCabecalhoEncontradas++;
            
            // Se encontrou pelo menos 2 palavras-chave, provavelmente é cabeçalho
            if (palavrasCabecalhoEncontradas >= 2) {
              pareceCabecalho = true;
              break;
            }
          }
        }
      }
      
      int linhaInicio = 0;
      if (pareceCabecalho) {
        indicesColunas = _detectarColunas(primeiraLinha);
        linhaInicio = 1;
        debugPrint('>>> [Excel Import] Cabeçalho detectado! Colunas encontradas:');
        indicesColunas.forEach((key, value) {
          if (value != null) {
            final nomeColuna = _lerCelula(primeiraLinha, value);
            debugPrint('  - $key: índice $value ("$nomeColuna")');
          }
        });
        (resultado['mensagens'] as List<String>).add('✅ Cabeçalho detectado automaticamente');
      } else {
        // Se não detectou cabeçalho, tentar detectar mesmo assim (pode ser que a primeira linha tenha dados misturados)
        debugPrint('>>> [Excel Import] Cabeçalho não detectado automaticamente, tentando detectar colunas mesmo assim...');
        indicesColunas = _detectarColunas(primeiraLinha);
        
        // Se ainda não detectou nada, usar ordem padrão
        if (indicesColunas.values.every((v) => v == null)) {
          debugPrint('>>> [Excel Import] Nenhuma coluna detectada, usando ordem padrão');
          // Ordem padrão: Código, Nome, Descrição, Unidade, Grupo, Preço, Preço Custo, Estoque, Código de Barras
          indicesColunas = {
            'codigo': 0,
            'nome': 1,
            'descricao': 2,
            'unidade': 3,
            'grupo': 4,
            'preco': 5,
            'precoCusto': 6,
            'estoque': 7,
            'codigoBarras': 8,
          };
          linhaInicio = 0; // Usar primeira linha também
        } else {
          // Detectou algumas colunas, usar cabeçalho
          linhaInicio = 1;
          debugPrint('>>> [Excel Import] Algumas colunas detectadas mesmo sem cabeçalho claro');
          indicesColunas.forEach((key, value) {
            if (value != null) {
              final nomeColuna = _lerCelula(primeiraLinha, value);
              debugPrint('  - $key: índice $value ("$nomeColuna")');
            }
          });
        }
      }

      // Carregar produtos existentes
      final produtosExistentes = dataService.produtos;
      final codigosExistentes = <String>{};
      final nomesExistentes = <String>{};
      final codigosBarrasExistentes = <String>{};
      
      for (final p in produtosExistentes) {
        if (p.codigo != null && p.codigo!.isNotEmpty) {
          codigosExistentes.add(p.codigo!);
        }
        nomesExistentes.add(p.nome.toLowerCase().trim());
        if (p.codigoBarras != null && p.codigoBarras!.isNotEmpty) {
          codigosBarrasExistentes.add(p.codigoBarras!);
        }
      }

      final produtosParaImportar = <Produto>[];
      final produtosParaAtualizar = <Produto>[];
      final produtosProcessados = <String>{}; // Para evitar duplicatas na mesma importação

      // Calcular total de linhas para processar
      final totalLinhas = sheet.rows.length - linhaInicio;
      int linhasProcessadas = 0;
      int linhasVazias = 0;

      debugPrint('>>> [Excel Import] Total de linhas na planilha: ${sheet.rows.length}');
      debugPrint('>>> [Excel Import] Linha de início (cabeçalho): $linhaInicio');
      debugPrint('>>> [Excel Import] Total de linhas para processar: $totalLinhas');

      // Notificar início do processamento
      onProgress?.call(0, totalLinhas, 'Lendo planilha...');

      // Processar cada linha
      debugPrint('>>> [Excel Import] Iniciando processamento de linhas de $linhaInicio até ${sheet.rows.length - 1}...');
      for (int i = linhaInicio; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        
        // Verificar se linha está vazia com mais detalhes
        if (row.isEmpty) {
          linhasVazias++;
          debugPrint('>>> [Excel Import] Linha ${i + 1}: row.isEmpty = true, pulando...');
          continue;
        }
        
        if (_linhaVazia(row)) {
          linhasVazias++;
          debugPrint('>>> [Excel Import] Linha ${i + 1}: _linhaVazia = true, pulando...');
          // Mostrar valores da linha para debug
          debugPrint('>>> [Excel Import] Linha ${i + 1} - Debug (tamanho: ${row.length}):');
          for (int col = 0; col < row.length && col < 10; col++) {
            final cellValue = row[col];
            final lerValor = _lerCelula(row, col);
            debugPrint('  Coluna $col: RAW="$cellValue", Lido="$lerValor"');
          }
          continue;
        }
        
        debugPrint('>>> [Excel Import] ========== Processando LINHA ${i + 1} de ${sheet.rows.length} ==========');
        
        // Mostrar valores RAW de todas as células da linha primeiro
        debugPrint('>>> [Excel Import] Linha ${i + 1} - Total de colunas: ${row.length}');
        debugPrint('>>> [Excel Import] Linha ${i + 1} - Valores RAW de todas as células:');
        for (int col = 0; col < row.length; col++) {
          final valorRaw = _lerCelula(row, col);
          debugPrint('  Coluna $col: "$valorRaw"');
        }
        
        // Notificar progresso durante processamento (SEMPRE, não apenas a cada 10)
        linhasProcessadas++;
        onProgress?.call(linhasProcessadas, totalLinhas, 'Processando linha $linhasProcessadas de $totalLinhas...');

        try {
          // Ler colunas usando índices detectados ou padrão
          final codigo = _lerValorSeguro(row, indicesColunas['codigo']);
          var nome = _lerValorSeguro(row, indicesColunas['nome']);
          final descricao = _lerValorSeguro(row, indicesColunas['descricao']);
          final unidadeStr = _lerValorSeguro(row, indicesColunas['unidade']);
          final grupoStr = _lerValorSeguro(row, indicesColunas['grupo']);
          var precoStr = _lerValorSeguro(row, indicesColunas['preco']);
          final precoCustoStr = _lerValorSeguro(row, indicesColunas['precoCusto']);
          final estoqueStr = _lerValorSeguro(row, indicesColunas['estoque']);
          final codigoBarras = _lerValorSeguro(row, indicesColunas['codigoBarras']);
          
          // Debug: mostrar quais colunas foram detectadas e seus valores LIDOS
          debugPrint('>>> [Excel Import] Linha ${i + 1} - Valores lidos usando índices detectados:');
          debugPrint('  - Código (índice ${indicesColunas['codigo']}): "$codigo"');
          debugPrint('  - Nome (índice ${indicesColunas['nome']}): "$nome"');
          debugPrint('  - Descrição (índice ${indicesColunas['descricao']}): "$descricao"');
          debugPrint('  - Preço (índice ${indicesColunas['preco']}): "$precoStr"');
          debugPrint('  - Preço Custo (índice ${indicesColunas['precoCusto']}): "$precoCustoStr"');
          debugPrint('  - Grupo (índice ${indicesColunas['grupo']}): "$grupoStr"');
          debugPrint('  - Unidade (índice ${indicesColunas['unidade']}): "$unidadeStr"');
          debugPrint('  - Estoque (índice ${indicesColunas['estoque']}): "$estoqueStr"');

          // IMPORTANTE: Preservar descrição ORIGINAL antes de qualquer manipulação
          final descricaoOriginal = (descricao != null && descricao.trim().isNotEmpty) 
              ? descricao.trim() 
              : null;
          
          // Se nome está vazio, tentar gerar nome (prioridade: descrição > código)
          if ((nome == null || nome.trim().isEmpty)) {
            if (descricaoOriginal != null) {
              // PRIORIDADE 1: Usar descrição como nome se nome não existe
              nome = descricaoOriginal;
              debugPrint('>>> [Excel Import] Linha ${i + 1}: ✅ Usando descrição como nome: "$nome"');
              // IMPORTANTE: A descrição original ainda será salva separadamente
            } else if (codigo != null && codigo.trim().isNotEmpty) {
              // PRIORIDADE 2: Se não tem descrição, gerar nome do código
              final codigoTrim = codigo.trim();
              // Se o código for apenas números, gerar nome com o código
              if (RegExp(r'^[0-9]+$').hasMatch(codigoTrim)) {
                nome = 'Produto COD-$codigoTrim';
              } else {
                nome = 'Produto $codigoTrim';
              }
              debugPrint('>>> [Excel Import] Linha ${i + 1}: ⚠️ Gerando nome do código "$codigoTrim": "$nome" (descrição não disponível)');
            }
          } else {
            // Nome existe - validar se não está pegando o código incorretamente
            if (codigo != null && codigo.trim().isNotEmpty && nome.trim() == codigo.trim()) {
              // Se nome é igual ao código, provavelmente está errado - tentar usar descrição
              if (descricaoOriginal != null && descricaoOriginal.trim().isNotEmpty) {
                debugPrint('>>> [Excel Import] Linha ${i + 1}: ⚠️ Nome igual ao código detectado, usando descrição como nome');
                nome = descricaoOriginal;
              }
            }
          }

          // Validações obrigatórias - deve ter nome (gerado ou fornecido)
          if (nome == null || nome.trim().isEmpty) {
            resultado['erros'] = (resultado['erros'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1}: ❌ ERRO - Nome/Descrição/Código é obrigatório para criar o produto');
            continue;
          }

          final nomeFinal = nome.trim();
          
          // Normalizar código ANTES de buscar produto existente para comparação correta
          var codigoFinal = (codigo != null && codigo.trim().isNotEmpty) 
              ? codigo.trim() 
              : null;
          
          // Normalizar código: se for apenas números, adicionar prefixo COD-
          if (codigoFinal != null && RegExp(r'^[0-9]+$').hasMatch(codigoFinal)) {
            codigoFinal = 'COD-$codigoFinal';
            debugPrint('>>> [Excel Import] Linha ${i + 1}: Código normalizado para "$codigoFinal"');
          }
          
          // Verificar se é atualização ANTES de validar preço
          bool deveAtualizar = false;
          Produto? produtoExistente;

          // Buscar produto existente por código
          if (codigoFinal != null && codigoFinal.isNotEmpty) {
            final codigoLower = codigoFinal.toLowerCase().trim();
            final encontrados = produtosExistentes.where((p) => 
              p.codigo != null && p.codigo!.toLowerCase().trim() == codigoLower
            ).toList();
            if (encontrados.isNotEmpty) {
              produtoExistente = encontrados.first;
              deveAtualizar = true;
            }
          }

          // Buscar por código de barras se não encontrou por código
          final codigoBarrasFinal = (codigoBarras != null && codigoBarras.trim().isNotEmpty) 
              ? codigoBarras.trim() 
              : null;
          if (!deveAtualizar && codigoBarrasFinal != null && codigoBarrasFinal.isNotEmpty) {
            final encontrados = produtosExistentes.where((p) => 
              p.codigoBarras != null && p.codigoBarras! == codigoBarrasFinal
            ).toList();
            if (encontrados.isNotEmpty) {
              produtoExistente = encontrados.first;
              deveAtualizar = true;
            }
          }

          // Buscar por nome normalizado (somente se código não fornecido ou não encontrado)
          if (!deveAtualizar && (codigoFinal == null || codigoFinal.isEmpty)) {
            final nomeNormalizado = nomeFinal.toLowerCase().trim();
            if (nomesExistentes.contains(nomeNormalizado)) {
              final encontrados = produtosExistentes.where((p) => 
                p.nome.toLowerCase().trim() == nomeNormalizado
              ).toList();
              if (encontrados.isNotEmpty) {
                produtoExistente = encontrados.first;
                // Se tem mesmo nome mas códigos diferentes, trata como duplicado
                if (produtoExistente.codigo != null && produtoExistente.codigo!.trim().isNotEmpty) {
                  resultado['duplicados'] = (resultado['duplicados'] as int) + 1;
                  (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Nome duplicado (produto já existe com código ${produtoExistente.codigo})');
                  continue;
                } else {
                  deveAtualizar = true;
                }
              }
            }
          }
          
          // Obter nome da coluna de preço detectada para mensagem de erro
          String nomeColunaPreco = 'preço';
          if (indicesColunas['preco'] != null) {
            final indicePreco = indicesColunas['preco']!;
            if (indicePreco < primeiraLinha.length) {
              final nomeColuna = _lerCelula(primeiraLinha, indicePreco);
              if (nomeColuna != null && nomeColuna.trim().isNotEmpty) {
                nomeColunaPreco = nomeColuna.trim().toLowerCase();
              }
            }
          }
          
          // NÃO buscar preço em outras colunas - usar apenas o índice detectado
          // Isso evita pegar código ou outros valores numéricos incorretamente
          if (precoStr == null || precoStr.trim().isEmpty) {
            debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ⚠️ Preço não encontrado na coluna "${nomeColunaPreco}" (índice ${indicesColunas['preco']})');
          } else {
            // VALIDAÇÃO: Verificar se o preço não é o código
            if (codigo != null && codigo.trim().isNotEmpty && precoStr.trim() == codigo.trim()) {
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ⚠️ AVISO - Preço igual ao código detectado! "$precoStr" == "$codigo" - Isso pode indicar erro na detecção de colunas');
              precoStr = null; // Limpar preço incorreto
            } else {
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ✅ Preço lido da coluna "${nomeColunaPreco}": "$precoStr"');
            }
          }
          
          // Validação de preço: obrigatório apenas para novos produtos
          double? preco;
          if (precoStr != null && precoStr.trim().isNotEmpty) {
            // Converter e validar valores numéricos
            preco = _parseDoubleInteligente(precoStr);
            if (preco == null || preco < 0) {
              resultado['erros'] = (resultado['erros'] as int) + 1;
              (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ❌ ERRO - Preço inválido: "$precoStr"');
              continue;
            }
          } else {
            // Sem preço fornecido
            if (deveAtualizar && produtoExistente != null) {
              // Para atualização: manter preço existente se não fornecido
              preco = produtoExistente.preco;
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): Preço não fornecido, mantendo preço existente: ${preco}');
            } else {
              // Para novo produto: preço é obrigatório
              resultado['erros'] = (resultado['erros'] as int) + 1;
              (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ❌ ERRO - Preço é obrigatório (coluna "$nomeColunaPreco" está vazia)');
              continue;
            }
          }

          double? precoCusto;
          if (precoCustoStr != null && precoCustoStr.trim().isNotEmpty) {
            final precoCustoTemp = _parseDoubleInteligente(precoCustoStr.trim());
            if (precoCustoTemp == null) {
              // Se não conseguiu converter, pode ser texto - ignorar mas avisar
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ⚠️ Preço de custo inválido (não numérico): "$precoCustoStr" - será ignorado');
              precoCusto = null;
            } else if (precoCustoTemp < 0) {
              precoCusto = null; // Ignora valores negativos
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ⚠️ Preço de custo negativo ($precoCustoTemp) ignorado');
            } else {
              precoCusto = precoCustoTemp;
              debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ✅ Preço de custo válido: R\$ $precoCusto');
            }
          } else {
            debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): ℹ️ Preço de custo não fornecido (será null)');
            precoCusto = null;
          }

          // IMPORTAR ESTOQUE - se disponível na planilha
          int estoqueFinal = 0;
          if (estoqueStr != null && estoqueStr.trim().isNotEmpty) {
            final estoqueParsed = _parseIntInteligente(estoqueStr);
            if (estoqueParsed != null && estoqueParsed >= 0) {
              estoqueFinal = estoqueParsed;
            } else {
              (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Estoque inválido, usando 0');
            }
          }

          // Normalizar valores de forma segura
          final unidadeFinal = (unidadeStr != null && unidadeStr.trim().isNotEmpty) 
              ? unidadeStr.trim().toUpperCase() 
              : 'UN';
          final grupoFinal = (grupoStr != null && grupoStr.trim().isNotEmpty) 
              ? grupoStr.trim() 
              : 'Sem Grupo';
          
          // Usar descrição original preservada anteriormente
          final descricaoFinal = descricaoOriginal;
          
          // Debug: mostrar valores finais que serão salvos
          debugPrint('>>> [Excel Import] Linha ${i + 1} - Valores finais:');
          debugPrint('  - Nome: "$nomeFinal"');
          debugPrint('  - Descrição: "$descricaoFinal"');
          debugPrint('  - Preço: $preco');
          debugPrint('  - Preço Custo: $precoCusto');
          debugPrint('  - Grupo: "$grupoFinal" (lido: "$grupoStr")');
          debugPrint('  - Unidade: "$unidadeFinal" (lido: "$unidadeStr")');
          debugPrint('  - Estoque: $estoqueFinal (lido: "$estoqueStr")');

          // Verificar duplicatas na planilha
          String? chaveUnica = _gerarChaveUnica(codigoFinal, codigoBarrasFinal, nomeFinal);
          if (produtosProcessados.contains(chaveUnica)) {
            resultado['duplicados'] = (resultado['duplicados'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Duplicado na planilha');
            continue;
          }
          produtosProcessados.add(chaveUnica);

          // Gerar código se não fornecido
          String? codigoGerado = codigoFinal;
          if (codigoGerado == null || codigoGerado.isEmpty) {
            final todosCodigos = [
              ...codigosExistentes,
              ...produtosParaImportar.where((p) => p.codigo != null).map((p) => p.codigo!),
            ];
            codigoGerado = CodigoService.gerarProximoUltimo(todosCodigos);
          }

          final agora = DateTime.now();

          if (deveAtualizar && produtoExistente != null) {
            // Atualizar produto existente - SOMAR ESTOQUE se já existir
            final estoqueAtual = produtoExistente.estoque;
            final estoqueNovo = estoqueFinal > 0 ? estoqueFinal : estoqueAtual; // Se não forneceu estoque, mantém o atual
            
            final produtoAtualizado = produtoExistente.copyWith(
              nome: nomeFinal,
              descricao: descricaoFinal ?? produtoExistente.descricao,
              unidade: unidadeFinal,
              grupo: grupoFinal, // Sempre atualiza o grupo (se não fornecido, usa "Sem Grupo")
              preco: preco,
              // Se preço de custo foi fornecido, usar. Caso contrário, manter o existente
              precoCusto: precoCusto ?? produtoExistente.precoCusto,
              estoque: estoqueNovo, // Usa o novo estoque ou mantém o atual
              codigoBarras: codigoBarrasFinal ?? produtoExistente.codigoBarras,
              codigo: codigoGerado.isNotEmpty ? codigoGerado : produtoExistente.codigo,
              updatedAt: agora,
            );
            produtosParaAtualizar.add(produtoAtualizado);
            resultado['atualizados'] = (resultado['atualizados'] as int) + 1;
            debugPrint('>>> [Excel Import] 🔄 Linha ${i + 1}: Produto será ATUALIZADO - "$nomeFinal" (COD: $codigoGerado, Preço: R\$ $preco, Custo: ${precoCusto != null ? "R\$ $precoCusto" : produtoExistente.precoCusto != null ? "R\$ ${produtoExistente.precoCusto} (mantido)" : "null"}, Grupo: "$grupoFinal", Desc: "$descricaoFinal")');
          } else {
            // Criar novo produto
            final idProduto = DateTime.now().millisecondsSinceEpoch.toString() +
                '_${i}_${nomeFinal.hashCode.abs()}';
            final novoProduto = Produto(
              id: idProduto,
              codigo: codigoGerado,
              codigoBarras: codigoBarrasFinal,
              nome: nomeFinal,
              descricao: descricaoFinal,
              unidade: unidadeFinal,
              grupo: grupoFinal,
              preco: preco,
              precoCusto: precoCusto,
              estoque: estoqueFinal, // Importa o estoque
              createdAt: agora,
              updatedAt: agora,
            );
            produtosParaImportar.add(novoProduto);
            codigosExistentes.add(codigoGerado);
            nomesExistentes.add(nomeFinal.toLowerCase().trim());
            if (codigoBarrasFinal != null && codigoBarrasFinal.isNotEmpty) {
              codigosBarrasExistentes.add(codigoBarrasFinal);
            }
            debugPrint('>>> [Excel Import] ✅ Linha ${i + 1}: Produto adicionado para importar - "$nomeFinal" (COD: $codigoGerado, Preço: R\$ $preco, Custo: ${precoCusto != null ? "R\$ $precoCusto" : "null"}, Grupo: "$grupoFinal", Desc: "$descricaoFinal")');
          }
        } catch (e, stackTrace) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          String nomeErro = 'Desconhecido';
          try {
            nomeErro = _lerValorSeguro(row, indicesColunas['nome']) ?? 
                      _lerValorSeguro(row, indicesColunas['descricao']) ?? 
                      'Linha ${i + 1}';
          } catch (e2) {
            // Se não conseguir ler o nome, usar número da linha
            nomeErro = 'Linha ${i + 1}';
          }
          
          final mensagemErro = e.toString();
          (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeErro): ❌ Erro: $mensagemErro');
          debugPrint('>>> [Excel Import] ❌ Erro ao processar linha ${i + 1}: $e');
          debugPrint('>>> [Excel Import] StackTrace: $stackTrace');
          
          // Tentar continuar processando outras linhas mesmo se uma falhar
          continue;
        }
      }
      
      debugPrint('>>> [Excel Import] ========== FIM DO PROCESSAMENTO DE LINHAS ==========');
      debugPrint('>>> [Excel Import] Total de linhas na planilha: ${sheet.rows.length}');
      debugPrint('>>> [Excel Import] Linha de início (pula cabeçalho): $linhaInicio');
      debugPrint('>>> [Excel Import] Linhas que deveriam ser processadas: $totalLinhas');
      debugPrint('>>> [Excel Import] Linhas efetivamente processadas: $linhasProcessadas');
      debugPrint('>>> [Excel Import] Linhas vazias puladas: $linhasVazias');
      debugPrint('>>> [Excel Import] Produtos para importar (NOVOS): ${produtosParaImportar.length}');
      debugPrint('>>> [Excel Import] Produtos para atualizar: ${produtosParaAtualizar.length}');
      debugPrint('>>> [Excel Import] Lista de produtos novos:');
      for (int idx = 0; idx < produtosParaImportar.length; idx++) {
        final p = produtosParaImportar[idx];
        debugPrint('  ${idx + 1}. ${p.nome} (COD: ${p.codigo})');
      }

      // Notificar início do salvamento
      onProgress?.call(linhasProcessadas, totalLinhas, 'Salvando ${produtosParaImportar.length} produtos novos...');

      // Salvar produtos novos
      int salvos = 0;
      for (final produto in produtosParaImportar) {
        try {
          await dataService.addProduto(produto);
          resultado['sucesso'] = (resultado['sucesso'] as int) + 1;
          salvos++;
          if (salvos % 10 == 0) {
            onProgress?.call(linhasProcessadas, totalLinhas, 'Salvando produto $salvos de ${produtosParaImportar.length}...');
          }
        } catch (e) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          (resultado['mensagens'] as List<String>).add('❌ Erro ao importar ${produto.nome}: $e');
          debugPrint('>>> Erro ao importar produto ${produto.nome}: $e');
        }
      }

      // Notificar atualização
      if (produtosParaAtualizar.isNotEmpty) {
        onProgress?.call(linhasProcessadas, totalLinhas, 'Atualizando ${produtosParaAtualizar.length} produtos...');
      }

      // Atualizar produtos existentes
      int atualizados = 0;
      for (final produto in produtosParaAtualizar) {
        try {
          await dataService.updateProduto(produto);
          atualizados++;
          if (atualizados % 10 == 0) {
            onProgress?.call(linhasProcessadas, totalLinhas, 'Atualizando produto $atualizados de ${produtosParaAtualizar.length}...');
          }
        } catch (e) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          (resultado['mensagens'] as List<String>).add('❌ Erro ao atualizar ${produto.nome}: $e');
          debugPrint('>>> Erro ao atualizar produto ${produto.nome}: $e');
        }
      }
      
      // Notificar conclusão
      onProgress?.call(linhasProcessadas, totalLinhas, 'Concluído!');

      // Mensagem final
      (resultado['mensagens'] as List<String>).add(
        '\n✅ RESUMO: ${resultado['sucesso']} novos, '
        '${resultado['atualizados']} atualizados, '
        '${resultado['duplicados']} duplicados ignorados, '
        '${resultado['erros']} erros',
      );
    } catch (e, stackTrace) {
      resultado['erros'] = (resultado['erros'] as int) + 1;
      (resultado['mensagens'] as List<String>).add('❌ Erro crítico ao ler arquivo Excel: $e');
      debugPrint('>>> Erro crítico ao importar Excel: $e\n$stackTrace');
    }

    return resultado;
  }

  /// Lê o valor de uma célula de forma segura e inteligente
  static String? _lerCelula(List<dynamic> row, int coluna) {
    try {
      if (coluna < 0 || coluna >= row.length) return null;
      
      final cell = row[coluna];
      if (cell == null) return null;

      // Tentar acessar o valor da célula de diferentes formas
      dynamic value;
      
      // Método 1: cell.value (formato padrão do pacote excel)
      try {
        value = (cell as dynamic).value;
      } catch (e) {
        // Método 2: Se não tiver .value, tentar como String direto
        try {
          if (cell is String) {
            value = cell;
          } else {
            value = cell.toString();
          }
        } catch (e2) {
          return null;
        }
      }
      
      if (value == null) return null;
      
      // Converter para String de forma inteligente
      if (value is String) {
        final str = value.trim();
        return str.isEmpty ? null : str;
      } else if (value is int) {
        return value.toString();
      } else if (value is double) {
        // Remover zeros desnecessários
        if (value % 1 == 0) {
          return value.toInt().toString();
        }
        return value.toString();
      } else if (value is bool) {
        return value ? '1' : '0';
      } else if (value is DateTime) {
        return value.toString();
      }
      
      final str = value.toString().trim();
      return str.isEmpty ? null : str;
    } catch (e) {
      debugPrint('>>> Erro ao ler célula coluna $coluna: $e');
      return null;
    }
  }

  /// Lê valor de uma célula usando índice (pode ser null)
  static String? _lerValorSeguro(List<dynamic> row, int? indice) {
    if (indice == null) return null;
    return _lerCelula(row, indice);
  }

  /// Verifica se uma linha está vazia
  static bool _linhaVazia(List<dynamic> row) {
    if (row.isEmpty) return true;
    for (int i = 0; i < row.length; i++) {
      final value = _lerCelula(row, i);
      if (value != null && value.trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  /// Converte string para double de forma inteligente
  /// Trata: vírgula, ponto, espaços, símbolos de moeda, etc.
  static double? _parseDoubleInteligente(String value) {
    if (value.isEmpty) return null;
    
    // Remover espaços e caracteres especiais comuns
    String normalized = value.trim()
        .replaceAll(RegExp(r'[^\d,.\-]'), '') // Remove tudo exceto dígitos, vírgula, ponto e menos
        .replaceAll(' ', '');
    
    if (normalized.isEmpty) return null;
    
    // Detectar formato brasileiro (vírgula como separador decimal)
    // Se tem vírgula e ponto: ponto é milhar, vírgula é decimal (ex: 1.234,56)
    // Se só tem vírgula: pode ser decimal ou milhar
    // Se só tem ponto: pode ser decimal ou milhar
    
    if (normalized.contains(',') && normalized.contains('.')) {
      // Formato: 1.234,56 ou 1,234.56
      final parts = normalized.split(',');
      if (parts.length == 2) {
        // Vírgula é decimal: 1.234,56
        normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // Ponto é decimal: 1,234.56
        normalized = normalized.replaceAll(',', '');
      }
    } else if (normalized.contains(',')) {
      // Só vírgula: assumir que é decimal (formato brasileiro)
      final parts = normalized.split(',');
      if (parts.length == 2 && parts[1].length <= 2) {
        // Vírgula é decimal: 1234,56
        normalized = normalized.replaceAll(',', '.');
      } else {
        // Vírgula pode ser milhar: 1,234
        normalized = normalized.replaceAll(',', '');
      }
    }
    
    return double.tryParse(normalized);
  }

  /// Converte string para int de forma inteligente
  static int? _parseIntInteligente(String value) {
    if (value.isEmpty) return null;
    
    // Tentar converter diretamente
    final intDireto = int.tryParse(value.trim());
    if (intDireto != null) return intDireto;
    
    // Se for double, converter para int
    final doubleValue = _parseDoubleInteligente(value);
    if (doubleValue != null) {
      return doubleValue.toInt();
    }
    
    return null;
  }

  /// Gera chave única para identificar duplicatas
  static String _gerarChaveUnica(String? codigo, String? codigoBarras, String nome) {
    if (codigo != null && codigo.isNotEmpty) {
      return 'cod:$codigo';
    }
    if (codigoBarras != null && codigoBarras.isNotEmpty) {
      return 'ean:$codigoBarras';
    }
    return 'nome:${nome.toLowerCase().trim()}';
  }
}
