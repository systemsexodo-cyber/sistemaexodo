import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sistema_exodo_novo/services/licenca_instalacao_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';

/// Tela que aparece quando o computador não tem licença de instalação válida.
///
/// É a trava do sistema: enquanto a licença de 30 dias não estiver ativa (ou
/// não for renovada após o vencimento), o app não abre o login nem o PDV.
class AtivacaoLicencaPage extends StatefulWidget {
  final ResultadoLicencaInstalacao resultado;
  final Future<void> Function() aoLiberar;

  const AtivacaoLicencaPage({
    super.key,
    required this.resultado,
    required this.aoLiberar,
  });

  @override
  State<AtivacaoLicencaPage> createState() => _AtivacaoLicencaPageState();
}

class _AtivacaoLicencaPageState extends State<AtivacaoLicencaPage> {
  bool _ocupado = false;
  /// O computador não tem arquivo, mas a nuvem já tem licença vencida: renova.
  bool _forcarRenovacao = false;
  bool _copiado = false;
  String _mensagem = '';
  bool _erro = false;
  String _maquinaId = '';
  final TextEditingController _codigoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarMaquina();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _carregarMaquina() async {
    final id = await LicencaInstalacaoService.identificadorMaquina();
    if (!mounted) return;
    setState(() => _maquinaId = id);
  }

  bool get _vencida =>
      widget.resultado.estado == EstadoLicencaInstalacao.expirada ||
      _forcarRenovacao;

