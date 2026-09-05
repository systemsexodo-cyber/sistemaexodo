import os

api_service_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\services\nfce_api_service.dart"
backend_service_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\services\nfce_backend_service.dart"

# 1. Ajustar nfce_api_service.dart para não quebrar a assinatura de NFCeServiceBase
with open(api_service_path, "r", encoding="utf-8") as f:
    content_api = f.read()

target_api = """  /// Emite uma NFC-e usando API pronta
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
  }) async {"""

replacement_api = """  /// Emite uma NFC-e usando API pronta
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    // Novos campos adicionados para manter a assinatura com NFCeServiceBase
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
    int? modelo,
    int? numero,
    String? destLogradouro,
    String? destNumero,
    String? destComplemento,
    String? destBairro,
    String? destMunicipio,
    String? destUf,
    String? destCep,
    String? destCodMunicipio,
    String? destTelefone,
    String? destEmail,
    String? destIe,
    int? finalidade,
    String? naturezaOperacao,
    String? chaveReferenciada,
    double? valorFrete,
    double? valorSeguro,
    double? outrasDespesas,
    int? modFrete,
    String? transpNome,
    String? transpCnpjCpf,
    String? transpInscEst,
    String? transpEndereco,
    String? transpMunicipio,
    String? transpUf,
    String? transpPlaca,
    String? transpPlacaUf,
    double? transpQtdVolumes,
    String? transpEspecie,
    double? transpPesoBruto,
    double? transpPesoLiquido,
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) async {"""

if target_api in content_api:
    content_api = content_api.replace(target_api, replacement_api)
    print("API_SERVICE_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_API_SERVICE")

with open(api_service_path, "w", encoding="utf-8") as f:
    f.write(content_api)


# 2. Ajustar nfce_backend_service.dart
with open(backend_service_path, "r", encoding="utf-8") as f:
    content_backend = f.read()

# 2.1 Adicionar na assinatura de NFCeServiceBase
target_base = """    double? transpPesoBruto,
    double? transpPesoLiquido,
  });"""

replacement_base = """    double? transpPesoBruto,
    double? transpPesoLiquido,
    
    // Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002)
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  });"""

if target_base in content_backend:
    content_backend = content_backend.replace(target_base, replacement_base)
    print("BASE_SERVICE_ASSINATURA_ATUALIZADA")
else:
    print("FALHA_AO_ATUALIZAR_BASE_SERVICE_ASSINATURA")

# 2.2 Adicionar nos parâmetros de NFCeBackendService.emitir
target_emitir = """    double? transpPesoBruto,
    double? transpPesoLiquido,
    String? vendaId,
    String? vendaNumero,
  }) async {"""

replacement_emitir = """    double? transpPesoBruto,
    double? transpPesoLiquido,
    String? vendaId,
    String? vendaNumero,
    
    // Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002)
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) async {"""

if target_emitir in content_backend:
    content_backend = content_backend.replace(target_emitir, replacement_emitir)
    print("EMITIR_BACKEND_ASSINATURA_ATUALIZADA")
else:
    # Se a ordem dos parâmetros no construtor for diferente:
    normalized_backend = content_backend.replace("\r\n", "\n")
    target_emitir_alt = """    double? transpPesoBruto,
    double? transpPesoLiquido,
  }) async {"""
    replacement_emitir_alt = """    double? transpPesoBruto,
    double? transpPesoLiquido,
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) async {"""
    if target_emitir_alt in normalized_backend:
        normalized_backend = normalized_backend.replace(target_emitir_alt, replacement_emitir_alt)
        content_backend = normalized_backend
        print("EMITIR_BACKEND_ASSINATURA_ATUALIZADA_ALT")
    else:
        print("FALHA_AO_ATUALIZAR_EMITIR_BACKEND_ASSINATURA")

# 2.3 Passar na chamada interna de _prepararPayload
target_preparar_call = """      transpPesoBruto: transpPesoBruto,
      transpPesoLiquido: transpPesoLiquido,
    );"""

replacement_preparar_call = """      transpPesoBruto: transpPesoBruto,
      transpPesoLiquido: transpPesoLiquido,
      icmsReducaoBc: icmsReducaoBc,
      icmsBaseCalculo: icmsBaseCalculo,
      icmsAliquota: icmsAliquota,
      icmsValor: icmsValor,
      creditoAliquota: creditoAliquota,
      creditoValor: creditoValor,
    );"""

if target_preparar_call in content_backend:
    content_backend = content_backend.replace(target_preparar_call, replacement_preparar_call)
    print("PREPARAR_CALL_ATUALIZADA")
else:
    normalized_backend = content_backend.replace("\r\n", "\n")
    normalized_target = target_preparar_call.replace("\r\n", "\n")
    normalized_replacement = replacement_preparar_call.replace("\r\n", "\n")
    if normalized_target in normalized_backend:
        normalized_backend = normalized_backend.replace(normalized_target, normalized_replacement)
        content_backend = normalized_backend
        print("PREPARAR_CALL_NORMALIZADA")
    else:
        print("FALHA_AO_ATUALIZAR_PREPARAR_CALL")

# 2.4 Assinatura do método privado _prepararPayload
target_preparar_sig = """    double? transpPesoBruto,
    double? transpPesoLiquido,
  }) {"""

replacement_preparar_sig = """    double? transpPesoBruto,
    double? transpPesoLiquido,
    double? icmsReducaoBc,
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? creditoAliquota,
    double? creditoValor,
  }) {"""

