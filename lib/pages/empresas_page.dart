import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/excel_import_service.dart';
import '../models/empresa.dart';
import '../theme.dart';
import 'adicionar_empresa_page.dart';
import 'login_page.dart';
import '../services/google_drive_service.dart';
import '../services/bridge_management_service.dart';

/// Página de gerenciamento de empresas
class EmpresasPage extends StatefulWidget {
  const EmpresasPage({super.key});

  @override
  State<EmpresasPage> createState() => _EmpresasPageState();
}

class _EmpresasPageState extends State<EmpresasPage> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    
    // Verificar se o usuário é "user" (único que pode acessar configuração da empresa)
    final podeAcessar = usuarioAtual?.email.toLowerCase() == 'user';
    
    if (!podeAcessar) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Gerenciar Empresas'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Acesso Restrito',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Apenas o usuário "user" pode acessar a configuração de empresas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Empresas'),
          actions: [
            // Botão de importar Excel - SEMPRE VISÍVEL
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: const Icon(Icons.file_upload, color: Colors.green, size: 24),
                ),
                tooltip: 'Importar Produtos do Excel',
                onPressed: () => _importarProdutosExcel(context),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Empresa',
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdicionarEmpresaPage(),
                  ),
                );
                if (resultado == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Empresa adicionada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Voltar para Login',
              onPressed: () async {
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      'Confirmar Saída',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Deseja realmente sair e voltar para a tela de login?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                );

                if (confirmar == true && mounted) {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final dataService = Provider.of<DataService>(context, listen: false);
                  
                  await authService.logout();
                  await dataService.definirEmpresaAtual(null);
                  
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Consumer<AuthService>(
          builder: (context, authService, child) {
            return RefreshIndicator(
              onRefresh: () async {
                await authService.carregarEmpresas();
              },
              child: Builder(
                builder: (context) {
                  // Cards das empresas (apenas empresas permitidas)
                  final empresasPermitidas = authService.getEmpresasDoUsuario();
                  return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Card de importação SEMPRE no topo (sempre visível)
                  _buildCardImportacao(context),
                  // Card do Google Drive (Apenas Admin)
                  _buildCardGoogleDrive(context),
                  // NOVO: Card de Gerenciamento do Emissor NFC-e
                  if (podeAcessar)
                    _buildCardBridgeManagement(context),
                  // Cards das empresas
                      if (empresasPermitidas.isEmpty)
                    _buildEmptyState()
                  else
                        ...empresasPermitidas.map((empresa) => _buildEmpresaCard(context, empresa, authService)),
                ],
                  );
                },
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _importarProdutosExcel(context),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.file_upload, color: Colors.white, size: 28),
          label: const Text(
            'IMPORTAR EXCEL',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  /// Realiza o backup de todas as empresas para o Google Drive
  Future<void> _realizarBackupGoogleDrive(BuildContext context) async {
    final driveService = GoogleDriveService.instance;
    
    // Mostrar diálogo de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Backup Google Drive', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 24),
            Text(
              'Realizando exportação e upload de todas as empresas...\nIsso pode levar alguns minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      final resultado = await driveService.realizarBackupTodasEmpresas();
      
      if (mounted) {
        Navigator.pop(context); // Fechar loading

        if (resultado['sucesso'] == true) {
          final detalhes = resultado['detalhes'];
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Backup Concluído', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Total de empresas: ${detalhes['total']}', style: const TextStyle(color: Colors.white70)),
                   Text('Sucesso: ${detalhes['sucesso']}', style: const TextStyle(color: Colors.white)),
                   if (detalhes['falha'] > 0)
                    Text('Falhas: ${detalhes['falha']}', style: const TextStyle(color: Colors.redAccent)),
                   const SizedBox(height: 16),
                   Text('Pasta no Drive: ${detalhes['pasta']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro no backup: ${resultado['mensagem']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro inesperado: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCardBridgeManagement(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarDialogoGerenciamentoBridge(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.terminal,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🖥️ GERENCIAR EMISSOR (BRIDGE)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Atualizar softwares, reiniciar serviços e identificar computadores de emissão remotamente.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.settings_remote,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildBridgeAction_Divider() {
    return Container(
      height: 1,
      color: Colors.white.withOpacity(0.05),
    );
  }

  void _mostrarDialogoGerenciamentoBridge(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.orange),
            SizedBox(width: 12),
            Text('Comandos do Emissor', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Estes comandos serão enviados para TODOS os computadores que estão rodando o Bridge NFC-e.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildBridgeActionTile(
              context,
              icon: Icons.play_arrow,
              color: Colors.orange,
              title: 'Iniciar Forçado (Watchdog)',
              subtitle: 'Aciona o monitor para abrir o emissor se estiver fechado.',
              onTap: () => _selecionarPCEDispararComando(context, 'start', 'Iniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeAction_Divider(),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.system_update,
              color: Colors.green,
              title: 'Atualizar Software (Git Pull)',
              subtitle: 'Baixa as correções de código mais recentes.',
              onTap: () => _selecionarPCEDispararComando(context, 'update', 'Atualizar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.restart_alt,
              color: Colors.blue,
              title: 'Reiniciar Serviços',
              subtitle: 'Força o reinício do emissor.',
              onTap: () => _selecionarPCEDispararComando(context, 'restart', 'Reiniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.info_outline,
              color: Colors.purple,
              title: 'Identificar Máquinas',
              subtitle: 'Solicita nome do PC e versão do Windows.',
              onTap: () => _selecionarPCEDispararComando(context, 'identify', 'Identificar'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildBridgeActionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  void _selecionarPCEDispararComando(BuildContext context, String comando, String acaoTitulo, {Map<String, dynamic>? extraData}) {
    // Primeiro traz a UI com a lista de computadores
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Selecione o PC para $acaoTitulo', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('bridge_status')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }

              final docs = snapshot.data?.docs ?? [];
              
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Nenhum emissor online encontrado.', style: TextStyle(color: Colors.white54)),
                );
              }

              return ListView(
                children: [
                  // Opção de enviar para todos
                  ListTile(
                    leading: const Icon(Icons.computer, color: Colors.white),
                    title: const Text('TODOS OS COMPUTADORES', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Fecha popup
                      _confirmarComandoBridge(context, comando, 'Deseja $acaoTitulo em TODOS os emissores simultaneamente?', targetPc: null, extraData: extraData);
                    },
                  ),
                  const Divider(color: Colors.white24),
                  // Lista de Pcs Específicos
                  ...docs.where((doc) => !doc.id.startsWith('watchdog_')).map((doc) {
                    // Extração de dados segura e dinâmica para o Flutter Web
                    final dynamic rawData = doc.data();
                    final Map<dynamic, dynamic> data = (rawData is Map) ? rawData : {};
                    final String pcName = (data['pc_name'] ?? doc.id).toString();
                    final bool isOnline = data['online'] == true;
                    
                    // Busca o watchdog de forma manual para evitar crashes de tipo
                    bool watchdogOnline = false;
                    for (var d in docs) {
                      if (d.id == 'watchdog_$pcName') {
                        final dynamic dRaw = d.data();
                        if (dRaw is Map && dRaw['online'] == true) {
                          watchdogOnline = true;
                        }
                        break;
                      }
                    }

                    return ListTile(
                      leading: Icon(
                        Icons.desktop_windows, 
                        color: isOnline ? Colors.green : (watchdogOnline ? Colors.orange : Colors.white12)
                      ),
                      title: Text(pcName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        isOnline ? 'Bridge Online' : (watchdogOnline ? 'Proteção Ativa' : 'Offline total'),
                        style: TextStyle(color: isOnline ? Colors.green : (watchdogOnline ? Colors.orange : Colors.white24), fontSize: 11),
                      ),
                      trailing: Icon(Icons.send, color: (isOnline || watchdogOnline) ? Colors.blue : Colors.white10, size: 16),
                      onTap: () {
                        if (!watchdogOnline && comando == 'start') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ Comando "Iniciar" impossível: A Proteção (Watchdog) não está ativa neste PC. Inicie manualmente uma vez para instalar.'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 4),
                            ),
                          );
                          return;
                        }
                        
                        if (!isOnline && !watchdogOnline) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('⚠️ Este PC está totalmente offline.')),
                          );
                          return;
                        }
                        Navigator.pop(context); // Fecha popup
                        _confirmarComandoBridge(context, comando, 'Deseja $acaoTitulo no PC: $pcName?', targetPc: pcName, extraData: extraData);
                      },
                    );
                  }).toList(),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _confirmarComandoBridge(BuildContext context, String comando, String pergunta, {String? targetPc, Map<String, dynamic>? extraData}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2E2E3E),
        title: const Text('Confirmar Comando', style: TextStyle(color: Colors.white)),
        content: Text(pergunta, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NÃO'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Fecha confirmação
              try {
                debugPrint('>>> [BridgeManager] Enviando comando "$comando" para PC: ${targetPc ?? "Todos"}');
                await BridgeManagementService.instance.enviarComando(comando, targetPc: targetPc, extraData: extraData);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Comando "$comando" enviado com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('>>> [BridgeManager] Erro ao enviar comando: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Erro: $e'), 
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 10),
                      action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('SIM, ENVIAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGoogleDrive(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.withOpacity(0.3), Colors.blue.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _realizarBackupGoogleDrive(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.cloud_upload,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '☁️ BACKUP GOOGLE DRIVE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Exportar todos os dados de TODAS as empresas para o seu Google Drive (2TB).',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhuma empresa cadastrada',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque no botão + para adicionar uma empresa',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardImportacao(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final empresaAtual = authService.empresaAtual;
        final empresasPermitidas = authService.getEmpresasDoUsuario();
        final podeImportar = empresaAtual != null || empresasPermitidas.length == 1;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: podeImportar
                ? LinearGradient(
                    colors: [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: podeImportar ? Colors.green : Colors.orange,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _importarProdutosExcel(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: podeImportar ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        podeImportar ? Icons.file_upload : Icons.warning,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            podeImportar 
                                ? '📊 IMPORTAR PRODUTOS EXCEL'
                                : '⚠️ Selecione uma empresa para importar',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            podeImportar
                                ? empresaAtual != null
                                    ? 'Empresa: ${empresaAtual.nomeExibicao}\nClique para selecionar arquivo Excel'
                                    : 'Clique para importar produtos de um arquivo Excel'
                                : 'Clique no botão "Selecionar" da empresa primeiro',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      podeImportar ? Icons.arrow_forward_ios : Icons.info_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpresaCard(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    final isEmpresaAtual = authService.empresaAtual?.id == empresa.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdicionarEmpresaPage(empresa: empresa),
            ),
          );
          if (resultado == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Empresa atualizada com sucesso!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone da empresa
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isEmpresaAtual
                      ? Colors.green.withOpacity(0.2)
                      : Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: isEmpresaAtual ? Colors.green : Colors.blueAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Informações da empresa
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            empresa.nomeExibicao,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Bridge Status Badge
                        Consumer<DataService>(
                          builder: (context, dataService, _) {
                            final bool isBridgeOnline = dataService.isEmpresaBridgeOnline(empresa.cnpj);
                            if (!isBridgeOnline) return const SizedBox.shrink();
                            
                            return Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, color: Colors.green, size: 6),
                                  SizedBox(width: 4),
                                  Text('ONLINE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          },
                        ),
                        if (isEmpresaAtual)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Atual',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (empresa.razaoSocial != empresa.nomeExibicao) ...[
                      const SizedBox(height: 4),
                      Text(
                        empresa.razaoSocial,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                    if (empresa.cnpj != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'CNPJ: ${empresa.cnpj}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                    if (empresa.cidade != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${empresa.cidade}${empresa.estado != null ? ' - ${empresa.estado}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Botão de selecionar (se não for a atual)
              if (!isEmpresaAtual)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Validar acesso antes de selecionar
                      final empresasPermitidas = authService.getEmpresasDoUsuario();
                      if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Você não tem permissão para acessar esta empresa'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      await authService.selecionarEmpresa(empresa);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Empresa ${empresa.nomeExibicao} selecionada! Agora você pode importar produtos.'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        setState(() {}); // Atualizar UI
                      }
                    },
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Selecionar', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              // Menu de ações
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                onSelected: (value) async {
                  if (value == 'editar') {
                    final resultado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdicionarEmpresaPage(empresa: empresa),
                      ),
                    );
                    if (resultado == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Empresa atualizada com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (value == 'selecionar') {
                    // Validar acesso antes de selecionar
                    final empresasPermitidas = authService.getEmpresasDoUsuario();
                    if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Você não tem permissão para acessar esta empresa'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    await authService.selecionarEmpresa(empresa);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Empresa ${empresa.nomeExibicao} selecionada'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (value == 'importar_produtos') {
                    // Verificar se a empresa está selecionada
                    if (!isEmpresaAtual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione a empresa antes de importar produtos'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    _importarProdutosExcel(context);
                  } else if (value == 'excluir') {
                    _confirmarExclusao(context, empresa, authService);
                  } else if (value == 'vincular_bridge') {
                    _selecionarPCEDispararComando(
                      context, 
                      'set_identity', 
                      'Vincular Computador',
                      extraData: {
                        'cnpj': empresa.cnpj,
                        'nome': empresa.nomeExibicao,
                      }
                    );
                  } else if (value == 'reiniciar_bridge') {
                    _selecionarPCEDispararComando(
                      context, 
                      'restart', 
                      'Reiniciar Emissor',
                    );
                  } else if (value == 'outros_bridge') {
                    _mostrarDialogoGerenciamentoBridge(context);
                  }
                },
                itemBuilder: (context) {
                  final usuarioAtual = authService.usuarioAtual;
                  final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
                  final podeImportarDeletar = isUsuarioMaster || usuarioAtual?.isMaster == true;
                  
                  return [
                    const PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    if (!isEmpresaAtual)
                      const PopupMenuItem(
                        value: 'selecionar',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 20),
                            SizedBox(width: 8),
                            Text('Selecionar'),
                          ],
                        ),
                      ),
                    if (isEmpresaAtual && podeImportarDeletar)
                      const PopupMenuItem(
                        value: 'importar_produtos',
                        child: Row(
                          children: [
                            Icon(Icons.file_upload, size: 20, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Importar Produtos Excel', style: TextStyle(color: Colors.green)),
                          ],
                        ),
                      ),
                    if (podeImportarDeletar)
                      const PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Excluir', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    
                    // Opção de Vínculo do Bridge (Apenas ADMIN "user")
                    if (isUsuarioMaster) ...[
                      const PopupMenuItem(
                        value: 'reiniciar_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.restart_alt, color: Colors.blue, size: 20),
                            SizedBox(width: 12),
                            Text('Reiniciar Emissor', style: TextStyle(color: Colors.blue)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'vincular_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.settings_remote, color: Colors.orange, size: 20),
                            SizedBox(width: 12),
                            Text('Vincular Bridge', style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'outros_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.more_horiz, color: Colors.white70, size: 20),
                            SizedBox(width: 12),
                            Text('Outros Comandos'),
                          ],
                        ),
                      ),
                    ],
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmarExclusao(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir a empresa "${empresa.nomeExibicao}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authService.removerEmpresa(empresa.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Empresa excluída com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  /// Importa produtos de um arquivo Excel
  Future<void> _importarProdutosExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Se não há empresa selecionada, tentar selecionar automaticamente
    if (authService.empresaAtual == null) {
      final empresasPermitidas = authService.getEmpresasDoUsuario();
      // Se houver apenas uma empresa permitida, selecionar automaticamente
      if (empresasPermitidas.length == 1) {
        await authService.selecionarEmpresa(empresasPermitidas.first);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Empresa ${empresasPermitidas.first.nomeExibicao} selecionada automaticamente'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (empresasPermitidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa cadastrada. Adicione uma empresa primeiro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else {
        // Se houver múltiplas empresas, pedir para selecionar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa antes de importar produtos (menu da empresa → Selecionar)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Mostrar diálogo de instruções
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Importar Produtos do Excel',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Formato esperado do Excel:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Coluna A: Código (opcional)\n'
                'Coluna B: Nome (obrigatório)\n'
                'Coluna C: Descrição (opcional)\n'
                'Coluna D: Unidade (padrão: UN)\n'
                'Coluna E: Grupo (padrão: Sem Grupo)\n'
                'Coluna F: Preço (obrigatório)\n'
                'Coluna G: Preço de Custo (opcional)\n'
                'Coluna H: Estoque (padrão: 0)\n'
                'Coluna I: Código de Barras (opcional)',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ A primeira linha será ignorada (cabeçalho).\n'
                  '⚠️ Produtos duplicados serão ignorados.\n'
                  '⚠️ Produtos existentes serão atualizados.',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (continuar != true) return;

    // Selecionar arquivo
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.single.path == null) {
      return; // Usuário cancelou
    }

    final arquivo = File(result.files.single.path!);

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Importando produtos...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Importar produtos
    try {
      final resultado = await ExcelImportService.importarProdutos(
        arquivo,
        dataService,
      );

      if (mounted) {
        Navigator.pop(context); // Fechar loading

        // Mostrar resultado
        final mensagem = resultado['mensagens'] as List<String>;
        final sucesso = resultado['sucesso'] as int;
        final atualizados = resultado['atualizados'] as int;
        final duplicados = resultado['duplicados'] as int;
        final erros = resultado['erros'] as int;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Resultado da Importação',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ Novos: $sucesso\n'
                    '🔄 Atualizados: $atualizados\n'
                    '⚠️ Duplicados ignorados: $duplicados\n'
                    '❌ Erros: $erros',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (mensagem.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Detalhes:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...mensagem.take(10).map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            m,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        )),
                    if (mensagem.length > 10)
                      Text(
                        '... e mais ${mensagem.length - 10} mensagens',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (sucesso > 0 || atualizados > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ ${sucesso + atualizados} produtos processados com sucesso!',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fechar loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

