import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../services/data_service.dart';
import '../theme.dart';
import 'venda_direta_page.dart';
import 'lancar_pedido_page.dart';

class ClienteDetalhesPage extends StatefulWidget {
  final Cliente? cliente;

  const ClienteDetalhesPage({super.key, this.cliente});

  @override
  State<ClienteDetalhesPage> createState() => _ClienteDetalhesPageState();
}

class _ClienteDetalhesPageState extends State<ClienteDetalhesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controladores
  final _nomeController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _cpfCnpjController = TextEditingController();
  final _rgIeController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _telefone2Controller = TextEditingController();
  final _whatsappController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _pontoReferenciaController = TextEditingController();
  final _profissaoController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _limiteCreditoController = TextEditingController();

  TipoPessoa _tipoPessoa = TipoPessoa.fisica;
  DateTime? _dataNascimento;
  bool _ativo = true;
  bool _bloqueado = false;

  bool get _isEditing => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    // Se está editando, mostrar 4 abas (incluindo Financeiro)
    _tabController = TabController(
      length: widget.cliente != null ? 4 : 3,
      vsync: this,
    );
    _carregarDados();
  }

  void _carregarDados() {
    if (widget.cliente != null) {
      final c = widget.cliente!;
      _nomeController.text = c.nome;
      _nomeFantasiaController.text = c.nomeFantasia ?? '';
      _tipoPessoa = c.tipoPessoa;
      _cpfCnpjController.text = c.cpfCnpj ?? '';
      _rgIeController.text = c.rgIe ?? '';
      _emailController.text = c.email ?? '';
      _telefoneController.text = c.telefone;
      _telefone2Controller.text = c.telefone2 ?? '';
      _whatsappController.text = c.whatsapp ?? '';
      _enderecoController.text = c.endereco ?? '';
      _numeroController.text = c.numero ?? '';
      _complementoController.text = c.complemento ?? '';
      _bairroController.text = c.bairro ?? '';
      _cidadeController.text = c.cidade ?? '';
      _estadoController.text = c.estado ?? '';
      _cepController.text = c.cep ?? '';
      _pontoReferenciaController.text = c.pontoReferencia ?? '';
      _dataNascimento = c.dataNascimento;
      _profissaoController.text = c.profissao ?? '';
      _observacoesController.text = c.observacoes ?? '';
      _limiteCreditoController.text = c.limiteCredito?.toStringAsFixed(2) ?? '';
      _ativo = c.ativo;
      _bloqueado = c.bloqueado;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nomeController.dispose();
    _nomeFantasiaController.dispose();
    _cpfCnpjController.dispose();
    _rgIeController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _telefone2Controller.dispose();
    _whatsappController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _pontoReferenciaController.dispose();
    _profissaoController.dispose();
    _observacoesController.dispose();
    _limiteCreditoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEditing ? 'Editar Cliente' : 'Novo Cliente'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                tooltip: 'Excluir cliente',
                onPressed: _confirmarExclusao,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.greenAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              isScrollable: _isEditing, // Scrollável se tiver 4 abas
              tabs: [
                const Tab(icon: Icon(Icons.person), text: 'Dados'),
                const Tab(icon: Icon(Icons.location_on), text: 'Endereço'),
                const Tab(icon: Icon(Icons.info), text: 'Adicional'),
                if (_isEditing)
                  const Tab(
                    icon: Icon(Icons.account_balance_wallet),
                    text: 'Financeiro',
                  ),
              ],
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTabDados(),
              _buildTabEndereco(),
              _buildTabAdicional(),
              if (_isEditing) _buildTabFinanceiro(),
            ],
          ),
        ),
        bottomNavigationBar: _buildBotaoSalvar(),
      ),
    );
  }

  Widget _buildTabDados() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo de Pessoa
          _buildSecaoTitulo('Tipo de Pessoa', Icons.badge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOpcaoTipo(
                  TipoPessoa.fisica,
                  'Pessoa Física',
                  Icons.person,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOpcaoTipo(
                  TipoPessoa.juridica,
                  'Pessoa Jurídica',
                  Icons.business,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Dados Principais
          _buildSecaoTitulo('Dados Principais', Icons.account_circle),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _nomeController,
            label: _tipoPessoa == TipoPessoa.fisica
                ? 'Nome Completo *'
                : 'Razão Social *',
            icon: Icons.person,
            required: true,
          ),
          if (_tipoPessoa == TipoPessoa.juridica) ...[
            const SizedBox(height: 12),
            _buildCampoTexto(
              controller: _nomeFantasiaController,
              label: 'Nome Fantasia',
              icon: Icons.store,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _cpfCnpjController,
                  label: _tipoPessoa == TipoPessoa.fisica ? 'CPF' : 'CNPJ',
                  icon: Icons.credit_card,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      _tipoPessoa == TipoPessoa.fisica ? 11 : 14,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _rgIeController,
                  label: _tipoPessoa == TipoPessoa.fisica
                      ? 'RG'
                      : 'Inscrição Estadual',
                  icon: Icons.badge,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Contato
          _buildSecaoTitulo('Contato', Icons.phone),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _telefoneController,
                  label: 'Telefone Principal *',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  required: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _telefone2Controller,
                  label: 'Telefone Secundário',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _whatsappController,
                  label: 'WhatsApp',
                  icon: Icons.chat,
                  keyboardType: TextInputType.phone,
                  prefixText: '+55 ',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _emailController,
                  label: 'E-mail',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabEndereco() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecaoTitulo('Endereço', Icons.home),
          const SizedBox(height: 12),

          // CEP com busca
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildCampoTexto(
                  controller: _cepController,
                  label: 'CEP',
                  icon: Icons.pin_drop,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildCampoTexto(
                  controller: _enderecoController,
                  label: 'Logradouro',
                  icon: Icons.location_on,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _numeroController,
                  label: 'Número',
                  icon: Icons.numbers,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _complementoController,
            label: 'Complemento',
            icon: Icons.apartment,
            hintText: 'Apto, Bloco, Sala...',
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _bairroController,
                  label: 'Bairro',
                  icon: Icons.location_city,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildCampoTexto(
                  controller: _cidadeController,
                  label: 'Cidade',
                  icon: Icons.location_city,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: _buildCampoTexto(
                  controller: _estadoController,
                  label: 'UF',
                  icon: Icons.map,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(2),
                    UpperCaseTextFormatter(),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _pontoReferenciaController,
            label: 'Ponto de Referência',
            icon: Icons.place,
            hintText: 'Próximo a...',
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTabAdicional() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações Pessoais
          if (_tipoPessoa == TipoPessoa.fisica) ...[
            _buildSecaoTitulo('Informações Pessoais', Icons.person_outline),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCampoData(
                    label: 'Data de Nascimento',
                    value: _dataNascimento,
                    onChanged: (data) {
                      setState(() => _dataNascimento = data);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCampoTexto(
                    controller: _profissaoController,
                    label: 'Profissão',
                    icon: Icons.work,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Crédito
          _buildSecaoTitulo('Crédito', Icons.account_balance_wallet),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _limiteCreditoController,
            label: 'Limite de Crédito (R\$)',
            icon: Icons.attach_money,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            prefixText: 'R\$ ',
          ),

          const SizedBox(height: 24),

          // Status
          _buildSecaoTitulo('Status', Icons.toggle_on),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Cliente Ativo',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _ativo
                        ? 'Cliente disponível para vendas'
                        : 'Cliente inativo',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  value: _ativo,
                  activeThumbColor: Colors.greenAccent,
                  onChanged: (value) => setState(() => _ativo = value),
                ),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  title: const Text(
                    'Bloqueado',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _bloqueado
                        ? 'Cliente bloqueado para novas vendas'
                        : 'Sem bloqueio',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  value: _bloqueado,
                  activeThumbColor: Colors.redAccent,
                  onChanged: (value) => setState(() => _bloqueado = value),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Observações
          _buildSecaoTitulo('Observações', Icons.notes),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _observacoesController,
            label: 'Observações',
            icon: Icons.notes,
            maxLines: 4,
            hintText: 'Anotações sobre o cliente...',
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoTitulo(String titulo, IconData icone) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icone, color: Colors.blue, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOpcaoTipo(TipoPessoa tipo, String label, IconData icone) {
    final isSelected = _tipoPessoa == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoPessoa = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icone,
              color: isSelected ? Colors.blue : Colors.white54,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: Colors.blue, size: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCampoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? hintText,
    String? prefixText,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: Colors.white54),
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: Colors.white),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Campo obrigatório';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildCampoData({
    required String label,
    required DateTime? value,
    required Function(DateTime?) onChanged,
  }) {
    return GestureDetector(
      onTap: () async {
        final data = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Colors.blue,
                  surface: Color(0xFF1E1E2E),
                ),
              ),
              child: child!,
            );
          },
        );
        if (data != null) {
          onChanged(data);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.white54, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value != null
                        ? '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'
                        : 'Selecionar data',
                    style: TextStyle(
                      color: value != null ? Colors.white : Colors.white54,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoSalvar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botão Nova Venda (apenas para cliente existente)
            if (_isEditing) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _mostrarDialogNovaVenda,
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Nova Venda'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _salvar,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isEditing ? 'Atualizar' : 'Cadastrar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogNovaVenda() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_cart, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Nova Venda',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selecione o tipo de venda para ${widget.cliente?.nome}:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildOpcaoVenda(
                    ctx,
                    'Venda Direta',
                    'PDV rápido',
                    Icons.point_of_sale,
                    Colors.green,
                    () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VendaDiretaPage(clienteInicial: widget.cliente),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOpcaoVenda(
                    ctx,
                    'Pedido',
                    'Venda completa',
                    Icons.receipt_long,
                    Colors.orange,
                    () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LancarPedidoPage(clienteInicial: widget.cliente),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpcaoVenda(
    BuildContext ctx,
    String titulo,
    String subtitulo,
    IconData icone,
    Color cor,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
              Icon(icone, color: cor, size: 36),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: TextStyle(
                  color: cor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                subtitulo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _salvar() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha os campos obrigatórios'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      final cliente = Cliente(
        id:
            widget.cliente?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        nome: _nomeController.text.trim(),
        nomeFantasia: _nomeFantasiaController.text.trim().isEmpty
            ? null
            : _nomeFantasiaController.text.trim(),
        tipoPessoa: _tipoPessoa,
        cpfCnpj: _cpfCnpjController.text.trim().isEmpty
            ? null
            : _cpfCnpjController.text.trim(),
        rgIe: _rgIeController.text.trim().isEmpty
            ? null
            : _rgIeController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        telefone: _telefoneController.text.trim(),
        telefone2: _telefone2Controller.text.trim().isEmpty
            ? null
            : _telefone2Controller.text.trim(),
        whatsapp: _whatsappController.text.trim().isEmpty
            ? null
            : _whatsappController.text.trim(),
        endereco: _enderecoController.text.trim().isEmpty
            ? null
            : _enderecoController.text.trim(),
        numero: _numeroController.text.trim().isEmpty
            ? null
            : _numeroController.text.trim(),
        complemento: _complementoController.text.trim().isEmpty
            ? null
            : _complementoController.text.trim(),
        bairro: _bairroController.text.trim().isEmpty
            ? null
            : _bairroController.text.trim(),
        cidade: _cidadeController.text.trim().isEmpty
            ? null
            : _cidadeController.text.trim(),
        estado: _estadoController.text.trim().isEmpty
            ? null
            : _estadoController.text.trim(),
        cep: _cepController.text.trim().isEmpty
            ? null
            : _cepController.text.trim(),
        pontoReferencia: _pontoReferenciaController.text.trim().isEmpty
            ? null
            : _pontoReferenciaController.text.trim(),
        dataNascimento: _dataNascimento,
        profissao: _profissaoController.text.trim().isEmpty
            ? null
            : _profissaoController.text.trim(),
        observacoes: _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
        limiteCredito: double.tryParse(
          _limiteCreditoController.text.replaceAll(',', '.'),
        ),
        bloqueado: _bloqueado,
        ativo: _ativo,
        createdAt: widget.cliente?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditing) {
        dataService.updateCliente(cliente);
      } else {
        await dataService.addCliente(cliente);
      }

      if (mounted) {
        Navigator.pop(context, cliente);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  _isEditing
                      ? 'Cliente atualizado com sucesso!'
                      : 'Cliente cadastrado com sucesso!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _confirmarExclusao() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Excluir Cliente', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir o cliente "${widget.cliente?.nome}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final dataService = Provider.of<DataService>(
                context,
                listen: false,
              );
              dataService.deleteCliente(widget.cliente!.id);
              Navigator.pop(context); // Fecha o dialog
              Navigator.pop(context); // Volta para a lista
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cliente excluído'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // ============ ABA FINANCEIRO ============
  Widget _buildTabFinanceiro() {
    final dataService = Provider.of<DataService>(context);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Buscar todos os pedidos do cliente
    final pedidosCliente =
        dataService.pedidos
            .where((p) => p.clienteId == widget.cliente?.id)
            .toList()
          ..sort((a, b) => b.dataPedido.compareTo(a.dataPedido));

    // Calcular estatísticas financeiras
    final estatisticas = _calcularEstatisticasFinanceiras(pedidosCliente);

    // Separar pagamentos pendentes (a prazo)
    final pagamentosPendentes = <_PagamentoPendenteInfo>[];
    final pagamentosRecebidos = <_PagamentoPendenteInfo>[];

    for (final pedido in pedidosCliente) {
      for (final pag in pedido.pagamentos) {
        final info = _PagamentoPendenteInfo(pedido: pedido, pagamento: pag);
        if (pag.recebido) {
          pagamentosRecebidos.add(info);
        } else {
          pagamentosPendentes.add(info);
        }
      }
    }

    // Ordenar pendentes por vencimento
    pagamentosPendentes.sort((a, b) {
      final dataA = a.pagamento.dataVencimento ?? DateTime.now();
      final dataB = b.pagamento.dataVencimento ?? DateTime.now();
      return dataA.compareTo(dataB);
    });

    // Ordenar recebidos por data de recebimento (mais recentes primeiro)
    pagamentosRecebidos.sort((a, b) {
      final dataA = a.pagamento.dataRecebimento ?? a.pedido.dataPedido;
      final dataB = b.pagamento.dataRecebimento ?? b.pedido.dataPedido;
      return dataB.compareTo(dataA);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dashboard Financeiro
          _buildDashboardFinanceiro(estatisticas, formatoMoeda),

          const SizedBox(height: 24),

          // Análise de Crédito
          _buildAnaliseCredito(estatisticas, formatoMoeda),

          const SizedBox(height: 24),

          // Pagamentos Pendentes (A Receber)
          if (pagamentosPendentes.isNotEmpty) ...[
            _buildSecaoTitulo('Pagamentos Pendentes', Icons.pending_actions),
            const SizedBox(height: 12),
            ...pagamentosPendentes.map(
              (info) => _buildCardPagamentoPendente(
                info,
                formatoMoeda,
                formatoData,
                dataService,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Histórico de Pagamentos Recebidos
          _buildSecaoTitulo('Histórico de Pagamentos', Icons.history),
          const SizedBox(height: 12),
          if (pagamentosRecebidos.isEmpty)
            _buildSemHistorico()
          else
            ...pagamentosRecebidos
                .take(20)
                .map(
                  (info) => _buildCardPagamentoRecebido(
                    info,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 24),

          // Histórico de Pedidos
          _buildSecaoTitulo('Histórico de Pedidos', Icons.receipt_long),
          const SizedBox(height: 12),
          if (pedidosCliente.isEmpty)
            _buildSemHistorico()
          else
            ...pedidosCliente
                .take(10)
                .map(
                  (pedido) => _buildCardPedidoHistorico(
                    pedido,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Map<String, dynamic> _calcularEstatisticasFinanceiras(List<Pedido> pedidos) {
    double totalCompras = 0;
    double totalPago = 0;
    double totalPendente = 0;
    double totalVencido = 0;
    int qtdPedidos = pedidos.length;
    int qtdPagamentosPendentes = 0;
    int qtdPagamentosVencidos = 0;
    int diasMaiorAtraso = 0;
    DateTime? ultimaCompra;

    for (final pedido in pedidos) {
      totalCompras += pedido.totalGeral;
      if (ultimaCompra == null || pedido.dataPedido.isAfter(ultimaCompra)) {
        ultimaCompra = pedido.dataPedido;
      }

      for (final pag in pedido.pagamentos) {
        if (pag.recebido) {
          totalPago += pag.valor;
        } else {
          totalPendente += pag.valor;
          qtdPagamentosPendentes++;

          if (pag.dataVencimento != null &&
              pag.dataVencimento!.isBefore(DateTime.now())) {
            totalVencido += pag.valor;
            qtdPagamentosVencidos++;
            final diasAtraso = DateTime.now()
                .difference(pag.dataVencimento!)
                .inDays;
            if (diasAtraso > diasMaiorAtraso) {
              diasMaiorAtraso = diasAtraso;
            }
          }
        }
      }
    }

    // Score de crédito baseado no histórico
    int scoreCredito = 100;
    if (qtdPagamentosVencidos > 0) {
      scoreCredito -= (qtdPagamentosVencidos * 10).clamp(0, 40);
    }
    if (diasMaiorAtraso > 30) scoreCredito -= 20;
    if (diasMaiorAtraso > 60) scoreCredito -= 20;
    if (totalVencido > 500) scoreCredito -= 10;
    scoreCredito = scoreCredito.clamp(0, 100);

    return {
      'totalCompras': totalCompras,
      'totalPago': totalPago,
      'totalPendente': totalPendente,
      'totalVencido': totalVencido,
      'qtdPedidos': qtdPedidos,
      'qtdPagamentosPendentes': qtdPagamentosPendentes,
      'qtdPagamentosVencidos': qtdPagamentosVencidos,
      'diasMaiorAtraso': diasMaiorAtraso,
      'ultimaCompra': ultimaCompra,
      'scoreCredito': scoreCredito,
      'ticketMedio': qtdPedidos > 0 ? totalCompras / qtdPedidos : 0.0,
    };
  }

  Widget _buildDashboardFinanceiro(
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final totalCompras = stats['totalCompras'] as double;
    final totalPago = stats['totalPago'] as double;
    final totalPendente = stats['totalPendente'] as double;
    final totalVencido = stats['totalVencido'] as double;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiro(
                  'Total Compras',
                  formatoMoeda.format(totalCompras),
                  Icons.shopping_cart,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiro(
                  'Total Pago',
                  formatoMoeda.format(totalPago),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiro(
                  'Pendente',
                  formatoMoeda.format(totalPendente),
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiro(
                  'Vencido',
                  formatoMoeda.format(totalVencido),
                  Icons.warning,
                  totalVencido > 0 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatFinanceiro(
    String label,
    String valor,
    IconData icon,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnaliseCredito(
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final scoreCredito = stats['scoreCredito'] as int;
    final qtdPedidos = stats['qtdPedidos'] as int;
    final ticketMedio = stats['ticketMedio'] as double;
    final diasMaiorAtraso = stats['diasMaiorAtraso'] as int;
    final qtdVencidos = stats['qtdPagamentosVencidos'] as int;
    final ultimaCompra = stats['ultimaCompra'] as DateTime?;

    Color corScore;
    String statusCredito;
    IconData iconeStatus;

    if (scoreCredito >= 80) {
      corScore = Colors.green;
      statusCredito = 'Excelente';
      iconeStatus = Icons.verified;
    } else if (scoreCredito >= 60) {
      corScore = Colors.lightGreen;
      statusCredito = 'Bom';
      iconeStatus = Icons.thumb_up;
    } else if (scoreCredito >= 40) {
      corScore = Colors.orange;
      statusCredito = 'Regular';
      iconeStatus = Icons.warning;
    } else {
      corScore = Colors.red;
      statusCredito = 'Atenção';
      iconeStatus = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corScore.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: corScore.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconeStatus, color: corScore, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Análise de Crédito',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Text(
                          statusCredito,
                          style: TextStyle(
                            color: corScore,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: corScore.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$scoreCredito pts',
                            style: TextStyle(
                              color: corScore,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Barra de progresso do score
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: scoreCredito / 100,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(corScore),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Detalhes
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildDetalheCredito(
                Icons.receipt,
                '$qtdPedidos pedidos',
                Colors.blue,
              ),
              _buildDetalheCredito(
                Icons.trending_up,
                'Ticket: ${formatoMoeda.format(ticketMedio)}',
                Colors.green,
              ),
              if (qtdVencidos > 0)
                _buildDetalheCredito(
                  Icons.warning,
                  '$qtdVencidos vencidos',
                  Colors.red,
                ),
              if (diasMaiorAtraso > 0)
                _buildDetalheCredito(
                  Icons.timer_off,
                  'Maior atraso: $diasMaiorAtraso dias',
                  Colors.orange,
                ),
              if (ultimaCompra != null)
                _buildDetalheCredito(
                  Icons.calendar_today,
                  'Última: ${DateFormat('dd/MM/yy').format(ultimaCompra)}',
                  Colors.purple,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheCredito(IconData icon, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(color: cor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCardPagamentoPendente(
    _PagamentoPendenteInfo info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
    DataService dataService,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;
    final isVencido =
        pag.dataVencimento != null &&
        pag.dataVencimento!.isBefore(DateTime.now());
    final diasAtraso = isVencido
        ? DateTime.now().difference(pag.dataVencimento!).inDays
        : 0;

    Color corTipo;
    IconData iconeTipo;

    switch (pag.tipo) {
      case TipoPagamento.crediario:
        corTipo = Colors.purple;
        iconeTipo = Icons.credit_score;
        break;
      case TipoPagamento.boleto:
        corTipo = Colors.orange;
        iconeTipo = Icons.receipt_long;
        break;
      default:
        corTipo = Colors.blue;
        iconeTipo = Icons.payment;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVencido
              ? Colors.red.withOpacity(0.5)
              : corTipo.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corTipo.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconeTipo, color: corTipo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            pag.tipo.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (pag.isParcela) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: corTipo.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${pag.numeroParcela}/${pag.parcelas}',
                                style: TextStyle(
                                  color: corTipo,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Pedido ${pedido.numero}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            isVencido ? Icons.warning : Icons.event,
                            size: 12,
                            color: isVencido ? Colors.red : Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            pag.dataVencimento != null
                                ? 'Venc: ${formatoData.format(pag.dataVencimento!)}'
                                : 'Sem vencimento',
                            style: TextStyle(
                              color: isVencido ? Colors.red : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (isVencido) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$diasAtraso dias',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatoMoeda.format(pag.valor),
                      style: TextStyle(
                        color: isVencido ? Colors.red : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão para marcar como recebido
          Container(
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _marcarComoRecebido(dataService, pedido, pag),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.withOpacity(0.8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Marcar como Recebido',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _marcarComoRecebido(
    DataService dataService,
    Pedido pedido,
    PagamentoPedido pagamento,
  ) {
    // Formas de recebimento disponíveis (sem fiado, pois fiado é só para lançamento)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado)
        .toList();

    TipoPagamento? formaSelecionada;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payments, color: Colors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Receber Pagamento',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor a receber
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Valor:',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          'R\$ ${pagamento.valor.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tipo original
                  Text(
                    'Forma original: ${pagamento.tipo.nome}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Label
                  const Text(
                    'Como o cliente está pagando?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botões de forma de recebimento
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              formaSelecionada = tipo;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cor.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? cor
                                    : Colors.white.withOpacity(0.2),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getIconeTipoRecebimento(tipo),
                                  color: isSelected ? cor : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tipo.nome,
                                  style: TextStyle(
                                    color: isSelected ? cor : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: formaSelecionada == null
                    ? null
                    : () {
                        // Atualizar o pagamento com a nova forma de recebimento
                        final novosPagamentos = pedido.pagamentos.map((p) {
                          if (p.id == pagamento.id) {
                            return PagamentoPedido(
                              id: p.id,
                              tipo: formaSelecionada!,
                              tipoOriginal: p.tipo, // Guardar tipo original
                              valor: p.valor,
                              recebido: true,
                              dataRecebimento: DateTime.now(),
                              dataVencimento: p.dataVencimento,
                              parcelas: p.parcelas,
                              numeroParcela: p.numeroParcela,
                              parcelamentoId: p.parcelamentoId,
                              observacao: p.observacao,
                            );
                          }
                          return p;
                        }).toList();

                        // Atualizar status do pedido
                        final todosRecebidos = novosPagamentos.every(
                          (p) => p.recebido,
                        );

                        final pedidoAtualizado = Pedido(
                          id: pedido.id,
                          numero: pedido.numero,
                          clienteId: pedido.clienteId,
                          clienteNome: pedido.clienteNome,
                          clienteTelefone: pedido.clienteTelefone,
                          clienteEndereco: pedido.clienteEndereco,
                          dataPedido: pedido.dataPedido,
                          status: todosRecebidos ? 'Pago' : pedido.status,
                          produtos: pedido.produtos,
                          servicos: pedido.servicos,
                          pagamentos: novosPagamentos,
                        );

                        dataService.updatePedido(pedidoAtualizado);

                        // Se era fiado, atualizar saldo devedor do cliente
                        if (pagamento.tipo == TipoPagamento.fiado &&
                            widget.cliente != null) {
                          final novoSaldo =
                              (widget.cliente!.saldoDevedor - pagamento.valor)
                                  .clamp(0.0, double.infinity);
                          final clienteAtualizado = widget.cliente!.copyWith(
                            saldoDevedor: novoSaldo,
                            updatedAt: DateTime.now(),
                          );
                          dataService.updateCliente(clienteAtualizado);
                        }

                        Navigator.pop(ctx);
                        setState(() {}); // Refresh

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✓ Recebido via ${formaSelecionada!.nome}!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: formaSelecionada != null
                      ? Colors.green
                      : Colors.grey,
                ),
                child: const Text('Confirmar Recebimento'),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getIconeTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }

  Color _getCorTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.purple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.pink;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }

  Widget _buildCardPagamentoRecebido(
    _PagamentoPendenteInfo info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pag.tipo.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Pedido ${pedido.numero} • ${formatoData.format(pag.dataRecebimento ?? pedido.dataPedido)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatoMoeda.format(pag.valor),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPedidoHistorico(
    Pedido pedido,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isPago = pedido.totalmenteRecebido;

    return _PedidoHistoricoExpandivel(
      pedido: pedido,
      formatoMoeda: formatoMoeda,
      formatoData: formatoData,
      isPago: isPago,
      onRepetirVenda: () => _repetirVenda(pedido),
    );
  }

  void _repetirVenda(Pedido pedido) {
    // Navegar para venda direta com os mesmos itens
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VendaDiretaPage(
          clienteInicial: widget.cliente,
          itensParaRepetir: pedido.produtos,
          servicosParaRepetir: pedido.servicos,
        ),
      ),
    );
  }

  Widget _buildSemHistorico() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro encontrado',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Classe auxiliar para informações de pagamento pendente
class _PagamentoPendenteInfo {
  final Pedido pedido;
  final PagamentoPedido pagamento;

  _PagamentoPendenteInfo({required this.pedido, required this.pagamento});
}

/// Formatter para transformar texto em maiúsculas
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Widget expandível para mostrar detalhes do pedido no histórico
class _PedidoHistoricoExpandivel extends StatefulWidget {
  final Pedido pedido;
  final NumberFormat formatoMoeda;
  final DateFormat formatoData;
  final bool isPago;
  final VoidCallback onRepetirVenda;

  const _PedidoHistoricoExpandivel({
    required this.pedido,
    required this.formatoMoeda,
    required this.formatoData,
    required this.isPago,
    required this.onRepetirVenda,
  });

  @override
  State<_PedidoHistoricoExpandivel> createState() =>
      _PedidoHistoricoExpandivelState();
}

class _PedidoHistoricoExpandivelState
    extends State<_PedidoHistoricoExpandivel> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: _expandido
            ? Border.all(color: Colors.blue.withOpacity(0.3))
            : null,
      ),
      child: Column(
        children: [
          // Header clicável
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (widget.isPago ? Colors.green : Colors.orange)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.isPago ? Icons.check_circle : Icons.schedule,
                        color: widget.isPago ? Colors.green : Colors.orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.pedido.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${widget.formatoData.format(widget.pedido.dataPedido)} • ${widget.pedido.produtos.length + widget.pedido.servicos.length} itens',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.formatoMoeda.format(widget.pedido.totalGeral),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (widget.isPago ? Colors.green : Colors.orange)
                                    .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.isPago ? 'Pago' : 'Pendente',
                            style: TextStyle(
                              color: widget.isPago
                                  ? Colors.green
                                  : Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expandido
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Conteúdo expandível
          if (_expandido) ...[
            Divider(color: Colors.white.withOpacity(0.1), height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lista de produtos
                  if (widget.pedido.produtos.isNotEmpty) ...[
                    Text(
                      'Produtos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.pedido.produtos.map(
                      (item) => _buildItemPedido(
                        item.nome,
                        item.quantidade,
                        item.preco,
                        widget.formatoMoeda,
                        Icons.inventory_2,
                      ),
                    ),
                  ],

                  // Lista de serviços
                  if (widget.pedido.servicos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Serviços',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.pedido.servicos.map(
                      (item) => _buildItemPedido(
                        item.descricao,
                        1,
                        item.valor,
                        widget.formatoMoeda,
                        Icons.build,
                      ),
                    ),
                  ],

                  // Total
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total da Venda',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.formatoMoeda.format(widget.pedido.totalGeral),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Botão Repetir Venda
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onRepetirVenda,
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Repetir esta Venda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemPedido(
    String nome,
    int quantidade,
    double preco,
    NumberFormat formatoMoeda,
    IconData icone,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icone, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nome,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${quantidade}x',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatoMoeda.format(preco * quantidade),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
