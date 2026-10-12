import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

import '../services/env_config.dart';
import '../services/lan_config_service.dart';

/// Conferência entre os DOIS bancos PostgreSQL LOCAIS (deste computador e do
/// caixa par na rede LAN). Igual à "Conferir os DADOS" (local × nuvem), mas
/// aqui o comparativo é PC×PC: quantas linhas cada tabela tem, e se a
/// estrutura (colunas) está alinhada. SÓ LEITURA: não altera nada.
class ConferenciaBancosLocaisPage extends StatefulWidget {
  const ConferenciaBancosLocaisPage({super.key});

  @override
  State<ConferenciaBancosLocaisPage> createState() =>
      _ConferenciaBancosLocaisPageState();
}

class _TabelaLinha {
  final String nome;
  final int? linhasLocal;
  final int? linhasPar;
  final int colunasSoLocal;
  final int colunasSoPar;
  final bool parFalta;
  const _TabelaLinha({
    required this.nome,
    this.linhasLocal,
    this.linhasPar,
    this.colunasSoLocal = 0,
    this.colunasSoPar = 0,
    this.parFalta = false,
  });

  bool get igual =>
      !parFalta && linhasLocal == linhasPar && colunasSoLocal == 0 && colunasSoPar == 0;
}

class _ConferenciaBancosLocaisPageState
    extends State<ConferenciaBancosLocaisPage> {
  bool _carregando = false;
  String? _erro;
  String _status = '';
  List<_TabelaLinha> _linhas = [];
  String _parNome = '';

  Future<Connection> _abrir({required bool local}) async {
    if (local) {
      return Connection.open(
        Endpoint(
          host: EnvConfig.dbHost.toLowerCase() == 'localhost'
              ? '127.0.0.1'
              : EnvConfig.dbHost,
          port: EnvConfig.dbPort,
          database: EnvConfig.dbName,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      ).timeout(const Duration(seconds: 10));
    }
    final lan = ConfigRedeLocal.ler();
    final mapa = EnvConfig.env;
    return Connection.open(
      Endpoint(
        host: lan.host,
        port: lan.porta,
        database: (mapa['PAR_DB_NAME'] ?? '').trim().isNotEmpty
            ? (mapa['PAR_DB_NAME'] ?? '').trim()
            : EnvConfig.dbName,
        username: (mapa['PAR_DB_USER'] ?? '').trim().isNotEmpty
            ? (mapa['PAR_DB_USER'] ?? '').trim()
            : EnvConfig.dbUser,
        password: (mapa['PAR_DB_PASSWORD'] ?? '').trim().isNotEmpty
            ? (mapa['PAR_DB_PASSWORD'] ?? '').trim()
            : EnvConfig.dbPassword,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    ).timeout(const Duration(seconds: 10));
  }

  Future<void> _conferir() async {
    setState(() {
      _carregando = true;
      _erro = null;
      _linhas = [];
      _status = 'Conectando...';
      _parNome = ConfigRedeLocal.ler().nome;
    });
    Connection? local;
    Connection? par;
    try {
      final lan = ConfigRedeLocal.ler();
      if (!lan.pronto) {
        throw StateError(
            'LAN não está configurada (PAR_HOST vazio). Configure em Rede LAN primeiro.');
      }
      local = await _abrir(local: true);
      par = await _abrir(local: false);

      Future<Map<String, int>> contagens(Connection conn) async {
        final resumo = <String, int>{};
        final res = await conn.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' "
            'ORDER BY tablename');
        for (final row in res) {
          try {
            final c = await conn
                .execute('SELECT count(*) FROM "${row[0]}"');
            resumo[row[0].toString()] = c.first[0] as int;
          } catch (_) {
            resumo[row[0].toString()] = -1;
          }
        }
        return resumo;
      }

      Future<Map<String, Set<String>>> colunas(Connection conn) async {
        final mapa = <String, Set<String>>{};
        final res = await conn.execute(
            "SELECT table_name, column_name FROM information_schema.columns "
            "WHERE table_schema='public' ORDER BY table_name");
        for (final row in res) {
          mapa
              .putIfAbsent(row[0].toString(), () => <String>{})
              .add(row[1].toString());
        }
        return mapa;
      }

      setState(() => _status = 'Contando linhas...');
      final localTabelas = await contagens(local);
      final parTabelas = await contagens(par);
      final localCols = await colunas(local);
      final parCols = await colunas(par);

      setState(() => _status = 'Comparando...');
      final nomes = <String>{...localTabelas.keys, ...parTabelas.keys}.toList()
        ..sort();
      final linhas = <_TabelaLinha>[];
      for (final n in nomes) {
        linhas.add(_TabelaLinha(
          nome: n,
          linhasLocal: localTabelas[n],
          linhasPar: parTabelas[n],
          colunasSoLocal: (localCols[n] ?? const <String>{})
              .difference(parCols[n] ?? const <String>{})
              .length,
          colunasSoPar: (parCols[n] ?? const <String>{})
              .difference(localCols[n] ?? const <String>{})
              .length,
          parFalta: !parTabelas.containsKey(n) || !localTabelas.containsKey(n),
        ));
      }
      setState(() {
        _linhas = linhas;
        _status = '';
      });
    } catch (e) {
      setState(() => _erro = e.toString());
    } finally {
      try {
        await local?.close();
        await par?.close();
      } catch (_) {}
      setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iguais = _linhas.where((l) => l.igual).length;
    final divergentes = _linhas.where((l) => !l.igual).length;
    return Scaffold(
      backgroundColor: const Color(0xFF120626),
      appBar: AppBar(
        title: const Text('Conferência Local × Local'),
        backgroundColor: const Color(0xFF1A0B2E),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este computador × par LAN${_parNome.isEmpty ? '' : ' ($_parNome)'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _carregando ? null : _conferir,
                  icon: _carregando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: Colors.lightGreenAccent),
                  label: const Text('Conferir agora',
                      style: TextStyle(color: Colors.lightGreenAccent)),
                ),
              ],
            ),
          ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_erro!, style: const TextStyle(color: Colors.redAccent)),
            ),
          if (_status.isNotEmpty && _carregando)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_status, style: const TextStyle(color: Colors.white38)),
            ),
          if (_linhas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$iguais tabelas iguais, $divergentes com diferença',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _linhas.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, i) {
                final l = _linhas[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        l.igual ? Icons.check_circle : Icons.warning_amber,
                        color: l.igual ? Colors.greenAccent : Colors.orangeAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.nome,
                                style: const TextStyle(color: Colors.white, fontSize: 13)),
                            if (!l.igual)
                              Text(
                                [
                                  if (l.parFalta) 'tabela só de um lado',
                                  if (l.linhasLocal != l.linhasPar)
                                    'dados: ${l.linhasLocal ?? "-"} × ${l.linhasPar ?? "-"}',
                                  if (l.colunasSoLocal > 0)
                                    'colunas só aqui (${l.colunasSoLocal})',
                                  if (l.colunasSoPar > 0)
                                    'colunas só no par (${l.colunasSoPar})',
                                ].join(' • '),
                                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${l.linhasLocal ?? "-"} × ${l.linhasPar ?? "-"}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

