import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

import 'env_config.dart';

import '../models/empresa.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/ticket_producao.dart';
import 'database_service.dart';
import 'venda_pdf_service.dart';
import 'pedido_pdf_service.dart';
import 'producao_pdf_service.dart';

/// Serviço que gerencia a Fila de Impressão Remota do Caixa.
///
/// Permite que pedidos e vendas gerados no CELULAR (via LAN ou Nuvem)
/// sejam automaticamente impressos na impressora térmica instalada no PC DO CAIXA.
class FilaImpressaoService {
  FilaImpressaoService._();
  static final FilaImpressaoService instance = FilaImpressaoService._();

  Timer? _timerMonitor;
  bool _monitorando = false;
  bool _processando = false;

  /// Última tentativa de ler a fila na NUVEM (evita abrir conexão a cada 2,5 s
  /// quando a loja não tem nada pendente na nuvem).
  DateTime? _ultimaTentativaNuvem;

  /// Retorna true se o app está rodando no computador Windows (provável Caixa com impressora).
  static bool get ehTerminalCaixaWindows => !kIsWeb && Platform.isWindows;

  /// Retorna true se o app está no celular (Android/iOS).
  static bool get ehDispositivoMovel =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ───────────────────────────────────────────────────────────────────────────
  // LADO DO CELULAR: Enfileira a venda para sair no caixa
  // ───────────────────────────────────────────────────────────────────────────

  /// Enfileira uma venda para ser impressa no Caixa físico.
  static Future<bool> enfileirarVendaParaImpressao({
    required VendaBalcao venda,
    required String empresaId,
    String destino = 'caixa',
  }) async {
    try {
      final db = DatabaseService();
      final id = const Uuid().v4();
      final dadosJson = jsonEncode(venda.toMap());

      await db.connection.then((conn) async {
        await conn.execute(
          r'''
          INSERT INTO fila_impressao (
            id, empresa_id, tipo, documento_id, numero, conteudo_json, impressora_destino, status, criado_em
          ) VALUES (
            $1, $2, $3, $4, $5, $6::jsonb, $7, 'pendente', NOW()
          )
          ''',
          parameters: [
            id,
            empresaId,
            'venda_balcao',
            venda.id,
            venda.numero,
            dadosJson,
            destino,
          ],
        );
      });

      debugPrint('>>> [FilaImpressao] ✅ Venda #${venda.numero} enfileirada para o Caixa ($destino).');
      return true;
    } catch (e) {
      debugPrint('>>> [FilaImpressao] ⚠️ Falha ao enfileirar venda no banco: $e');
      return false;
    }
  }

  /// Enfileira uma VIA DE PRODUÇÃO (cozinha, bar, ...) para o Caixa imprimir
  /// na impressora do setor certo.
  ///
  /// O celular não tem as impressoras dos setores, então a via vai com o
  /// payload do ticket (itens + detalhes + nome da impressora do setor, que
  /// veio da configuração dos departamentos). O PC do caixa regenera o PDF e
  /// manda direto para a impressora indicada.
  static Future<bool> enfileirarProducaoParaImpressao({
    required TicketProducao ticket,
    required String empresaId,
  }) async {
    try {
      final db = DatabaseService();
      final id = const Uuid().v4();
      final dadosJson = jsonEncode(ticket.toMap());

      await db.connection.then((conn) async {
        await conn.execute(
          r'''
          INSERT INTO fila_impressao (
            id, empresa_id, tipo, documento_id, numero, conteudo_json, impressora_destino, status, criado_em
          ) VALUES (
            $1, $2, $3, $4, $5, $6::jsonb, $7, 'pendente', NOW()
          )
          ''',
          parameters: [
            id,
            empresaId,
            'producao',
            ticket.documento,
            ticket.documento,
            dadosJson,
            ticket.impressora.trim().isEmpty ? 'caixa' : ticket.impressora,
          ],
        );
      });

      debugPrint('>>> [FilaImpressao] ✅ Via de produção do setor '
          '"${ticket.setor}" (${ticket.documento}) enfileirada para o Caixa.');
      return true;
    } catch (e) {
      debugPrint('>>> [FilaImpressao] ⚠️ Falha ao enfileirar via de produção: $e');
      return false;
    }
  }

