import 'dart:io';

void main() {
  final file = File('lib/services/data_service.dart');
  final lines = file.readAsLinesSync();
  
  // Find the last closing brace
  int lastBraceIndex = -1;
  for (int i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim() == '}') {
      lastBraceIndex = i;
      break;
    }
  }
  
  if (lastBraceIndex == -1) {
    print('Error: Could not find closing brace in DataService.');
    return;
  }
  
  final additions = """
  // ===========================================================================
  // PERFIS TRIBUTÁRIOS (RESTORED)
  // ===========================================================================
  
  List<PerfilTributario> _perfisTributarios = [];
  List<PerfilTributario> get perfisTributarios => _perfisTributarios;

  Future<void> salvarPerfilTributario(PerfilTributario perfil) async {
    final index = _perfisTributarios.indexWhere((p) => p.id == perfil.id);
    if (index >= 0) {
      _perfisTributarios[index] = perfil;
    } else {
      _perfisTributarios.add(perfil);
    }
    
    if (perfil.isDefault) {
      for (int i = 0; i < _perfisTributarios.length; i++) {
        if (_perfisTributarios[i].id != perfil.id && _perfisTributarios[i].isDefault) {
          final p = _perfisTributarios[i];
          _perfisTributarios[i] = PerfilTributario(
            id: p.id, nome: p.nome, cfop: p.cfop, icmsCst: p.icmsCst, csosn: p.csosn, aliquotaIcms: p.aliquotaIcms, pisCst: p.pisCst, aliquotaPis: p.aliquotaPis, cofinsCst: p.cofinsCst, aliquotaCofins: p.aliquotaCofins, cstIbs: p.cstIbs, aliquotaIbs: p.aliquotaIbs, cstCbs: p.cstCbs, aliquotaCbs: p.aliquotaCbs, ipiCst: p.ipiCst, aliquotaIpi: p.aliquotaIpi, mva: p.mva, reducaoBaseIcms: p.reducaoBaseIcms, aliquotaFcp: p.aliquotaFcp, aliquotaIcmsInterestadual: p.aliquotaIcmsInterestadual, ncm: p.ncm, isDefault: false,
          );
        }
      }
    }
    
    await _storage.salvarLista(_getEmpresaKey('perfis_tributarios'), _perfisTributarios.map((p) => p.toMap()).toList());
    
    final map = perfil.toMap();
    map['empresa_id'] = _empresaId;
    _syncQueue.addOperacao('perfis_tributarios', 'UPSERT', map);
    
    notifyListeners();
  }

  Future<void> excluirPerfilTributario(PerfilTributario perfil) async {
    _perfisTributarios.removeWhere((p) => p.id == perfil.id);
    await _storage.salvarLista(_getEmpresaKey('perfis_tributarios'), _perfisTributarios.map((p) => p.toMap()).toList());
    _syncQueue.addOperacao('perfis_tributarios', 'DELETE', {'id': perfil.id, 'empresa_id': _empresaId});
    notifyListeners();
  }

  double calcularDinheiroEmCaixa() {
    if (!caixaAberto || _aberturaAtual == null) return 0.0;
    double total = _aberturaAtual!.valorAbertura;
    
    for (var sup in _suprimentosCaixa.where((s) => s.aberturaCaixaId == _aberturaAtual!.id)) {
      total += sup.valor;
    }
    for (var sang in _sangriasCaixa.where((s) => s.aberturaCaixaId == _aberturaAtual!.id)) {
      total -= sang.valor;
    }
    for (var venda in _vendasBalcao.where((v) => v.aberturaCaixaId == _aberturaAtual!.id && !v.isCancelada)) {
      if (venda.tipoPagamento.name.toLowerCase().contains('dinheiro')) {
        total += venda.valorTotal;
      }
    }
    return total;
  }
""";

  lines.insert(lastBraceIndex, additions);
  
  // Need to import PerfilTributario if not present
  bool hasImport = lines.any((line) => line.contains("import '../models/perfil_tributario.dart'"));
  if (!hasImport) {
    int importIndex = lines.indexWhere((line) => line.startsWith('import '));
    if (importIndex == -1) importIndex = 0;
    lines.insert(importIndex, "import '../models/perfil_tributario.dart';");
  }

  file.writeAsStringSync(lines.join('\\n'));
  print('Done restoring lost methods.');
}