if target_preparar_sig in content_backend:
    content_backend = content_backend.replace(target_preparar_sig, replacement_preparar_sig)
    print("PREPARAR_SIG_ATUALIZADA")
else:
    normalized_backend = content_backend.replace("\r\n", "\n")
    normalized_target = target_preparar_sig.replace("\r\n", "\n")
    normalized_replacement = replacement_preparar_sig.replace("\r\n", "\n")
    if normalized_target in normalized_backend:
        normalized_backend = normalized_backend.replace(normalized_target, normalized_replacement)
        content_backend = normalized_backend
        print("PREPARAR_SIG_NORMALIZADA")
    else:
        print("FALHA_AO_ATUALIZAR_PREPARAR_SIG")

# 2.5 Injetar os valores tributários no JSON de cada item dentro de _prepararPayload
target_payload_item = """        return {
          'codigo': p.codigo ?? p.id,
          'descricao': p.nome,
          'ncm': ncm,
          'cfop': cfop,
          'quantidade': qty,
          'valor_unitario': p.preco,
          'valor_total': p.preco * qty,
          if (csosn != null && csosn.isNotEmpty) 'csosn': csosn,
          if (icmsCst != null && icmsCst.isNotEmpty) 'icms_cst': icmsCst,
          if (pisCst != null && pisCst.isNotEmpty) 'pis_cst': pisCst,
          if (cofinsCst != null && cofinsCst.isNotEmpty) 'cofins_cst': cofinsCst,
          if (icmsAliquota != null) 'icms_aliquota': icmsAliquota,
          if (ipiCst != null && ipiCst.isNotEmpty) 'ipi_cst': ipiCst,
          if (aliquotaIpi != null) 'ipi_aliquota': aliquotaIpi,
          if (mva != null) 'mva': mva,
          if (reducaoBaseIcms != null) 'reducao_base_icms': reducaoBaseIcms,
          if (aliquotaFcp != null) 'fcp_aliquota': aliquotaFcp,
          if (aliquotaIcmsInterestadual != null) 'icms_aliquota_interestadual': aliquotaIcmsInterestadual,
          if (cstIbs != null && cstIbs.isNotEmpty) 'ibs_cst': cstIbs,
          if (aliquotaIbs != null) 'ibs_aliquota': aliquotaIbs,
          if (cstCbs != null && cstCbs.isNotEmpty) 'cbs_cst': cstCbs,
          if (aliquotaCbs != null) 'cbs_aliquota': aliquotaCbs,
        };"""

replacement_payload_item = """        return {
          'codigo': p.codigo ?? p.id,
          'descricao': p.nome,
          'ncm': ncm,
          'cfop': cfop,
          'quantidade': qty,
          'valor_unitario': p.preco,
          'valor_total': p.preco * qty,
          if (csosn != null && csosn.isNotEmpty) 'csosn': csosn,
          if (icmsCst != null && icmsCst.isNotEmpty) 'icms_cst': icmsCst,
          if (pisCst != null && pisCst.isNotEmpty) 'pis_cst': pisCst,
          if (cofinsCst != null && cofinsCst.isNotEmpty) 'cofins_cst': cofinsCst,
          
          // Suporte a Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002)
          'icms_reducao_bc': icmsReducaoBc ?? (reducaoBaseIcms ?? 0.0),
          'icms_base_calculo': icmsBaseCalculo ?? (p.preco * qty),
          'icms_aliquota': icmsAliquota ?? 0.0,
          'icms_valor': icmsValor ?? 0.0,
          'credito_aliquota': creditoAliquota ?? 0.0,
          'credito_valor': creditoValor ?? 0.0,
          
          if (ipiCst != null && ipiCst.isNotEmpty) 'ipi_cst': ipiCst,
          if (aliquotaIpi != null) 'ipi_aliquota': aliquotaIpi,
          if (mva != null) 'mva': mva,
          if (reducaoBaseIcms != null) 'reducao_base_icms': reducaoBaseIcms,
          if (aliquotaFcp != null) 'fcp_aliquota': aliquotaFcp,
          if (aliquotaIcmsInterestadual != null) 'icms_aliquota_interestadual': aliquotaIcmsInterestadual,
          if (cstIbs != null && cstIbs.isNotEmpty) 'ibs_cst': cstIbs,
          if (aliquotaIbs != null) 'ibs_aliquota': aliquotaIbs,
          if (cstCbs != null && cstCbs.isNotEmpty) 'cbs_cst': cstCbs,
          if (aliquotaCbs != null) 'cbs_aliquota': aliquotaCbs,
        };"""

if target_payload_item in content_backend:
    content_backend = content_backend.replace(target_payload_item, replacement_payload_item)
    print("PAYLOAD_ITEM_TRIBUTOS_INJETADOS")
else:
    normalized_backend = content_backend.replace("\r\n", "\n")
    normalized_target = target_payload_item.replace("\r\n", "\n")
    normalized_replacement = replacement_payload_item.replace("\r\n", "\n")
    if normalized_target in normalized_backend:
        normalized_backend = normalized_backend.replace(normalized_target, normalized_replacement)
        content_backend = normalized_backend
        print("PAYLOAD_ITEM_TRIBUTOS_NORMALIZADOS")
    else:
        print("FALHA_AO_INJETAR_PAYLOAD_ITEM_TRIBUTOS")

with open(backend_service_path, "w", encoding="utf-8") as f:
    f.write(content_backend)
