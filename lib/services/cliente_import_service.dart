import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/cliente.dart';
import '../models/forma_pagamento.dart';
import '../models/pedido.dart';
import 'data_service.dart';

/// Resultado do planejamento da importação (parsing puro, sem gravar nada).
class PlanoImportacaoClientes {
  /// Clientes novos que serão criados.
  final List<Cliente> novos;

  /// Clientes que já existiam e terão o cadastro completado.
  final List<Cliente> atualizados;

  /// Linhas vazias / sem nome / duplicadas no próprio arquivo.
  final int ignorados;

  /// Linhas que estouraram erro.
  final int erros;

  /// Soma dos saldos devedores dos clientes NOVOS.
  final double saldoTotal;

  final List<String> mensagens;

  PlanoImportacaoClientes({
    required this.novos,
    required this.atualizados,
    required this.ignorados,
    required this.erros,
    required this.saldoTotal,
    required this.mensagens,
  });

  /// Novos clientes com saldo devedor que virarão fiado em aberto.
  List<Cliente> get comSaldoDevedor =>
      novos.where((c) => c.saldoDevedor > 0.01).toList();
}

/// Serviço para importar CLIENTES de arquivos Excel.
///
/// Complementa o [ExcelImportService] (que importa produtos):
/// - Detecta automaticamente as colunas pelo cabeçalho;
/// - Importa também o SALDO DEVEDOR (fiado) de cada cliente;
/// - Opcionalmente lança um "saldo inicial" em aberto na aba FIADO/CREDIÁRIO
///   do PDV, para o valor aparecer nos extratos e nos recebimentos;
/// - Persiste no PostgreSQL local (via [DataService.addClientesLote]) e na nuvem.
///
/// Formato esperado (flexível, qualquer ordem — detecta pelo nome da coluna):
///   Nome (obrigatório), CPF/CNPJ, Telefone, Celular/WhatsApp, E-mail,
///   Endereço, Número, Bairro, Cidade, Estado/UF, CEP,
///   Limite de Crédito, Saldo Devedor / Fiado, Observações.
class ClienteImportService {
  static const _uuid = Uuid();

