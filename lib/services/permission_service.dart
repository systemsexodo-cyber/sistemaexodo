import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import '../models/permissao.dart';

/// Serviço para gerenciar e verificar permissões do sistema
class PermissionService extends ChangeNotifier {
  // Cache de permissões padrão por tipo de usuário
  final Map<TipoUsuario, Set<String>> _permissoesPadrao = {};
  
  PermissionService() {
    _inicializarPermissoesPadrao();
  }

  /// Inicializa as permissões padrão para cada tipo de usuário
  void _inicializarPermissoesPadrao() {
    // Administrador tem todas as permissões
    _permissoesPadrao[TipoUsuario.administrador] = TipoPermissao.values
        .map((p) => p.codigo)
        .toSet();

    // Gerente tem a maioria das permissões, exceto configurações críticas
    _permissoesPadrao[TipoUsuario.gerente] = {
      // Vendas
      TipoPermissao.vendasVisualizar.codigo,
      TipoPermissao.vendasCriar.codigo,
      TipoPermissao.vendasEditar.codigo,
      TipoPermissao.vendasCancelar.codigo,
      TipoPermissao.vendasAplicarDesconto.codigo,
      TipoPermissao.vendasVerCusto.codigo,
      TipoPermissao.vendasAlterarPrecoItem.codigo,
      
      // Produtos
      TipoPermissao.produtosVisualizar.codigo,
      TipoPermissao.produtosCriar.codigo,
      TipoPermissao.produtosEditar.codigo,
      TipoPermissao.produtosAlterarPreco.codigo,
      TipoPermissao.produtosGerenciarEstoque.codigo,
      TipoPermissao.produtosVisualizarCusto.codigo,
      
      // Clientes
      TipoPermissao.clientesVisualizar.codigo,
      TipoPermissao.clientesCriar.codigo,
      TipoPermissao.clientesEditar.codigo,
      TipoPermissao.clientesVerHistorico.codigo,
      
      // Relatórios
      TipoPermissao.relatoriosVisualizar.codigo,
      TipoPermissao.relatoriosVendas.codigo,
      TipoPermissao.relatoriosFinanceiro.codigo,
      TipoPermissao.relatoriosEstoque.codigo,
      TipoPermissao.relatoriosExportar.codigo,
      
      // Dashboard e Informações Financeiras
      TipoPermissao.dashboardVisualizar.codigo,
      TipoPermissao.dashboardFinanceiro.codigo,
      TipoPermissao.dashboardVerTotais.codigo,
      
      // NFC-e
      TipoPermissao.nfceEmitir.codigo,
      TipoPermissao.nfceVisualizar.codigo,
      TipoPermissao.nfceCancelar.codigo,
      TipoPermissao.nfceReenviar.codigo,
      
      // Caixa
      TipoPermissao.caixaAbrir.codigo,
      TipoPermissao.caixaFechar.codigo,
      TipoPermissao.caixaVisualizar.codigo,
      TipoPermissao.caixaMovimentar.codigo,
      TipoPermissao.caixaVerTotaisFormasPagamento.codigo,
      TipoPermissao.caixaVerTotalVendidoFechamento.codigo,
      TipoPermissao.caixaVerFluxoCaixa.codigo,
      
      // Cozinha/Bar
      TipoPermissao.cozinhaVisualizar.codigo,
      TipoPermissao.cozinhaPreparar.codigo,
      TipoPermissao.cozinhaFinalizar.codigo,
      TipoPermissao.cozinhaCancelar.codigo,
      TipoPermissao.cozinhaFuncionario.codigo,
      
      // Financeiro
      TipoPermissao.financeiroVisualizar.codigo,
      TipoPermissao.financeiroReceber.codigo,
      TipoPermissao.financeiroPagar.codigo,
      TipoPermissao.financeiroConciliar.codigo,
      
      // Estoque
      TipoPermissao.estoqueVisualizar.codigo,
      TipoPermissao.estoqueEntrada.codigo,
      TipoPermissao.estoqueSaida.codigo,
      TipoPermissao.estoqueAjuste.codigo,
      TipoPermissao.estoqueTransferencia.codigo,
      
      // Configurações (limitadas)
      TipoPermissao.configuracoesVisualizar.codigo,
      // configuracoesEmpresa removida - apenas "user" (administrador) tem acesso
    };

    // Operador tem permissões básicas (PDV, Vendas, Produtos, Pedidos, Caixa) sem acesso ao Preço de Custo
    _permissoesPadrao[TipoUsuario.operador] = {
      // Vendas & Pedidos
      TipoPermissao.vendasVisualizar.codigo,
      TipoPermissao.vendasCriar.codigo,
      TipoPermissao.vendasEditar.codigo,
      
      // Produtos
      TipoPermissao.produtosVisualizar.codigo,
      
      // Clientes
      TipoPermissao.clientesVisualizar.codigo,
      TipoPermissao.clientesCriar.codigo,
      TipoPermissao.clientesEditar.codigo,
      
      // NFC-e
      TipoPermissao.nfceEmitir.codigo,
      TipoPermissao.nfceVisualizar.codigo,
      
      // Caixa
      TipoPermissao.caixaVisualizar.codigo,
      TipoPermissao.caixaAbrir.codigo,
      TipoPermissao.caixaFechar.codigo,
      TipoPermissao.caixaMovimentar.codigo,
      
      // Cozinha/Bar
      TipoPermissao.cozinhaVisualizar.codigo,
      TipoPermissao.cozinhaPreparar.codigo,
      TipoPermissao.cozinhaFinalizar.codigo,
      
      // Estoque
      TipoPermissao.estoqueVisualizar.codigo,
    };

    // Vendedor tem permissões mínimas
    _permissoesPadrao[TipoUsuario.vendedor] = {
      // Vendas
      TipoPermissao.vendasVisualizar.codigo,
      TipoPermissao.vendasCriar.codigo,
      
      // Produtos
      TipoPermissao.produtosVisualizar.codigo,
      
      // Clientes
      TipoPermissao.clientesVisualizar.codigo,
      TipoPermissao.clientesCriar.codigo,
      
      // NFC-e
      TipoPermissao.nfceEmitir.codigo,
      TipoPermissao.nfceVisualizar.codigo,
      
      // Cozinha/Bar
      TipoPermissao.cozinhaVisualizar.codigo,
    };
  }

