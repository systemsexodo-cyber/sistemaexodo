import '../models/empresa.dart';
import '../models/tela_sistema.dart';
import '../models/usuario.dart';

/// Serviço para verificar acesso às telas do sistema
class TelaAccessService {
  /// Verifica se o usuário pode acessar uma tela específica
  /// 
  /// Regras:
  /// - Usuário "user" sempre tem acesso a todas as telas
  /// - Se o usuário tiver a tela em telasOcultas, não pode acessar
  /// - Se a empresa não tiver telasPermitidas configuradas (null), todas as telas são permitidas
  /// - Caso contrário, verifica se a tela está na lista de telas permitidas
  static bool podeAcessarTela(
    Usuario? usuario,
    Empresa? empresa,
    TelaSistema tela,
  ) {
    // Usuário "user", admin ou master sempre tá acesso a tudo
    if (usuario != null && (usuario.email.toLowerCase() == 'user' || usuario.isAdmin || usuario.isMaster)) {
      return true;
    }
    
    // Verificar se o usuário tem a tela oculta
    if (usuario != null && usuario.telasOcultas != null && usuario.telasOcultas!.contains(tela.codigo)) {
      return false;
    }
    
    // Se não houver empresa, permitir acesso (fallback)
    if (empresa == null) {
      return true;
    }
    
    // Verificar se a empresa permite acesso à tela
    return empresa.podeAcessarTela(tela.codigo);
  }
  
  /// Verifica se o usuário pode acessar uma tela por código
  static bool podeAcessarTelaPorCodigo(
    Usuario? usuario,
    Empresa? empresa,
    String codigoTela,
  ) {
    // Usuário "user", admin ou master sempre tém acesso a tudo
    if (usuario != null && (usuario.email.toLowerCase() == 'user' || usuario.isAdmin || usuario.isMaster)) {
      return true;
    }
    
    // Verificar se o usuário tem a tela oculta
    if (usuario != null && usuario.telasOcultas != null && usuario.telasOcultas!.contains(codigoTela)) {
      return false;
    }
    
    // Se não houver empresa, permitir acesso (fallback)
    if (empresa == null) {
      return true;
    }
    
    // Verificar se a empresa permite acesso à tela
    return empresa.podeAcessarTela(codigoTela);
  }
  
  /// Retorna todas as telas que o usuário pode acessar
  static List<TelaSistema> obterTelasAcessiveis(
    Usuario? usuario,
    Empresa? empresa,
  ) {
    // Usuário "user", admin ou master sempre tém acesso a tudo
    if (usuario != null && (usuario.email.toLowerCase() == 'user' || usuario.isAdmin || usuario.isMaster)) {
      return TelaSistema.values;
    }
    
    // Começar com todas as telas
    var telas = TelaSistema.values;
    
    // Filtrar telas ocultas do usuário
    if (usuario != null && usuario.telasOcultas != null && usuario.telasOcultas!.isNotEmpty) {
      telas = telas.where((tela) => !usuario.telasOcultas!.contains(tela.codigo)).toList();
    }
    
    // Se não houver empresa, retornar telas filtradas (fallback)
    if (empresa == null) {
      return telas;
    }
    
    // Se empresa não tiver restrições, retornar telas filtradas
    if (empresa.telasPermitidas == null || empresa.telasPermitidas!.isEmpty) {
      return telas;
    }
    
    // Retornar apenas telas permitidas pela empresa e não ocultas pelo usuário
    return telas
        .where((tela) => empresa.telasPermitidas!.contains(tela.codigo))
        .toList();
  }
}