  /// Lê o Excel e monta o plano (sem gravar nada). Ideal para testes.
  static PlanoImportacaoClientes planejar(
    Uint8List bytes, {
    required Iterable<Cliente> existentes,
  }) {
    final novos = <Cliente>[];
    final atualizados = <Cliente>[];
    final mensagens = <String>[];
    var ignorados = 0;
    var erros = 0;
    var saldoTotal = 0.0;

    try {
      final excel = Excel.decodeBytes(Uint8List.fromList(bytes));
      if (excel.tables.isEmpty) {
        mensagens.add('❌ Arquivo Excel vazio ou inválido');
        return PlanoImportacaoClientes(
          novos: novos,
          atualizados: atualizados,
          ignorados: ignorados,
          erros: erros,
          saldoTotal: saldoTotal,
          mensagens: mensagens,
        );
      }

      final sheet = excel.tables[excel.tables.keys.first]!;
      if (sheet.rows.isEmpty) {
        mensagens.add('❌ Planilha vazia');
        return PlanoImportacaoClientes(
          novos: novos,
          atualizados: atualizados,
          ignorados: ignorados,
          erros: erros,
          saldoTotal: saldoTotal,
          mensagens: mensagens,
        );
      }

      // 1. Detectar o cabeçalho nas primeiras linhas.
      Map<String, int?> colunas = {};
      int linhaInicio = 0;
      bool achouCabecalho = false;
      for (int i = 0; i < sheet.rows.length && i < 10; i++) {
        final row = sheet.rows[i];
        int palavras = 0;
        bool temNome = false;
        for (int j = 0; j < row.length; j++) {
          final v = _normalizar(_lerCelula(row, j) ?? '');
          if (v.isEmpty) continue;
          if (_ehPalavraChave(v)) palavras++;
          if (_ehNome(v)) temNome = true;
        }
        if (palavras >= 2 && temNome) {
          colunas = _detectarColunas(row);
          linhaInicio = i + 1;
          achouCabecalho = true;
          debugPrint(
            '>>> [Cliente Import] Cabeçalho detectado na linha $i: $colunas',
          );
          break;
        }
      }

      if (!achouCabecalho) {
        // Sem cabeçalho: assume a primeira coluna como Nome (caso comum de
        // listas simples "Nome; Telefone; Saldo").
        colunas = {'nome': 0};
        linhaInicio = 0;
        mensagens.add(
          '⚠️ Cabeçalho não identificado. Usando a 1ª coluna como Nome.',
        );
      }

      // 2. Índices dos clientes já existentes (para não duplicar).
      final porDocumento = <String, Cliente>{};
      final porNome = <String, Cliente>{};
      for (final c in existentes) {
        final doc = _somenteDigitos(c.cpfCnpj);
        if (doc.isNotEmpty) porDocumento[doc] = c;
        final nomeKey = _chaveNome(c.nome);
        if (nomeKey.isNotEmpty) porNome[nomeKey] = c;
      }

      final chavesVistas = <String>{};

      for (int i = linhaInicio; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (_linhaVazia(row)) {
          ignorados++;
          continue;
        }

        try {
          final nome = _ler(row, colunas['nome'])?.trim() ?? '';
          if (nome.isEmpty) {
            ignorados++;
            continue;
          }

          final doc = _somenteDigitos(_ler(row, colunas['cpfCnpj']));
          final chave = doc.isNotEmpty ? 'doc:$doc' : 'nome:${_chaveNome(nome)}';
          if (!chavesVistas.add(chave)) {
            // Duplicado dentro do próprio arquivo.
            ignorados++;
            continue;
          }

          final saldo = _parseDouble(_ler(row, colunas['saldoDevedor'])) ?? 0.0;
          final limite = _parseDouble(_ler(row, colunas['limiteCredito']));

          final existente =
              doc.isNotEmpty ? porDocumento[doc] : porNome[_chaveNome(nome)];

          if (existente != null) {
            // Não mexe no saldo devedor de quem já existe (evita cobrar o
            // fiado duas vezes numa reimportação); só completa o cadastro.
            atualizados.add(
              _aplicarCadastro(
                existente,
                row,
                colunas,
                nome: nome,
                doc: doc,
                limite: limite,
              ),
            );
            continue;
          }

          final cliente = _novoCliente(
            row,
            colunas,
            nome: nome,
            doc: doc,
            saldo: saldo,
            limite: limite,
          );
          novos.add(cliente);
          porNome[_chaveNome(cliente.nome)] = cliente;
          if (doc.isNotEmpty) porDocumento[doc] = cliente;
          saldoTotal += saldo;
        } catch (e) {
          erros++;
          mensagens.add('Linha ${i + 1}: ❌ Erro: $e');
          debugPrint('>>> [Cliente Import] Erro na linha ${i + 1}: $e');
        }
      }
    } catch (e, st) {
      erros++;
      mensagens.add('❌ Erro crítico ao ler o Excel: $e');
      debugPrint('>>> [Cliente Import] Erro crítico: $e\n$st');
    }

    return PlanoImportacaoClientes(
      novos: novos,
      atualizados: atualizados,
      ignorados: ignorados,
      erros: erros,
      saldoTotal: saldoTotal,
      mensagens: mensagens,
    );
  }

  /// Importa clientes a partir de um [File] (desktop/mobile).
  static Future<Map<String, dynamic>> importarClientes(
    File arquivo,
    DataService dataService, {
    bool lancarFiadoEmAberto = true,
    void Function(int processados, int total, String etapa)? onProgress,
  }) async {
    final bytes = await arquivo.readAsBytes();
    return importarClientesDeBytes(
      bytes,
      dataService,
      lancarFiadoEmAberto: lancarFiadoEmAberto,
      onProgress: onProgress,
    );
  }

