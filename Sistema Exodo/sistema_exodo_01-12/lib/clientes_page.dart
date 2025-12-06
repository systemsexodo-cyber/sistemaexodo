import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/cliente_detalhes_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  String _filtroStatus = 'Todos'; // Todos, Ativos, Inativos, Bloqueados

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Cliente> _filtrarClientes(List<Cliente> clientes) {
    var resultado = clientes.toList();

    // Filtro por status
    if (_filtroStatus == 'Ativos') {
      resultado = resultado.where((c) => c.ativo && !c.bloqueado).toList();
    } else if (_filtroStatus == 'Inativos') {
      resultado = resultado.where((c) => !c.ativo).toList();
    } else if (_filtroStatus == 'Bloqueados') {
      resultado = resultado.where((c) => c.bloqueado).toList();
    }

    // Filtro por busca
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.toLowerCase();
      resultado = resultado.where((c) {
        return c.nome.toLowerCase().contains(termo) ||
            c.telefone.contains(termo) ||
            (c.cpfCnpj?.contains(termo) ?? false) ||
            (c.email?.toLowerCase().contains(termo) ?? false) ||
            (c.cidade?.toLowerCase().contains(termo) ?? false);
      }).toList();
    }

    // Ordenar por nome
    resultado.sort((a, b) => a.nome.compareTo(b.nome));

    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    // Usar listen: true para atualizar automaticamente quando os dados mudarem
    final service = p.Provider.of<DataService>(context, listen: true);
    final clientesFiltrados = _filtrarClientes(service.clientes);
    final estatisticas = _calcularEstatisticas(service.clientes);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Clientes'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtros',
              onPressed: _mostrarFiltros,
            ),
          ],
        ),
        body: Column(
          children: [
            // Dashboard
            _buildDashboard(estatisticas),

            // Campo de busca
            _buildCampoBusca(),

            // Lista de clientes
            Expanded(
              child: clientesFiltrados.isEmpty
                  ? _buildListaVazia()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: clientesFiltrados.length,
                      itemBuilder: (context, index) {
                        return _buildCardCliente(clientesFiltrados[index]);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _abrirCadastro(null),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.person_add),
          label: const Text('Novo Cliente'),
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, int> stats) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              stats['total'].toString(),
              Colors.blue,
              Icons.people,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Ativos',
              stats['ativos'].toString(),
              Colors.green,
              Icons.check_circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Inativos',
              stats['inativos'].toString(),
              Colors.grey,
              Icons.cancel,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Bloqueados',
              stats['bloqueados'].toString(),
              Colors.red,
              Icons.block,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCampoBusca() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _buscaController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar por nome, telefone, CPF/CNPJ, e-mail...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: _termoBusca.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    setState(() {
                      _buscaController.clear();
                      _termoBusca = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) => setState(() => _termoBusca = value),
      ),
    );
  }

  Widget _buildCardCliente(Cliente cliente) {
    final isPJ = cliente.tipoPessoa == TipoPessoa.juridica;
    final isBloqueado = cliente.bloqueado;
    final isInativo = !cliente.ativo;

    Color corStatus = Colors.green;
    String statusLabel = 'Ativo';
    if (isBloqueado) {
      corStatus = Colors.red;
      statusLabel = 'Bloqueado';
    } else if (isInativo) {
      corStatus = Colors.grey;
      statusLabel = 'Inativo';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBloqueado
              ? [Colors.red.shade900.withOpacity(0.3), const Color(0xFF2C3E50)]
              : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: isBloqueado
            ? Border.all(color: Colors.red.withOpacity(0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _abrirCadastro(cliente),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isPJ
                          ? Colors.purple.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isPJ ? Icons.business : Icons.person,
                      color: isPJ ? Colors.purple : Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Nome e tipo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (cliente.nomeFantasia != null &&
                            cliente.nomeFantasia!.isNotEmpty)
                          Text(
                            cliente.nomeFantasia!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isPJ
                                    ? Colors.purple.withOpacity(0.3)
                                    : Colors.blue.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isPJ ? 'PJ' : 'PF',
                                style: TextStyle(
                                  color: isPJ ? Colors.purple : Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: corStatus.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: corStatus,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // CPF/CNPJ
                  if (cliente.cpfCnpjFormatado != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cliente.cpfCnpjFormatado!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Contato
              Row(
                children: [
                  // Telefone
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone,
                          color: Colors.greenAccent.withOpacity(0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          cliente.telefone,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Email
                  if (cliente.email != null && cliente.email!.isNotEmpty)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.email,
                            color: Colors.blue.withOpacity(0.7),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cliente.email!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // Endereço
              if (cliente.endereco != null && cliente.endereco!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.white.withOpacity(0.5),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cliente.enderecoCompleto,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Limite de crédito
              if (cliente.limiteCredito != null &&
                  cliente.limiteCredito! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: Colors.amber.withOpacity(0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Limite: R\$ ${cliente.limiteCredito!.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.amber.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaVazia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 24),
          Text(
            _termoBusca.isNotEmpty
                ? 'Nenhum cliente encontrado'
                : 'Nenhum cliente cadastrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _termoBusca.isNotEmpty
                ? 'Tente buscar por outro termo'
                : 'Clique no botão abaixo para cadastrar',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _calcularEstatisticas(List<Cliente> clientes) {
    return {
      'total': clientes.length,
      'ativos': clientes.where((c) => c.ativo && !c.bloqueado).length,
      'inativos': clientes.where((c) => !c.ativo).length,
      'bloqueados': clientes.where((c) => c.bloqueado).length,
    };
  }

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtrar por Status',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChipFiltro('Todos', Icons.all_inclusive, Colors.blue),
                _buildChipFiltro('Ativos', Icons.check_circle, Colors.green),
                _buildChipFiltro('Inativos', Icons.cancel, Colors.grey),
                _buildChipFiltro('Bloqueados', Icons.block, Colors.red),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildChipFiltro(String label, IconData icone, Color cor) {
    final isSelected = _filtroStatus == label;
    return GestureDetector(
      onTap: () {
        setState(() => _filtroStatus = label);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? cor.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? cor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: isSelected ? cor : Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirCadastro(Cliente? cliente) async {
    final resultado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesPage(cliente: cliente),
      ),
    );

    // Forçar atualização da lista após salvar
    // O Provider já notifica automaticamente, mas garantimos a atualização
    if (mounted) {
      setState(() {});
    }
  }
}
