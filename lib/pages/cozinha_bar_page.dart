import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/mesa_comanda.dart';
import '../models/departamento.dart';
import '../widgets/cozinha_bar_lista_itens.dart';
import 'cadastro_departamentos_page.dart';

/// Página para acompanhamento de pedidos da cozinha e bar.
///
/// As abas são geradas dinamicamente a partir dos DEPARTAMENTOS cadastrados
/// (ex.: Cozinha, Bar, Sobremesas) + a aba "Todos". O departamento é separado
/// da configuração de impressora.
class CozinhaBarPage extends StatefulWidget {
  const CozinhaBarPage({super.key});

  @override
  State<CozinhaBarPage> createState() => _CozinhaBarPageState();
}

class _CozinhaBarPageState extends State<CozinhaBarPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _ultimoTamanho = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reconstrói as abas quando os departamentos carregam/mudam
    final tamanho = _abas(context).length;
    if (tamanho != _ultimoTamanho) {
      _ultimoTamanho = tamanho;
      final novoLength = tamanho + 1; // departamentos + 'Todos'
      final indiceAtual = _tabController.index.clamp(0, novoLength - 1);
      final antigo = _tabController;
      _tabController = TabController(length: novoLength, vsync: this, initialIndex: indiceAtual);
      antigo.dispose();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Monta a lista de abas a partir dos departamentos cadastrados.
  /// Fallback para os padrões Cozinha/Bar se ainda não houver departamentos.
  List<Departamento> _abas(BuildContext context) {
    final ds = Provider.of<DataService>(context, listen: true);
    final deps = ds.departamentos;
    if (deps.isEmpty) {
      // Fallback (antes de carregar): garante visualmente as abas padrão
      return [
        Departamento(id: 'dep_cozinha', nome: 'Cozinha', cor: '#FF5722', icone: 'restaurant'),
        Departamento(id: 'dep_bar', nome: 'Bar', cor: '#2196F3', icone: 'local_bar'),
      ];
    }
    return deps;
  }

  IconData _iconeDepartamento(Departamento d) {
    switch (d.icone) {
      case 'local_bar':
        return Icons.local_bar;
      case 'soup_kitchen':
        return Icons.soup_kitchen;
      case 'bakery_dining':
        return Icons.bakery_dining;
      case 'icecream':
        return Icons.icecream;
      case 'coffee':
        return Icons.coffee;
      case 'flatware':
        return Icons.flatware;
      case 'kitchen':
        return Icons.kitchen;
      default:
        return Icons.restaurant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final abas = _abas(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: const Text(
          'Cozinha e Bar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          IconButton(
            tooltip: 'Gerenciar Departamentos',
            icon: const Icon(Icons.food_bank_outlined, color: Colors.orangeAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CadastroDepartamentosPage(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: [
            ...abas.map((d) => Tab(
                  icon: Icon(_iconeDepartamento(d)),
                  text: d.nome,
                )),
            const Tab(
              icon: Icon(Icons.view_list),
              text: 'Todos',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ...abas.map((d) => CozinhaBarListaItens(
                setor: d.nome,
                onMarcarEmPreparo: _marcarEmPreparo,
                onMarcarPronto: _marcarPronto,
                onDesmarcarPronto: _desmarcarPronto,
              )),
          CozinhaBarListaItens(
            setor: 'Todos',
            onMarcarEmPreparo: _marcarEmPreparo,
            onMarcarPronto: _marcarPronto,
            onDesmarcarPronto: _desmarcarPronto,
          ),
        ],
      ),
    );
  }

  Future<void> _marcarEmPreparo(
    ItemMesaComanda item,
    MesaComanda mesaComanda,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.emPreparo,
      );
      setState(() {});
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.nome} - Preparo iniciado'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _marcarPronto(
    ItemMesaComanda item,
    MesaComanda mesaComanda,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.pronto,
      );
      setState(() {});
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.nome} - Pronto para entrega!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _desmarcarPronto(
    ItemMesaComanda item,
    MesaComanda mesaComanda,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.emPreparo,
      );
      setState(() {});
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.nome} voltou para preparo'),
            backgroundColor: Colors.blueGrey,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao desfazer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