  /// Importa clientes a partir dos bytes do arquivo (funciona também na web).
  ///
  /// Grava no banco local (PostgreSQL) e na nuvem, e devolve um mapa com o
  /// resumo da importação.
  static Future<Map<String, dynamic>> importarClientesDeBytes(
    Uint8List bytes,
    DataService dataService, {
    bool lancarFiadoEmAberto = true,
    void Function(int processados, int total, String etapa)? onProgress,
  }) async {
    final resultado = <String, dynamic>{
      'sucesso': 0,
      'atualizados': 0,
      'ignorados': 0,
      'erros': 0,
      'fiados': 0,
      'saldoTotal': 0.0,
      'mensagens': <String>[],
    };
    final mensagens = resultado['mensagens'] as List<String>;

    try {
      dataService.setImportandoExcel(true);
      onProgress?.call(0, 0, 'Lendo planilha...');

      final plano = planejar(bytes, existentes: dataService.clientes);
      mensagens.addAll(plano.mensagens);
      resultado['ignorados'] = plano.ignorados;
      resultado['erros'] = plano.erros;
      resultado['saldoTotal'] = plano.saldoTotal;

      // 1. Salvar clientes novos (e atualizados) no banco local + nuvem.
      if (plano.novos.isNotEmpty) {
        for (int i = 0; i < plano.novos.length; i += 200) {
          final fim =
              (i + 200 > plano.novos.length) ? plano.novos.length : i + 200;
          onProgress?.call(
            fim,
            plano.novos.length,
            'Salvando clientes ($fim de ${plano.novos.length})...',
          );
          await dataService.addClientesLote(plano.novos.sublist(i, fim));
        }
        resultado['sucesso'] = plano.novos.length;
      }
      if (plano.atualizados.isNotEmpty) {
        onProgress?.call(
          0,
          plano.atualizados.length,
          'Atualizando cadastros existentes...',
        );
        await dataService.addClientesLote(plano.atualizados);
        resultado['atualizados'] = plano.atualizados.length;
      }

      // 2. Lançar o saldo devedor como FIADO em aberto (opcional).
      if (lancarFiadoEmAberto) {
        final fiados = plano.comSaldoDevedor;
        for (int i = 0; i < fiados.length; i++) {
          onProgress?.call(
            i + 1,
            fiados.length,
            'Lançando fiado em aberto (${i + 1} de ${fiados.length})...',
          );
          try {
            await dataService.addPedido(_pedidoFiadoInicial(dataService, fiados[i]));
            resultado['fiados'] = (resultado['fiados'] as int) + 1;
          } catch (e) {
            resultado['erros'] = (resultado['erros'] as int) + 1;
            mensagens.add('Fiado de ${fiados[i].nome}: ❌ $e');
            debugPrint('>>> [Cliente Import] Erro ao lançar fiado: $e');
          }
        }
      }

      mensagens.add(
        '\n✅ RESUMO: ${plano.novos.length} novos '
        '(${_moeda(plano.saldoTotal)} em saldos), '
        '${plano.atualizados.length} atualizados, '
        '${resultado['fiados']} fiados em aberto, '
        '${plano.ignorados} ignorados, ${resultado['erros']} erros',
      );
    } catch (e, st) {
      resultado['erros'] = (resultado['erros'] as int) + 1;
      mensagens.add('❌ Erro crítico ao importar clientes: $e');
      debugPrint('>>> [Cliente Import] Erro crítico: $e\n$st');
    } finally {
      dataService.setImportandoExcel(false);
    }

    return resultado;
  }

  // ── Montagem dos modelos ────────────────────────────────────────────────

