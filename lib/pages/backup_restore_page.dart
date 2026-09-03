import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../services/backup_restore_service.dart';
import '../theme.dart';

/// Página de Backup e Restauração por empresa
/// Permite:
/// - Fazer backup manual (download .json)
/// - Restaurar backup (upload .json)
/// - Ver histórico de backups
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  BackupRestoreService? _backupService;
  List<Map<String, dynamic>> _historicoBackups = [];
  bool _isLoading = true;
  bool _isRestoring = false;
  bool _isRestoringDump = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataService = Provider.of<DataService>(context, listen: false);
      _backupService = BackupRestoreService(dataService);
      _carregarHistorico();
    });
  }

  Future<void> _carregarHistorico() async {
    if (_backupService == null) return;
    setState(() => _isLoading = true);
    final historico = await _backupService!.listarHistoricoBackups();
    if (mounted) {
      setState(() {
        _historicoBackups = historico;
        _isLoading = false;
      });
    }
  }

  Future<void> _fazerBackup() async {
    if (_backupService == null) return;
    
    final result = await _backupService!.salvarBackupEmArquivo();
    if (!mounted) return;

    if (result != null) {
      _mostrarSnackBar('✅ Backup concluído! Arquivo: ${result.split('/').last}', Colors.green);
      _carregarHistorico();
    } else {
      _mostrarSnackBar('❌ Erro ao fazer backup', Colors.red);
    }
  }

  Future<void> _restaurarBackup() async {
    if (_backupService == null) return;

    // Confirmar
    final confirmado = await _mostrarDialogConfirmacao(
      '⚠️ Restaurar Backup',
      'Isso SUBSTITUIRÁ todos os dados atuais da empresa pelos dados do backup.\n\n'
      'Recomenda-se fazer um backup ANTES de restaurar.\n\n'
      'Deseja continuar?',
    );
    if (!confirmado || !mounted) return;

    // Selecionar arquivo
    final backup = await _backupService!.selecionarArquivoBackup();
    if (backup == null) return;

    // Validar
    final erro = _backupService!.validarBackup(backup);
    if (erro != null) {
      _mostrarSnackBar('❌ $erro', Colors.red);
      return;
    }

    // Restaurar
    setState(() => _isRestoring = true);
    _mostrarSnackBar('🔄 Restaurando dados...', Colors.orange);

    final sucesso = await _backupService!.restaurarBackup(backup);
    if (!mounted) return;

    setState(() => _isRestoring = false);

    if (sucesso) {
      _mostrarSnackBar(
        '✅ Dados restaurados com sucesso! ${_contarItens(backup)} itens importados.',
        Colors.green,
      );
    } else {
      _mostrarSnackBar('❌ Erro ao restaurar backup', Colors.red);
    }
  }

  Future<void> _restaurarDumpPostgres() async {
    if (_backupService == null) return;

    // Confirmar
    final confirmado = await _mostrarDialogConfirmacao(
      '⚠️ Restaurar Dump PostgreSQL',
      'Isso irá executar pg_restore/psql para restaurar o banco de dados PostgreSQL.\n\n'
      '⚠️ ATENÇÃO: Isso SUBSTITUIRÁ todos os dados do banco local!\n\n'
      'Recomenda-se fazer um backup ANTES de restaurar.\n\n'
      'Deseja continuar?',
    );
    if (!confirmado || !mounted) return;

    // Selecionar arquivo
    final dumpFile = await _backupService!.selecionarArquivoDump();
    if (dumpFile == null) return;

    // Restaurar
    setState(() => _isRestoringDump = true);
    _mostrarSnackBar('🔄 Restaurando dump PostgreSQL... Isso pode demorar.', Colors.orange);

    final (sucesso, mensagem) = await _backupService!.restaurarDumpPostgres(dumpFile);
    if (!mounted) return;

    setState(() => _isRestoringDump = false);

    if (sucesso) {
      _mostrarSnackBar('✅ $mensagem', Colors.green);
      // Recarregar dados do banco local
      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.recarregarDados();
      _mostrarSnackBar('✅ Dados recarregados do banco!', Colors.green);
    } else {
      _mostrarSnackBar('❌ $mensagem', Colors.red);
    }
  }

  String _contarItens(Map<String, dynamic> backup) {
    final colecoes = backup['colecoes'] as Map<String, dynamic>? ?? {};
    int total = 0;
    for (final entry in colecoes.entries) {
      if (entry.value is List) {
        total += (entry.value as List).length;
      }
    }
    return total.toString();
  }

  Future<bool> _mostrarDialogConfirmacao(String titulo, String mensagem) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _mostrarSnackBar(String msg, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: cor,
      duration: const Duration(seconds: 3),
    ));
  }

  String _formatarData(String? dataIso) {
    if (dataIso == null) return '';
    final dt = DateTime.tryParse(dataIso);
    if (dt == null) return dataIso;
    return DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
  }

  String _formatarTamanho(int? tamanho) {
    if (tamanho == null) return '';
    if (tamanho < 1024) return '$tamanho B';
    if (tamanho < 1024 * 1024) return '${(tamanho / 1024).toStringAsFixed(1)} KB';
    return '${(tamanho / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Backup e Restauração'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _carregarHistorico,
              tooltip: 'Atualizar',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _carregarHistorico,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // === CARD PRINCIPAL: AÇÕES ===
                    _buildCardAcoes(),
                    const SizedBox(height: 16),

                    // === INFO BACKUP ===
                    _buildCardInfo(),
                    const SizedBox(height: 16),

                    // === HISTÓRICO ===
                    _buildCardHistorico(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildCardAcoes() {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.security, color: Colors.blue, size: 28),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Segurança dos Dados',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Faça backup dos dados da sua empresa e restaure quando necessário.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: _buildBotaoAcao(
                    icon: Icons.download,
                    label: 'Fazer Backup',
                    desc: 'Exportar dados',
                    cor: Colors.green,
                    onTap: (_isRestoring || _isRestoringDump) ? null : _fazerBackup,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBotaoAcao(
                    icon: Icons.upload,
                    label: 'Restaurar',
                    desc: 'Importar backup',
                    cor: Colors.orange,
                    onTap: (_isRestoring || _isRestoringDump) ? null : _restaurarBackup,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Botão Restaurar Dump PostgreSQL
            SizedBox(
              width: double.infinity,
              child: _buildBotaoAcao(
                icon: Icons.storage,
                label: 'Restaurar Dump PostgreSQL',
                desc: 'Importar backup .dump ou .sql do banco de dados',
                cor: Colors.blue,
                onTap: (_isRestoring || _isRestoringDump) ? null : _restaurarDumpPostgres,
              ),
            ),

            if (_isRestoring || _isRestoringDump) ...[
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: _isRestoringDump ? Colors.blue : Colors.orange),
                    const SizedBox(height: 8),
                    Text(
                      _isRestoringDump ? 'Restaurando dump PostgreSQL... Isso pode demorar.' : 'Restaurando dados...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoAcao({
    required IconData icon,
    required String label,
    required String desc,
    required Color cor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: cor, size: 36),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(desc, style: TextStyle(color: cor.withOpacity(0.7), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardInfo() {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Informações',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoLinha(Icons.storage, 'O backup contém todos os dados da empresa'),
            _buildInfoLinha(Icons.warning_amber, 'Restaurar SUBSTITUI todos os dados atuais'),
            _buildInfoLinha(Icons.schedule, 'Faça backups regularmente para segurança'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoLinha(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHistorico() {
    return Card(
      color: const Color(0xFF1E1E2E).withOpacity(0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.history, color: Colors.purple, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Histórico (${_historicoBackups.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_isLoading)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 16),
            if (_historicoBackups.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.backup_outlined, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Nenhum backup registrado ainda',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Clique em "Fazer Backup" para criar o primeiro',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._historicoBackups.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final nome = item['arquivo'] as String? ?? '';
                final data = _formatarData(item['data'] as String?);
                final tamanho = _formatarTamanho(item['tamanho'] as int?);
                final isSemanal = nome.contains('SEMANAL');
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSemanal ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isSemanal ? Icons.star : Icons.backup,
                          color: isSemanal ? Colors.green : Colors.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isSemanal ? 'Backup Semanal' : index == 0 ? 'Último Backup' : 'Backup #${_historicoBackups.length - index}',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(tamanho, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle, color: Colors.green.withOpacity(0.5), size: 18),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
