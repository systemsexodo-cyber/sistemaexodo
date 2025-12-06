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
    
    for (int i = 0; i < cabecalho.length; i++) {
      final valor = _lerCelula(cabecalho, i);
      if (valor == null || valor.trim().isEmpty) continue;
      
      final valorLower = valor.toLowerCase().trim();
      
      // Detectar códigos de coluna
      if (indices['codigo'] == null) {
        if (valorLower.contains('código') || valorLower.contains('codigo') || 
            valorLower == 'cod' || valorLower == 'cód') {
          indices['codigo'] = i;
          continue;
        }
      }
      
      if (indices['nome'] == null) {
        if (valorLower.contains('nome') || valorLower.contains('produto') ||
            valorLower.contains('descrição curta') || valorLower == 'prod') {
          indices['nome'] = i;
          continue;
        }
      }
      
      if (indices['descricao'] == null) {
        if (valorLower.contains('descrição') || valorLower.contains('descricao') ||
            valorLower.contains('detalhe') || valorLower == 'desc') {
          indices['descricao'] = i;
          // Se não encontrou nome, usar descrição como nome também
          if (indices['nome'] == null) {
            indices['nome'] = i;
          }
          continue;
        }
      }
      
      if (indices['unidade'] == null) {
        if (valorLower.contains('unidade') || valorLower.contains('un') ||
            valorLower.contains('medida') || valorLower == 'und') {
          indices['unidade'] = i;
          continue;
        }
      }
      
      if (indices['grupo'] == null) {
        if (valorLower.contains('grupo') || valorLower.contains('categoria') ||
            valorLower.contains('categ') || valorLower == 'cat') {
          indices['grupo'] = i;
          continue;
        }
      }
      
      if (indices['preco'] == null) {
        // Detectar "preco de venda" ou variações
        if (valorLower.contains('preço') || valorLower.contains('preco') ||
            valorLower.contains('valor') || valorLower.contains('venda') ||
            valorLower == 'pre' || valorLower == 'vlr' ||
            valorLower == 'preco de venda' || valorLower == 'preço de venda' ||
            (valorLower.contains('preco') && valorLower.contains('venda')) ||
            (valorLower.contains('preço') && valorLower.contains('venda'))) {
          indices['preco'] = i;
          debugPrint('>>> [Excel Import] Coluna de preço detectada na coluna $i: "$valorLower"');
          continue;
        }
      }
      
      if (indices['precoCusto'] == null) {
        if (valorLower.contains('custo') || valorLower.contains('preço de custo') ||
            valorLower.contains('preco de custo') || valorLower.contains('compra') ||
            valorLower == 'cust') {
          indices['precoCusto'] = i;
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
    DataService dataService,
  ) async {
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
      bool pareceCabecalho = false;
      int colunasComTexto = 0;
      for (int i = 0; i < primeiraLinha.length && i < 15; i++) {
        final valor = _lerCelula(primeiraLinha, i);
        if (valor != null && valor.trim().isNotEmpty) {
          colunasComTexto++;
          final valorLower = valor.toLowerCase().trim();
          // Verificar se parece um cabeçalho (palavras-chave comuns)
          if (valorLower.contains('código') || valorLower.contains('codigo') || 
              valorLower.contains('nome') || valorLower.contains('produto') ||
              valorLower.contains('preço') || valorLower.contains('preco') ||
              valorLower.contains('valor') || valorLower.contains('venda') ||
              valorLower.contains('estoque') || valorLower.contains('quantidade') ||
              valorLower.contains('qtd') || valorLower.contains('qtde') ||
              valorLower.contains('descrição') || valorLower.contains('descricao') ||
              valorLower.contains('grupo') || valorLower.contains('categoria') ||
              valorLower.contains('unidade') || valorLower.contains('medida') ||
              valorLower.contains('custo') || valorLower.contains('barras') ||
              valorLower.contains('ean') || valorLower.contains('gtin')) {
            pareceCabecalho = true;
            debugPrint('>>> [Excel Import] Cabeçalho detectado na coluna $i: "$valorLower"');
          }
        }
      }
      
      debugPrint('>>> [Excel Import] Colunas com dados no cabeçalho: $colunasComTexto');
      
      // Se várias colunas têm texto não numérico, provavelmente é cabeçalho
      if (!pareceCabecalho && colunasComTexto >= 2) {
        pareceCabecalho = true;
        debugPrint('>>> [Excel Import] Cabeçalho detectado por padrão (muitas colunas de texto)');
      }
      
      int linhaInicio = 0;
      if (pareceCabecalho) {
        indicesColunas = _detectarColunas(primeiraLinha);
        linhaInicio = 1;
        (resultado['mensagens'] as List<String>).add('✅ Cabeçalho detectado automaticamente');
      } else {
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

      // Processar cada linha
      for (int i = linhaInicio; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty || _linhaVazia(row)) continue;

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

          // Se nome está vazio mas descrição não, usar descrição como nome
          if ((nome == null || nome.trim().isEmpty) && 
              (descricao != null && descricao.trim().isNotEmpty)) {
            nome = descricao;
            debugPrint('>>> [Excel Import] Linha ${i + 1}: Usando descrição como nome: "$nome"');
          }

          // Validações obrigatórias
          if (nome == null || nome.trim().isEmpty) {
            resultado['erros'] = (resultado['erros'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1}: ⚠️ Nome/Descrição é obrigatório');
            continue;
          }

          final nomeFinal = nome.trim();
          
          // Se preço não foi encontrado, tentar buscar em todas as colunas
          if (precoStr == null || precoStr.trim().isEmpty) {
            debugPrint('>>> [Excel Import] Linha ${i + 1} ($nomeFinal): Preço não encontrado na coluna especificada, buscando em outras colunas...');
            for (int col = 0; col < row.length; col++) {
              final valorTeste = _lerCelula(row, col);
              if (valorTeste != null) {
                final precoTeste = _parseDoubleInteligente(valorTeste);
                if (precoTeste != null && precoTeste > 0) {
                  precoStr = valorTeste;
                  debugPrint('>>> [Excel Import] Preço encontrado na coluna $col: $precoTeste');
                  break;
                }
              }
            }
          }
          
          if (precoStr == null || precoStr.trim().isEmpty) {
            resultado['erros'] = (resultado['erros'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Preço é obrigatório');
            continue;
          }

          // Converter e validar valores numéricos
          final preco = _parseDoubleInteligente(precoStr);
          if (preco == null || preco < 0) {
            resultado['erros'] = (resultado['erros'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Preço inválido: $precoStr');
            continue;
          }

          double? precoCusto;
          if (precoCustoStr != null && precoCustoStr.trim().isNotEmpty) {
            precoCusto = _parseDoubleInteligente(precoCustoStr);
            if (precoCusto != null && precoCusto < 0) {
              precoCusto = null; // Ignora valores negativos
            }
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
          final descricaoFinal = (descricao != null && descricao.trim().isNotEmpty) 
              ? descricao.trim() 
              : null;
          final codigoBarrasFinal = (codigoBarras != null && codigoBarras.trim().isNotEmpty) 
              ? codigoBarras.trim() 
              : null;
          
          // Normalizar código - adicionar prefixo "COD-" se necessário
          String? codigoFinal;
          if (codigo != null && codigo.trim().isNotEmpty) {
            final codigoTrim = codigo.trim();
            final codigoUpper = codigoTrim.toUpperCase();
            
            // Se já tem prefixo COD, manter como está
            if (codigoUpper.startsWith('COD')) {
              codigoFinal = codigoTrim;
            } else {
              // Adicionar prefixo COD- ao número
              // Remover espaços e caracteres especiais, manter apenas números
              final numeroCodigo = codigoTrim.replaceAll(RegExp(r'[^\d]'), '');
              if (numeroCodigo.isNotEmpty) {
                codigoFinal = 'COD-$numeroCodigo';
                debugPrint('>>> [Excel Import] Linha ${i + 1}: Código formatado "$codigoTrim" -> "$codigoFinal"');
              } else {
                codigoFinal = codigoTrim; // Se não tem número, manter como está
              }
            }
          }

          // Verificar duplicatas e produtos existentes
          String? chaveUnica = _gerarChaveUnica(codigoFinal, codigoBarrasFinal, nomeFinal);
          if (produtosProcessados.contains(chaveUnica)) {
            resultado['duplicados'] = (resultado['duplicados'] as int) + 1;
            (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeFinal): ⚠️ Duplicado na planilha');
            continue;
          }
          produtosProcessados.add(chaveUnica);

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
              grupo: grupoFinal,
              preco: preco,
              precoCusto: precoCusto ?? produtoExistente.precoCusto,
              estoque: estoqueNovo, // Usa o novo estoque ou mantém o atual
              codigoBarras: codigoBarrasFinal ?? produtoExistente.codigoBarras,
              codigo: codigoGerado.isNotEmpty ? codigoGerado : produtoExistente.codigo,
              updatedAt: agora,
            );
            produtosParaAtualizar.add(produtoAtualizado);
            resultado['atualizados'] = (resultado['atualizados'] as int) + 1;
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
          }
        } catch (e, stackTrace) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          String nomeErro = 'Desconhecido';
          try {
            nomeErro = _lerValorSeguro(row, indicesColunas['nome']) ?? 'Linha ${i + 1}';
          } catch (e2) {
            // Se não conseguir ler o nome, usar número da linha
            nomeErro = 'Linha ${i + 1}';
          }
          
          final mensagemErro = e.toString();
          (resultado['mensagens'] as List<String>).add('Linha ${i + 1} ($nomeErro): ❌ Erro: $mensagemErro');
          debugPrint('>>> [Excel Import] Erro ao processar linha ${i + 1}: $e');
          debugPrint('>>> [Excel Import] StackTrace: $stackTrace');
          
          // Tentar continuar processando outras linhas mesmo se uma falhar
          continue;
        }
      }

      // Salvar produtos novos
      for (final produto in produtosParaImportar) {
        try {
          await dataService.addProduto(produto);
          resultado['sucesso'] = (resultado['sucesso'] as int) + 1;
        } catch (e) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          (resultado['mensagens'] as List<String>).add('❌ Erro ao importar ${produto.nome}: $e');
          debugPrint('>>> Erro ao importar produto ${produto.nome}: $e');
        }
      }

      // Atualizar produtos existentes
      for (final produto in produtosParaAtualizar) {
        try {
          await dataService.updateProduto(produto);
        } catch (e) {
          resultado['erros'] = (resultado['erros'] as int) + 1;
          (resultado['mensagens'] as List<String>).add('❌ Erro ao atualizar ${produto.nome}: $e');
          debugPrint('>>> Erro ao atualizar produto ${produto.nome}: $e');
        }
      }

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
    
