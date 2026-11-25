import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/servico_realizado.dart';
import '../services/data_service.dart';
import '../services/nfse_service.dart';
import '../theme.dart';

/// Tela de emissão de Nota Fiscal de Serviço Eletrônica (NFS-e).
///
/// Abre a partir de um [ServicoRealizado] já recebido (quitado).
/// Prepara os dados da nota, calcula o ISS e envia para a API da NFS-e Nacional (ADN).
class EmitirNfsePage extends StatefulWidget {
  final ServicoRealizado servico;

  const EmitirNfsePage({super.key, required this.servico});

  @override
  State<EmitirNfsePage> createState() => _EmitirNfsePageState();
}

class _EmitirNfsePageState extends State<EmitirNfsePage> {
  final _formKey = GlobalKey<FormState>();

  /// Código do serviço na Lista Nacional de Serviços (NBS).
  /// Ex: "12.01" (desenvolvimento de programas), "17.02", etc.
  final _codigoServicoController = TextEditingController();

  final _descricaoServicoController = TextEditingController();
  final _aliquotaIssController = TextEditingController(text: '5,00');

  bool _enviando = false;
  String? _erro;
  NfseEmitResult? _resultado;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _descricaoServicoController.text = widget.servico.observacoes ??
        widget.servico.servicos.map((s) => s.descricao).join('; ');
  }

  @override
  void dispose() {
    _codigoServicoController.dispose();
    _descricaoServicoController.dispose();
    _aliquotaIssController.dispose();
    super.dispose();
  }

  double _lerAliquota() {
    final texto = _aliquotaIssController.text.replaceAll(',', '.');
    return double.tryParse(texto) ?? 5.0;
  }

  Future<void> _emitir() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _erro = null;
      _resultado = null;
    });

    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = dataService.empresaAtual;

      if (empresa == null) {
        setState(() {
          _enviando = false;
          _erro = 'Empresa não carregada.';
        });
        return;
      }

      final nfseService = NfseService(dataService: dataService, empresa: empresa);

      final nfse = nfseService.montarNfse(
        widget.servico,
        codigoServico: _codigoServicoController.text.trim(),
        descricaoServico: _descricaoServicoController.text.trim(),
        aliquotaIss: _lerAliquota(),
      );

      await nfseService.salvarRascunho(nfse);

      final resultado = await nfseService.emitir(nfse);

      setState(() {
        _enviando = false;
        _resultado = resultado;
        if (!resultado.sucesso) {
          _erro = resultado.mensagem;
        }
      });

      if (resultado.sucesso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'NFS-e ${resultado.numeroNfse ?? ''} emitida com sucesso',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _enviando = false;
        _erro = 'Erro inesperado: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final valorTotal = widget.servico.totalGeral;
    final issEstimado = valorTotal * (_lerAliquota() / 100);
    final totalComIss = valorTotal + issEstimado;

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emitir NFS-e'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            if (_resultado != null && _resultado!.sucesso)
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => Navigator.pop(context, _resultado),
                tooltip: 'Concluir',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Serviço ${widget.servico.numero}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.servico.clienteNome ?? 'Cliente'} • ${_moeda.format(valorTotal)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Código do serviço (NBS)
              TextFormField(
                controller: _codigoServicoController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Código do serviço (NBS)',
                  hintText: 'Ex: 12.01',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.category, color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Informe o código do serviço' : null,
              ),
              const SizedBox(height: 12),

              // Descrição
              TextFormField(
                controller: _descricaoServicoController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Descrição do serviço',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.description, color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Informe a descrição' : null,
              ),
              const SizedBox(height: 12),

              // Alíquota ISS
              TextFormField(
                controller: _aliquotaIssController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Alíquota ISS (%)',
                  hintText: 'Ex: 5,00',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.percent, color: Colors.white70),
                  suffixText: '%',
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Informe a alíquota';
                  if (double.tryParse(v.replaceAll(',', '.')) == null) {
                    return 'Alíquota inválida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Resumo dos valores
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    _linhaResumo('Valor dos serviços', _moeda.format(valorTotal)),
                    _linhaResumo(
                      'ISS (${_lerAliquota().toStringAsFixed(2)}%)',
                      _moeda.format(issEstimado),
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    _linhaResumo(
                      'Total da NFS-e',
                      _moeda.format(totalComIss),
                      negrito: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Aviso de credenciais
              if (_temCredenciais())
                _aviso(
                  'A nota será enviada para a NFS-e Nacional (ambiente '
                  '${_ambienteTexto()}).',
                  tipo: 'info',
                )
              else
                _aviso(
                  'Token de acesso da NFS-e Nacional não configurado na empresa. '
                  'A emissão será bloqueada até cadastrar o token em Cadastro de Empresa.',
                  tipo: 'alerta',
                ),

              const SizedBox(height: 20),

              if (_erro != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    _erro!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),

              if (_resultado != null && _resultado!.sucesso) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'NFS-e autorizada!',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_resultado!.numeroNfse != null)
                        Text(
                          'Número: ${_resultado!.numeroNfse}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      if (_resultado!.chaveAcesso != null)
                        Text(
                          'Chave: ${_resultado!.chaveAcesso}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _enviando ? null : _emitir,
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send, size: 20),
                  label: Text(
                    _enviando ? 'Enviando...' : 'Emitir NFS-e',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linhaResumo(String label, String valor, {bool negrito = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: negrito ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  bool _temCredenciais() {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = dataService.empresaAtual;
      return empresa?.focusNFeToken != null && empresa!.focusNFeToken!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _ambienteTexto() {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = dataService.empresaAtual;
      return (empresa?.ambienteHomologacao ?? true) ? 'Homologação' : 'Produção';
    } catch (_) {
      return 'Homologação';
    }
  }

  Widget _aviso(String texto, {required String tipo}) {
    final cor = tipo == 'alerta' ? Colors.orange : Colors.blue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tipo == 'alerta' ? Icons.warning : Icons.info, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: cor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