  /// Enfileira um pedido para ser impresso no Caixa físico.
  static Future<bool> enfileirarPedidoParaImpressao({
    required Pedido pedido,
    required String empresaId,
    String destino = 'caixa',
  }) async {
    try {
      final db = DatabaseService();
      final id = const Uuid().v4();
      final dadosJson = jsonEncode(pedido.toMap());

      await db.connection.then((conn) async {
        await conn.execute(
          r'''
          INSERT INTO fila_impressao (
            id, empresa_id, tipo, documento_id, numero, conteudo_json, impressora_destino, status, criado_em
          ) VALUES (
            $1, $2, $3, $4, $5, $6::jsonb, $7, 'pendente', NOW()
          )
          ''',
          parameters: [
            id,
            empresaId,
            'pedido',
            pedido.id,
            pedido.numero,
            dadosJson,
            destino,
          ],
        );
      });

      debugPrint('>>> [FilaImpressao] ✅ Pedido #${pedido.numero} enfileirado para o Caixa ($destino).');
      return true;
    } catch (e) {
      debugPrint('>>> [FilaImpressao] ⚠️ Falha ao enfileirar pedido no banco: $e');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // LADO DO PC DO CAIXA: Monitora a fila e imprime fisicamente na impressora
  // ───────────────────────────────────────────────────────────────────────────

  /// Inicia o monitoramento de impressões pendentes no PC do Caixa.
  void iniciarMonitoramento({required Empresa empresa}) {
    if (!ehTerminalCaixaWindows) return;
    if (_monitorando) return;

    _monitorando = true;
    debugPrint('>>> [FilaImpressao] 🖨️ Monitor de impressão do Caixa ATIVADO (empresa: ${empresa.id}).');

    // Executa verificação inicial imediata
    _verificarEImprimirPendentes(empresa);

    // Loop periódico a cada 2.5 segundos para capturar vendas geradas em celulares (LAN ou Nuvem)
    _timerMonitor?.cancel();
    _timerMonitor = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _verificarEImprimirPendentes(empresa);
    });
  }

  /// Para o monitoramento de impressão.
  void pararMonitoramento() {
    _timerMonitor?.cancel();
    _timerMonitor = null;
    _monitorando = false;
  }

  /// Processa as linhas pendentes de UMA conexão (local do PC ou nuvem).
  ///
  /// Devolve `true` quando havia pelo menos uma linha pendente nesta conexão.
  /// O status é atualizado na MESMA conexão de origem, para que o item não
  /// fique "pendente" para sempre nem seja reimpresso em duplicata.
  Future<bool> _processarPendentes(Connection conn, Empresa empresa) async {
    final resultado = await conn.execute(
      r'''
      SELECT id, tipo, numero, conteudo_json, impressora_destino
      FROM fila_impressao
      WHERE empresa_id = $1 AND status = 'pendente'
      ORDER BY criado_em ASC
      LIMIT 5
      ''',
      parameters: [empresa.id],
    );

    if (resultado.isEmpty) return false;

    for (final linha in resultado) {
      final id = linha[0] as String;
      final tipo = linha[1] as String;
      final numero = linha[2] as String?;
      final conteudoRaw = linha[3];

      Map<String, dynamic> conteudo;
      if (conteudoRaw is Map) {
        conteudo = Map<String, dynamic>.from(conteudoRaw);
      } else if (conteudoRaw is String) {
        conteudo = jsonDecode(conteudoRaw);
      } else {
        continue;
      }

      debugPrint('>>> [FilaImpressao] 📄 Imprimindo no Caixa: $tipo #$numero (ID: $id)...');

      bool impressoComSucesso = false;
      String? erroMensagem;

      try {
        if (tipo == 'venda_balcao') {
          final venda = VendaBalcao.fromMap(conteudo);
          await VendaPDFService.imprimirPDFTermico(
            venda: venda,
            empresa: empresa,
            forcarPreview: false,
          );
          impressoComSucesso = true;
        } else if (tipo == 'pedido') {
          final pedido = Pedido.fromMap(conteudo);
          await PedidoPDFService.imprimirPedidoSilenciosoTermico(
            pedido: pedido,
            empresa: empresa,
          );
          impressoComSucesso = true;
        } else if (tipo == 'producao') {
          // Via de produção: cada setor tem a SUA impressora. O ticket já
          // traz o nome configurado no departamento; o PC imprime direto
          // nela (sem diálogo) e, se falhar, a via fica na fila local de
          // produção do Monitor de Produção.
          final ticket = TicketProducao.fromMap(conteudo);
          impressoComSucesso = await ProducaoPdfService.reimprimirTicket(
            ticket: ticket.copyWith(empresaId: empresa.id),
            empresa: empresa,
          );
          if (!impressoComSucesso) {
            erroMensagem =
                'A via não saiu na impressora "${ticket.descricaoImpressora}" do setor ${ticket.setor}';
          }
        }
      } catch (e) {
        debugPrint('>>> [FilaImpressao] ❌ Erro ao enviar para impressora: $e');
        erroMensagem = e.toString();
      }

      // Atualizar status no banco
      if (impressoComSucesso) {
        await conn.execute(
          r'''
          UPDATE fila_impressao
          SET status = 'impresso', impresso_em = NOW(), impresso_por = 'caixa_windows'
          WHERE id = $1
          ''',
          parameters: [id],
        );
        debugPrint('>>> [FilaImpressao] ✅ Documento #$numero impresso com sucesso!');
      } else if (erroMensagem != null) {
        await conn.execute(
          r'''
          UPDATE fila_impressao
          SET status = 'erro', erro = $2
          WHERE id = $1
          ''',
          parameters: [id, erroMensagem],
        );
      }
    }
    return true;
  }

