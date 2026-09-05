import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/perfil_tributario.dart';

class CadastroPerfisTributariosPage extends StatefulWidget {
  const CadastroPerfisTributariosPage({super.key});

  @override
  State<CadastroPerfisTributariosPage> createState() => _CadastroPerfisTributariosPageState();
}

class _CadastroPerfisTributariosPageState extends State<CadastroPerfisTributariosPage> {
  @override
  Widget build(BuildContext context) {
    final ds = Provider.of<DataService>(context);
    // Mostra apenas os perfis do regime tributário atual da empresa
    // (Simples Nacional = perfis com CSOSN; Regime Normal = perfis com CST)
    final perfis = ds.perfisTributariosDoRegime;

    return Scaffold(
      backgroundColor: const Color(0xFF161621),
      appBar: AppBar(
        title: const Text('Perfis Tributários (Impostos)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gerencie modelos de impostos reutilizáveis (incluindo IBS/CBS, IPI, MVA/ST, FCP e Reduções) para associar aos produtos de forma simples.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ds.empresaRegimeSimples
                    ? Colors.blueAccent.withOpacity(0.12)
                    : Colors.greenAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ds.empresaRegimeSimples
                      ? Colors.blueAccent.withOpacity(0.4)
                      : Colors.greenAccent.withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ds.empresaRegimeSimples ? Icons.storefront : Icons.account_balance,
                    size: 18,
                    color: ds.empresaRegimeSimples ? Colors.blueAccent : Colors.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ds.empresaRegimeSimples
                          ? 'Mostrando perfis do regime SIMPLES NACIONAL (CSOSN). Para usar CST, troque o regime da empresa no cadastro.'
                          : 'Mostrando perfis do regime NORMAL (CST). Para usar CSOSN, troque o regime da empresa no cadastro.',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: perfis.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long, size: 64, color: Colors.white24),
                          const SizedBox(height: 16),
                          const Text('Nenhum perfil tributário cadastrado', style: TextStyle(color: Colors.white60)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _abrirFormulario(null),
                            icon: const Icon(Icons.add),
                            label: const Text('Criar Primeiro Perfil'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          )
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: perfis.length,
                      itemBuilder: (context, index) {
                        final p = perfis[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.isDefault ? Colors.blueAccent.withOpacity(0.5) : Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                        if (p.isDefault) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.blueAccent, width: 0.5),
                                            ),
                                            child: const Text('PADRÃO', style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _buildBadge('CFOP: ${p.cfop}', Colors.cyanAccent),
                                        if (p.csosn != null && p.csosn!.isNotEmpty)
                                          _buildBadge('CSOSN: ${p.csosn}', Colors.orangeAccent),
                                        if (p.icmsCst != null && p.icmsCst!.isNotEmpty)
                                          _buildBadge('CST ICMS: ${p.icmsCst}', Colors.greenAccent),
                                        if (p.aliquotaIcms != null)
                                          _buildBadge('ICMS: ${p.aliquotaIcms}%', Colors.amberAccent),
                                        if (p.reducaoBaseIcms != null)
                                          _buildBadge('Redução BC: ${p.reducaoBaseIcms}%', Colors.orangeAccent),
                                        if (p.mva != null)
                                          _buildBadge('MVA: ${p.mva}%', Colors.cyanAccent),
                                        if (p.ipiCst != null && p.ipiCst!.isNotEmpty)
                                          _buildBadge('CST IPI: ${p.ipiCst}', Colors.lightGreenAccent),
                                        if (p.aliquotaIpi != null)
                                          _buildBadge('IPI: ${p.aliquotaIpi}%', Colors.tealAccent),
                                        if (p.aliquotaFcp != null)
                                          _buildBadge('FCP: ${p.aliquotaFcp}%', Colors.redAccent),
                                        if (p.aliquotaIcmsInterestadual != null)
                                          _buildBadge('ICMS Inter: ${p.aliquotaIcmsInterestadual}%', Colors.indigoAccent),
                                        if (p.cstIbs != null && p.cstIbs!.isNotEmpty)
                                          _buildBadge('CST IBS: ${p.cstIbs}', Colors.purpleAccent),
                                        if (p.aliquotaIbs != null)
                                          _buildBadge('IBS: ${p.aliquotaIbs}%', Colors.purpleAccent),
                                        if (p.cstCbs != null && p.cstCbs!.isNotEmpty)
                                          _buildBadge('CST CBS: ${p.cstCbs}', Colors.deepOrangeAccent),
                                        if (p.aliquotaCbs != null)
                                          _buildBadge('CBS: ${p.aliquotaCbs}%', Colors.deepOrangeAccent),
                                        if (p.ncm != null && p.ncm!.isNotEmpty)
                                          _buildBadge('NCM: ${p.ncm}', Colors.white30),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.white60),
                                onPressed: () => _abrirFormulario(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _excluirPerfil(p),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: perfis.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _abrirFormulario(null),
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _abrirFormulario(PerfilTributario? perfil) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PerfilTributarioFormDialog(perfil: perfil),
    );
  }

  void _excluirPerfil(PerfilTributario perfil) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Excluir Perfil Tributário', style: TextStyle(color: Colors.white)),
        content: Text('Tem certeza que deseja excluir o perfil "${perfil.nome}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white30)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final ds = Provider.of<DataService>(context, listen: false);
              try {
                await ds.excluirPerfilTributario(perfil.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Perfil excluído com sucesso!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Excluir'),
          )
        ],
      ),
    );
  }
}

class _PerfilTributarioFormDialog extends StatefulWidget {
  final PerfilTributario? perfil;
  const _PerfilTributarioFormDialog({this.perfil});

