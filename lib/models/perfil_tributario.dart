class PerfilTributario {
  final String id;
  final String nome;
  final String cfop;
  final String? icmsCst;      // Usado se Regime Normal
  final String? csosn;        // Usado se Simples Nacional
  final double? aliquotaIcms;
  final String? pisCst;
  final double? aliquotaPis;
  final String? cofinsCst;
  final double? aliquotaCofins;
  
  // Reforma Tributária (IBS e CBS)
  final String? cstIbs;       // Novo: CST do IBS
  final double? aliquotaIbs;  // Alíquota do IBS (%)
  final String? cstCbs;       // Novo: CST da CBS
  final double? aliquotaCbs;  // Alíquota do CBS (%)
  
  // Tributação avançada
  final String? ipiCst;              // CST do IPI
  final double? aliquotaIpi;          // Alíquota do IPI (%)
  final double? mva;                  // Margem de Valor Agregado (%) - usado em ICMS ST
  final double? reducaoBaseIcms;      // Redução de Base de Cálculo do ICMS (%)
  final double? aliquotaFcp;          // Alíquota do Fundo de Combate à Pobreza (%)
  final double? aliquotaIcmsInterestadual; // Alíquota do ICMS Interestadual (%)
  
  final String? ncm;          // NCM padrão (opcional)
  final bool isDefault;       // Se true, é o perfil padrão do sistema

  PerfilTributario({
    required this.id,
    required this.nome,
    required this.cfop,
    this.icmsCst,
    this.csosn,
    this.aliquotaIcms,
    this.pisCst,
    this.aliquotaPis,
    this.cofinsCst,
    this.aliquotaCofins,
    this.cstIbs,
    this.aliquotaIbs,
    this.cstCbs,
    this.aliquotaCbs,
    this.ipiCst,
    this.aliquotaIpi,
    this.mva,
    this.reducaoBaseIcms,
    this.aliquotaFcp,
    this.aliquotaIcmsInterestadual,
    this.ncm,
    this.isDefault = false,
  });

  factory PerfilTributario.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    return PerfilTributario(
      id: map['id']?.toString() ?? '',
      nome: map['nome'] ?? '',
      cfop: map['cfop'] ?? '5102',
      icmsCst: map['icms_cst'] ?? map['icmsCst'],
      csosn: map['csosn'],
      aliquotaIcms: parseDouble(map['aliquota_icms'] ?? map['aliquotaIcms']),
      pisCst: map['pis_cst'] ?? map['pisCst'],
      aliquotaPis: parseDouble(map['aliquota_pis'] ?? map['aliquotaPis']),
      cofinsCst: map['cofins_cst'] ?? map['cofinsCst'],
      aliquotaCofins: parseDouble(map['aliquota_cofins'] ?? map['aliquotaCofins']),
      
      cstIbs: map['cst_ibs'] ?? map['cstIbs'],
      aliquotaIbs: parseDouble(map['aliquota_ibs'] ?? map['aliquotaIbs']),
      cstCbs: map['cst_cbs'] ?? map['cstCbs'],
      aliquotaCbs: parseDouble(map['aliquota_cbs'] ?? map['aliquotaCbs']),
      
      ipiCst: map['ipi_cst'] ?? map['ipiCst'],
      aliquotaIpi: parseDouble(map['aliquota_ipi'] ?? map['aliquotaIpi']),
      mva: parseDouble(map['mva']),
      reducaoBaseIcms: parseDouble(map['reducao_base_icms'] ?? map['reducaoBaseIcms']),
      aliquotaFcp: parseDouble(map['aliquota_fcp'] ?? map['aliquotaFcp']),
      aliquotaIcmsInterestadual: parseDouble(map['aliquota_icms_interestadual'] ?? map['aliquotaIcmsInterestadual']),
      
      ncm: map['ncm'],
      isDefault: map['is_default'] ?? map['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'cfop': cfop,
      'icms_cst': icmsCst,
      'csosn': csosn,
      'aliquota_icms': aliquotaIcms,
      'pis_cst': pisCst,
      'aliquota_pis': aliquotaPis,
      'cofins_cst': cofinsCst,
      'aliquota_cofins': aliquotaCofins,
      
      'cst_ibs': cstIbs,
      'aliquota_ibs': aliquotaIbs,
      'cst_cbs': cstCbs,
      'aliquota_cbs': aliquotaCbs,
      
      'ipi_cst': ipiCst,
      'aliquota_ipi': aliquotaIpi,
      'mva': mva,
      'reducao_base_icms': reducaoBaseIcms,
      'aliquota_fcp': aliquotaFcp,
      'aliquota_icms_interestadual': aliquotaIcmsInterestadual,
      
      'ncm': ncm,
      'is_default': isDefault,
    };
  }
}