  static Cliente _novoCliente(
    List<dynamic> row,
    Map<String, int?> colunas, {
    required String nome,
    required String doc,
    required double saldo,
    double? limite,
  }) {
    final agora = DateTime.now();
    return Cliente(
      id: _uuid.v4(),
      nome: nome,
      nomeFantasia: _ler(row, colunas['nomeFantasia']),
      tipoPessoa: doc.length == 14 ? TipoPessoa.juridica : TipoPessoa.fisica,
      cpfCnpj: doc.isNotEmpty ? doc : null,
      email: _ler(row, colunas['email']),
      telefone: _ler(row, colunas['telefone']) ?? '',
      telefone2: _ler(row, colunas['telefone2']),
      whatsapp: _ler(row, colunas['whatsapp']),
      endereco: _ler(row, colunas['endereco']),
      numero: _ler(row, colunas['numero']),
      complemento: _ler(row, colunas['complemento']),
      bairro: _ler(row, colunas['bairro']),
      cidade: _ler(row, colunas['cidade']),
      estado: _ler(row, colunas['estado']),
      cep: _ler(row, colunas['cep']),
      observacoes: _ler(row, colunas['observacoes']),
      limiteCredito: limite,
      saldoDevedor: saldo,
      ativo: true,
      createdAt: agora,
      updatedAt: agora,
    );
  }

  static Cliente _aplicarCadastro(
    Cliente existente,
    List<dynamic> row,
    Map<String, int?> colunas, {
    required String nome,
    required String doc,
    double? limite,
  }) {
    String? ou(String? novo, String? atual) =>
        (novo != null && novo.trim().isNotEmpty) ? novo.trim() : atual;

    return existente.copyWith(
      nome: nome.isNotEmpty ? nome : existente.nome,
      nomeFantasia:
          ou(_ler(row, colunas['nomeFantasia']), existente.nomeFantasia),
      cpfCnpj: doc.isNotEmpty ? doc : existente.cpfCnpj,
      email: ou(_ler(row, colunas['email']), existente.email),
      telefone: ou(_ler(row, colunas['telefone']), existente.telefone),
      telefone2: ou(_ler(row, colunas['telefone2']), existente.telefone2),
      whatsapp: ou(_ler(row, colunas['whatsapp']), existente.whatsapp),
      endereco: ou(_ler(row, colunas['endereco']), existente.endereco),
      numero: ou(_ler(row, colunas['numero']), existente.numero),
      complemento: ou(_ler(row, colunas['complemento']), existente.complemento),
      bairro: ou(_ler(row, colunas['bairro']), existente.bairro),
      cidade: ou(_ler(row, colunas['cidade']), existente.cidade),
      estado: ou(_ler(row, colunas['estado']), existente.estado),
      cep: ou(_ler(row, colunas['cep']), existente.cep),
      observacoes: ou(_ler(row, colunas['observacoes']), existente.observacoes),
      limiteCredito: limite ?? existente.limiteCredito,
      updatedAt: DateTime.now(),
    );
  }

  /// Cria o pedido de FIADO em aberto que representa o saldo inicial.
  static Pedido _pedidoFiadoInicial(DataService dataService, Cliente cliente) {
    return montarPedidoFiado(cliente, numero: dataService.getProximoNumeroPedido());
  }

  /// Monta o pedido de FIADO em aberto que representa o saldo inicial do
  /// cliente. Puro (não grava nada), para poder ser verificado em teste.
  static Pedido montarPedidoFiado(Cliente cliente, {required String numero}) {
    final agora = DateTime.now();
    return Pedido(
      id: _uuid.v4(),
      numero: numero,
      clienteId: cliente.id,
      clienteNome: cliente.nome,
      clienteTelefone: cliente.telefone,
      clienteCpfCnpj: cliente.cpfCnpj,
      dataPedido: agora,
      status: 'Pendente',
      total: cliente.saldoDevedor,
      observacoes: 'Saldo devedor importado (saldo inicial)',
      produtos: const [],
      servicos: const [],
      pagamentos: [
        PagamentoPedido(
          id: _uuid.v4(),
          tipo: TipoPagamento.fiado,
          valor: cliente.saldoDevedor,
          recebido: false,
          observacao: 'Saldo inicial importado',
        ),
      ],
      createdAt: agora,
      updatedAt: agora,
    );
  }

