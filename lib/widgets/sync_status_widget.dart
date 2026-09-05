import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../services/clock_check_service.dart';

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  void _mostrarDialogoLogs(BuildContext context, DataService service) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 600,
            height: 500,
            decoration: BoxDecoration(
              color: const Color(0xFF13131A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabeçalho
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_sync,
                          color: service.isOffline ? Colors.orange : (service.ultimoErroSync != null ? Colors.red : Colors.green),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Histórico de Sincronia',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                
                // Status Rápido
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusItem(
                        'Conexão',
                        service.isOffline ? 'Offline' : 'Online',
                        service.isOffline ? Colors.orange : Colors.green,
                      ),
                      _buildStatusItem(
                        'Último Sync',
                        service.ultimaSincronizacaoSucesso != null 
                            ? "${service.ultimaSincronizacaoSucesso!.hour.toString().padLeft(2, '0')}:${service.ultimaSincronizacaoSucesso!.minute.toString().padLeft(2, '0')}:${service.ultimaSincronizacaoSucesso!.second.toString().padLeft(2, '0')}"
                            : 'Nenhum',
                        Colors.blue,
                      ),
                      _buildStatusItem(
                        'Modo',
                        service.isModoLeve ? 'Leve' : 'Completo',
                        Colors.purpleAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Logs
                const Text(
                  'LOGS DE EVENTOS RECENTES:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: service.syncLogs.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum log registrado nesta sessão.',
                              style: TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            itemCount: service.syncLogs.length,
                            itemBuilder: (context, idx) {
                              final log = service.syncLogs[service.syncLogs.length - 1 - idx];
                              Color logColor = Colors.white70;
                              if (log.contains('❌') || log.contains('⚠️')) {
                                logColor = Colors.redAccent;
                              } else if (log.contains('✅') || log.contains('✓')) {
                                logColor = Colors.greenAccent;
                              } else if (log.contains('🔌') || log.contains('offline')) {
                                logColor = Colors.orangeAccent;
                              } else if (log.contains('🔄')) {
                                logColor = Colors.cyanAccent;
                              }
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  log,
                                  style: TextStyle(
                                    color: logColor,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Ações do rodapé
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        if (service.syncLogs.isEmpty) return;
                        final logText = service.syncLogs.join('\n');
                        Clipboard.setData(ClipboardData(text: logText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Logs copiados para a área de transferência!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16, color: Colors.blueAccent),
                      label: const Text('Copiar Logs', style: TextStyle(color: Colors.blueAccent)),
                    ),
                    const SizedBox(width: 8),
                    if (service.conflitosCount > 0) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await service.resolverTodosConflitos();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✓ Todos os conflitos foram marcados como resolvidos!'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.gavel, size: 16),
                        label: const Text('Corrigir Conflitos'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        service.forceSync();
                      },
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Forçar Sync'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Diálogo com informações detalhadas sobre o relógio do sistema
  void _mostrarDialogoRelogio(BuildContext context, ClockCheckService clockService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              clockService.relogioCritico ? Icons.warning_amber_rounded : Icons.schedule,
              color: Color(clockService.corAlerta),
              size: 24,
            ),
            const SizedBox(width: 10),
            const Text('Relógio do Sistema', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card de status
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Color(clockService.corAlerta).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(clockService.corAlerta).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(clockService.iconeStatus, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clockService.descricaoDiferenca,
                          style: TextStyle(
                            color: Color(clockService.corAlerta),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (clockService.ultimaVerificacao != null)
                          Text(
                            'Verificado às ${clockService.ultimaVerificacao!.hour.toString().padLeft(2,'0')}:${clockService.ultimaVerificacao!.minute.toString().padLeft(2,'0')}',
                            style: const TextStyle(color: Colors.grey, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Explicação dos riscos
            const Text(
              'Por que isso importa?',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _buildRiscoItem(Icons.sync_problem, 'Conflitos de sincronização', 
              'Dados mais antigos podem sobrescrever dados recentes no banco de dados'),
            _buildRiscoItem(Icons.vpn_key_off, 'Token de sessão inválido', 
              'A sessão do Supabase pode expirar prematuramente'),
            _buildRiscoItem(Icons.receipt_long, 'NF-e/NFC-e rejeitada', 
              'A SEFAZ exige diferença de relógio menor que 5 minutos'),
            _buildRiscoItem(Icons.history, 'Histórico em ordem incorreta', 
              'Operações podem aparecer fora de sequência nos relatórios'),
            
            const SizedBox(height: 16),
            // Instrução de correção no Windows
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🖥️ Como corrigir no Windows:',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1. Clique com direito no relógio da barra de tarefas\n'
                    '2. "Ajustar data/hora"\n'
                    '3. Ative "Definir hora automaticamente"\n'
                    '4. Clique em "Sincronizar agora"',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await clockService.ignorarPor24h();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Ignorar por 24h', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await clockService.verificar(forcar: true);
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reverificar'),
          ),
        ],
      ),
    );
  }

  Widget _buildRiscoItem(IconData icon, String titulo, String descricao) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(descricao, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ClockCheckService é um singleton global — acesso direto, sem depender de Provider
    // para evitar erros em páginas que não registram o serviço no seu contexto.
    final clockService = ClockCheckService();

    return Consumer<DataService>(
      builder: (context, service, _) {
        return ListenableBuilder(
          listenable: clockService,
          builder: (context, _) {
            final isOffline = service.isOffline;
            final temErro = service.ultimoErroSync != null;
            // Ocultado temporariamente a pedido do usuário, para não causar confusão
            final temConflitos = false;
            final relogioErrado = clockService.relogioErrado;
            final relogioCritico = clockService.relogioCritico;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Indicador de Relógio (exibe apenas se errado) ──────────────
                if (relogioErrado)
                  Tooltip(
                    message: '${clockService.descricaoDiferenca}. Clique para detalhes.',
                    child: InkWell(
                      onTap: () => _mostrarDialogoRelogio(context, clockService),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (relogioCritico ? Colors.red : Colors.orange).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (relogioCritico ? Colors.red : Colors.orange).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              relogioCritico ? Icons.warning_amber_rounded : Icons.schedule,
                              color: relogioCritico ? Colors.redAccent : Colors.orange,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              relogioCritico ? 'RELÓGIO CRÍTICO' : 'Relógio errado',
                              style: TextStyle(
                                color: relogioCritico ? Colors.redAccent : Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (relogioErrado) const SizedBox(width: 4),

                // ── Indicador de Sincronização ─────────────────────────────────
                Tooltip(
                  message: isOffline 
                      ? 'Internet desconectada. Modo Offline. Clique para ver logs.' 
                      : (temErro 
                          ? 'Erro na sincronização. Clique para ver logs.' 
                          : (temConflitos 
                              ? 'Existem ${service.conflitosCount} conflitos pendentes de revisão. Clique para ver logs.' 
                              : '${service.getSyncStatusText}. Clique para ver logs.')),
                  child: InkWell(
                    onTap: () => _mostrarDialogoLogs(context, service),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOffline 
                            ? Colors.orange.withValues(alpha: 0.1) 
                            : (temErro 
                                ? Colors.red.withValues(alpha: 0.1) 
                                : (temConflitos 
                                    ? Colors.amber.withValues(alpha: 0.1) 
                                    : Colors.white.withValues(alpha: 0.05))),
                        borderRadius: BorderRadius.circular(20),
                        border: isOffline 
                            ? Border.all(color: Colors.orange.withValues(alpha: 0.3)) 
                            : (temErro 
                                ? Border.all(color: Colors.red.withValues(alpha: 0.3)) 
                                : (temConflitos 
                                    ? Border.all(color: Colors.amber.withValues(alpha: 0.3)) 
                                    : null)),
                      ),
                      child: Row(
                        children: [
                          if (!isOffline && service.syncEmAndamento)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            )
                          else
                            Icon(
                              isOffline 
                                  ? Icons.wifi_off 
                                  : (temErro 
                                      ? Icons.cloud_off 
                                      : (temConflitos ? Icons.cloud_queue : Icons.cloud_done)),
                              color: isOffline 
                                  ? Colors.orange
                                  : (temErro 
                                      ? Colors.red 
                                      : (temConflitos 
                                          ? Colors.amber 
                                          : (service.ultimaSincronizacaoSucesso != null ? Colors.green : Colors.grey))),
                              size: 16,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            isOffline 
                                ? 'MODO OFFLINE' 
                                : (temErro 
                                    ? 'Erro na sincronização' 
                                    : (temConflitos 
                                        ? 'Conflitos (${service.conflitosCount})' 
                                        : service.getSyncStatusText)),
                            style: TextStyle(
                              color: isOffline 
                                  ? Colors.orangeAccent 
                                  : (temErro 
                                      ? Colors.redAccent 
                                      : (temConflitos 
                                          ? Colors.amberAccent 
                                          : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.6) : Colors.black87))),
                              fontSize: 10,
                              fontWeight: isOffline || temErro || temConflitos ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.refresh, 
                    size: 20,
                    color: temErro ? Colors.redAccent : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                  ),
                  tooltip: 'Tentar sincronizar novamente',
                  onPressed: () => service.forceSync(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
