import '../models/empresa.dart';
import '../models/produto.dart';
import '../models/nfce.dart';
import 'nfce_service.dart';

/// Serviço para testes em ambiente de homologação
class TesteHomologacaoService {
  final NFCeService _nfceService;

  TesteHomologacaoService({
    required NFCeService nfceService,
  }) : _nfceService = nfceService;

  /// Executa teste básico de emissão em homologação
  Future<Map<String, dynamic>> executarTesteBasico({
    required Empresa empresa,
    required List<Produto> produtos,
    required double valorTotal,
  }) async {
    try {
      // Validar dados mínimos
      if (empresa.certificadoDigitalUrl == null) {
        return {
          'sucesso': false,
          'erro': 'Certificado digital não configurado',
        };
      }

      if (empresa.senhaCertificado == null) {
        return {
          'sucesso': false,
          'erro': 'Senha do certificado não configurada',
        };
      }

      // Criar pagamento de teste
      final pagamentos = [
        NFCePagamento(
          tipo: '01', // Dinheiro
          valor: valorTotal,
        ),
      ];

      // Criar mapa de quantidades (1.0 para cada produto por padrão)
      final quantidades = <String, double>{};
      for (final produto in produtos) {
        quantidades[produto.id] = 1.0;
      }

      // Tentar emitir NFC-e
      final nfce = await _nfceService.emitir(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        valorTotal: valorTotal,
        ambienteHomologacao: true, // Sempre homologação para testes
      );

      return {
        'sucesso': true,
        'nfce': nfce.toMap(),
        'status': nfce.status,
        'chaveAcesso': nfce.chaveAcesso,
        'protocolo': nfce.protocolo,
        'qrCode': nfce.qrCode,
      };
    } catch (e) {
      return {
        'sucesso': false,
        'erro': e.toString(),
      };
    }
  }

  /// Valida configuração antes de testar
  Future<Map<String, dynamic>> validarConfiguracao(Empresa empresa) async {
    final erros = <String>[];

    if (empresa.cnpj == null || empresa.cnpj!.isEmpty) {
      erros.add('CNPJ não informado');
    }

    if (empresa.inscricaoEstadual == null || empresa.inscricaoEstadual!.isEmpty) {
      erros.add('Inscrição Estadual não informada');
    }

    if (empresa.certificadoDigitalUrl == null || empresa.certificadoDigitalUrl!.isEmpty) {
      erros.add('Certificado Digital não configurado');
    }

    if (empresa.senhaCertificado == null || empresa.senhaCertificado!.isEmpty) {
      erros.add('Senha do Certificado não configurada');
    }

    if (empresa.crt == null) {
      erros.add('CRT (Regime Tributário) não configurado');
    }

    if (empresa.csc == null || empresa.csc!.isEmpty) {
      erros.add('CSC não configurado (obrigatório para produção)');
    }

    if (empresa.cscIdToken == null || empresa.cscIdToken!.isEmpty) {
      erros.add('ID Token CSC não configurado (obrigatório para produção)');
    }

    return {
      'valido': erros.isEmpty,
      'erros': erros,
    };
  }
}

