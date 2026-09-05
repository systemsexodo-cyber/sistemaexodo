import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/taxa_entrega.dart';

void main() async {
  final conn = await Connection.open(
    Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'exodo_db',
      username: 'postgres',
      password: 'postgrespassword',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    print('Conectado ao DB.');

    // Fetch column types (simulate what database_service does)
    var resultColumns = await conn.execute('''
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public'
    ''');
    Map<String, Map<String, String>> _tableColumnTypes = {};
    for (var row in resultColumns) {
      final tableName = row[0] as String;
      final columnName = row[1] as String;
      final dataType = row[2] as String;
      _tableColumnTypes.putIfAbsent(tableName, () => {})[columnName] = dataType.toUpperCase();
    }

    final tablesToTest = [
      'clientes', 'produtos', 'servicos', 'pedidos', 'vendas_balcao',
      'agendamentos_servico', 'contas_pagar', 'sangrias_caixa', 'suprimentos_caixa',
      'notas_entrada', 'taxas_entrega', 'ordens_servico', 'entregas',
      'trocas_devolucoes', 'estoque_historico', 'aberturas_caixa', 'fechamentos_caixa',
      'mesas_comandas', 'motoristas', 'funcionarios', 'nfces'
    ];

    for (final table in tablesToTest) {
      print('\\n--- Verificando \$table ---');
      try {
        var result = await conn.execute('SELECT * FROM "\$table" LIMIT 50');
        print('\$table: \${result.length} linhas.');
        
        final columns = _tableColumnTypes[table];
        
        int failures = 0;
        
        for (var row in result) {
          final rowMap = row.toColumnMap();
          final convertedMap = <String, dynamic>{};
          for (final entry in rowMap.entries) {
            var k = entry.key;
            if (k.contains('_')) {
              final parts = k.split('_');
              k = parts[0] + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
            }
            
            var val = entry.value;
            // The fix applied in database_service.dart:
            if (val is String && columns != null) {
              final colType = columns[entry.key]?.toUpperCase() ?? '';
              if (colType.contains('NUMERIC') || colType.contains('DECIMAL') || colType.contains('REAL') || colType.contains('DOUBLE')) {
                val = num.tryParse(val) ?? val;
              }
            }
            convertedMap[k] = val;
          }
          
          try {
            if (table == 'vendas_balcao') VendaBalcao.fromMap(convertedMap);
            else if (table == 'entregas') Entrega.fromMap(convertedMap);
            else if (table == 'taxas_entrega') TaxaEntrega.fromMap(convertedMap);
            else if (table == 'nfces') NFCe.fromMap(convertedMap);
            else if (table == 'aberturas_caixa') AberturaCaixa.fromMap(convertedMap);
          } catch (e, st) {
            print('Erro parseando na tabela \$table: \$e');
            failures++;
          }
        }
        if (failures == 0) print('Tabela \$table OK!');
      } catch (e) {
         // table might not exist
         print('Tabela \$table skip: \$e');
      }
    }

  } catch (e) {
    print('Error: \$e');
  } finally {
    await conn.close();
  }
}