  /// Abre uma conexão direta com o PostgreSQL da NUVEM (Neon), quando
  /// configurado. Usada pelo monitor do Caixa para capturar itens que o
  /// celular enfileirou fora da rede local (em que o aparelho só alcançou
  /// a nuvem). Devolve `null` se não houver configuração ou se falhar.
  Future<Connection?> _abrirConexaoNuvem() async {
    final host = EnvConfig.dbCloudHost;
    if (host.isEmpty) return null;
    try {
      return await Connection.open(
        Endpoint(
          host: host,
          port: EnvConfig.dbCloudPort,
          database: EnvConfig.dbCloudName,
          username: EnvConfig.dbCloudUser,
          password: EnvConfig.dbCloudPassword,
        ),
        settings: ConnectionSettings(
          sslMode: EnvConfig.dbCloudSsl ? SslMode.require : SslMode.disable,
          directTls: EnvConfig.dbCloudSsl,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('>>> [FilaImpressao] ⚠️ Nuvem indisponível: $e');
      return null;
    }
  }

  Future<void> _verificarEImprimirPendentes(Empresa empresa) async {
    if (_processando) return;
    _processando = true;

    try {
      final db = DatabaseService();
      // PC local: tenta o banco da loja quando ele atende (ou ainda não
      // provou que está fora).
      bool localTevePendentes = false;
      if (db.bancoLocalAtendeu || !db.bancoLocalFalhou) {
        try {
          final conn = await db.connection;
          localTevePendentes = await _processarPendentes(conn, empresa);
        } catch (e) {
          // Silencia erros de timeout de rede do monitor para não poluir log
        }
      }

      // NUVEM: o celular (fora da loja) enfileira direto na nuvem. O monitor
      // do Caixa também precisa olhar lá, senão a via de produção/venda
      // nunca sai. Só tenta quando a loja não tinha pendente local (evita
      // custo de rede a cada 2,5 s) e com um intervalo mínimo entre
      // tentativas.
      if (!localTevePendentes) {
        final agora = DateTime.now();
        final podeTentarNuvem = _ultimaTentativaNuvem == null ||
            agora.difference(_ultimaTentativaNuvem!) >=
                const Duration(seconds: 10);
        if (podeTentarNuvem) {
          _ultimaTentativaNuvem = agora;
          Connection? connNuvem;
          try {
            connNuvem = await _abrirConexaoNuvem();
            if (connNuvem != null) {
              await _processarPendentes(connNuvem, empresa);
            }
          } catch (e) {
            // Silencia erros de timeout de rede do monitor para não poluir log
          } finally {
            final c = connNuvem;
            if (c != null) {
              try {
                await c.close();
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      // Silencia erros de timeout de rede do monitor para não poluir log
    } finally {
      _processando = false;
    }
  }
}