  // ── Detecção de colunas ─────────────────────────────────────────────────

  /// Remove acentos/símbolos para facilitar a comparação de cabeçalhos.
  static String _normalizar(String texto) {
    final comAcentos = 'àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ';
    final semAcentos = 'aaaaaaaceeeeiiiionooooooouuuuyby';
    var resultado = texto.toLowerCase().trim();
    for (int i = 0; i < comAcentos.length; i++) {
      resultado = resultado.replaceAll(comAcentos[i], semAcentos[i]);
    }
    resultado = resultado.replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    resultado = resultado.replaceAll(RegExp(r'\s+'), ' ').trim();
    return resultado;
  }

  static bool _ehNome(String v) =>
      v == 'nome' ||
      v == 'cliente' ||
      v == 'nome cliente' ||
      v == 'nome do cliente' ||
      v.contains('nome cliente') ||
      v.contains('nomecliente');

  static bool _ehPalavraChave(String v) =>
      _ehNome(v) ||
      v.contains('cpf') ||
      v.contains('cnpj') ||
      v.contains('documento') ||
      v.contains('telefone') ||
      v.contains('celular') ||
      v.contains('fone') ||
      v.contains('whatsapp') ||
      v.contains('email') ||
      v.contains('saldo') ||
      v.contains('divida') ||
      v.contains('devedor') ||
      v.contains('fiado') ||
      v.contains('limite') ||
      v.contains('endereco') ||
      v.contains('cidade') ||
      v.contains('bairro');

  static Map<String, int?> _detectarColunas(List<dynamic> cabecalho) {
    final idx = <String, int?>{};
    for (int i = 0; i < cabecalho.length; i++) {
      final v = _normalizar(_lerCelula(cabecalho, i) ?? '');
      if (v.isEmpty) continue;

      // Nome (com prioridade sobre "nome fantasia"/"razão social").
      if (idx['nome'] == null && _ehNome(v)) {
        idx['nome'] = i;
        continue;
      }
      if (idx['nomeFantasia'] == null &&
          (v.contains('fantasia') || v.contains('razao'))) {
        idx['nomeFantasia'] = i;
        continue;
      }
      // Documento
      if (idx['cpfCnpj'] == null &&
          (v.contains('cpf') ||
              v.contains('cnpj') ||
              v.contains('documento'))) {
        idx['cpfCnpj'] = i;
        continue;
      }
      // Telefones / WhatsApp
      if (idx['whatsapp'] == null && v.contains('whats')) {
        idx['whatsapp'] = i;
        continue;
      }
      if (idx['telefone2'] == null &&
          (v.contains('telefone2') ||
              v.contains('telefone 2') ||
              v.contains('celular2') ||
              v.contains('fone2') ||
              v.contains('fone 2'))) {
        idx['telefone2'] = i;
        continue;
      }
      if (idx['telefone'] == null &&
          (v.contains('telefone') ||
              v.contains('celular') ||
              v.contains('fone') ||
              v == 'tel' ||
              v == 'contato')) {
        idx['telefone'] = i;
        continue;
      }
      // Saldo devedor / fiado (checar ANTES de "limite").
      if (idx['saldoDevedor'] == null &&
          (v.contains('saldo') ||
              v.contains('divida') ||
              v.contains('devedor') ||
              v.contains('devido') ||
              v.contains('devendo') ||
              v.contains('fiado') ||
              v.contains('receber'))) {
        idx['saldoDevedor'] = i;
        continue;
      }
      if (idx['limiteCredito'] == null && v.contains('limite')) {
        idx['limiteCredito'] = i;
        continue;
      }
      if (idx['email'] == null && v.contains('email')) {
        idx['email'] = i;
        continue;
      }
      if (idx['cep'] == null && v.contains('cep')) {
        idx['cep'] = i;
        continue;
      }
      if (idx['estado'] == null && (v == 'uf' || v.contains('estado'))) {
        idx['estado'] = i;
        continue;
      }
      if (idx['cidade'] == null &&
          (v.contains('cidade') || v.contains('municipio'))) {
        idx['cidade'] = i;
        continue;
      }
      if (idx['bairro'] == null && v.contains('bairro')) {
        idx['bairro'] = i;
        continue;
      }
      if (idx['complemento'] == null && v.contains('complemento')) {
        idx['complemento'] = i;
        continue;
      }
      if (idx['numero'] == null &&
          (v == 'numero' ||
              v == 'num' ||
              v.contains('numero') ||
              v.contains('nr'))) {
        idx['numero'] = i;
        continue;
      }
      if (idx['endereco'] == null &&
          (v.contains('endereco') ||
              v.contains('logradouro') ||
              v.contains('rua') ||
              v == 'end')) {
        idx['endereco'] = i;
        continue;
      }
      if (idx['observacoes'] == null &&
          (v.contains('observacao') ||
              v.contains('obs') ||
              v.contains('nota'))) {
        idx['observacoes'] = i;
        continue;
      }
    }

    if (idx['nome'] == null) {
      // Sem coluna "nome" explícita: usa a primeira coluna.
      idx['nome'] = 0;
    }
    return idx;
  }

