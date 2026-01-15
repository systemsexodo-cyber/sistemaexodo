/// Enum das telas disponíveis no sistema
enum TelaSistema {
  // Vendas e PDV
  pdv(codigo: 'pdv', nome: 'PDV - Ponto de Venda', categoria: 'Vendas'),
  vendas(codigo: 'vendas', nome: 'Vendas', categoria: 'Vendas'),
  pedidos(codigo: 'pedidos', nome: 'Pedidos', categoria: 'Vendas'),
  
  // Cadastros
  clientes(codigo: 'clientes', nome: 'Clientes', categoria: 'Cadastros'),
  produtos(codigo: 'produtos', nome: 'Produtos', categoria: 'Cadastros'),
  servicos(codigo: 'servicos', nome: 'Serviços', categoria: 'Cadastros'),
  funcionarios(codigo: 'funcionarios', nome: 'Funcionários', categoria: 'Cadastros'),
  
  // Estoque
  estoque(codigo: 'estoque', nome: 'Estoque', categoria: 'Estoque'),
  entradaMercadorias(codigo: 'entrada_mercadorias', nome: 'Entrada de Mercadorias', categoria: 'Estoque'),
  
  // Financeiro
  financeiro(codigo: 'financeiro', nome: 'Financeiro', categoria: 'Financeiro'),
  contasPagar(codigo: 'contas_pagar', nome: 'Contas a Pagar', categoria: 'Financeiro'),
  contasReceber(codigo: 'contas_receber', nome: 'Contas a Receber', categoria: 'Financeiro'),
  caixa(codigo: 'caixa', nome: 'Caixa', categoria: 'Financeiro'),
  agendaContas(codigo: 'agenda_contas', nome: 'Agenda de Contas', categoria: 'Financeiro'),
  
  // Relatórios
  relatorios(codigo: 'relatorios', nome: 'Relatórios', categoria: 'Relatórios'),
  relatorioVendas(codigo: 'relatorio_vendas', nome: 'Relatório de Vendas', categoria: 'Relatórios'),
  relatorioEstoque(codigo: 'relatorio_estoque', nome: 'Relatório de Estoque', categoria: 'Relatórios'),
  relatorioFinanceiro(codigo: 'relatorio_financeiro', nome: 'Relatório Financeiro', categoria: 'Relatórios'),
  
  // Operacional
  cozinhaBar(codigo: 'cozinha_bar', nome: 'Cozinha/Bar', categoria: 'Operacional'),
  mesas(codigo: 'mesas', nome: 'Mesas', categoria: 'Operacional'),
  
  // Configurações
  configuracoes(codigo: 'configuracoes', nome: 'Configurações', categoria: 'Configurações'),
  usuarios(codigo: 'usuarios', nome: 'Usuários', categoria: 'Configurações'),
  empresas(codigo: 'empresas', nome: 'Empresas', categoria: 'Configurações'),
  permissoes(codigo: 'permissoes', nome: 'Permissões', categoria: 'Configurações'),
  
  // Dashboard
  dashboard(codigo: 'dashboard', nome: 'Dashboard', categoria: 'Dashboard'),
  
  // E-commerce
  linksVendedores(codigo: 'links_vendedores', nome: 'Links de Vendedores', categoria: 'E-commerce'),
  vendedorDashboard(codigo: 'vendedor_dashboard', nome: 'Dashboard Vendedor', categoria: 'E-commerce'),
  lojaPublica(codigo: 'loja_publica', nome: 'Loja Pública', categoria: 'E-commerce'),
  personalizarLoja(codigo: 'personalizar_loja', nome: 'Personalizar Loja', categoria: 'E-commerce'),
  gerenciarImagens(codigo: 'gerenciar_imagens', nome: 'Gerenciar Imagens', categoria: 'Configurações'),
  ;

  final String codigo;
  final String nome;
  final String categoria;

  const TelaSistema({
    required this.codigo,
    required this.nome,
    required this.categoria,
  });

  /// Converte uma string de código para TelaSistema
  static TelaSistema? fromCodigo(String codigo) {
    try {
      return TelaSistema.values.firstWhere((t) => t.codigo == codigo);
    } catch (e) {
      return null;
    }
  }

  /// Retorna todas as telas agrupadas por categoria
  static Map<String, List<TelaSistema>> porCategoria() {
    final categorias = <String, List<TelaSistema>>{};
    for (final tela in TelaSistema.values) {
      if (!categorias.containsKey(tela.categoria)) {
        categorias[tela.categoria] = [];
      }
      categorias[tela.categoria]!.add(tela);
    }
    return categorias;
  }
}