  Future<void> _ativar() async {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      setState(() {
        _erro = true;
        _mensagem =
            'Informe o código de ativação que acompanha a compra do sistema.';
      });
      return;
    }
    await _executar(
      () => LicencaInstalacaoService.ativar(codigoAtivacao: codigo),
    );
  }

  bool get _relogioAlterado =>
      widget.resultado.estado == EstadoLicencaInstalacao.relogioAlterado;

  Future<void> _executar(Future<RespostaLicencaInstalacao> Function() acao) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _mensagem = '';
      _erro = false;
    });

    final resposta = await acao();
    if (!mounted) return;

    if (resposta.ok) {
      setState(() {
        _ocupado = false;
        _erro = false;
        _mensagem = resposta.mensagem;
      });
      // Recarrega o gate: se a licença entrou, o sistema abre.
      await widget.aoLiberar();
      return;
    }

    setState(() {
      _ocupado = false;
      _erro = true;
      // Reinstalou/apagou o arquivo: não ganha outros 30 dias, tem que renovar.
      if (resposta.codigo == 'licenca_expirada') {
        _forcarRenovacao = true;
      }
      if (resposta.codigo == 'pagamento_pendente' ||
          resposta.codigo == 'empresa_nao_vinculada' ||
          resposta.codigo == 'licenca_expirada') {
        _mensagem = '${resposta.mensagem}\n\nFale com o suporte para liberar '
            'a mensalidade e tente novamente.';
      } else {
        _mensagem = resposta.mensagem;
      }
    });
  }

  Future<void> _renovar() =>
      _executar(LicencaInstalacaoService.renovar);

  /// Contingência: aplica a licença de instalação assinada no painel local,
  /// sem falar com a nuvem. Valida assinatura, computador e vencimento antes
  /// de gravar o arquivo que o gate de boot lê.
  Future<void> _abrirLicencaOffline() async {
    final controller = TextEditingController();
    String? erro;
    var aplicando = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> escolherArquivo() async {
              try {
                final escolhido = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['json'],
                  withData: true,
                );
                final arquivo = escolhido?.files.single;
                if (arquivo == null) return;
                String? conteudo;
                final bytes = arquivo.bytes;
                if (bytes != null) {
                  conteudo = utf8.decode(bytes);
                } else if (arquivo.path != null) {
                  conteudo = await File(arquivo.path!).readAsString();
                }
                if (conteudo == null) {
                  setDialogState(
                    () => erro = 'Não foi possível ler o arquivo escolhido.',
                  );
                  return;
                }
                controller.text = conteudo;
                setDialogState(() => erro = null);
              } catch (e) {
                setDialogState(() => erro = 'Falha ao ler o arquivo: $e');
              }
            }

            Future<void> aplicar() async {
              setDialogState(() {
                aplicando = true;
                erro = null;
              });
              // Captura o Navigator antes do await: usar o context do diálogo
              // depois de esperar a validação é o que o lint reclama.
              final navegador = Navigator.of(dialogContext);
              final resposta = await LicencaInstalacaoService.ativarOffline(
                controller.text,
              );
              if (!mounted) return;
              if (!resposta.ok) {
                setDialogState(() {
                  aplicando = false;
                  erro = resposta.mensagem;
                });
                return;
              }
              navegador.pop();
              setState(() {
                _erro = false;
                _mensagem = resposta.mensagem;
              });
              await widget.aoLiberar();
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF171B24),
              title: const Text(
                'Licença offline',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sem internet? Digite o código de liberação offline '
                      '(EXO-OFF-...) enviado pelo suporte, cole o conteúdo do '
                      'arquivo de licença ou escolha o arquivo .json.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      enabled: !aplicando,
                      minLines: 5,
                      maxLines: 9,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'EXO-OFF-XXXXXX-XXXXXX ou { "payload": { ... }, "assinatura": "..." }',
                        hintStyle: const TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0E121A),
                        errorText: erro,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF303746)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF303746)),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: aplicando ? null : escolherArquivo,
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('Escolher arquivo .json'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: aplicando
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: aplicando ? null : aplicar,
                  icon: aplicando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: Text(aplicando ? 'VALIDANDO...' : 'APLICAR LICENÇA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: const Color(0xFF17120A),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _copiarMaquina() async {
    if (_maquinaId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _maquinaId));
    if (!mounted) return;
    setState(() => _copiado = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  String get _titulo {
    if (_relogioAlterado) return 'Data do computador incorreta';
    if (_vencida) return 'Licença de instalação vencida';
    if (widget.resultado.estado == EstadoLicencaInstalacao.outraMaquina) {
      return 'Licença de outro computador';
    }
    if (widget.resultado.estado == EstadoLicencaInstalacao.invalida) {
      return 'Licença de instalação inválida';
    }
    return 'Ative este computador';
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF171B24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF303746)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExodoLogo(fontSize: 46, showSubtitle: true),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _relogioAlterado
                        ? Icons.access_time_filled_rounded
                        : _vencida
                        ? Icons.lock_clock_outlined
                        : Icons.verified_user_outlined,
                    color: const Color(0xFFFF9800),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.resultado.mensagem,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (widget.resultado.licenca != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E121A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF303746)),
                    ),
                    child: Text(
                      widget.resultado.licenca!.expirada
                          ? 'Venceu em ${_formatarData(widget.resultado.licenca!.expiraEm)}'
                          : 'Válida até ${_formatarData(widget.resultado.licenca!.expiraEm)} '
                                '(${widget.resultado.licenca!.diasRestantes} dia(s))',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _cartaoMaquina(),
                if (!_vencida) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codigoController,
                    enabled: !_ocupado,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Código de ativação',
                      hintText: 'EXO-XXXX-XXXX-XXXX  ou  EXO-OFF-XXXXXX-XXXXXX',
                      hintStyle: const TextStyle(color: Colors.white24),
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF0E121A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF303746)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF303746)),
                      ),
                    ),
                  ),
                ],
                if (_mensagem.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _erro ? const Color(0xFF32191B) : const Color(0xFF102B20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _erro ? const Color(0xFF79363B) : const Color(0xFF276B48),
                      ),
                    ),
                    child: Text(
                      _mensagem,
                      style: TextStyle(
                        color: _erro ? const Color(0xFFFFB9BD) : const Color(0xFFA9F0C5),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (!_relogioAlterado)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _ocupado
                          ? null
                          : (_vencida ? _renovar : _ativar),
                      icon: _ocupado
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                              ),
                            )
                          : Icon(_vencida ? Icons.autorenew : Icons.key_rounded),
                      label: Text(
                        _ocupado
                            ? 'Falando com a nuvem...'
                            : _vencida
                            ? 'RENOVAR LICENÇA'
                            : 'ATIVAR ESTE COMPUTADOR',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        foregroundColor: const Color(0xFF17120A),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _ocupado ? null : _abrirLicencaOffline,
                  icon: const Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Sem internet? Aplicar licença offline',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 2),
                TextButton.icon(
                  onPressed: _ocupado ? null : widget.aoLiberar,
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  label: const Text(
                    'Verificar novamente',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A licença vale 30 dias e é renovada após o pagamento da '
                  'mensalidade. Cada computador tem a sua.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartaoMaquina() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E121A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303746)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ID DESTE COMPUTADOR',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _maquinaId.isEmpty ? 'Calculando...' : _maquinaId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                onPressed: _maquinaId.isEmpty ? null : _copiarMaquina,
                icon: Icon(
                  _copiado ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                  color: _copiado ? const Color(0xFFA9F0C5) : Colors.white54,
                ),
                tooltip: 'Copiar ID',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatarData(DateTime data) {
    final local = data.toLocal();
    String dois(int valor) => valor.toString().padLeft(2, '0');
    return '${dois(local.day)}/${dois(local.month)}/${local.year}';
  }
}