  @override
  State<_PerfilTributarioFormDialog> createState() => _PerfilTributarioFormDialogState();
}

class _PerfilTributarioFormDialogState extends State<_PerfilTributarioFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cfopController = TextEditingController();
  final _aliquotaIcmsController = TextEditingController();
  final _aliquotaPisController = TextEditingController();
  final _aliquotaCofinsController = TextEditingController();
  final _aliquotaIbsController = TextEditingController();
  final _aliquotaCbsController = TextEditingController();
  
  // Novos controllers avançados
  final _aliquotaIpiController = TextEditingController();
  final _mvaController = TextEditingController();
  final _reducaoBaseIcmsController = TextEditingController();
  final _aliquotaFcpController = TextEditingController();
  final _aliquotaIcmsInterestadualController = TextEditingController();
  
  final _ncmController = TextEditingController();
  
  String? _icmsCstSelected;
  String? _csosnSelected;
  String? _pisCstSelected;
  String? _cofinsCstSelected;
  String? _ipiCstSelected;
  
  // Novos seletores da Reforma Tributária
  String? _ibsCstSelected;
  String? _cbsCstSelected;
  
  bool _isDefault = false;
  bool _regimeSimples = true;

  // Dicionários com opções de códigos fiscais
  static const List<Map<String, String>> _cstIcmsOptions = [
    {'value': '00', 'label': '00 - Tributada integralmente'},
    {'value': '10', 'label': '10 - Tributada com cobrança de ST'},
    {'value': '20', 'label': '20 - Com redução de base de cálculo'},
    {'value': '30', 'label': '30 - Isenta ou NT e com cobrança de ST'},
    {'value': '40', 'label': '40 - Isenta'},
    {'value': '41', 'label': '41 - Não tributada'},
    {'value': '50', 'label': '50 - Suspensão'},
    {'value': '51', 'label': '51 - Diferimento'},
    {'value': '60', 'label': '60 - ICMS cobrado anteriormente por ST'},
    {'value': '70', 'label': '70 - Com redução de BC e cobrança de ST'},
    {'value': '90', 'label': '90 - Outras'},
  ];

