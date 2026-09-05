import os

data_service_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\services\data_service.dart"
caixa_page_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\caixa_page.dart"
venda_direta_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"
home_page_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\home_page.dart"


# --- 1. Atualizar o data_service.dart ---
with open(data_service_path, "r", encoding="utf-8") as f:
    content_data = f.read()

# Inserir o responsavelAtivo e alterar a flag caixaAberto
target_caixa_decl = """  // Controle de caixa
  bool _caixaAberto = false; // Flag rápida para verificações de UI
  bool get caixaAberto => _caixaAberto;"""

replacement_caixa_decl = """  // Controle de caixa
  String? responsavelAtivo;
  bool get caixaAberto => aberturaCaixaAtual != null;"""

if target_caixa_decl in content_data:
    content_data = content_data.replace(target_caixa_decl, replacement_caixa_decl)
    print("DATA_SERVICE_DECLARACAO_ATUALIZADA")
else:
    print("FALHA_AO_ATUALIZAR_DATA_SERVICE_DECLARACAO")

# Atualizar o aberturaCaixaAtual para filtrar por operador responsavelAtivo
target_abertura_getter = """  /// Última abertura de caixa que ainda não possui fechamento
  AberturaCaixa? get aberturaCaixaAtual {
    if (_aberturasCaixa.isEmpty) return null;

    // OTIMIZAÇÃO: Procurar de trás para frente (mais recente primeiro)
    // a primeira abertura que não tenha um fechamento correspondente.
    for (int i = _aberturasCaixa.length - 1; i >= 0; i--) {
      final abertura = _aberturasCaixa[i];
      final temFechamento = _fechamentosCaixa.any(
        (f) => f.aberturaCaixaId == abertura.id,
      );

      if (!temFechamento) {
        return abertura;
      }
    }

    return null;
  }"""

replacement_abertura_getter = """  /// Última abertura de caixa que ainda não possui fechamento
  AberturaCaixa? get aberturaCaixaAtual {
    if (_aberturasCaixa.isEmpty) return null;

    // OTIMIZAÇÃO: Procurar de trás para frente (mais recente primeiro)
    // a primeira abertura que não tenha um fechamento correspondente de acordo com o operador logado.
    for (int i = _aberturasCaixa.length - 1; i >= 0; i--) {
      final abertura = _aberturasCaixa[i];
      
      // Separar por usuário/operador logado
      if (responsavelAtivo != null && responsavelAtivo!.isNotEmpty) {
        // Se a abertura não foi feita por este operador, desconsidera para este contexto de caixa
        if (abertura.responsavel != responsavelAtivo) {
          continue;
        }
      }

      final temFechamento = _fechamentosCaixa.any(
        (f) => f.aberturaCaixaId == abertura.id,
      );

      if (!temFechamento) {
        return abertura;
      }
    }

    return null;
  }"""

if target_abertura_getter in content_data:
    content_data = content_data.replace(target_abertura_getter, replacement_abertura_getter)
    print("DATA_SERVICE_GETTER_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_DATA_SERVICE_GETTER")

with open(data_service_path, "w", encoding="utf-8") as f:
    f.write(content_data)


# --- 2. Injetar a definição do responsavelAtivo nas páginas principais ---

# A) No caixa_page.dart (no início do build do CaixaPage)
with open(caixa_page_path, "r", encoding="utf-8") as f:
    content_caixa = f.read()

target_caixa_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);"""

replacement_caixa_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    dataService.responsavelAtivo = usuarioLogado?.email ?? usuarioLogado?.nome;"""

if target_caixa_build in content_caixa:
    content_caixa = content_caixa.replace(target_caixa_build, replacement_caixa_build)
    print("CAIXA_PAGE_BUILD_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_CAIXA_PAGE_BUILD")

with open(caixa_page_path, "w", encoding="utf-8") as f:
    f.write(content_caixa)


# B) No venda_direta_page.dart (no início do build do _VendaDiretaPageState)
with open(venda_direta_path, "r", encoding="utf-8") as f:
    content_venda = f.read()

target_venda_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);"""

replacement_venda_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    dataService.responsavelAtivo = usuarioLogado?.email ?? usuarioLogado?.nome;"""

if target_venda_build in content_venda:
    content_venda = content_venda.replace(target_venda_build, replacement_venda_build)
    print("VENDA_DIRETA_PAGE_BUILD_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_VENDA_DIRETA_PAGE_BUILD")

with open(venda_direta_path, "w", encoding="utf-8") as f:
    f.write(content_venda)


# C) No home_page.dart (no início do build da HomePage)
with open(home_page_path, "r", encoding="utf-8") as f:
    content_home = f.read()

target_home_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);"""

replacement_home_build = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    dataService.responsavelAtivo = usuarioLogado?.email ?? usuarioLogado?.nome;"""

if target_home_build in content_home:
    content_home = content_home.replace(target_home_build, replacement_home_build)
    print("HOME_PAGE_BUILD_ATUALIZADO")
else:
    # Caso a declaração no HomePage seja um pouco diferente, buscamos variação
    normalized_home = content_home.replace("\r\n", "\n")
    target_home_build_alt = """  @override
  Widget build(BuildContext context) {"""
    replacement_home_build_alt = """  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    dataService.responsavelAtivo = usuarioLogado?.email ?? usuarioLogado?.nome;"""
    if target_home_build_alt in normalized_home:
        normalized_home = normalized_home.replace(target_home_build_alt, replacement_home_build_alt)
        content_home = normalized_home
        print("HOME_PAGE_BUILD_ATUALIZADO_ALT")
    else:
        print("FALHA_AO_ATUALIZAR_HOME_PAGE_BUILD")

with open(home_page_path, "w", encoding="utf-8") as f:
    f.write(content_home)
