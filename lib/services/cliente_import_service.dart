import 'dart:convert';
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
///   Código, Nome (obrigatório), CPF/CNPJ, Telefone, Celular/WhatsApp, E-mail,
///   Endereço, Número, Bairro, Cidade, Estado/UF, CEP,
///   Limite de Crédito, Saldo Devedor / Fiado, Observações.
class ClienteImportService {
  static const _uuid = Uuid();

  /// Lê a planilha (Excel ou CSV) e monta o plano (sem gravar nada).
  /// Ideal para testes.
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
      final linhas = _lerLinhas(bytes);
      if (linhas.isEmpty) {
        mensagens.add('❌ Arquivo vazio ou inválido');
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
      for (int i = 0; i < linhas.length && i < 10; i++) {
        final row = linhas[i];
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

      for (int i = linhaInicio; i < linhas.length; i++) {
        final row = linhas[i];
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
      mensagens.add('❌ Erro crítico ao ler o arquivo: $e');
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

      if (plano.novos.isEmpty && plano.atualizados.isEmpty) {
        mensagens.add(
          '⚠️ Nenhum cliente foi lido do arquivo. Confira se a 1ª linha é o '
          'cabeçalho (ex.: "Nome;Telefone;Saldo Devedor") e se o arquivo é '
          'Excel (.xlsx/.xls) ou CSV de verdade (.csv/.txt).',
        );
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
      codigo: _ler(row, colunas['codigo']),
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
      codigo: ou(_ler(row, colunas['codigo']), existente.codigo),
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
      v == 'codigo' ||
      v == 'cod' ||
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
      // Código do cliente ("Código", "Cód", "Código do Cliente").
      if (idx['codigo'] == null &&
          (v == 'codigo' ||
              v == 'cod' ||
              v == 'codigo cliente' ||
              v == 'cod cliente' ||
              v == 'codigo do cliente' ||
              v == 'cod do cliente')) {
        idx['codigo'] = i;
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

  // ── Leitura do arquivo (Excel ou CSV) ───────────────────────────────────

  /// Lê as linhas do arquivo escolhido.
  ///
  /// Aceita planilhas Excel (.xlsx/.xls) e também arquivos CSV/TXT, que antes
  /// eram simplesmente rejeitados — o seletor só oferecia Excel.
  static List<List<dynamic>> _lerLinhas(Uint8List bytes) {
    if (_ehCsv(bytes)) {
      final linhas = _lerCsv(_textoDeBytes(bytes));
      debugPrint(
        '>>> [Cliente Import] CSV lido: ${linhas.length} linhas',
      );
      return linhas.cast<List<dynamic>>();
    }

    final excel = Excel.decodeBytes(Uint8List.fromList(bytes));
    if (excel.tables.isEmpty) return <List<dynamic>>[];
    final sheet = excel.tables[excel.tables.keys.first]!;
    return sheet.rows;
  }

  /// Decide se os bytes são de texto (CSV) ou de uma planilha binária.
  static bool _ehCsv(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return false; // XLSX (ZIP: "PK")
    }
    // CSV/TXT salvo como "Texto Unicode" pelo Excel vem em UTF-16 (com BOM).
    if (_utf16ComBom(bytes)) return true;
    if (bytes.length >= 4 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0) {
      return false; // XLS antigo (OLE)
    }
    // Muitos bytes nulos sem BOM também indicam texto UTF-16 (Excel).
    if (_pareceUtf16SemBom(bytes)) return true;
    // Qualquer byte nulo indica arquivo binário, não texto.
    final amostra = bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes;
    for (final b in amostra) {
      if (b == 0) return false;
    }
    return true;
  }

  static bool _utf16ComBom(Uint8List bytes) {
    if (bytes.length < 2) return false;
    return (bytes[0] == 0xFF && bytes[1] == 0xFE) ||
        (bytes[0] == 0xFE && bytes[1] == 0xFF);
  }

  static bool _pareceUtf16SemBom(Uint8List bytes) {
    if (bytes.length < 8) return false;
    final amostra = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
    var nulos = 0;
    for (final b in amostra) {
      if (b == 0) nulos++;
    }
    return nulos > amostra.length ~/ 4;
  }

  /// Decodifica o texto tentando UTF-8, UTF-16 (Excel) e caindo para Latin-1
  /// (comum em CSVs exportados pelo Excel em português).
  static String _textoDeBytes(Uint8List bytes) {
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _decodificarUtf16(bytes.sublist(2), littleEndian: true);
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _decodificarUtf16(bytes.sublist(2), littleEndian: false);
      }
    }
    if (_pareceUtf16SemBom(bytes)) {
      // Sem BOM: deduz a ordem pelo byte nulo da primeira letra.
      final littleEndian = bytes.length > 1 && bytes[1] == 0;
      return _decodificarUtf16(bytes, littleEndian: littleEndian);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _decodificarUtf16(
    Uint8List bytes, {
    required bool littleEndian,
  }) {
    final unidades = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      unidades.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(unidades);
  }

  /// Converte o conteúdo de um CSV em linhas/campos, respeitando aspas.
  static List<List<String>> _lerCsv(String texto) {
    var conteudo = texto;
    if (conteudo.isNotEmpty && conteudo.codeUnitAt(0) == 0xFEFF) {
      conteudo = conteudo.substring(1); // remove BOM
    }

    // O delimitador mais frequente na primeira linha preenchida manda.
    final primeiraLinha = conteudo
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final delimitador = _detectarDelimitador(primeiraLinha);

    final linhas = <List<String>>[];
    var linha = <String>[];
    final campo = StringBuffer();
    var dentroAspas = false;

    for (int i = 0; i < conteudo.length; i++) {
      final c = conteudo[i];
      if (dentroAspas) {
        if (c == '"') {
          if (i + 1 < conteudo.length && conteudo[i + 1] == '"') {
            campo.write('"');
            i++;
          } else {
            dentroAspas = false;
          }
        } else {
          campo.write(c);
        }
        continue;
      }

      if (c == '"') {
        dentroAspas = true;
      } else if (c == delimitador) {
        linha.add(campo.toString());
        campo.clear();
      } else if (c == '\n') {
        linha.add(campo.toString());
        campo.clear();
        linhas.add(linha);
        linha = <String>[];
      } else if (c == '\r') {
        // Ignorado: o \n é quem fecha a linha.
      } else {
        campo.write(c);
      }
    }
    if (campo.isNotEmpty || linha.isNotEmpty) {
      linha.add(campo.toString());
      linhas.add(linha);
    }
    return linhas;
  }

  static String _detectarDelimitador(String linha) {
    const candidatos = [';', ',', '\t', '|'];
    var melhor = ';';
    var maior = 0;
    for (final d in candidatos) {
      final qtd = d.allMatches(linha).length;
      if (qtd > maior) {
        maior = qtd;
        melhor = d;
      }
    }
    return melhor;
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
