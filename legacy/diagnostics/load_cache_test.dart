import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/agendamento_servico.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/ordem_servico.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/troca_devolucao.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/models/taxa_entrega.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('simulate full local cache loading to pinpoint exceptions', () async {
    final db = DatabaseService();
    final String empresaId = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
    db.setEmpresaId(empresaId);

    String getEmpresaKey(String baseKey) {
      return 'empresa_${empresaId}_$baseKey';
    }

    final storage = LocalStorageService();

    final keys = {
      'clientes': getEmpresaKey(LocalStorageService.keyClientes),
      'produtos': getEmpresaKey(LocalStorageService.keyProdutos),
      'servicos': getEmpresaKey(LocalStorageService.keyServicos),
      'pedidos': getEmpresaKey(LocalStorageService.keyPedidos),
      'vendas_balcao': getEmpresaKey(LocalStorageService.keyVendasBalcao),
      'agendamentos': getEmpresaKey(LocalStorageService.keyAgendamentosServico),
      'notas_entrada': getEmpresaKey(LocalStorageService.keyNotasEntrada),
      'funcionarios': getEmpresaKey(LocalStorageService.keyFuncionarios),
      'taxas': getEmpresaKey(LocalStorageService.keyTaxasEntrega),
      'contas_pagar': getEmpresaKey(LocalStorageService.keyContasPagar),
      'nfces': getEmpresaKey(LocalStorageService.keyNFCes),
      'mesas': getEmpresaKey(LocalStorageService.keyMesasComandas),
      'sangrias': getEmpresaKey(LocalStorageService.keySangriasField),
      'suprimentos': getEmpresaKey(LocalStorageService.keySuprimentosField),
      'ordens': getEmpresaKey(LocalStorageService.keyOrdensServico),
      'entregas': getEmpresaKey(LocalStorageService.keyEntregas),
      'trocas': getEmpresaKey(LocalStorageService.keyTrocasDevolucoes),
      'estoque': getEmpresaKey(LocalStorageService.keyEstoqueHistorico),
      'links_vendedores': getEmpresaKey(LocalStorageService.keyLinksVendedores),
      'comissoes_vendedores': getEmpresaKey(LocalStorageService.keyComissoesVendedores),
      'romaneios': getEmpresaKey(LocalStorageService.keyRomaneios),
      'perfis_tributarios': getEmpresaKey('perfis_tributarios'),
    };

    for (final entry in keys.entries) {
      print('>>> Loading list for key: ${entry.value} (${entry.key})');
      try {
        final list = await storage.carregarLista(entry.value);
        print('    Loaded ${list.length} rows.');
        int success = 0;
        int failed = 0;
        for (final map in list) {
          try {
            switch (entry.key) {
              case 'clientes':
                Cliente.fromMap(map);
                break;
              case 'produtos':
                Produto.fromMap(map);
                break;
              case 'servicos':
                Servico.fromMap(map);
                break;
              case 'pedidos':
                Pedido.fromMap(map);
                break;
              case 'vendas_balcao':
                VendaBalcao.fromMap(map);
                break;
              case 'agendamentos':
                AgendamentoServico.fromMap(map);
                break;
              case 'notas_entrada':
                // NoteEntrada doesn't have fromMap
                break;
              case 'funcionarios':
                Funcionario.fromMap(map);
                break;
              case 'taxas':
                TaxaEntrega.fromMap(map);
                break;
              case 'contas_pagar':
                ContaPagar.fromMap(map);
                break;
              case 'nfces':
                NFCe.fromMap(map);
                break;
              case 'mesas':
                MesaComanda.fromMap(map);
                break;
              case 'sangrias':
                SangriaCaixa.fromMap(map);
                break;
              case 'suprimentos':
                SuprimentoCaixa.fromMap(map);
                break;
              case 'ordens':
                OrdemServico.fromMap(map);
                break;
              case 'entregas':
                Entrega.fromMap(map);
                break;
              case 'trocas':
                TrocaDevolucao.fromMap(map);
                break;
              case 'estoque':
                EstoqueHistorico.fromMap(map);
                break;
              case 'links_vendedores':
                LinkVendedor.fromMap(map);
                break;
              case 'comissoes_vendedores':
                ComissaoVendedor.fromMap(map);
                break;
              case 'romaneios':
                Romaneio.fromMap(map);
                break;
              case 'perfis_tributarios':
                PerfilTributario.fromMap(map);
                break;
            }
            success++;
          } catch (e, st) {
            failed++;
            print('    ❌ FAILED to parse item: $e');
            print('    Map: $map');
          }
        }
        print('    Successfully parsed: $success, Failed: $failed');
      } catch (e, st) {
        print('    ❌ CRITICAL ERROR LOADING KEY: $e');
      }
    }
  });
}
