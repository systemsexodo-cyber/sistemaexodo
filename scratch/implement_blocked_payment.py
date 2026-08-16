import os

data_service_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\services\data_service.dart"
main_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\main.dart"

# --- 1. Atualizar o data_service.dart ---
with open(data_service_path, "r", encoding="utf-8") as f:
    content_data = f.read()

# Injetar variáveis de liberação temporária e o método correspondente
target_data_decl = """  // Controle de caixa
  String? responsavelAtivo;"""

replacement_data_decl = """  // Controle de caixa
  String? responsavelAtivo;
  
  // Controle de liberação provisória por mensalidade vencida
  bool _liberacaoProvisoriaAtiva = false;
  bool get liberacaoProvisoriaAtiva => _liberacaoProvisoriaAtiva;

  Future<void> carregarLiberacaoProvisoria() async {
    final dataStr = await _storage.carregarLiberacaoTemporaria();
    if (dataStr != null) {
      final date = DateTime.tryParse(dataStr);
      if (date != null && DateTime.now().isBefore(date)) {
        _liberacaoProvisoriaAtiva = true;
      } else {
        _liberacaoProvisoriaAtiva = false;
      }
    } else {
      _liberacaoProvisoriaAtiva = false;
    }
    notifyListeners();
  }

  Future<void> sincronizarEmpresaImediatamente() async {
    await _carregarDadosDoSupabase(modoLeve: false);
  }"""

if target_data_decl in content_data:
    content_data = content_data.replace(target_data_decl, replacement_data_decl)
    print("DATA_SERVICE_LIBERACAO_INJETADA")
else:
    print("FALHA_AO_INJETAR_DATA_SERVICE_LIBERACAO")


# Injetar o carregamento da liberação provisória em _carregarDadosSalvos()
target_carregar_salvos = """  Future<void> _carregarDadosSalvos() async {
    if (_currentEmpresaId == null) {"""

replacement_carregar_salvos = """  Future<void> _carregarDadosSalvos() async {
    await carregarLiberacaoProvisoria();
    if (_currentEmpresaId == null) {"""

if target_carregar_salvos in content_data:
    content_data = content_data.replace(target_carregar_salvos, replacement_carregar_salvos)
    print("CARREGAMENTO_SALVOS_ATUALIZADO")
else:
    print("FALHA_AO_ATUALIZAR_CARREGAMENTO_SALVOS")

with open(data_service_path, "w", encoding="utf-8") as f:
    f.write(content_data)


# --- 2. Atualizar o main.dart para incluir a validação de bloqueio no AuthWrapper ---
with open(main_path, "r", encoding="utf-8") as f:
    content_main = f.read()

# Primeiro importamos a página de bloqueio no topo do main.dart
target_imports = "import 'package:sistema_exodo_novo/pages/home_page.dart';"
replacement_imports = "import 'package:sistema_exodo_novo/pages/home_page.dart';\nimport 'package:sistema_exodo_novo/pages/bloqueio_mensalidade_page.dart';"

if target_imports in content_main:
    content_main = content_main.replace(target_imports, replacement_imports)
    print("IMPORT_BLOQUEIO_INJETADO")
else:
    print("FALHA_AO_INJETAR_IMPORT")


# Agora injetamos a validação de bloqueio antes de retornar a HomePage no build do AuthWrapper
target_home_return = """            // SE ESTÁ TUDO OK, MOSTRA A HOME PAGE
            return HomePage(initialPage: rotaInicial);"""

replacement_home_return = """            // VALIDAR SE A EMPRESA ESTÁ BLOQUEADA POR MENSALIDADE
            if (empresaAtual != null && !dataService.liberacaoProvisoriaAtiva) {
              final configs = empresaAtual.configuracoes;
              bool estaBloqueado = false;
              if (configs != null) {
                // 1. Bloqueio manual direto
                if (configs['bloqueado'] == true || configs['bloqueado'] == 'true') {
                  estaBloqueado = true;
                }
                // 2. Bloqueio por status inadimplente
                else if (configs['status_pagamento'] == 'inadimplente') {
                  estaBloqueado = true;
                }
                // 3. Bloqueio automático por data de cobrança
                else {
                  final dataCobrancaStr = configs['data_cobranca'] ?? configs['dataCobranca'];
                  if (dataCobrancaStr != null) {
                    final dataCobranca = DateTime.tryParse(dataCobrancaStr.toString());
                    if (dataCobranca != null && DateTime.now().isAfter(dataCobranca)) {
                      if (configs['status_pagamento'] != 'pago') {
                        estaBloqueado = true;
                      }
                    }
                  }
                }
              }

              if (estaBloqueado) {
                return BloqueioMensalidadePage(configs: configs ?? {});
              }
            }

            // SE ESTÁ TUDO OK, MOSTRA A HOME PAGE
            return HomePage(initialPage: rotaInicial);"""

if target_home_return in content_main:
    content_main = content_main.replace(target_home_return, replacement_home_return)
    print("BLOQUEIO_MENSALIDADE_INJETADO_NO_ROTEADOR")
else:
    print("FALHA_AO_INJETAR_BLOQUEIO_ROTEADOR")

with open(main_path, "w", encoding="utf-8") as f:
    f.write(content_main)
