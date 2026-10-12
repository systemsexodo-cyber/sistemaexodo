import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';

/// Diagnóstico SOMENTE-LEITURA: reproduz o caminho de leitura do
/// `_carregarDadosSalvos` para aberturas/fechamentos de caixa da BMJ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('caminho de leitura do app para os caixas da BMJ', () async {
    final db = DatabaseService();
    const empresaId = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
    db.setEmpresaId(empresaId);

    final storage = LocalStorageService();

    final aberturas = await storage
        .carregarLista('empresa_${empresaId}_${LocalStorageService.keyAberturasCaixa}');
    print('>>> aberturas lidas: ${aberturas.length}');
    if (aberturas.isNotEmpty) print('>>> primeira: ${aberturas.first}');

    int ok = 0, falhas = 0;
    for (final m in aberturas) {
      try {
        AberturaCaixa.fromMap(m);
        ok++;
      } catch (e, st) {
        falhas++;
        print('>>> ❌ parse abertura id=${m['id']}: $e');
        print('>>>    mapa: $m');
        print('>>>    $st');
      }
    }
    print('>>> aberturas parseadas: $ok, falhas: $falhas');

    final fechamentos = await storage
        .carregarLista('empresa_${empresaId}_${LocalStorageService.keyFechamentosCaixa}');
    print('>>> fechamentos lidos: ${fechamentos.length}');
    if (fechamentos.isNotEmpty) print('>>> primeiro: ${fechamentos.first}');

    int okF = 0, falhasF = 0;
    for (final m in fechamentos) {
      try {
        FechamentoCaixa.fromMap(m);
        okF++;
      } catch (e) {
        falhasF++;
        print('>>> ❌ parse fechamento id=${m['id']}: $e');
        print('>>>    mapa: $m');
      }
    }
    print('>>> fechamentos parseados: $okF, falhas: $falhasF');

    final sangrias = await storage
        .carregarLista('empresa_${empresaId}_${LocalStorageService.keySangriasField}');
    print('>>> sangrias lidas: ${sangrias.length}');

    expect(aberturas, isNotEmpty,
        reason: 'o caminho de leitura do app devia ver as aberturas da BMJ');
  });
}