  // ── Leitura/parse de células ────────────────────────────────────────────

  static String? _ler(List<dynamic> row, int? coluna) {
    if (coluna == null) return null;
    return _lerCelula(row, coluna);
  }

  static String? _lerCelula(List<dynamic> row, int coluna) {
    try {
      if (coluna < 0 || coluna >= row.length) return null;
      final cell = row[coluna];
      if (cell == null) return null;

      dynamic value;
      try {
        value = (cell as dynamic).value;
      } catch (_) {
        value = cell is String ? cell : cell.toString();
      }
      if (value == null) return null;

      if (value is String) {
        final s = value.trim();
        return s.isEmpty ? null : s;
      } else if (value is int) {
        return value.toString();
      } else if (value is double) {
        return value % 1 == 0 ? value.toInt().toString() : value.toString();
      } else if (value is bool) {
        return value ? '1' : '0';
      } else if (value is DateTime) {
        return value.toString();
      }
      final s = value.toString().trim();
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint('>>> [Cliente Import] Erro ao ler célula $coluna: $e');
      return null;
    }
  }

  static bool _linhaVazia(List<dynamic> row) {
    if (row.isEmpty) return true;
    for (int i = 0; i < row.length; i++) {
      final v = _lerCelula(row, i);
      if (v != null && v.trim().isNotEmpty) return false;
    }
    return true;
  }

  /// Converte texto em double aceitando formato brasileiro (1.234,56) e
  /// símbolos de moeda.
  static double? _parseDouble(String? value) {
    if (value == null) return null;
    var s = value.trim().replaceAll(RegExp(r'[^\d,.\-]'), '');
    if (s.isEmpty) return null;
    if (s.contains(',') && s.contains('.')) {
      // 1.234,56 → ponto é milhar
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (s.contains(',')) {
      final partes = s.split(',');
      s = (partes.length == 2 && partes[1].length <= 2)
          ? s.replaceAll(',', '.')
          : s.replaceAll(',', '');
    }
    return double.tryParse(s);
  }

  static String _somenteDigitos(String? valor) =>
      (valor ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  static String _chaveNome(String nome) => _normalizar(nome);

  static String _moeda(double valor) => 'R\$ ${valor.toStringAsFixed(2)}';
}