  /// Obtém todas as permissões de um usuário (padrão + personalizadas)
  Set<String> obterPermissoes(Usuario usuario) {
    final permissoes = <String>{};
    
    // Adiciona permissões padrão do tipo de usuário
    final permissoesPadrao = _permissoesPadrao[usuario.tipo] ?? {};
    permissoes.addAll(permissoesPadrao);
    
    // Adiciona permissões personalizadas do usuário (se houver)
    if (usuario.permissoesPersonalizadas != null) {
      permissoes.addAll(usuario.permissoesPersonalizadas!);
    }
    
    // Remove permissões negadas (se houver)
    if (usuario.permissoesNegadas != null) {
      permissoes.removeAll(usuario.permissoesNegadas!);
    }
    
    return permissoes;
  }

  /// Verifica se o usuário tem uma permissão específica
  bool temPermissao(Usuario? usuario, TipoPermissao permissao) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    
    // Administrador sempre tem todas as permissões
    if (usuario.isAdmin) {
      return true;
    }
    
    final permissoes = obterPermissoes(usuario);
    return permissoes.contains(permissao.codigo);
  }

  /// Verifica se o usuário tem uma permissão por código
  bool temPermissaoPorCodigo(Usuario? usuario, String codigoPermissao) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    
    // Administrador sempre tem todas as permissões
    if (usuario.isAdmin) {
      return true;
    }
    
    final permissoes = obterPermissoes(usuario);
    return permissoes.contains(codigoPermissao);
  }

  /// Verifica se o usuário tem pelo menos uma das permissões especificadas
  bool temAlgumaPermissao(Usuario? usuario, List<TipoPermissao> permissoes) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    
    // Administrador sempre tem todas as permissões
    if (usuario.isAdmin) {
      return true;
    }
    
    final permissoesUsuario = obterPermissoes(usuario);
    return permissoes.any((p) => permissoesUsuario.contains(p.codigo));
  }

  /// Verifica se o usuário tem todas as permissões especificadas
  bool temTodasPermissoes(Usuario? usuario, List<TipoPermissao> permissoes) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    
    // Administrador sempre tem todas as permissões
    if (usuario.isAdmin) {
      return true;
    }
    
    final permissoesUsuario = obterPermissoes(usuario);
    return permissoes.every((p) => permissoesUsuario.contains(p.codigo));
  }

  /// Verifica se o usuário pode ver os TOTAIS de vendas/faturamento do período.
  ///
  /// Sem esta permissão, os valores financeiros (faturamento, entradas, totais do
  /// histórico de vendas) ficam ocultos para o operador/funcionário — eles podem
  /// operar o caixa e fazer vendas, mas não saber quanto a empresa vende.
  /// Administrador, Master e Gerente sempre têm acesso aos totais.
  bool podeVerTotais(Usuario? usuario) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    if (usuario.isAdmin || usuario.isMaster || usuario.isGerente) {
      return true;
    }
    return temPermissao(usuario, TipoPermissao.dashboardVerTotais);
  }

  /// Verifica se o usuário pode ver o total de CADA forma de pagamento
  /// (Dinheiro, PIX, Cartão etc.) no fechamento do caixa.
  ///
  /// Permissão separada de [podeVerTotais]: mesmo quem não vê o faturamento
  /// geral pode (ou não) ver o detalhamento por forma de pagamento, conforme
  /// configurado em Gerenciar Permissões. Admin/Master/Gerente sempre veem.
  bool podeVerTotaisFormasPagamento(Usuario? usuario) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    if (usuario.isAdmin || usuario.isMaster || usuario.isGerente) {
      return true;
    }
    return temPermissao(usuario, TipoPermissao.caixaVerTotaisFormasPagamento);
  }

  /// Verifica se o usuário pode ver o valor total vendido (valor esperado)
  /// ao fechar o caixa. Sem esta permissão, o operador fecha o caixa sem
  /// saber quanto vendeu. Admin/Master/Gerente sempre veem.
  bool podeVerTotalVendidoFechamento(Usuario? usuario) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    if (usuario.isAdmin || usuario.isMaster || usuario.isGerente) {
      return true;
    }
    return temPermissao(usuario, TipoPermissao.caixaVerTotalVendidoFechamento);
  }

  /// Verifica se o usuário pode visualizar a tela de Fluxo de Caixa.
  ///
  /// Sem esta permissão, o operador/funcionário não vê a tela de Fluxo de
  /// Caixa (entradas, saídas e histórico de encerramentos). Admin/Master/Gerente
  /// sempre podem.
  bool podeVerFluxoCaixa(Usuario? usuario) {
    if (usuario == null || !usuario.ativo) {
      return false;
    }
    if (usuario.isAdmin || usuario.isMaster || usuario.isGerente) {
      return true;
    }
    return temPermissao(usuario, TipoPermissao.caixaVerFluxoCaixa);
  }

  /// Obtém todas as permissões disponíveis no sistema
  List<TipoPermissao> obterTodasPermissoes() {
    return TipoPermissao.values;
  }

  /// Obtém permissões agrupadas por categoria
  Map<String, List<TipoPermissao>> obterPermissoesPorCategoria() {
    final categorias = <String, List<TipoPermissao>>{};
    
    for (final permissao in TipoPermissao.values) {
      final categoria = permissao.categoria;
      if (!categorias.containsKey(categoria)) {
        categorias[categoria] = [];
      }
      categorias[categoria]!.add(permissao);
    }
    
    return categorias;
  }

  /// Obtém permissões padrão de um tipo de usuário
  Set<String> obterPermissoesPadrao(TipoUsuario tipo) {
    return Set.from(_permissoesPadrao[tipo] ?? {});
  }

  /// Verifica se uma permissão pode ser concedida a um tipo de usuário
  bool podeConcederPermissao(TipoUsuario tipo, TipoPermissao permissao) {
    // Administrador pode ter qualquer permissão
    if (tipo == TipoUsuario.administrador) {
      return true;
    }
    
    // Verifica se a permissão está nas permissões padrão do tipo
    final permissoesPadrao = _permissoesPadrao[tipo] ?? {};
    return permissoesPadrao.contains(permissao.codigo);
  }
}

