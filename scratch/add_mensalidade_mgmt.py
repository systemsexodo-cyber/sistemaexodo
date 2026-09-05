import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\selecionar_empresa_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar o case switch no PopupMenuButton ---
target_switch = """                        case 'limpar':
                          _confirmarExcluirTodosProdutos(context, Provider.of<DataService>(context, listen: false));
                          break;"""

replacement_switch = """                        case 'limpar':
                          _confirmarExcluirTodosProdutos(context, Provider.of<DataService>(context, listen: false));
                          break;
                        case 'mensalidade':
                          _abrirDialogMensalidade(context, empresa);
                          break;"""

content = content.replace(target_switch, replacement_switch)
print("SWITCH_MENSALIDADE_ADICIONADO")


# --- 2. Adicionar o item visual no PopupMenuButton ---
target_menu_items = """                      const PopupMenuItem(value: 'importar', child: Row(children: [Icon(Icons.file_upload_outlined, color: Colors.green, size: 18), SizedBox(width: 12), Text('Importar Excel')])),
                      const PopupMenuItem(value: 'limpar', child: Row(children: [Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18), SizedBox(width: 12), Text('Limpar Produtos')])),"""

replacement_menu_items = """                      const PopupMenuItem(value: 'importar', child: Row(children: [Icon(Icons.file_upload_outlined, color: Colors.green, size: 18), SizedBox(width: 12), Text('Importar Excel')])),
                      const PopupMenuItem(value: 'mensalidade', child: Row(children: [Icon(Icons.monetization_on_outlined, color: Colors.amber, size: 18), SizedBox(width: 12), Text('Mensalidade / Licença')])),
                      const PopupMenuItem(value: 'limpar', child: Row(children: [Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18), SizedBox(width: 12), Text('Limpar Produtos')])),"""

content = content.replace(target_menu_items, replacement_menu_items)
print("BOTAO_MENU_MENSALIDADE_ADICIONADO")


# --- 3. Injetar o método _abrirDialogMensalidade ---
target_build_end = """  /// Realiza o backup de todas as empresas para o Google Drive"""

replacement_build_end = """  /// Abre a modal de gerenciamento de mensalidade da empresa
  void _abrirDialogMensalidade(BuildContext context, Empresa empresa) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final configs = empresa.configuracoes ?? {};
    
    // Controladores
    final dataInicioCtrl = TextEditingController(text: configs['data_inicio'] ?? configs['dataInicio'] ?? '');
    final dataCobrancaCtrl = TextEditingController(text: configs['data_cobranca'] ?? configs['dataCobranca'] ?? '');
    final linkPagamentoCtrl = TextEditingController(text: configs['link_pagamento'] ?? configs['linkPagamento'] ?? '');
    String statusPagamento = configs['status_pagamento'] ?? configs['statusPagamento'] ?? 'pago';
    bool bloqueadoManual = configs['bloqueado'] == true || configs['bloqueado'] == 'true';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.monetization_on_outlined, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mensalidade - ${empresa.razaoSocial}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Data Inicio
                    TextFormField(
                      controller: dataInicioCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Data de Início (AAAA-MM-DD)',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: 'Ex: 2026-07-01',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                    const SizedBox(height: 16),

                    // Data Cobrança (Vencimento)
                    TextFormField(
                      controller: dataCobrancaCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Data de Cobrança / Vencimento (AAAA-MM-DD)',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: 'Ex: 2026-08-01',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                    const SizedBox(height: 16),

                    // Link Pagamento
                    TextFormField(
                      controller: linkPagamentoCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Link de Faturamento / Pagamento',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: 'https://link.mercadopago.com.br/...',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),

                    // Status Pagamento Dropdown
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF1E1E2E),
                      value: statusPagamento,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Status do Pagamento',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pago', child: Text('Pago / Licenciado')),
                        DropdownMenuItem(value: 'pendente', child: Text('Pendente de Pagamento')),
                        DropdownMenuItem(value: 'inadimplente', child: Text('Bloqueado por Inadimplência')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            statusPagamento = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Checkbox Bloqueado Manualmente
                    CheckboxListTile(
                      title: const Text('Bloqueado Manualmente', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Suspende o acesso do cliente de imediato', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      value: bloqueadoManual,
                      onChanged: (val) {
                        setState(() {
                          bloqueadoManual = val ?? false;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  onPressed: () async {
                    try {
                      // Montar o novo dicionário de configurações da empresa
                      final Map<String, dynamic> novasConfigs = Map<String, dynamic>.from(configs);
                      novasConfigs['data_inicio'] = dataInicioCtrl.text.trim().isEmpty ? null : dataInicioCtrl.text.trim();
                      novasConfigs['data_cobranca'] = dataCobrancaCtrl.text.trim().isEmpty ? null : dataCobrancaCtrl.text.trim();
                      novasConfigs['link_pagamento'] = linkPagamentoCtrl.text.trim().isEmpty ? null : linkPagamentoCtrl.text.trim();
                      novasConfigs['status_pagamento'] = statusPagamento;
                      novasConfigs['bloqueado'] = bloqueadoManual;

                      final empresaAtualizada = empresa.copyWith(
                        configuracoes: novasConfigs,
                      );

                      // Chamar a gravação no Supabase/SQLite
                      await authService.atualizarEmpresa(empresaAtualizada);

                      if (context.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Mensalidade/Licença da empresa atualizada com sucesso!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao atualizar: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Salvar Alterações', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Realiza o backup de todas as empresas para o Google Drive"""

if target_build_end in content:
    content = content.replace(target_build_end, replacement_build_end)
    print("METODO_DIALOG_MENSALIDADE_ADICIONADO")
else:
    print("FALHA_AO_ADICIONAR_METODO_DIALOG")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
