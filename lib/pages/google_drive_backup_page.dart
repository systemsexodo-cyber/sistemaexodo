import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import '../services/google_drive_service.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/supabase_service.dart';
import 'package:provider/provider.dart';
import '../theme.dart';

class GoogleDriveBackupPage extends StatefulWidget {
  const GoogleDriveBackupPage({super.key});

  @override
  State<GoogleDriveBackupPage> createState() => _GoogleDriveBackupPageState();
}

class _GoogleDriveBackupPageState extends State<GoogleDriveBackupPage> {
  List<drive.File> _backups = [];
  bool _isLoading = false;
  String? _selectedEmpresaSlug;

  @override
  void initState() {
    super.initState();
    _carregarBackups();
  }

  Future<void> _carregarBackups() async {
    setState(() => _isLoading = true);
    try {
      final backups = await GoogleDriveService.instance.listarBackupsDisponiveis(
        empresaSlug: _selectedEmpresaSlug,
      );
      setState(() => _backups = backups);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar backups: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _realizarBackup() async {
    setState(() => _isLoading = true);
    try {
      final resultado = await GoogleDriveService.instance.realizarBackupTodasEmpresas();
      if (mounted) {
        if (resultado['sucesso'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Backup concluído com sucesso!'), backgroundColor: Colors.green),
          );
          _carregarBackups();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Erro no backup: ${resultado['mensagem']}'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sincronizarComSupabase() async {
    if (!SupabaseService.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Supabase não está disponível'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.publicarSincronizacaoTotal();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('☁️ Dados sincronizados com sucesso no Supabase!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao sincronizar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmarRestauracao(drive.File item) async {
    final isFolder = item.mimeType == 'application/vnd.google-apps.folder';
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          isFolder ? 'Restaurar TODAS as Empresas' : 'Confirmar Restauração',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          isFolder 
            ? 'Deseja restaurar os dados de TODAS as empresas contidas na pasta "${item.name}"?\n\n'
              '⚠️ Isso substituirá os dados de todas as empresas envolvidas no Firebase.'
            : 'Deseja realmente restaurar os dados do backup "${item.name}"?\n\n'
              '⚠️ Isso irá substituir os dados atuais desta empresa no Firebase.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: isFolder ? Colors.orange : Colors.red),
            child: Text(isFolder ? 'RESTAURAR TUDO' : 'RESTAURAR AGORA'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      if (isFolder) {
        _executarRestauracaoTotal(item);
      } else {
        _executarRestauracaoIndividual(item.id!);
      }
    }
  }

  Future<void> _executarRestauracaoIndividual(String fileId) async {
    setState(() => _isLoading = true);
    try {
      final resultado = await GoogleDriveService.instance.restaurarBackup(fileId);
      if (mounted) {
        if (resultado['sucesso'] == true) {
          _mostrarSucesso('Restauração Concluída', 
            'Dados restaurados para: ${resultado['detalhes']['empresa']}\n'
            'Itens: ${resultado['detalhes']['total_itens']}');
        } else {
          _mostrarErro(resultado['mensagem']);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executarRestauracaoTotal(drive.File folder) async {
    setState(() => _isLoading = true);
    try {
      final resultado = await GoogleDriveService.instance.restaurarTodosBackupsDePasta(folder.id!);
      if (mounted) {
        if (resultado['sucesso'] == true) {
          final det = resultado['detalhes'];
          _mostrarSucesso('Restauração Total Concluída', 
            'Empresas Restauradas: ${det['sucesso']}\n'
            'Falhas: ${det['falha']}\n'
            'Lista: ${det['empresas'].join(", ")}');
        } else {
          _mostrarErro(resultado['mensagem']);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarSucesso(String titulo, String mensagem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('✅ $titulo', style: const TextStyle(color: Colors.white)),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Erro: $mensagem'), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final empresas = authService.getEmpresasDoUsuario();

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Backup & Sincronização'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregarBackups,
              tooltip: 'Atualizar Lista',
            ),
          ],
        ),
        body: Column(
          children: [
            // Cabeçalho de Ações
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black12,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _realizarBackup,
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('BACKUP GOOGLE DRIVE'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _sincronizarComSupabase,
                          icon: const Icon(Icons.sync),
                          label: const Text('ENVIAR DADOS PARA SUPABASE'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Filtro por Empresa
                  DropdownButtonFormField<String?>(
                    value: _selectedEmpresaSlug,
                    dropdownColor: const Color(0xFF1E1E2E),
                    decoration: const InputDecoration(
                      labelText: 'Filtrar backups no Drive',
                      prefixIcon: Icon(Icons.search),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Ver todos (Arquivos e Pastas)')),
                      ...empresas.map((e) => DropdownMenuItem(
                            value: e.slug,
                            child: Text('Backup de: ${e.nomeExibicao}'),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedEmpresaSlug = val);
                      _carregarBackups();
                    },
                  ),
                ],
              ),
            ),

            // Lista de Backups
            Expanded(
              child: !GoogleDriveService.instance.isLoggedIn 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        const Text(
                          'Conecte-se ao Google Drive para ver os backups.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final ok = await GoogleDriveService.instance.login();
                            if (ok) _carregarBackups();
                          },
                          icon: const Icon(Icons.login),
                          label: const Text('CONECTAR CONTA GOOGLE'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : _isLoading && _backups.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _backups.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum backup encontrado no Google Drive.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _backups.length,
                          itemBuilder: (context, index) {
                            final item = _backups[index];
                            final isFolder = item.mimeType == 'application/vnd.google-apps.folder';
                            final data = item.createdTime ?? DateTime.now();
                            final format = DateFormat('dd/MM/yyyy HH:mm');
                            
                            return Card(
                              color: isFolder ? Colors.blueGrey.withOpacity(0.2) : const Color(0xFF2E2E3E),
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: isFolder 
                                  ? BorderSide(color: Colors.blue.withOpacity(0.5)) 
                                  : BorderSide.none,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isFolder ? Icons.folder_zip : Icons.insert_drive_file, 
                                  color: isFolder ? Colors.blue : Colors.orange,
                                  size: 32,
                                ),
                                title: Text(
                                  item.name ?? 'Sem nome',
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontWeight: isFolder ? FontWeight.bold : FontWeight.normal,
                                    fontSize: isFolder ? 16 : 14,
                                  ),
                                ),
                                subtitle: Text(
                                  'Criado em: ${format.format(data)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : () => _confirmarRestauracao(item),
                                  icon: Icon(isFolder ? Icons.all_inclusive : Icons.restore, size: 18),
                                  label: Text(isFolder ? 'RESTAURAR TODAS' : 'RESTAURAR'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isFolder ? Colors.blue.withOpacity(0.7) : Colors.green.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
