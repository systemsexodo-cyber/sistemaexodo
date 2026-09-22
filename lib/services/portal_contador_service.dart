import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/empresa.dart';
import '../models/nfce.dart';
import '../models/produto.dart';
import '../models/venda_balcao.dart';
import 'supabase_service.dart';

/// Tipo do documento fiscal exibido no Portal do Contador.
///
/// O portal mostra "todas as notas separadas": as NFC-e emitidas, as NF-e
/// emitidas e as NF-e de entrada (recebidas) ficam em seções distintas.
enum TipoDocumentoPortal {
  nfceEmitida('NFC-e Emitidas', 'nfces'),
  nfeEmitida('NF-e Emitidas', 'nfes'),
  nfeRecebida('NF-e Recebidas', 'notas_entrada');

  const TipoDocumentoPortal(this.titulo, this.tabela);

  final String titulo;
  final String tabela;
}

/// Um XML disponível para download no portal.
class DocumentoFiscalPortal {
  final TipoDocumentoPortal tipo;
  final String empresaId;
  final String id;
  final String numero;
  final String serie;
  final String chave;
  final String status;
  final DateTime? data;
  final double valor;
  final String participante;

  /// XML já gravado na coluna da tabela (quando existir).
  final String xml;

  /// true quando o XML está no bucket `xmls` do Storage, mesmo que a coluna da
  /// tabela esteja vazia. É de lá que o app desktop envia os arquivos de
  /// `C:\ExodoNFCe`, então na prática é a fonte principal.
  final bool disponivelNaNuvem;

  DocumentoFiscalPortal({
    required this.tipo,
    required this.empresaId,
    required this.id,
    required this.numero,
    required this.serie,
    required this.chave,
    required this.status,
    required this.data,
    required this.valor,
    required this.participante,
    required this.xml,
    required this.disponivelNaNuvem,
  });

  bool get temXml => xml.trim().isNotEmpty || disponivelNaNuvem;

  /// Caminho do XML dentro do bucket `xmls`.
  String get caminhoStorage => '$empresaId/$chave.xml';

  /// Nome do arquivo sugerido para download (mesmo padrão usado pelo sistema
  /// no disco: `[CHAVE]-nfe.xml`).
  String get nomeArquivo {
    if (chave.isNotEmpty) return '$chave-nfe.xml';
    final base = '${tipo.name}_${numero}_$id';
    return '${base.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}.xml';
  }

  String get identificacao => chave.isNotEmpty ? chave : 'SEM-CHAVE-$id';
}

/// Sessão do contador autenticado no portal.
class PortalContadorSessao {
  final String cnpj;
  final String nome;
  final List<EmpresaPortalContador> empresas;

  PortalContadorSessao({
    required this.cnpj,
    required this.nome,
    required this.empresas,
  });
}

/// Empresa liberada para o contador (uma ou mais, quando o mesmo CNPJ possui
/// mais de um cadastro).
class EmpresaPortalContador {
  final String id;
  final String nome;
  final String cnpj;

  EmpresaPortalContador({
    required this.id,
    required this.nome,
    required this.cnpj,
  });
}

/// Serviço do Portal do Contador: autentica pelo CNPJ + senha e entrega os
/// XMLs das notas da empresa para download.
class PortalContadorService {
  PortalContadorService._();

  static final PortalContadorService instance = PortalContadorService._();

  static const String _tabelaAcessos = 'portal_contador_acessos';
  static const String _tabelaEmpresas = 'empresas';

  /// Bucket do Storage onde ficam os XMLs (`xmls/<empresa_id>/<chave>.xml`).
  static const String _bucketXmls = 'xmls';

  /// XMLs já baixados do Storage nesta sessão (evita baixar de novo no ZIP).
  final Map<String, String> _cacheXml = {};

  /// Colunas de data usadas pelas tabelas fiscais.
  static const List<String> _colunasDataFiscais = [
    'data_emissao',
    'dataEmissao',
    'data_entrada',
  ];

  /// Colunas de data usadas pela tabela de vendas.
  static const List<String> _colunasDataVendas = ['data_venda', 'dataVenda'];

  // ==========================================================================
  // DADOS PARA OS RELATÓRIOS (PDF FISCAL E EXCEL)
  // ==========================================================================

