import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/bridge_manager_service.dart';

/// Widget para mostrar o status do bridge NFC-e
class BridgeStatusWidget extends StatefulWidget {
  final VoidCallback? onStatusChanged;

  const BridgeStatusWidget({super.key, this.onStatusChanged});

  @override
  State<BridgeStatusWidget> createState() => _BridgeStatusWidgetState();
}

class _BridgeStatusWidgetState extends State<BridgeStatusWidget> {
  BridgeStatus? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkBridgeStatus();
  }

  Future<void> _checkBridgeStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final status = await BridgeManagerService.getBridgeStatus();
      setState(() {
        _status = status;
        _isLoading = false;
      });
      widget.onStatusChanged?.call();
    } catch (e) {
      setState(() {
        _status = BridgeStatus(isInstalled: false, isRunning: false);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Verificando emissor NFC-e...'),
            ],
          ),
        ),
      );
    }

    if (_status == null || !_status!.isInstalled) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text(
                    'Emissor NFC-e Não Instalado',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'O emissor NFC-e local não foi encontrado no computador.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text(
                  '📋 Como instalar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade100,
                    child: Text(
                      BridgeManagerService.getInstallationInstructions(),
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _checkBridgeStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Verificar Novamente'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _showInstructionsDialog(),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Ajuda'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (!_status!.isRunning) {
      return Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Text(
                    'Emissor NFC-e Parado',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'O emissor NFC-e está instalado mas não está rodando.\n'
                'Caminho: ${_status!.executablePath ?? "Desconhecido"}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _startBridge,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar Emissor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _checkBridgeStatus,
                child: const Text('Verificar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    // Bridge está rodando
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Emissor NFC-e Online',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    'URL: ${_status!.url ?? "Desconhecida"}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _checkBridgeStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startBridge() async {
    final started = await BridgeManagerService.startBridge();
    if (started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Emissor NFC-e iniciado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Falha ao iniciar o emissor NFC-e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    await _checkBridgeStatus();
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📋 Instalação do Emissor NFC-e'),
        content: SingleChildScrollView(
          child: Text(
            BridgeManagerService.getInstallationInstructions(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
