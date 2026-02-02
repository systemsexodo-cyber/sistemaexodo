import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/empresa.dart';
import '../theme.dart';

class ConfiguracoesAgendaPage extends StatefulWidget {
  const ConfiguracoesAgendaPage({super.key});

  @override
  State<ConfiguracoesAgendaPage> createState() => _ConfiguracoesAgendaPageState();
}

class _ConfiguracoesAgendaPageState extends State<ConfiguracoesAgendaPage> {
  final _novoBairroController = TextEditingController();
  final _taxaController = TextEditingController();
  final _taxaBuscaController = TextEditingController();
  final _taxaSolevaController = TextEditingController();
  List<Map<String, dynamic>> _bairrosConfig = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  void _carregarConfiguracoes() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa != null && empresa.configuracoes != null) {
      final config = empresa.configuracoes!;
      final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
      
      final bairrosData = (config['bairrosTaxiDogV2'] ?? agendamentoConfig['bairrosTaxiDogV2']) as List<dynamic>?;
      
      if (bairrosData != null) {
        _bairrosConfig = bairrosData.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        final bairrosAntigos = (config['bairrosTaxiDog'] ?? agendamentoConfig['bairrosTaxiDog']) as List<dynamic>?;
        if (bairrosAntigos != null) {
          _bairrosConfig = bairrosAntigos.map((e) => {
            'bairro': e.toString(), 
            'taxa': 0.0,
            'taxaBusca': 0.0,
            'taxaSoleva': 0.0,
          }).toList();
        }
      }
    }
  }

  Future<void> _salvarConfiguracoes() async {
    setState(() => _isLoading = true);
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;

    if (empresa != null) {
      final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      final agendamentoConfig = Map<String, dynamic>.from(novasConfigs['agendamento'] ?? {});
      
      agendamentoConfig['bairrosTaxiDogV2'] = _bairrosConfig;
      agendamentoConfig['bairrosTaxiDog'] = _bairrosConfig.map((e) => e['bairro']).toList();
      
      novasConfigs['agendamento'] = agendamentoConfig;
      novasConfigs['bairrosTaxiDogV2'] = _bairrosConfig;
      novasConfigs['bairrosTaxiDog'] = _bairrosConfig.map((e) => e['bairro']).toList();

      final novaEmpresa = empresa.copyWith(configuracoes: novasConfigs);
      
      try {
        await dataService.atualizarDadosEmpresa(novaEmpresa);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configurações salvas com sucesso!'), backgroundColor: Colors.green),
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
    setState(() => _isLoading = false);
  }

  void _adicionarBairro() {
    final nome = _novoBairroController.text.trim();
    final taxa = double.tryParse(_taxaController.text.replaceAll(',', '.')) ?? 0.0;
    final taxaBusca = double.tryParse(_taxaBuscaController.text.replaceAll(',', '.')) ?? 0.0;
    final taxaSoleva = double.tryParse(_taxaSolevaController.text.replaceAll(',', '.')) ?? 0.0;

    if (nome.isNotEmpty) {
      setState(() {
        // Verificar se já existe (case-insensitive)
        final index = _bairrosConfig.indexWhere(
          (element) => element['bairro'].toString().toLowerCase() == nome.toLowerCase()
        );

        if (index != -1) {
          // Atualizar existente
          _bairrosConfig[index] = {
            'bairro': nome, // Mantém o nome digitado agora (pode mudar o casing)
            'taxa': taxa,
            'taxaBusca': taxaBusca,
            'taxaSoleva': taxaSoleva,
          };
        } else {
          // Adicionar novo
          _bairrosConfig.add({
            'bairro': nome, 
            'taxa': taxa,
            'taxaBusca': taxaBusca,
            'taxaSoleva': taxaSoleva,
          });
        }
        
        _novoBairroController.clear();
        _taxaController.clear();
        _taxaBuscaController.clear();
        _taxaSolevaController.clear();
      });
    }
  }

  void _removerBairro(int index) {
    setState(() {
      _bairrosConfig.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Configurações de Agendamento'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              icon: const Icon(Icons.save, color: Colors.greenAccent),
              onPressed: _salvarConfiguracoes,
              tooltip: 'Salvar Alterações',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildFormNovoBairro(),
            const SizedBox(height: 32),
            const Text(
              'Bairros e Taxas Cadastradas',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildListaBairros(),
            const SizedBox(height: 32),
            if (_bairrosConfig.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvarConfiguracoes,
                icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
                label: Text(_isLoading ? 'Salvando...' : 'Salvar Todas as Taxas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: Colors.green.withOpacity(0.5),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.local_shipping_rounded, color: Colors.blueAccent, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Taxas de Taxi Dog',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Configure o valor cobrado para cada bairro atendido pelo Taxi Dog.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormNovoBairro() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _novoBairroController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Bairro',
              labelStyle: const TextStyle(color: Colors.white60),
              hintText: 'Ex: Centro',
              prefixIcon: const Icon(Icons.location_on, color: Colors.white30),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taxaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Leva e Traz (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.swap_horiz, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxaBuscaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Só Busca (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.arrow_downward, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxaSolevaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Só Leva (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.arrow_upward, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _novoBairroController,
            builder: (context, value, child) {
              final nome = value.text.trim().toLowerCase();
              final jaExiste = _bairrosConfig.any((b) => b['bairro'].toString().toLowerCase() == nome);
              
              return ElevatedButton.icon(
                onPressed: _adicionarBairro,
                icon: Icon(jaExiste ? Icons.edit : Icons.add),
                label: Text(jaExiste ? 'Atualizar Bairro Existente' : 'Adicionar Novo Bairro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: jaExiste ? Colors.orangeAccent : Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListaBairros() {
    if (_bairrosConfig.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              const Text('Nenhum bairro cadastrado ainda.', style: TextStyle(color: Colors.white24)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _bairrosConfig.length,
      itemBuilder: (context, index) {
        final item = _bairrosConfig[index];
        final double taxa = (item['taxa'] as num?)?.toDouble() ?? 0.0;
        final double taxaBusca = (item['taxaBusca'] as num?)?.toDouble() ?? 0.0;
        final double taxaSoleva = (item['taxaSoleva'] as num?)?.toDouble() ?? 0.0;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: const Icon(Icons.location_city_rounded, color: Colors.white70, size: 20),
            ),
            title: Text(item['bairro'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildMiniBadge('Leva/Traz: R\$ ${taxa.toStringAsFixed(2)}', Colors.greenAccent),
                    const SizedBox(width: 8),
                    _buildMiniBadge('Busca: R\$ ${taxaBusca.toStringAsFixed(2)}', Colors.orangeAccent),
                    const SizedBox(width: 8),
                    _buildMiniBadge('Leva: R\$ ${taxaSoleva.toStringAsFixed(2)}', Colors.blueAccent),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                  onPressed: () {
                    setState(() {
                      _novoBairroController.text = item['bairro'] ?? '';
                      _taxaController.text = taxa.toStringAsFixed(2).replaceAll('.', ',');
                      _taxaBuscaController.text = taxaBusca.toStringAsFixed(2).replaceAll('.', ',');
                      _taxaSolevaController.text = taxaSoleva.toStringAsFixed(2).replaceAll('.', ',');
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () => _removerBairro(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
