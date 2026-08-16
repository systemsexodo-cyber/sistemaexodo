import '../models/empresa.dart';
import '../models/tela_sistema.dart';
import '../models/usuario.dart';
import 'permission_service.dart';

/// Serviço para verificar acesso às telas do sistema
class TelaAccessService {
  
  /// Mapeia o código de uma tela para a permissão de visualização necessária
  static String? _mapearTelaParaPermissao(String codigoTela) {
    switch (codigoTela) {
      case 'pdv':
        return 'vendas.criar';
      case 'vendas':
      case 'pedidos':
      case 'mesas':
        return 'vendas.visualizar';
      case 'clientes':
        return 'clientes.visualizar';
      case 'produtos':
      case 'servicos':
        return 'produtos.visualizar';
      case 'funcionarios':
      case 'usuarios':
        return 'configuracoes.usuarios';
      case 'estoque':
      case 'entrada_mercadorias':
        return 'estoque.visualizar';
      case 'financeiro':
      case 'contas_pagar':
      case 'contas_receber':
      case 'agenda_contas':
        return 'financeiro.visualizar';
      case 'caixa':
        return 'caixa.visualizar';
      case 'relatorios':
        return 'relatorios.visualizar';
      case 'relatorio_vendas':
        return 'relatorios.vendas';
      case 'relatorio_estoque':
        return 'relatorios.estoque';
      case 'relatorio_financeiro':
        return 'relatorios.financeiro';
      case 'cozinha_bar':
        return 'cozinha.visualizar';
      case 'configuracoes':
        return 'configuracoes.visualizar';
      case 'empresas':
        return 'configuracoes.empresa';
      case 'permissoes':
        return 'configuracoes.permissoes';
      case 'dashboard':
        return 'dashboard.visualizar';
      default:
        return null;
    }
  }

  /// Verifica se o usuário pode acessar uma tela específica
  static bool podeAcessarTela(
    Usuario? usuario,
    Empresa? empresa,
    TelaSistema tela,
  ) {
    return podeAcessarTelaPorCodigo(usuario, empresa, tela.codigo);
  }
  
  /// Verifica se o usuário pode acessar uma tela por código
  static bool podeAcessarTelaPorCodigo(
    Usuario? usuario,
    Empresa? empresa,
    String codigoTela,
  ) {
    // 1. Usuário "user", admin, master ou GERENTE sempre têm acesso total
    if (usuario != null) {
      final emailMin = usuario.email.toLowerCase();
      final isUserSuporte = emailMin == 'user';
      final isGerente = usuario.isGerente || usuario.tipo.name == 'gerente';
      
      if (isUserSuporte || usuario.isAdmin || usuario.isMaster || isGerente) {
        return true;
      }
    }
    
    // 2. Verificar se o usuário tem a tela explicitamente oculta (bloqueio individual)
    if (usuario != null && usuario.telasOcultas != null && usuario.telasOcultas!.contains(codigoTela)) {
      return false;
    }
    
    // 3. Verificar se o usuário tem a permissão para acessar essa tela (por cargo ou personalizada)
    // Isso é verificado ANTES da restrição de empresa para que operadores com permissões adequadas
    // possam acessar as telas mesmo que a empresa tenha telasPermitidas configuradas (licença)
    final codigoPermissao = _mapearTelaParaPermissao(codigoTela);
    if (usuario != null && codigoPermissao != null) {
      final permissionService = PermissionService();
      if (permissionService.temPermissaoPorCodigo(usuario, codigoPermissao)) {
        return true;
      }
    }
    
    // 4. Se não tem permissão para essa tela, verifica empresa (licença)
    // Se a empresa tem lista de telas e esta tela não está nela, bloqueia
    if (empresa != null && !empresa.podeAcessarTela(codigoTela)) {
      return false;
    }
    
    // 5. Default: se não tem permissão mapeada e não é licença de empresa, bloqueia por segurança
    return false;
  }
  
  /// Retorna todas as telas que o usuário pode acessar
  static List<TelaSistema> obterTelasAcessiveis(
    Usuario? usuario,
    Empresa? empresa,
  ) {
    // Se for admin, master, suporte ou gerente, retorna todas as telas do sistema
    if (usuario != null) {
      final emailMin = usuario.email.toLowerCase();
      final isUserSuporte = emailMin == 'user';
      final isGerente = usuario.isGerente || usuario.tipo.name == 'gerente';
      
      if (isUserSuporte || usuario.isAdmin || usuario.isMaster || isGerente) {
        return TelaSistema.values;
      }
    }
    
    // Para operadores e vendedores, filtramos com base nas permissões
    final telasAcessiveis = <TelaSistema>[];
    for (final tela in TelaSistema.values) {
      if (podeAcessarTelaPorCodigo(usuario, empresa, tela.codigo)) {
        telasAcessiveis.add(tela);
      }
    }
    
    return telasAcessiveis;
  }
}
