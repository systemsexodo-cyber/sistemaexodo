/// Modelo para representar uma permissão do sistema
class Permissao {
  final String id;
  final String codigo; // Código único da permissão (ex: 'vendas.criar', 'relatorios.visualizar')
  final String nome; // Nome amigável da permissão
  final String descricao; // Descrição detalhada
  final String categoria; // Categoria da permissão (ex: 'vendas', 'relatorios', 'configuracoes')
  final DateTime createdAt;
  final DateTime updatedAt;

  Permissao({
    required this.id,
    required this.codigo,
    required this.nome,
    required this.descricao,
    required this.categoria,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Permissao.fromMap(Map<String, dynamic> map) {
    return Permissao(
      id: map['id']?.toString() ?? '',
      codigo: map['codigo'] ?? '',
      nome: map['nome'] ?? '',
      descricao: map['descricao'] ?? '',
      categoria: map['categoria'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'nome': nome,
      'descricao': descricao,
      'categoria': categoria,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Permissao copyWith({
    String? id,
    String? codigo,
    String? nome,
    String? descricao,
    String? categoria,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Permissao(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      categoria: categoria ?? this.categoria,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Enum com todas as permissões do sistema
enum TipoPermissao {
  // Vendas
  vendasVisualizar,
  vendasCriar,
  vendasEditar,
  vendasCancelar,
  vendasExcluir,
  vendasAplicarDesconto,
  vendasVerCusto,
  vendasAlterarPrecoItem,
  
  // Produtos
  produtosVisualizar,
  produtosCriar,
  produtosEditar,
  produtosExcluir,
  produtosAlterarPreco,
  produtosGerenciarEstoque,
  produtosVisualizarCusto,
  
  // Clientes
  clientesVisualizar,
  clientesCriar,
  clientesEditar,
  clientesExcluir,
  clientesVerHistorico,
  
  // Relatórios
  relatoriosVisualizar,
  relatoriosVendas,
  relatoriosFinanceiro,
  relatoriosEstoque,
  relatoriosExportar,
  
  // Dashboard e Informações Financeiras
  dashboardVisualizar,
  dashboardFinanceiro,
  dashboardVerTotais,
  
  // Configurações
  configuracoesVisualizar,
  configuracoesEmpresa,
  configuracoesUsuarios,
  configuracoesPermissoes,
  configuracoesSistema,
  
  // NFC-e / Notas Fiscais
  nfceEmitir,
  nfceVisualizar,
  nfceCancelar,
  nfceReenviar,
  
  // Caixa
  caixaAbrir,
  caixaFechar,
  caixaVisualizar,
  caixaMovimentar,
  caixaVerTotaisFormasPagamento,
  caixaVerTotalVendidoFechamento,
  caixaVerFluxoCaixa,
  
  // Cozinha/Bar
  cozinhaVisualizar,
  cozinhaPreparar,
  cozinhaFinalizar,
  cozinhaCancelar,
  
  // Cozinha/Bar Funcionário (tela simplificada)
  cozinhaFuncionario,
  
  // Financeiro
  financeiroVisualizar,
  financeiroReceber,
  financeiroPagar,
  financeiroConciliar,
  
  // Estoque
  estoqueVisualizar,
  estoqueEntrada,
  estoqueSaida,
  estoqueAjuste,
  estoqueTransferencia,
}

/// Extensão para obter informações das permissões
extension TipoPermissaoExtension on TipoPermissao {
  String get codigo {
    switch (this) {
      // Vendas
      case TipoPermissao.vendasVisualizar:
        return 'vendas.visualizar';
      case TipoPermissao.vendasCriar:
        return 'vendas.criar';
      case TipoPermissao.vendasEditar:
        return 'vendas.editar';
      case TipoPermissao.vendasCancelar:
        return 'vendas.cancelar';
      case TipoPermissao.vendasExcluir:
        return 'vendas.excluir';
      case TipoPermissao.vendasAplicarDesconto:
        return 'vendas.aplicar_desconto';
      case TipoPermissao.vendasVerCusto:
        return 'vendas.ver_custo';
      case TipoPermissao.vendasAlterarPrecoItem:
        return 'vendas.alterar_preco_item';
      
      // Produtos
      case TipoPermissao.produtosVisualizar:
        return 'produtos.visualizar';
      case TipoPermissao.produtosCriar:
        return 'produtos.criar';
      case TipoPermissao.produtosEditar:
        return 'produtos.editar';
      case TipoPermissao.produtosExcluir:
        return 'produtos.excluir';
      case TipoPermissao.produtosAlterarPreco:
        return 'produtos.alterar_preco';
      case TipoPermissao.produtosGerenciarEstoque:
        return 'produtos.gerenciar_estoque';
      case TipoPermissao.produtosVisualizarCusto:
        return 'produtos.visualizar_custo';
      
      // Clientes
      case TipoPermissao.clientesVisualizar:
        return 'clientes.visualizar';
      case TipoPermissao.clientesCriar:
        return 'clientes.criar';
      case TipoPermissao.clientesEditar:
        return 'clientes.editar';
      case TipoPermissao.clientesExcluir:
        return 'clientes.excluir';
      case TipoPermissao.clientesVerHistorico:
        return 'clientes.ver_historico';
      
      // Relatórios
      case TipoPermissao.relatoriosVisualizar:
        return 'relatorios.visualizar';
      case TipoPermissao.relatoriosVendas:
        return 'relatorios.vendas';
      case TipoPermissao.relatoriosFinanceiro:
        return 'relatorios.financeiro';
      case TipoPermissao.relatoriosEstoque:
        return 'relatorios.estoque';
      case TipoPermissao.relatoriosExportar:
        return 'relatorios.exportar';
      
      // Dashboard e Informações Financeiras
      case TipoPermissao.dashboardVisualizar:
        return 'dashboard.visualizar';
      case TipoPermissao.dashboardFinanceiro:
        return 'dashboard.financeiro';
      case TipoPermissao.dashboardVerTotais:
        return 'dashboard.ver_totais';
      
      // Configurações
      case TipoPermissao.configuracoesVisualizar:
        return 'configuracoes.visualizar';
      case TipoPermissao.configuracoesEmpresa:
        return 'configuracoes.empresa';
      case TipoPermissao.configuracoesUsuarios:
        return 'configuracoes.usuarios';
      case TipoPermissao.configuracoesPermissoes:
        return 'configuracoes.permissoes';
      case TipoPermissao.configuracoesSistema:
        return 'configuracoes.sistema';
      
      // NFC-e
      case TipoPermissao.nfceEmitir:
        return 'nfce.emitir';
      case TipoPermissao.nfceVisualizar:
        return 'nfce.visualizar';
      case TipoPermissao.nfceCancelar:
        return 'nfce.cancelar';
      case TipoPermissao.nfceReenviar:
        return 'nfce.reenviar';
      
      // Caixa
      case TipoPermissao.caixaAbrir:
        return 'caixa.abrir';
      case TipoPermissao.caixaFechar:
        return 'caixa.fechar';
      case TipoPermissao.caixaVisualizar:
        return 'caixa.visualizar';
      case TipoPermissao.caixaMovimentar:
        return 'caixa.movimentar';
      case TipoPermissao.caixaVerTotaisFormasPagamento:
        return 'caixa.ver_totais_formas_pagamento';
      case TipoPermissao.caixaVerTotalVendidoFechamento:
        return 'caixa.ver_total_vendido_fechamento';
      case TipoPermissao.caixaVerFluxoCaixa:
        return 'caixa.ver_fluxo_caixa';
      
      // Cozinha/Bar
      case TipoPermissao.cozinhaVisualizar:
        return 'cozinha.visualizar';
      case TipoPermissao.cozinhaPreparar:
        return 'cozinha.preparar';
      case TipoPermissao.cozinhaFinalizar:
        return 'cozinha.finalizar';
      case TipoPermissao.cozinhaCancelar:
        return 'cozinha.cancelar';
      case TipoPermissao.cozinhaFuncionario:
        return 'cozinha.funcionario';
      
      // Financeiro
      case TipoPermissao.financeiroVisualizar:
        return 'financeiro.visualizar';
      case TipoPermissao.financeiroReceber:
        return 'financeiro.receber';
      case TipoPermissao.financeiroPagar:
        return 'financeiro.pagar';
      case TipoPermissao.financeiroConciliar:
        return 'financeiro.conciliar';
      
      // Estoque
      case TipoPermissao.estoqueVisualizar:
        return 'estoque.visualizar';
      case TipoPermissao.estoqueEntrada:
        return 'estoque.entrada';
      case TipoPermissao.estoqueSaida:
        return 'estoque.saida';
      case TipoPermissao.estoqueAjuste:
        return 'estoque.ajuste';
      case TipoPermissao.estoqueTransferencia:
        return 'estoque.transferencia';
    }
  }

  String get nome {
    switch (this) {
      // Vendas
      case TipoPermissao.vendasVisualizar:
        return 'Visualizar Vendas';
      case TipoPermissao.vendasCriar:
        return 'Criar Vendas';
      case TipoPermissao.vendasEditar:
        return 'Editar Vendas';
      case TipoPermissao.vendasCancelar:
        return 'Cancelar Vendas';
      case TipoPermissao.vendasExcluir:
        return 'Excluir Vendas';
      case TipoPermissao.vendasAplicarDesconto:
        return 'Aplicar Desconto';
      case TipoPermissao.vendasVerCusto:
        return 'Ver Custo de Produtos';
      case TipoPermissao.vendasAlterarPrecoItem:
        return 'Alterar Preço do Produto no Carrinho (PDV)';
      
      // Produtos
      case TipoPermissao.produtosVisualizar:
        return 'Visualizar Produtos';
      case TipoPermissao.produtosCriar:
        return 'Criar Produtos';
      case TipoPermissao.produtosEditar:
        return 'Editar Produtos';
      case TipoPermissao.produtosExcluir:
        return 'Excluir Produtos';
      case TipoPermissao.produtosAlterarPreco:
        return 'Alterar Preço';
      case TipoPermissao.produtosGerenciarEstoque:
        return 'Gerenciar Estoque';
      case TipoPermissao.produtosVisualizarCusto:
        return 'Visualizar Preço de Custo';
      
      // Clientes
      case TipoPermissao.clientesVisualizar:
        return 'Visualizar Clientes';
      case TipoPermissao.clientesCriar:
        return 'Criar Clientes';
      case TipoPermissao.clientesEditar:
        return 'Editar Clientes';
      case TipoPermissao.clientesExcluir:
        return 'Excluir Clientes';
      case TipoPermissao.clientesVerHistorico:
        return 'Ver Histórico de Clientes';
      
      // Relatórios
      case TipoPermissao.relatoriosVisualizar:
        return 'Visualizar Relatórios';
      case TipoPermissao.relatoriosVendas:
        return 'Relatórios de Vendas';
      case TipoPermissao.relatoriosFinanceiro:
        return 'Relatórios Financeiros';
      case TipoPermissao.relatoriosEstoque:
        return 'Relatórios de Estoque';
      case TipoPermissao.relatoriosExportar:
        return 'Exportar Relatórios';
      
      // Dashboard e Informações Financeiras
      case TipoPermissao.dashboardVisualizar:
        return 'Visualizar Dashboard';
      case TipoPermissao.dashboardFinanceiro:
        return 'Visualizar Informações Financeiras';
      case TipoPermissao.dashboardVerTotais:
        return 'Ver Totais de Vendas';
      
      // Configurações
      case TipoPermissao.configuracoesVisualizar:
        return 'Visualizar Configurações';
      case TipoPermissao.configuracoesEmpresa:
        return 'Configurar Empresa';
      case TipoPermissao.configuracoesUsuarios:
        return 'Gerenciar Usuários';
      case TipoPermissao.configuracoesPermissoes:
        return 'Gerenciar Permissões';
      case TipoPermissao.configuracoesSistema:
        return 'Configurações do Sistema';
      
      // NFC-e
      case TipoPermissao.nfceEmitir:
        return 'Emitir NFC-e';
      case TipoPermissao.nfceVisualizar:
        return 'Visualizar NFC-e';
      case TipoPermissao.nfceCancelar:
        return 'Cancelar NFC-e';
      case TipoPermissao.nfceReenviar:
        return 'Reenviar NFC-e';
      
      // Caixa
      case TipoPermissao.caixaAbrir:
        return 'Abrir Caixa';
      case TipoPermissao.caixaFechar:
        return 'Fechar Caixa';
      case TipoPermissao.caixaVisualizar:
        return 'Visualizar Caixa';
      case TipoPermissao.caixaMovimentar:
        return 'Movimentar Caixa';
      case TipoPermissao.caixaVerTotaisFormasPagamento:
        return 'Ver Total por Forma de Pagamento';
      case TipoPermissao.caixaVerTotalVendidoFechamento:
        return 'Ver Total Vendido no Fechamento';
      case TipoPermissao.caixaVerFluxoCaixa:
        return 'Ver Fluxo de Caixa';
      
      // Cozinha/Bar
      case TipoPermissao.cozinhaVisualizar:
        return 'Visualizar Cozinha/Bar';
      case TipoPermissao.cozinhaPreparar:
        return 'Preparar Pedidos';
      case TipoPermissao.cozinhaFinalizar:
        return 'Finalizar Pedidos';
      case TipoPermissao.cozinhaCancelar:
        return 'Cancelar Pedidos';
      case TipoPermissao.cozinhaFuncionario:
        return 'Cozinha/Bar Funcionário';
      
      // Financeiro
      case TipoPermissao.financeiroVisualizar:
        return 'Visualizar Financeiro';
      case TipoPermissao.financeiroReceber:
        return 'Receber Valores';
      case TipoPermissao.financeiroPagar:
        return 'Pagar Valores';
      case TipoPermissao.financeiroConciliar:
        return 'Conciliar Contas';
      
      // Estoque
      case TipoPermissao.estoqueVisualizar:
        return 'Visualizar Estoque';
      case TipoPermissao.estoqueEntrada:
        return 'Entrada de Estoque';
      case TipoPermissao.estoqueSaida:
        return 'Saída de Estoque';
      case TipoPermissao.estoqueAjuste:
        return 'Ajuste de Estoque';
      case TipoPermissao.estoqueTransferencia:
        return 'Transferência de Estoque';
    }
  }

  String get categoria {
    switch (this) {
      case TipoPermissao.vendasVisualizar:
      case TipoPermissao.vendasCriar:
      case TipoPermissao.vendasEditar:
      case TipoPermissao.vendasCancelar:
      case TipoPermissao.vendasExcluir:
      case TipoPermissao.vendasAplicarDesconto:
      case TipoPermissao.vendasVerCusto:
      case TipoPermissao.vendasAlterarPrecoItem:
        return 'Vendas';
      
      case TipoPermissao.produtosVisualizar:
      case TipoPermissao.produtosCriar:
      case TipoPermissao.produtosEditar:
      case TipoPermissao.produtosExcluir:
      case TipoPermissao.produtosAlterarPreco:
      case TipoPermissao.produtosGerenciarEstoque:
      case TipoPermissao.produtosVisualizarCusto:
        return 'Produtos';
      
      case TipoPermissao.clientesVisualizar:
      case TipoPermissao.clientesCriar:
      case TipoPermissao.clientesEditar:
      case TipoPermissao.clientesExcluir:
      case TipoPermissao.clientesVerHistorico:
        return 'Clientes';
      
      case TipoPermissao.relatoriosVisualizar:
      case TipoPermissao.relatoriosVendas:
      case TipoPermissao.relatoriosFinanceiro:
      case TipoPermissao.relatoriosEstoque:
      case TipoPermissao.relatoriosExportar:
        return 'Relatórios';
      
      case TipoPermissao.dashboardVisualizar:
      case TipoPermissao.dashboardFinanceiro:
      case TipoPermissao.dashboardVerTotais:
        return 'Dashboard';
      
      case TipoPermissao.configuracoesVisualizar:
      case TipoPermissao.configuracoesEmpresa:
      case TipoPermissao.configuracoesUsuarios:
      case TipoPermissao.configuracoesPermissoes:
      case TipoPermissao.configuracoesSistema:
        return 'Configurações';
      
      case TipoPermissao.nfceEmitir:
      case TipoPermissao.nfceVisualizar:
      case TipoPermissao.nfceCancelar:
      case TipoPermissao.nfceReenviar:
        return 'NFC-e';
      
      case TipoPermissao.caixaAbrir:
      case TipoPermissao.caixaFechar:
      case TipoPermissao.caixaVisualizar:
      case TipoPermissao.caixaMovimentar:
      case TipoPermissao.caixaVerTotaisFormasPagamento:
      case TipoPermissao.caixaVerTotalVendidoFechamento:
      case TipoPermissao.caixaVerFluxoCaixa:
        return 'Caixa';
      
      case TipoPermissao.cozinhaVisualizar:
      case TipoPermissao.cozinhaPreparar:
      case TipoPermissao.cozinhaFinalizar:
      case TipoPermissao.cozinhaCancelar:
      case TipoPermissao.cozinhaFuncionario:
        return 'Cozinha/Bar';
      
      case TipoPermissao.financeiroVisualizar:
      case TipoPermissao.financeiroReceber:
      case TipoPermissao.financeiroPagar:
      case TipoPermissao.financeiroConciliar:
        return 'Financeiro';
      
      case TipoPermissao.estoqueVisualizar:
      case TipoPermissao.estoqueEntrada:
      case TipoPermissao.estoqueSaida:
      case TipoPermissao.estoqueAjuste:
      case TipoPermissao.estoqueTransferencia:
        return 'Estoque';
    }
  }

  String get descricao {
    switch (this) {
      case TipoPermissao.vendasVisualizar:
        return 'Permite visualizar vendas realizadas';
      case TipoPermissao.vendasCriar:
        return 'Permite criar novas vendas';
      case TipoPermissao.vendasEditar:
        return 'Permite editar vendas existentes';
      case TipoPermissao.vendasCancelar:
        return 'Permite cancelar vendas';
      case TipoPermissao.vendasExcluir:
        return 'Permite excluir vendas';
      case TipoPermissao.vendasAplicarDesconto:
        return 'Permite aplicar descontos em vendas';
      case TipoPermissao.vendasVerCusto:
        return 'Permite visualizar o custo dos produtos nas vendas';
      case TipoPermissao.vendasAlterarPrecoItem:
        return 'Permite alterar o preço unitário de um produto no carrinho (PDV)';
      
      case TipoPermissao.produtosVisualizar:
        return 'Permite visualizar produtos cadastrados';
      case TipoPermissao.produtosCriar:
        return 'Permite criar novos produtos';
      case TipoPermissao.produtosEditar:
        return 'Permite editar produtos existentes';
      case TipoPermissao.produtosExcluir:
        return 'Permite excluir produtos';
      case TipoPermissao.produtosAlterarPreco:
        return 'Permite alterar preços de produtos';
      case TipoPermissao.produtosGerenciarEstoque:
        return 'Permite gerenciar estoque de produtos';
      case TipoPermissao.produtosVisualizarCusto:
        return 'Permite visualizar o preço de custo dos produtos no cadastro e relatórios';
      
      case TipoPermissao.clientesVisualizar:
        return 'Permite visualizar clientes cadastrados';
      case TipoPermissao.clientesCriar:
        return 'Permite criar novos clientes';
      case TipoPermissao.clientesEditar:
        return 'Permite editar clientes existentes';
      case TipoPermissao.clientesExcluir:
        return 'Permite excluir clientes';
      case TipoPermissao.clientesVerHistorico:
        return 'Permite visualizar histórico de compras do cliente';
      
      case TipoPermissao.relatoriosVisualizar:
        return 'Permite visualizar relatórios';
      case TipoPermissao.relatoriosVendas:
        return 'Permite acessar relatórios de vendas';
      case TipoPermissao.relatoriosFinanceiro:
        return 'Permite acessar relatórios financeiros';
      case TipoPermissao.relatoriosEstoque:
        return 'Permite acessar relatórios de estoque';
      case TipoPermissao.relatoriosExportar:
        return 'Permite exportar relatórios';
      
      case TipoPermissao.configuracoesVisualizar:
        return 'Permite visualizar configurações';
      case TipoPermissao.configuracoesEmpresa:
        return 'Permite configurar dados da empresa';
      case TipoPermissao.configuracoesUsuarios:
        return 'Permite gerenciar usuários do sistema';
      case TipoPermissao.configuracoesPermissoes:
        return 'Permite gerenciar permissões de usuários';
      case TipoPermissao.configuracoesSistema:
        return 'Permite alterar configurações do sistema';
      
      case TipoPermissao.nfceEmitir:
        return 'Permite emitir notas fiscais';
      case TipoPermissao.nfceVisualizar:
        return 'Permite visualizar notas fiscais emitidas';
      case TipoPermissao.nfceCancelar:
        return 'Permite cancelar notas fiscais';
      case TipoPermissao.nfceReenviar:
        return 'Permite reenviar notas fiscais';
      
      case TipoPermissao.caixaAbrir:
        return 'Permite abrir caixa';
      case TipoPermissao.caixaFechar:
        return 'Permite fechar caixa';
      case TipoPermissao.caixaVisualizar:
        return 'Permite visualizar movimentações do caixa';
      case TipoPermissao.caixaMovimentar:
        return 'Permite realizar movimentações no caixa';
      case TipoPermissao.caixaVerTotaisFormasPagamento:
        return 'Permite ver o total de cada forma de pagamento (Dinheiro, PIX, Cartão etc.) no fechamento do caixa. Desative para ocultar do operador.';
      case TipoPermissao.caixaVerTotalVendidoFechamento:
        return 'Permite ver o valor total vendido (valor esperado) ao fechar o caixa. Desative para o operador não saber quanto vendeu.';
      case TipoPermissao.caixaVerFluxoCaixa:
        return 'Permite visualizar a tela de Fluxo de Caixa (entradas, saídas e histórico de encerramentos). Desative para ocultar do operador.';
      
      case TipoPermissao.cozinhaVisualizar:
        return 'Permite visualizar pedidos na cozinha/bar';
      case TipoPermissao.cozinhaPreparar:
        return 'Permite marcar pedidos como em preparo';
      case TipoPermissao.cozinhaFinalizar:
        return 'Permite finalizar pedidos';
      case TipoPermissao.cozinhaCancelar:
        return 'Permite cancelar pedidos na cozinha/bar';
      case TipoPermissao.cozinhaFuncionario:
        return 'Permite acessar tela simplificada de cozinha/bar e mesas para funcionários';
      
      case TipoPermissao.financeiroVisualizar:
        return 'Permite visualizar informações financeiras';
      case TipoPermissao.financeiroReceber:
        return 'Permite registrar recebimentos';
      case TipoPermissao.financeiroPagar:
        return 'Permite registrar pagamentos';
      case TipoPermissao.financeiroConciliar:
        return 'Permite conciliar contas';
      
      case TipoPermissao.estoqueVisualizar:
        return 'Permite visualizar estoque';
      case TipoPermissao.estoqueEntrada:
        return 'Permite registrar entrada de estoque';
      case TipoPermissao.estoqueSaida:
        return 'Permite registrar saída de estoque';
      case TipoPermissao.estoqueAjuste:
        return 'Permite realizar ajustes de estoque';
      case TipoPermissao.estoqueTransferencia:
        return 'Permite realizar transferências de estoque';
      
      // Dashboard e Informações Financeiras
      case TipoPermissao.dashboardVisualizar:
        return 'Permite visualizar dashboard com estatísticas gerais';
      case TipoPermissao.dashboardFinanceiro:
        return 'Permite visualizar informações financeiras (totais vendidos, receitas, despesas, etc.)';
      case TipoPermissao.dashboardVerTotais:
        return 'Permite ver os totais de vendas e faturamento do período no dashboard. Desative para ocultar valores financeiros do operador.';
    }
  }
}