  static const List<Map<String, String>> _csosnOptions = [
    {'value': '101', 'label': '101 - Tributada com permissão de crédito'},
    {'value': '102', 'label': '102 - Tributada sem permissão de crédito'},
    {'value': '103', 'label': '103 - Isenção do ICMS para faixa de receita bruta'},
    {'value': '201', 'label': '201 - Tributada com permissão de crédito e com cobrança de ST'},
    {'value': '202', 'label': '202 - Tributada sem permissão de crédito e com cobrança de ST'},
    {'value': '203', 'label': '203 - Isenção e com cobrança de ST'},
    {'value': '300', 'label': '300 - Imune'},
    {'value': '400', 'label': '400 - Não tributada pelo Simples Nacional'},
    {'value': '500', 'label': '500 - ICMS cobrado anteriormente por ST (Substituído)'},
    {'value': '900', 'label': '900 - Outros'},
  ];

  static const List<Map<String, String>> _cstPisCofinsOptions = [
    {'value': '01', 'label': '01 - Tributável com Alíquota Básica'},
    {'value': '02', 'label': '02 - Tributável com Alíquota Diferenciada'},
    {'value': '03', 'label': '03 - Alíquota por Unidade de Medida'},
    {'value': '04', 'label': '04 - Tributável Monofásica (Alíquota Zero)'},
    {'value': '05', 'label': '05 - Tributável por ST'},
    {'value': '06', 'label': '06 - Alíquota Zero'},
    {'value': '07', 'label': '07 - Isenta da Contribuição'},
    {'value': '08', 'label': '08 - Sem Incidência da Contribuição'},
    {'value': '09', 'label': '09 - Com Suspensão da Contribuição'},
    {'value': '49', 'label': '49 - Outras Operações de Saída'},
  ];

  static const List<Map<String, String>> _cstIpiOptions = [
    {'value': '50', 'label': '50 - Saída Tributada'},
    {'value': '51', 'label': '51 - Saída com Alíquota Zero'},
    {'value': '52', 'label': '52 - Saída Isenta'},
    {'value': '53', 'label': '53 - Saída Não-Tributada'},
    {'value': '54', 'label': '54 - Saída Imune'},
    {'value': '55', 'label': '55 - Saída com Suspensão'},
    {'value': '99', 'label': '99 - Outras Saídas'},
  ];

