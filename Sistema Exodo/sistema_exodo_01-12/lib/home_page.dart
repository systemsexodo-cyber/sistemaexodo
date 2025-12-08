import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/data_service.dart';
import 'package:sistema_exodo_novo/pages/clientes_page.dart';
import 'package:sistema_exodo_novo/pages/produtos_page.dart';
import 'package:sistema_exodo_novo/pages/servicos_page.dart';
import 'package:sistema_exodo_novo/pages/pedidos_page.dart';
import 'package:sistema_exodo_novo/pages/pdv_page.dart';
import 'package:sistema_exodo_novo/pages/entregas_page.dart';
import 'package:sistema_exodo_novo/pages/contas_pagar_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _busca = '';
  final _buscaController = TextEditingController();

  List<dynamic> _filtrarProdutos(List<dynamic> produtos) {
    String normalizar(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final buscaNorm = normalizar(_busca);
    if (buscaNorm.isEmpty) return produtos;
    return produtos.where((p) {
      final nomeNorm = normalizar(p.nome);
      final descNorm = normalizar(p.descricao ?? '');
      final unidadeNorm = normalizar(p.unidade ?? '');
      final precoNorm = p.preco?.toStringAsFixed(2) ?? '';
      final estoqueNorm = p.estoque?.toString() ?? '';
      final createdAtNorm =
          p.createdAt?.toIso8601String().substring(0, 10) ?? '';
      final updatedAtNorm =
          p.updatedAt?.toIso8601String().substring(0, 10) ?? '';
      return nomeNorm.contains(buscaNorm) ||
          descNorm.contains(buscaNorm) ||
          unidadeNorm.contains(buscaNorm) ||
          precoNorm.contains(buscaNorm) ||
          estoqueNorm.contains(buscaNorm) ||
          createdAtNorm.contains(buscaNorm) ||
          updatedAtNorm.contains(buscaNorm);
    }).toList();
  }

  void _navigateTo(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    final produtos = _filtrarProdutos(
      (Provider.of<DataService>(context, listen: false).produtos),
    );
    final primary = Theme.of(context).colorScheme.primary;
    final cardColor =
        Theme.of(context).cardTheme.color ?? Colors.white.withOpacity(0.9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exodo'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                // Use the new ExodoLogo widget (show name alongside)
                const ExodoLogo(size: 78),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bem-vindo ao Gestor Completo',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sistema de gestão de vendas, pedidos e serviços',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Botão PDV destacado
            InkWell(
              onTap: () => _navigateTo(const PdvPage()),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C853), Color(0xFF00E676)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.point_of_sale,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PDV - Ponto de Venda',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Receber pagamentos dos pedidos',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Botão Contas a Pagar destacado
            InkWell(
              onTap: () => _navigateTo(const ContasPagarPage()),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFF44336)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.payment,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contas a Pagar',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Gerenciar despesas e pagamentos',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Botão Entregas destacado
            InkWell(
              onTap: () => _navigateTo(const EntregasPage()),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.blue.shade900,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Controle de Entregas',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Rastrear e gerenciar entregas',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            // Feature grid with square colorful cards
            const SizedBox(height: 6),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildSquareCard(
                  context,
                  Colors.deepPurple,
                  Icons.people,
                  'Clientes',
                  () => _navigateTo(const ClientesPage()),
                ),
                _buildSquareCard(
                  context,
                  Colors.teal,
                  Icons.inventory,
                  'Produtos',
                  () => _navigateTo(const ProdutosPage()),
                ),
                _buildSquareCard(
                  context,
                  Colors.orange,
                  Icons.build,
                  'Serviços',
                  () => _navigateTo(const ServicosPage()),
                ),
                _buildSquareCard(
                  context,
                  Colors.pink,
                  Icons.shopping_cart,
                  'Pedidos',
                  () => _navigateTo(const PedidosPage()),
                ),
                _buildSquareCard(
                  context,
                  Colors.red,
                  Icons.payment,
                  'Contas a Pagar',
                  () => _navigateTo(const ContasPagarPage()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                controller: _buscaController,
                decoration: InputDecoration(
                  labelText: 'Buscar produto',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _busca = value;
                  });
                },
              ),
            ),
            if (_busca.isNotEmpty)
              Container(
                constraints: BoxConstraints(maxHeight: 220),
                child: produtos.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum produto encontrado',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: produtos.length,
                        itemBuilder: (context, index) {
                          final p = produtos[index];
                          return Card(
                            color: Colors.white.withOpacity(0.08),
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: ListTile(
                              title: Text(
                                p.nome,
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                'R\$ ${p.preco.toStringAsFixed(2)} | Estoque: ${p.estoque}',
                                style: TextStyle(color: Colors.white70),
                              ),
                              trailing: Text(
                                p.unidade ?? '',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          );
                        },
                      ),
              ),

            Text(
              'Toque em um cartão para navegar',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Lógica de teste do Firebase
              },
              child: const Text('Testar Firebase'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    // kept for backward compatibility; not used by the new layout
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title - Em desenvolvimento')));
      },
    );
  }

  Widget _buildFeatureTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$title - Em desenvolvimento')));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[700])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareCard(
    BuildContext context,
    Color baseColor,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [baseColor.withOpacity(0.95), baseColor.withOpacity(0.6)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExodoLogo {
  const ExodoLogo({required int size});
}