  /// Empresa usada no cabeçalho dos relatórios.
  Future<Empresa?> carregarEmpresa(String empresaId) async {
    try {
      final linha = await _client
          .from(_tabelaEmpresas)
          .select('*')
          .eq('id', empresaId)
          .maybeSingle();
      if (linha == null) return null;
      return Empresa.fromMap(Map<String, dynamic>.from(linha));
    } catch (e) {
      debugPrint('>>> [PortalContador] Erro ao carregar a empresa: $e');
      return null;
    }
  }

  /// NFC-e da empresa no período — base do pacote contábil.
  Future<List<NFCe>> carregarNfces({
    required String empresaId,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    final linhas = await _consultarPeriodo(
      'nfces',
      empresaId,
      inicio,
      fim,
      _colunasDataFiscais,
    );
    return _converterLista(linhas, NFCe.fromMap);
  }

  /// Vendas do balcão no período (para separar faturamento fiscal do não fiscal).
  Future<List<VendaBalcao>> carregarVendas({
    required String empresaId,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    final linhas = await _consultarPeriodo(
      'vendas_balcao',
      empresaId,
      inicio,
      fim,
      _colunasDataVendas,
    );
    return _converterLista(linhas, VendaBalcao.fromMap);
  }

  /// Produtos da empresa (NCM, código e unidade usados nos relatórios).
  Future<List<Produto>> carregarProdutos(String empresaId) async {
    final linhas = await _consultarPeriodo('produtos', empresaId, null, null, const []);
    return _converterLista(linhas, Produto.fromMap);
  }

  /// Quantidade máxima de linhas que o PostgREST devolve por requisição.
  /// Sem paginar, os relatórios veriam só as primeiras 1000 linhas.
  static const int _tamanhoPagina = 1000;

  /// Consulta genérica por empresa + período, resolvendo a coluna de data e
  /// paginando o resultado até o fim.
  Future<List<Map<String, dynamic>>> _consultarPeriodo(
    String tabela,
    String empresaId,
    DateTime? inicio,
    DateTime? fim,
    List<String> candidatosData,
  ) async {
    try {
      final coluna = await _colunaData(tabela, candidatosData);

      PostgrestFilterBuilder<PostgrestList> montarFiltro() {
        var filtro =
            _client.from(tabela).select('*').inFilter('empresa_id', [empresaId]);
        if (coluna != null) {
          if (inicio != null) filtro = filtro.gte(coluna, _isoInicio(inicio));
          if (fim != null) filtro = filtro.lte(coluna, _isoFim(fim));
        }
        return filtro;
      }

      final linhas = <Map<String, dynamic>>[];
      var deslocamento = 0;
      while (true) {
        final filtro = montarFiltro();
        final ate = deslocamento + _tamanhoPagina - 1;
        final lote = coluna != null
            ? await filtro.order(coluna, ascending: false).range(deslocamento, ate)
            : await filtro.range(deslocamento, ate);

        for (final linha in lote) {
          linhas.add(Map<String, dynamic>.from(linha));
        }

        if (lote.length < _tamanhoPagina) break;
        deslocamento += _tamanhoPagina;

        // Trava de segurança: 200 mil linhas é muito acima de qualquer uso real.
        if (deslocamento >= 200000) break;
      }

      return linhas;
    } catch (e) {
      debugPrint('>>> [PortalContador] Erro ao consultar $tabela: $e');
      return [];
    }
  }

  static List<T> _converterLista<T>(
    List<Map<String, dynamic>> linhas,
    T Function(Map<String, dynamic>) converter,
  ) {
    final itens = <T>[];
    for (final linha in linhas) {
      try {
        itens.add(converter(linha));
      } catch (e) {
        debugPrint('>>> [PortalContador] Registro ignorado na conversão: $e');
      }
    }
    return itens;
  }

  /// Cache das colunas que realmente existem em cada tabela, para montar o
  /// filtro de período sem quebrar quando o banco usa camelCase ou snake_case.
  final Map<String, String?> _cacheColunaData = {};

  SupabaseClient get _client => SupabaseService.instance.client;

  // ==========================================================================
  // AUTENTICAÇÃO
  // ==========================================================================

  /// Autentica o contador pelo CNPJ + senha cadastrados em
  /// `portal_contador_acessos` e devolve as empresas liberadas.
  Future<PortalContadorSessao> login({
    required String cnpj,
    required String senha,
  }) async {
    if (!SupabaseService.isAvailable) {
      throw Exception('Sem conexão com a nuvem. Tente novamente em instantes.');
    }

    final cnpjLimpo = somenteDigitos(cnpj);
    if (cnpjLimpo.isEmpty) {
      throw Exception('Informe o CNPJ.');
    }
    if (senha.trim().isEmpty) {
      throw Exception('Informe a senha.');
    }

    Map<String, dynamic> acesso;
    try {
      final resposta = await _client
          .from(_tabelaAcessos)
          .select('*')
          .eq('cnpj', cnpjLimpo)
          .maybeSingle();
      if (resposta == null) {
        throw Exception('CNPJ não cadastrado no portal. Fale com o suporte.');
      }
      acesso = Map<String, dynamic>.from(resposta);
    } on PostgrestException catch (e) {
      debugPrint('>>> [PortalContador] Erro ao consultar acesso: $e');
      throw Exception(
        'Portal ainda não configurado na nuvem. Rode o script '
        'CRIAR_PORTAL_CONTADOR_SUPABASE.sql no Supabase.',
      );
    }

    if (acesso['ativo'] == false) {
      throw Exception('Acesso desativado. Fale com o suporte.');
    }

    final salt = acesso['salt']?.toString() ?? '';
    final esperado = (acesso['senha_hash']?.toString() ?? '').toLowerCase();
    final calculado = gerarHash(senha: senha.trim(), salt: salt);

    if (esperado.isEmpty || calculado != esperado) {
      throw Exception('Senha incorreta.');
    }

    final empresas = await _buscarEmpresasPorCnpj(cnpjLimpo);
    if (empresas.isEmpty) {
      throw Exception(
        'Nenhuma empresa cadastrada com o CNPJ $cnpjLimpo no sistema.',
      );
    }

    // Registra o último acesso (best-effort: não impede o login).
    try {
      await _client.from(_tabelaAcessos).update({
        'ultimo_acesso': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', acesso['id'].toString());
    } catch (e) {
      debugPrint('>>> [PortalContador] Não foi possível registrar último acesso: $e');
    }

    return PortalContadorSessao(
      cnpj: cnpjLimpo,
      nome: acesso['nome']?.toString() ?? 'Contador',
      empresas: empresas,
    );
  }

  /// Busca as empresas cujo CNPJ (com ou sem máscara) casa com o informado.
  Future<List<EmpresaPortalContador>> _buscarEmpresasPorCnpj(String cnpj) async {
    final resultado = <EmpresaPortalContador>[];
    try {
      final linhas = await _client.from(_tabelaEmpresas).select('*');
      for (final linha in linhas) {
        final registro = Map<String, dynamic>.from(linha);
        final cnpjEmpresa = somenteDigitos(
          registro['cnpj']?.toString() ?? '',
        );
        if (cnpjEmpresa != cnpj) continue;

        resultado.add(EmpresaPortalContador(
          id: registro['id']?.toString() ?? '',
          nome: _nomeEmpresa(registro),
          cnpj: cnpjEmpresa,
        ));
      }
    } catch (e) {
      debugPrint('>>> [PortalContador] Erro ao buscar empresas: $e');
    }
    return resultado;
  }

  // ==========================================================================
  // XMLs
  // ==========================================================================

  /// Lista todos os documentos (por tipo) de uma ou mais empresas no período.
  ///
  /// [inicio] e [fim] filtram pela data de emissão. Quando não informados,
  /// retorna tudo o que estiver na nuvem.
  Future<List<DocumentoFiscalPortal>> listarDocumentos({
    required List<String> empresaIds,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    final ids = empresaIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return [];

    // Uma única consulta ao Storage já diz quais chaves têm XML na nuvem.
    final chavesNaNuvem = await _chavesNoStorage(ids);

    final documentos = <DocumentoFiscalPortal>[];

    // Chaves já incluídas. A mesma nota pode existir em `nfces` (gravada pela
    // bridge) e em `nfes` (gravada pelo app), então sem isso ela apareceria
    // duplicada. Notas sem chave de acesso são identificadas por número+série.
    final vistos = <String>{};

    // Índice por número+série+tipo: o mesmo documento pode chegar aqui duas
    // vezes (ex.: a nota autorizada na tabela e o rascunho do app), e as duas
    // versões não compartilham a chave de acesso. Nesse caso fica a que TEM
    // chave — é a nota fiscal de verdade.
    final porNumero = <String, int>{};

    void adicionar(DocumentoFiscalPortal documento) {
      if (documento.chave.isNotEmpty && !vistos.add('chave:${documento.chave}')) {
        return;
      }

      if (documento.numero.isNotEmpty) {
        final chaveNota =
            '${documento.tipo.name}:${documento.numero}:${documento.serie}';
        final existente = porNumero[chaveNota];
        if (existente != null) {
          final atual = documentos[existente];
          if (atual.chave.isEmpty && documento.chave.isNotEmpty) {
            documentos[existente] = documento;
          }
          return;
        }
        porNumero[chaveNota] = documentos.length;
      }

      documentos.add(documento);
    }

    // A tabela `nfces` guarda TODAS as notas emitidas pelo sistema — inclusive
    // as NF-e modelo 55, porque é nela que a bridge de emissão grava. Por isso o
    // tipo é decidido pelo MODELO dentro da chave de acesso (posições 21 e 22) e
    // não pelo nome da tabela: antes a NF-e saía no portal como se fosse NFC-e.
    for (final documento in await _buscarPorTipo(
      tipo: TipoDocumentoPortal.nfceEmitida,
      empresaIds: ids,
      inicio: inicio,
      fim: fim,
      chavesNaNuvem: chavesNaNuvem,
    )) {
      adicionar(
        modeloDaChave(documento.chave) == '55'
            ? _reclassificar(documento, TipoDocumentoPortal.nfeEmitida)
            : documento,
      );
    }

    for (final tipo in const [
      TipoDocumentoPortal.nfeEmitida,
      TipoDocumentoPortal.nfeRecebida,
    ]) {
      for (final documento in await _buscarPorTipo(
        tipo: tipo,
        empresaIds: ids,
        inicio: inicio,
        fim: fim,
        chavesNaNuvem: chavesNaNuvem,
      )) {
        adicionar(documento);
      }
    }

    documentos.sort((a, b) {
      final da = a.data ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.data ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return documentos;
  }

  /// Modelo do documento (`55` = NF-e, `65` = NFC-e) extraído da chave de acesso
  /// (44 dígitos, posições 21 e 22).
  ///
  /// Como NF-e e NFC-e ficam na MESMA tabela (`nfces`), essa é a única forma
  /// confiável de saber o modelo de cada nota — não existe coluna de modelo no
  /// banco.
  static String? modeloDaChave(String chave) {
    final digitos = somenteDigitos(chave);
    if (digitos.length != 44) return null;
    return digitos.substring(20, 22);
  }

  /// Devolve o mesmo documento apontando para outro tipo (o modelo não pode ser
  /// deduzido da tabela em que a nota foi gravada).
  static DocumentoFiscalPortal _reclassificar(
    DocumentoFiscalPortal documento,
    TipoDocumentoPortal tipo,
  ) {
    return DocumentoFiscalPortal(
      tipo: tipo,
      empresaId: documento.empresaId,
      id: documento.id,
      numero: documento.numero,
      serie: documento.serie,
      chave: documento.chave,
      status: documento.status,
      data: documento.data,
      valor: documento.valor,
      participante: documento.participante,
      xml: documento.xml,
      disponivelNaNuvem: documento.disponivelNaNuvem,
    );
  }

  /// Lê o bucket `xmls` e devolve o conjunto de chaves com arquivo na nuvem.
  Future<Set<String>> _chavesNoStorage(List<String> empresaIds) async {
    final chaves = <String>{};
    for (final empresaId in empresaIds) {
      try {
        var deslocamento = 0;
        while (true) {
          final arquivos = await _client.storage.from(_bucketXmls).list(
                path: empresaId,
                searchOptions: SearchOptions(
                  limit: _tamanhoPagina,
                  offset: deslocamento,
                ),
              );
          for (final arquivo in arquivos) {
            final nome = arquivo.name;
            if (nome.toLowerCase().endsWith('.xml')) {
              chaves.add(nome.substring(0, nome.length - 4));
            }
          }
          if (arquivos.length < _tamanhoPagina) break;
          deslocamento += _tamanhoPagina;
          if (deslocamento >= 200000) break;
        }
      } catch (e) {
        debugPrint('>>> [PortalContador] Storage indisponível ($empresaId): $e');
      }
    }
    debugPrint('>>> [PortalContador] ${chaves.length} XML(s) no Storage');
    return chaves;
  }

  /// Devolve o XML do documento: usa a coluna da tabela quando preenchida e,
  /// senão, baixa do bucket `xmls`.
  Future<String> obterXml(DocumentoFiscalPortal documento) async {
    if (documento.xml.trim().isNotEmpty) return documento.xml;
    if (!documento.disponivelNaNuvem) return '';

    if (_cacheXml.containsKey(documento.caminhoStorage)) {
      return _cacheXml[documento.caminhoStorage]!;
    }

    try {
      final bytes =
          await _client.storage.from(_bucketXmls).download(documento.caminhoStorage);
      final xml = utf8.decode(bytes, allowMalformed: true);
      _cacheXml[documento.caminhoStorage] = xml;
      return xml;
    } catch (e) {
      debugPrint('>>> [PortalContador] Falha ao baixar ${documento.caminhoStorage}: $e');
      return '';
    }
  }

  Future<List<DocumentoFiscalPortal>> _buscarPorTipo({
    required TipoDocumentoPortal tipo,
    required List<String> empresaIds,
    required Set<String> chavesNaNuvem,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    final tabela = tipo.tabela;
    try {
      final registros = <Map<String, dynamic>>[];
      for (final empresaId in empresaIds) {
        registros.addAll(await _consultarPeriodo(
          tabela,
          empresaId,
          inicio,
          fim,
          _colunasDataFiscais,
        ));
      }

      final documentos = <DocumentoFiscalPortal>[];
      var rascunhos = 0;

      for (final registro in registros) {
        // Rascunhos `pend-<millis>` são as notas "em emissão" gravadas pelo app
        // antes de falar com a SEFAZ. Não são documentos fiscais (não têm chave
        // nem XML) e, quando o app não consegue apagá-los, apareceriam no portal
        // como uma cópia "PENDENTE" da nota que já foi autorizada.
        if (_ehRascunho(registro)) {
          rascunhos++;
          continue;
        }

        final data = _dataDoRegistro(registro);

        // Filtro de segurança no cliente: garante o período mesmo quando a
        // tabela não tem uma coluna de data reconhecida.
        if (inicio != null && data != null && data.isBefore(_inicioDoDia(inicio))) {
          continue;
        }
        if (fim != null && data != null && data.isAfter(_fimDoDia(fim))) {
          continue;
        }

        documentos.add(_converter(tipo, registro, data, chavesNaNuvem));
      }

      if (rascunhos > 0) {
        debugPrint(
          '>>> [PortalContador] ${tipo.titulo}: $rascunhos rascunho(s) ignorado(s)',
        );
      }
      debugPrint('>>> [PortalContador] ${tipo.titulo}: ${documentos.length} documento(s)');
      return documentos;
    } catch (e) {
      debugPrint('>>> [PortalContador] Erro ao ler $tabela: $e');
      return [];
    }
  }

  /// Rascunho de emissão do app (ainda não é documento fiscal).
  ///
  /// O fluxo de emissão grava um registro com `id` começando em `pend-` antes de
  /// falar com a SEFAZ e o remove quando a nota é autorizada. Se esse DELETE
  /// falhar (app fechado, queda de rede), o registro fica para trás — e o portal
  /// não pode exibi-lo, senão a nota aparece duas vezes: autorizada e "Pendente".
  static bool _ehRascunho(Map<String, dynamic> registro) =>
      (registro['id']?.toString() ?? '').toLowerCase().startsWith('pend-');

  DocumentoFiscalPortal _converter(
    TipoDocumentoPortal tipo,
    Map<String, dynamic> registro,
    DateTime? data,
    Set<String> chavesNaNuvem,
  ) {
    final empresaId = registro['empresa_id']?.toString() ??
        registro['empresaId']?.toString() ??
        '';
    final chave = somenteDigitos(
      _primeiroTexto(registro, [
        'chave_acesso',
        'chaveAcesso',
        'chaveNFe',
        'chave_nfe',
      ]),
    );

    return DocumentoFiscalPortal(
      tipo: tipo,
      empresaId: empresaId,
      id: registro['id']?.toString() ?? '',
      numero: _primeiroTexto(registro, ['numero', 'numeroNotaReal', 'numero_nota_real']),
      serie: _primeiroTexto(registro, ['serie']),
      chave: chave,
      status: _primeiroTexto(registro, ['status']).toLowerCase(),
      data: data,
      valor: _primeiroNumero(registro, ['valor_total', 'valorTotal']),
      participante: _primeiroTexto(registro, [
        'nome_consumidor',
        'nomeConsumidor',
        'fornecedor_nome',
        'fornecedorNome',
      ]),
      xml: _xmlDoRegistro(registro),
      disponivelNaNuvem: chave.isNotEmpty && chavesNaNuvem.contains(chave),
    );
  }

  /// Extrai o XML do registro aceitando os dois padrões de nome usados pelo
  /// sistema (snake_case e camelCase). Prioriza o XML AUTORIZADO.
  static String _xmlDoRegistro(Map<String, dynamic> registro) {
    const candidatos = [
      'xml_autorizado',
      'xmlAutorizado',
      'xml_enviado',
      'xmlEnviado',
      'xml_original',
      'xmlOriginal',
      'xml',
      'xml_retorno',
      'xmlRetorno',
    ];
    for (final chave in candidatos) {
      final valor = registro[chave];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }
    return '';
  }

  /// Descobre (e memoriza) qual coluna de data a tabela possui.
  Future<String?> _colunaData(String tabela, List<String> candidatos) async {
    if (_cacheColunaData.containsKey(tabela)) return _cacheColunaData[tabela];

    String? encontrada;
    try {
      final amostra = await _client.from(tabela).select('*').limit(1);
      if (amostra.isNotEmpty) {
        final registro = Map<String, dynamic>.from(amostra.first);
        for (final candidato in candidatos) {
          if (registro.containsKey(candidato)) {
            encontrada = candidato;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [PortalContador] Não foi possível inspecionar $tabela: $e');
    }

    _cacheColunaData[tabela] = encontrada;
    return encontrada;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  /// Hash usado na coluna `senha_hash`: sha256(salt + senha) em hexadecimal.
  /// O script `criar_acesso_portal_contador.py` gera exatamente o mesmo valor.
  static String gerarHash({required String senha, required String salt}) {
    return sha256.convert(utf8.encode('$salt$senha')).toString();
  }

  /// Gera um salt aleatório simples (hexadecimal) para novos acessos.
  static String gerarSalt() {
    final agora = DateTime.now().microsecondsSinceEpoch.toString();
    return sha256.convert(utf8.encode(agora)).toString().substring(0, 32);
  }

  static String somenteDigitos(String valor) =>
      valor.replaceAll(RegExp(r'[^0-9]'), '');

  static String _nomeEmpresa(Map<String, dynamic> registro) {
    for (final chave in ['nomeFantasia', 'nome_fantasia', 'razaoSocial', 'razao_social', 'nome']) {
      final valor = registro[chave]?.toString().trim() ?? '';
      if (valor.isNotEmpty) return valor;
    }
    return 'Empresa';
  }

  static String _primeiroTexto(Map<String, dynamic> registro, List<String> chaves) {
    for (final chave in chaves) {
      final valor = registro[chave]?.toString().trim() ?? '';
      if (valor.isNotEmpty) return valor;
    }
    return '';
  }

  static double _primeiroNumero(Map<String, dynamic> registro, List<String> chaves) {
    for (final chave in chaves) {
      final valor = registro[chave];
      if (valor == null) continue;
      if (valor is num) return valor.toDouble();
      final convertido = double.tryParse(valor.toString());
      if (convertido != null) return convertido;
    }
    return 0;
  }

  static DateTime? _dataDoRegistro(Map<String, dynamic> registro) {
    for (final chave in ['data_emissao', 'dataEmissao', 'data_entrada', 'created_at', 'createdAt']) {
      final valor = registro[chave];
      if (valor == null) continue;
      final data = DateTime.tryParse(valor.toString());
      if (data != null) return data.toLocal();
    }
    return null;
  }

  static DateTime _inicioDoDia(DateTime data) =>
      DateTime(data.year, data.month, data.day);

  static DateTime _fimDoDia(DateTime data) =>
      DateTime(data.year, data.month, data.day, 23, 59, 59);

  static String _isoInicio(DateTime data) =>
      _inicioDoDia(data).toUtc().toIso8601String();

  static String _isoFim(DateTime data) => _fimDoDia(data).toUtc().toIso8601String();
}
