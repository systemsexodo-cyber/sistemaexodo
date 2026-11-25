import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/whatsapp_service.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'bot_teste_page.dart';

class WhatsAppGerenciamentoPage extends StatefulWidget {
  const WhatsAppGerenciamentoPage({super.key});

  @override
  State<WhatsAppGerenciamentoPage> createState() => _WhatsAppGerenciamentoPageState();
}

class _WhatsAppGerenciamentoPageState extends State<WhatsAppGerenciamentoPage> {
  bool _isLoading = false;
  bool _verificando = false;
  String? _connectionState;
  String? _qrCodeBase64;
  String? _erroStatus;
  Timer? _refreshTimer;
  
  // Controllers para edição rápida se necessário
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _instanceController = TextEditingController();
  final _resumoNumeroController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _iniciarMonitoramento();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _urlController.dispose();
    _apiKeyController.dispose();
    _instanceController.dispose();
    _resumoNumeroController.dispose();
    super.dispose();
  }

  void _carregarConfiguracoes() {
    final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
    if (empresa != null) {
      _urlController.text = empresa.whatsappApiUrl ?? '';
      _apiKeyController.text = empresa.whatsappApiKey ?? '';
      _instanceController.text = empresa.whatsappInstanceName ?? '';
      _resumoNumeroController.text = empresa.whatsappNumeroResumo ?? '';
    }
  }

  void _iniciarMonitoramento() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && !_isLoading) {
        _verificarStatus();
      }
    });
    // Primeira verificação imediata
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarStatus());
  }

  Future<void> _verificarStatus() async {
    if (_verificando) return;

    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return;

    final url = empresa.whatsappApiUrl?.trim() ?? '';
    final apiKey = empresa.whatsappApiKey?.trim() ?? '';
    final instancia = empresa.whatsappInstanceName?.trim() ?? '';
    final isTwilio =
        empresa.whatsappTipo == 'twilio' || instancia == 'twilio-bridge';

    if (url.isEmpty || apiKey.isEmpty || (!isTwilio && instancia.isEmpty)) {
      if (mounted) {
        setState(() {
          _connectionState = null;
          _qrCodeBase64 = null;
          _erroStatus =
              'Preencha a URL, a API Key e o nome da instância para conectar.';
        });
      }
      return;
    }

    _verificando = true;
    try {
      final service = WhatsAppService.fromEmpresa(empresa);
      var state = await service.verificarConexao();
      String? erro;

      // Sem estado significa que a instância ainda não existe no servidor.
      // Cria (a chamada é idempotente) e tenta de novo antes de pedir o QR.
      if (!isTwilio && state == null) {
        final criada = await service.criarInstancia();
        if (criada) {
          await Future.delayed(const Duration(seconds: 2));
          state = await service.verificarConexao();
        } else {
          erro =
              'Não foi possível criar a instância. Confira a URL e a API Key.';
        }
      }

      if (!mounted) return;
      setState(() {
        _connectionState = state;
        _erroStatus = erro;
        if (state == 'open') _qrCodeBase64 = null;
      });

      if (!isTwilio && state != 'open') {
        await _carregarQRCode(service);
      }
    } catch (e) {
      debugPrint('Erro ao verificar status WhatsApp: $e');
      if (mounted) {
        setState(() => _erroStatus = 'Falha ao falar com a API: $e');
      }
    } finally {
      _verificando = false;
    }
  }

  Future<void> _carregarQRCode(WhatsAppService service) async {
    if (_connectionState == 'open') return;

    var qr = await service.obterQRCode();
    // Instância recém-criada pode levar alguns segundos para expor o QR Code.
    for (var tentativa = 0; qr == null && tentativa < 2; tentativa++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _connectionState == 'open') return;
      qr = await service.obterQRCode();
    }

    if (mounted && qr != null) {
      setState(() => _qrCodeBase64 = qr);
    }
  }

  Future<void> _salvarConfiguracoes() async {
    setState(() => _isLoading = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = dataService.empresaAtual;
      
      if (empresa != null) {
        final novaEmpresa = empresa.copyWith(
          whatsappApiUrl: _urlController.text.trim(),
          whatsappApiKey: _apiKeyController.text.trim(),
          whatsappInstanceName: _instanceController.text.trim(),
          // Destino único do resumo do dia (o resumo nunca vai para outro número).
          configuracoes: {
            'whatsapp_numero_resumo': _resumoNumeroController.text.trim(),
          },
          updatedAt: DateTime.now(),
        );
        
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.atualizarEmpresa(novaEmpresa);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configurações salvas com sucesso!'), backgroundColor: Colors.green),
          );
          // URL/instância podem ter mudado: descarta o estado anterior.
          setState(() {
            _connectionState = null;
            _qrCodeBase64 = null;
            _erroStatus = null;
          });
          _verificarStatus();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Envia uma mensagem de teste para um número, confirmando que o envio
  /// (e não só o status da conexão) está funcionando.
  Future<void> _enviarMensagemTeste() async {
    final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
    if (empresa == null) return;

    var numeroDigitado = '';
    final numero = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Enviar mensagem de teste',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.phone,
          onChanged: (valor) => numeroDigitado = valor,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'WhatsApp com DDD',
            hintText: 'Ex.: 11 99999-9999',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, numeroDigitado.trim()),
            child: const Text('ENVIAR'),
          ),
        ],
      ),
    );

    if (numero == null || numero.isEmpty || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final service = WhatsAppService.fromEmpresa(empresa);
      final ok = await service.enviarMensagemTeste(numero);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Mensagem de teste enviada!'
                : 'Falha ao enviar. Confira a conexão e o número.',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar mensagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enviarResumoDiario() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      final enviado = await dataService.enviarResumoDiarioWhatsApp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enviado
                  ? 'Resumo diário enviado!'
                  : 'Defina o número do resumo e salve antes de enviar.',
            ),
            backgroundColor: enviado ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar resumo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _desconectar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Desconexão'),
        content: const Text('Deseja realmente desconectar o WhatsApp deste sistema?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('DESCONECTAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isLoading = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final service = WhatsAppService.fromEmpresa(dataService.empresaAtual!);
      await service.desconectar();
      await _verificarStatus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciamento WhatsApp'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.smart_toy_outlined),
              tooltip: 'Conversar com o bot / pausar',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BotTestePage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _verificarStatus,
              tooltip: 'Atualizar Status',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 24),
              _buildConfigCard(),
              const SizedBox(height: 24),
              _buildHelpCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final isTwilio = dataService.empresaAtual?.whatsappTipo == 'twilio';
    final isConnected = _connectionState == 'open';
    final color = isConnected ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected ? Icons.check_circle : (isTwilio ? Icons.cloud_off : Icons.warning_amber_rounded),
                  color: color,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? 'SISTEMA ONLINE' : (isTwilio ? 'PONTE OFFLINE' : 'AGUARDANDO CONEXÃO'),
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      isConnected 
                        ? 'O serviço de mensageria está operando normalmente.' 
                        : (isTwilio 
                            ? 'O servidor da ponte no Render não responde. Verifique a URL.' 
                            : 'Escaneie o QR Code abaixo para ativar o serviço.'),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    if (!isConnected && _erroStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _erroStatus!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!isConnected && !isTwilio && _qrCodeBase64 != null) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _qrCodeBase64!.startsWith('data:image') 
                    ? Image.memory(
                        base64Decode(_qrCodeBase64!.split(',').last),
                        width: 250,
                        height: 250,
                      )
                    : const SizedBox(
                        width: 250,
                        height: 250,
                        child: Center(child: Text('QR Code inválido')),
                      ),
                  const SizedBox(height: 12),
                  const Text(
                    'Abra o WhatsApp > Aparelhos Conectados\nE escaneie este código',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
          if (isTwilio && !isConnected) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'A Ponte Twilio não utiliza QR Code. Se o status for offline, verifique se o servidor no Render está ativo e se a API Key está correta.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (isConnected) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _enviarMensagemTeste,
              icon: const Icon(Icons.send, color: Color(0xFF25D366)),
              label: const Text(
                'ENVIAR MENSAGEM DE TESTE',
                style: TextStyle(color: Color(0xFF25D366)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF25D366)),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _enviarResumoDiario,
              icon: const Icon(Icons.bar_chart, color: Color(0xFF25D366)),
              label: const Text(
                'ENVIAR RESUMO DO DIA',
                style: TextStyle(color: Color(0xFF25D366)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF25D366)),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              ),
            ),
          ],
          if (isConnected && !isTwilio) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _desconectar,
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text('DESCONECTAR APARELHO', style: TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigCard() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final isTwilio = dataService.empresaAtual?.whatsappTipo == 'twilio';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONFIGURAÇÕES TÉCNICAS',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
              _buildTipoChip(isTwilio),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _urlController,
            label: isTwilio ? 'URL da Ponte (Render)' : 'URL da API (Evolution API)',
            icon: Icons.link,
            hint: isTwilio ? 'https://sua-ponte.onrender.com' : 'https://sua-api.railway.app',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _apiKeyController,
            label: 'API Key / Secret Token',
            icon: Icons.vpn_key,
            isPassword: true,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _instanceController,
            label: isTwilio ? 'Apelido do Serviço' : 'Nome da Instância',
            icon: Icons.label_outline,
            hint: isTwilio ? 'twilio-bridge' : 'exodo_vendas',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _resumoNumeroController,
            label: 'Número que recebe o resumo do dia',
            icon: Icons.bar_chart,
            hint: 'Ex.: 11 99999-9999 (com DDD)',
          ),
          const SizedBox(height: 8),
          const Text(
            'O resumo do dia só é enviado para este número. Sem ele, nada é enviado.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _salvarConfiguracoes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('SALVAR CONFIGURAÇÕES', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _alternarTipo,
                tooltip: 'Mudar Tipo de Serviço',
                icon: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipoChip(bool isTwilio) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isTwilio ? Colors.purple.withOpacity(0.2) : Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isTwilio ? Colors.purple : Colors.green, width: 1),
      ),
      child: Text(
        isTwilio ? 'TWILIO' : 'EVOLUTION',
        style: TextStyle(
          color: isTwilio ? Colors.purple : Colors.green,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _alternarTipo() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return;

    final novoTipo = empresa.whatsappTipo == 'twilio' ? 'evolution' : 'twilio';
    
    setState(() => _isLoading = true);
    try {
      final novaEmpresa = empresa.copyWith(
        whatsappTipo: novoTipo,
        updatedAt: DateTime.now(),
      );
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.atualizarEmpresa(novaEmpresa);
      _verificarStatus();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 20),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent)),
      ),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blueAccent),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'A integração Evolution API permite enviar mensagens ilimitadas utilizando seu próprio número de WhatsApp.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
