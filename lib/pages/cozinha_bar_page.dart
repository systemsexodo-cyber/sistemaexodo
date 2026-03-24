import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/mesa_comanda.dart';
import '../widgets/cozinha_bar_lista_itens.dart';

/// Página para acompanhamento de pedidos da cozinha e bar
class CozinhaBarPage extends StatefulWidget {
  const CozinhaBarPage({super.key});

  @override
  State<CozinhaBarPage> createState() => _CozinhaBarPageState();
}

class _CozinhaBarPageState extends State<CozinhaBarPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: const Text(
          'Cozinha e Bar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(
              icon: Icon(Icons.restaurant),
              text: 'Cozinha',
            ),
            Tab(
              icon: Icon(Icons.local_bar),
              text: 'Bar',
            ),
            Tab(
              icon: Icon(Icons.view_list),
              text: 'Todos',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CozinhaBarListaItens(
            setor: 'Cozinha',
            onMarcarEmPreparo: _marcarEmPreparo,
            onMarcarPronto: _marcarPronto,
            onDesmarcarPronto: _desmarcarPronto,
          ),
          CozinhaBarListaItens(
            setor: 'Bar',
            onMarcarEmPreparo: _marcarEmPreparo,
            onMarcarPronto: _marcarPronto,
            onDesmarcarPronto: _desmarcarPronto,
          ),
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