  static const List<Map<String, String>> _cstIbsCbsOptions = [
    {'value': '01', 'label': '01 - Tributada integralmente (Alíquota padrão)'},
    {'value': '02', 'label': '02 - Tributada com regime diferenciado (redução)'},
    {'value': '03', 'label': '03 - Isenta ou Não Tributada'},
    {'value': '04', 'label': '04 - Alíquota Zero'},
    {'value': '05', 'label': '05 - Imune'},
    {'value': '06', 'label': '06 - Suspensa'},
    {'value': '07', 'label': '07 - Monofásica (combustíveis)'},
    {'value': '08', 'label': '08 - Regimes específicos'},
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.perfil;
    
    final ds = Provider.of<DataService>(context, listen: false);
    final empAtual = ds.empresaAtual;
    final crt = empAtual?.configuracoes?['crt']?.toString() ?? empAtual?.crt?.toString() ?? '1';
    _regimeSimples = crt == '1' || crt == '2';

    if (p != null) {
      _nomeController.text = p.nome;
      _cfopController.text = p.cfop;
      _icmsCstSelected = p.icmsCst;
      _csosnSelected = p.csosn;
      _aliquotaIcmsController.text = p.aliquotaIcms?.toString() ?? '';
      _pisCstSelected = p.pisCst;
      _aliquotaPisController.text = p.aliquotaPis?.toString() ?? '';
      _cofinsCstSelected = p.cofinsCst;
      _aliquotaCofinsController.text = p.aliquotaCofins?.toString() ?? '';
      
      _ibsCstSelected = p.cstIbs;
      _aliquotaIbsController.text = p.aliquotaIbs?.toString() ?? '';
      _cbsCstSelected = p.cstCbs;
      _aliquotaCbsController.text = p.aliquotaCbs?.toString() ?? '';
      
      _ipiCstSelected = p.ipiCst;
      _aliquotaIpiController.text = p.aliquotaIpi?.toString() ?? '';
      _mvaController.text = p.mva?.toString() ?? '';
      _reducaoBaseIcmsController.text = p.reducaoBaseIcms?.toString() ?? '';
      _aliquotaFcpController.text = p.aliquotaFcp?.toString() ?? '';
      _aliquotaIcmsInterestadualController.text = p.aliquotaIcmsInterestadual?.toString() ?? '';
      
      _ncmController.text = p.ncm ?? '';
      _isDefault = p.isDefault;
    } else {
      _cfopController.text = '5102';
      _csosnSelected = '102';
      _icmsCstSelected = '00';
      _pisCstSelected = '07';
      _cofinsCstSelected = '07';
      _ipiCstSelected = '99';
      _ibsCstSelected = '01';
      _cbsCstSelected = '01';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cfopController.dispose();
    _aliquotaIcmsController.dispose();
    _aliquotaPisController.dispose();
    _aliquotaCofinsController.dispose();
    _aliquotaIbsController.dispose();
    _aliquotaCbsController.dispose();
    _aliquotaIpiController.dispose();
    _mvaController.dispose();
    _reducaoBaseIcmsController.dispose();
    _aliquotaFcpController.dispose();
    _aliquotaIcmsInterestadualController.dispose();
    _ncmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.perfil == null ? 'Novo Perfil Tributário' : 'Editar Perfil Tributário',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _buildTextField(_nomeController, 'Nome do Perfil', 'Ex: Bebidas Frias, Lucro Presumido Geral', true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(_cfopController, 'CFOP Padrão', 'Ex: 5102', true),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(_ncmController, 'NCM Padrão (Opcional)', 'Ex: 22011000', false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Regime de Tributação da Empresa', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: _regimeSimples,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) => setState(() => _regimeSimples = val!),
                        ),
                        const Text('Simples Nacional', style: TextStyle(color: Colors.white70)),
                        const SizedBox(width: 16),
                        Radio<bool>(
                          value: false,
                          groupValue: _regimeSimples,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) => setState(() => _regimeSimples = val!),
                        ),
                        const Text('Regime Normal / Lucro Presumido (CST)', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_regimeSimples)
                      _buildDropdownField(
                        label: 'CSOSN Padrão',
                        value: _csosnSelected,
                        options: _csosnOptions,
                        onChanged: (v) => setState(() => _csosnSelected = v),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildDropdownField(
                              label: 'CST ICMS Padrão',
                              value: _icmsCstSelected,
                              options: _cstIcmsOptions,
                              onChanged: (v) => setState(() => _icmsCstSelected = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _buildTextField(_aliquotaIcmsController, 'Alíquota ICMS (%)', 'Ex: 18.00', false, keyboardType: TextInputType.number),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdownField(
                            label: 'CST PIS',
                            value: _pisCstSelected,
                            options: _cstPisCofinsOptions,
                            onChanged: (v) => setState(() => _pisCstSelected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_aliquotaPisController, 'Alíquota PIS (%)', 'Ex: 0.65', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdownField(
                            label: 'CST COFINS',
                            value: _cofinsCstSelected,
                            options: _cstPisCofinsOptions,
                            onChanged: (v) => setState(() => _cofinsCstSelected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_aliquotaCofinsController, 'Alíquota COFINS (%)', 'Ex: 3.00', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.add_moderator, color: Colors.blueAccent, size: 16),
                          SizedBox(width: 8),
                          Text('Impostos de ST, IPI e Reduções', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdownField(
                            label: 'CST do IPI',
                            value: _ipiCstSelected,
                            options: _cstIpiOptions,
                            onChanged: (v) => setState(() => _ipiCstSelected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_aliquotaIpiController, 'Alíquota IPI (%)', 'Ex: 5.00', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(_mvaController, 'MVA / IVA (%)', 'Ex: 40.00', false, keyboardType: TextInputType.number),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(_reducaoBaseIcmsController, 'Redução Base ICMS (%)', 'Ex: 20.00', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(_aliquotaFcpController, 'FCP / FECOP (%)', 'Ex: 2.00', false, keyboardType: TextInputType.number),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(_aliquotaIcmsInterestadualController, 'ICMS Interestadual (%)', 'Ex: 12.00', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.gavel, color: Colors.purpleAccent, size: 16),
                          SizedBox(width: 8),
                          Text('Reforma Tributária (Transição)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdownField(
                            label: 'CST IBS',
                            value: _ibsCstSelected,
                            options: _cstIbsCbsOptions,
                            onChanged: (v) => setState(() => _ibsCstSelected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_aliquotaIbsController, 'Alíquota IBS (%)', 'Ex: 17.70', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdownField(
                            label: 'CST CBS',
                            value: _cbsCstSelected,
                            options: _cstIbsCbsOptions,
                            onChanged: (v) => setState(() => _cbsCstSelected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildTextField(_aliquotaCbsController, 'Alíquota CBS (%)', 'Ex: 8.80', false, keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('Definir como Perfil Padrão', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Produtos sem impostos específicos usarão estas regras.', style: TextStyle(color: Colors.white30, fontSize: 11)),
                      value: _isDefault,
                      activeColor: Colors.blueAccent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setState(() => _isDefault = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white30)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _salvar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Salvar Perfil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<Map<String, String>> options,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = options.any((o) => o['value'] == value) ? value : null;

    return DropdownButtonFormField<String?>(
      value: validValue,
      isExpanded: true,
      dropdownColor: const Color(0xFF161621),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF161621),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: options.map((opt) {
        return DropdownMenuItem<String?>(
          value: opt['value'],
          child: Text(
            opt['label'] ?? '',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String placeholder,
    bool required, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
        hintText: placeholder,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF161621),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueAccent, width: 1)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: required
          ? (val) {
              if (val == null || val.trim().isEmpty) return 'Campo obrigatório';
              return null;
            }
          : null,
    );
  }

  void _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final ds = Provider.of<DataService>(context, listen: false);
    final id = widget.perfil?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

    final perfil = PerfilTributario(
      id: id,
      nome: _nomeController.text.trim(),
      cfop: _cfopController.text.trim(),
      csosn: _regimeSimples ? _csosnSelected : null,
      icmsCst: !_regimeSimples ? _icmsCstSelected : null,
      aliquotaIcms: double.tryParse(_aliquotaIcmsController.text),
      pisCst: _pisCstSelected,
      aliquotaPis: double.tryParse(_aliquotaPisController.text),
      cofinsCst: _cofinsCstSelected,
      aliquotaCofins: double.tryParse(_aliquotaCofinsController.text),
      
      cstIbs: _ibsCstSelected,
      aliquotaIbs: double.tryParse(_aliquotaIbsController.text),
      cstCbs: _cbsCstSelected,
      aliquotaCbs: double.tryParse(_aliquotaCbsController.text),
      
      ipiCst: _ipiCstSelected,
      aliquotaIpi: double.tryParse(_aliquotaIpiController.text),
      mva: double.tryParse(_mvaController.text),
      reducaoBaseIcms: double.tryParse(_reducaoBaseIcmsController.text),
      aliquotaFcp: double.tryParse(_aliquotaFcpController.text),
      aliquotaIcmsInterestadual: double.tryParse(_aliquotaIcmsInterestadualController.text),
      
      ncm: _ncmController.text.trim(),
      isDefault: _isDefault,
    );

    try {
      await ds.salvarPerfilTributario(perfil);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil tributário salvo com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
