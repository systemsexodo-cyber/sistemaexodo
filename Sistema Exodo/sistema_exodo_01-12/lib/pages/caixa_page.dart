import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/caixa.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'home_page.dart';

/// Página de gerenciamento de caixa
class CaixaPage extends StatefulWidget {
  const CaixaPage({super.key});

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Caixa'),
          backgroundColor: Colors.transparent,
        ),
        body: Consumer<DataService>(
          builder: (context, dataService, child) {
            final caixaAberto = dataService.caixaAberto;
            final aberturaAtual = dataService.aberturaCaixaAtual;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card de status do caixa - Moderno e Inteligente
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: caixaAberto
                            ? [
                                Colors.green.withOpacity(0.3),
                                Colors.greenAccent.withOpacity(0.1),
                              ]
                            : [
                                Colors.grey.withOpacity(0.3),
                                Colors.grey.withOpacity(0.1),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: caixaAberto
                            ? Colors.green.withOpacity(0.5)
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: caixaAberto
                              ? Colors.green.withOpacity(0.3)
                              : Colors.grey.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: caixaAberto
                                        ? [
                                            Colors.green.withOpacity(0.4),
                                            Colors.greenAccent.withOpacity(0.2),
                                          ]
                                        : [
                                            Colors.grey.withOpacity(0.4),
                                            Colors.grey.withOpacity(0.2),
                                          ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: caixaAberto
                                          ? Colors.green.withOpacity(0.5)
                                          : Colors.grey.withOpacity(0.3),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  caixaAberto
                                      ? Icons.lock_open_rounded
                                      : Icons.lock_rounded,
                                  color: caixaAberto
                                      ? Colors.greenAccent
                                      : Colors.grey,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: caixaAberto
                                                ? Colors.green.withOpacity(0.3)
                                                : Colors.grey.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            caixaAberto ? 'ABERTO' : 'FECHADO',
                                            style: TextStyle(
                                              color: caixaAberto
                                                  ? Colors.greenAccent
                                                  : Colors.grey,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (aberturaAtual != null) ...[
                                      Text(
                                        aberturaAtual.numero,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: Colors.white.withOpacity(0.6),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Aberto em: ${formatoData.format(aberturaAtual.dataAbertura)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.white.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (aberturaAtual.valorInicial > 0) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.blue.withOpacity(0.4),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.account_balance_wallet,
                                                color: Colors.blue,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Valor inicial: ${formatoMoeda.format(aberturaAtual.valorInicial)}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ] else ...[
                                      Text(
                                        'Nenhum caixa aberto',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Botões de ação modernos
                          if (!caixaAberto)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green.withOpacity(0.8),
                                    Colors.greenAccent.withOpacity(0.6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.4),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _mostrarDialogoAbertura(context, dataService),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.lock_open_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Abrir Caixa',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            // Botões de Sangria e Suprimento
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.orange.withOpacity(0.8),
                                          Colors.orangeAccent.withOpacity(0.6),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.withOpacity(0.4),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _mostrarDialogoSangria(context, dataService),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 18),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.remove_circle_outline,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                              const SizedBox(width: 12),
                                              const Text(
                                                'Sangria',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.blue.withOpacity(0.8),
                                          Colors.blueAccent.withOpacity(0.6),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.4),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _mostrarDialogoSuprimento(context, dataService),
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 18),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.add_circle_outline,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                              const SizedBox(width: 12),
                                              const Text(
                                                'Suprimento',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.withOpacity(0.8),
                                    Colors.redAccent.withOpacity(0.6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.4),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _mostrarDialogoFechamento(context, dataService),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.lock_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Fechar Caixa',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Histórico de aberturas
                  Text(
                    'Histórico de Caixas',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  if (dataService.aberturasCaixa.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.point_of_sale_outlined,
                                size: 64,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhum caixa registrado',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    // Mostrar todos os caixas (abertos e fechados)
                    // Criar lista de caixas com seus fechamentos e ordenar
                    ...() {
                      // Criar lista de caixas com seus fechamentos
                      final caixasComFechamento = dataService.aberturasCaixa.map((abertura) {
                        final fechamento = dataService.fechamentosCaixa
                            .where((f) => f.aberturaCaixaId == abertura.id)
                            .firstOrNull;
                        return MapEntry(abertura, fechamento);
                      }).toList();
                      
                      // Ordenar: abertos primeiro, depois fechados (mais recentes primeiro em cada grupo)
                      caixasComFechamento.sort((a, b) {
                        // Primeiro ordenar por status: abertos primeiro, depois fechados
                        final aAberto = a.value == null;
                        final bAberto = b.value == null;
                        if (aAberto != bAberto) {
                          return aAberto ? -1 : 1; // Abertos primeiro
                        }
                        // Se ambos têm o mesmo status, ordenar por data (mais recente primeiro)
                        return b.key.dataAbertura.compareTo(a.key.dataAbertura);
                      });
                      
                      // Retornar lista de widgets dos caixas
                      return caixasComFechamento.map((entry) {
                        return _buildCardCaixa(entry.key, entry.value, formatoMoeda, formatoData);
                      }).toList();
                    }(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardCaixa(
    AberturaCaixa abertura,
    FechamentoCaixa? fechamento,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isAberto = fechamento == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isAberto ? Icons.lock_open : Icons.lock,
                    color: isAberto ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abertura.numero,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        formatoData.format(abertura.dataAbertura),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAberto ? 'Aberto' : 'Fechado',
                    style: TextStyle(
                      color: isAberto ? Colors.green : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valor Inicial',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(abertura.valorInicial),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (fechamento != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Valor Real',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorReal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (fechamento != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valor Esperado',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorEsperado),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Diferença',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.diferenca),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: fechamento.diferenca >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Fechado em: ${formatoData.format(fechamento.dataFechamento)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoAbertura(BuildContext context, DataService dataService) {
    final valorController = TextEditingController(text: '0.00');
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Abrir Caixa', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor Inicial (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor inicial';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor < 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomePage()),
                (route) => false,
              );
            },
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.abrirCaixaComValor(
                    valor,
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Caixa aberto com ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao abrir caixa: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Abrir Caixa'),
          ),
        ],
      ),
    );
  }

  // Função auxiliar para construir linha de informação
  Widget _buildInfoRow(String label, String value, IconData icon, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.6), size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white.withOpacity(0.9),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoFechamento(BuildContext context, DataService dataService) {
    final abertura = dataService.aberturaCaixaAtual;
    if (abertura == null) return;

    final valorEsperadoController = TextEditingController();
    final valorRealController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    // Calcular valor esperado baseado nas vendas desde a abertura do caixa
    final vendasDoCaixa = dataService.vendasBalcao.where((v) {
      return v.dataVenda.isAfter(abertura.dataAbertura) ||
          v.dataVenda.isAtSameMomentAs(abertura.dataAbertura);
    }).toList();

    // Calcular apenas vendas pagas em dinheiro ou PIX (que entram no caixa físico)
    // IMPORTANTE: Vendas com tipoPagamento "outro" são vendas salvas e NÃO devem ser contabilizadas
    final totalVendas = vendasDoCaixa.fold(0.0, (sum, v) {
      // Excluir vendas canceladas e vendas salvas (tipoPagamento "outro")
      if (v.isCancelada || v.tipoPagamento == TipoPagamento.outro) {
        return sum;
      }
      // Somar apenas pagamentos em dinheiro ou PIX
      if (v.tipoPagamento == TipoPagamento.dinheiro ||
          v.tipoPagamento == TipoPagamento.pix) {
        return sum + v.valorTotal;
      }
      return sum;
    });
    
    // Incluir também pedidos recebidos no período
    // IMPORTANTE: Pedidos com pagamento tipo "outro" são vendas salvas e NÃO devem ser contabilizadas
    // Considerar apenas pagamentos em dinheiro ou PIX que foram recebidos após a abertura
    final pedidosRecebidos = dataService.pedidos.where((p) {
      // Excluir pedidos que têm apenas pagamento tipo "outro" (vendas salvas)
      final temApenasOutro = p.pagamentos.isNotEmpty && 
          p.pagamentos.every((pag) => pag.tipo == TipoPagamento.outro);
      if (temApenasOutro) return false;
      
      // Verificar se tem algum pagamento recebido após a abertura do caixa
      return p.pagamentos.any((pag) {
        if (!pag.recebido || pag.dataRecebimento == null) return false;
        // Verificar se o recebimento foi após a abertura do caixa
        if (pag.dataRecebimento!.isBefore(abertura.dataAbertura)) return false;
        // Excluir pagamentos tipo "outro" (vendas salvas)
        if (pag.tipo == TipoPagamento.outro) return false;
        // Considerar apenas dinheiro ou PIX
        return pag.tipo == TipoPagamento.dinheiro || pag.tipo == TipoPagamento.pix;
      });
    }).toList();
    
    // Calcular total de pedidos recebidos em dinheiro ou PIX
    final totalPedidosRecebidos = pedidosRecebidos.fold(0.0, (sum, p) {
      // Somar apenas os pagamentos recebidos após a abertura em dinheiro ou PIX
      // Excluir pagamentos tipo "outro" (vendas salvas)
      return sum + p.pagamentos.where((pag) {
        if (!pag.recebido || pag.dataRecebimento == null) return false;
        if (pag.dataRecebimento!.isBefore(abertura.dataAbertura)) return false;
        // Excluir pagamentos tipo "outro" (vendas salvas)
        if (pag.tipo == TipoPagamento.outro) return false;
        return pag.tipo == TipoPagamento.dinheiro || pag.tipo == TipoPagamento.pix;
      }).fold(0.0, (pagSum, pag) => pagSum + pag.valor);
    });
    
    // Calcular sangrias e suprimentos do caixa atual
    final sangriasCaixaAtual = dataService.getSangriasCaixaAtual();
    final suprimentosCaixaAtual = dataService.getSuprimentosCaixaAtual();
    final totalSangrias = sangriasCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos = suprimentosCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    
    final valorEsperadoCalculado = abertura.valorInicial + totalVendas + totalPedidosRecebidos - totalSangrias + totalSuprimentos;
    valorEsperadoController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');
    valorRealController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.redAccent.withOpacity(0.3),
                Colors.red.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fechar Caixa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Preencha os dados para finalizar',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Informações da abertura - Card melhorado
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.2),
                        Colors.blue.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.4), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.point_of_sale, color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            abertura.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Data de Abertura',
                        formatoData.format(abertura.dataAbertura),
                        Icons.calendar_today,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Valor Inicial',
                        formatoMoeda.format(abertura.valorInicial),
                        Icons.account_balance_wallet,
                        Colors.greenAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Vendas Diretas',
                        formatoMoeda.format(totalVendas),
                        Icons.shopping_cart,
                        Colors.blueAccent,
                      ),
                      if (totalPedidosRecebidos > 0) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Pedidos Recebidos',
                          formatoMoeda.format(totalPedidosRecebidos),
                          Icons.receipt_long,
                          Colors.greenAccent,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Total de Vendas',
                        formatoMoeda.format(totalVendas + totalPedidosRecebidos),
                        Icons.attach_money,
                        Colors.amber,
                      ),
                      if (totalSangrias > 0) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Total de Sangrias',
                          formatoMoeda.format(totalSangrias),
                          Icons.remove_circle,
                          Colors.orangeAccent,
                        ),
                      ],
                      if (totalSuprimentos > 0) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Total de Suprimentos',
                          formatoMoeda.format(totalSuprimentos),
                          Icons.add_circle,
                          Colors.blueAccent,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calculate, color: Colors.greenAccent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Valor Esperado',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              formatoMoeda.format(valorEsperadoCalculado),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Seção de Valores
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.attach_money, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Valores do Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: valorEsperadoController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Esperado (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.calculate, color: Colors.blueAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor esperado';
                          }
                          final valor = double.tryParse(
                            value.replaceAll('.', '').replaceAll(',', '.'),
                          );
                          if (valor == null || valor < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: valorRealController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Real no Caixa (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.account_balance_wallet, color: Colors.greenAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor real';
                          }
                          final valor = double.tryParse(
                            value.replaceAll('.', '').replaceAll(',', '.'),
                          );
                          if (valor == null || valor < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Informações do Responsável
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withOpacity(0.15),
                        Colors.purple.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline, color: Colors.purpleAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Responsável pelo Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: responsavelController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Nome Completo',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Ex: João Silva',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.person, color: Colors.purpleAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                        // Campo agora é opcional - sem validação obrigatória
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Observações
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.note_alt, color: Colors.orangeAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Observações',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: observacaoController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Informe observações sobre o fechamento:\n• Diferenças encontradas\n• Problemas identificados\n• Observações importantes',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          prefixIcon: const Icon(Icons.edit_note, color: Colors.orangeAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
                          ),
                        ),
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Informação sobre campos obrigatórios
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Certifique-se de preencher todos os campos obrigatórios antes de fechar o caixa.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              print('>>> [Fechar Caixa] ========== BOTÃO PRESSIONADO ==========');
              
              // Teste imediato - mostrar que o botão funciona
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Processando fechamento...'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
              
              // Verificar se formKey existe
              if (formKey.currentState == null) {
                print('>>> [Fechar Caixa] ERRO: formKey.currentState é null!');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Erro: Formulário não inicializado'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              
              // Validar formulário
              print('>>> [Fechar Caixa] Validando formulário...');
              final isValid = formKey.currentState!.validate();
              print('>>> [Fechar Caixa] Resultado da validação: $isValid');
              
              if (!isValid) {
                print('>>> [Fechar Caixa] Validação do formulário falhou');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, preencha todos os campos obrigatórios corretamente'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
                return;
              }
              
              // Salvar estado do formulário
              formKey.currentState!.save();
              
              print('>>> [Fechar Caixa] Validação passou');
              
              try {
                print('>>> [Fechar Caixa] Processando valores...');
                
                final valorEsperadoStr = valorEsperadoController.text.replaceAll('.', '').replaceAll(',', '.');
                final valorRealStr = valorRealController.text.replaceAll('.', '').replaceAll(',', '.');
                
                print('>>> [Fechar Caixa] Valor esperado (string): $valorEsperadoStr');
                print('>>> [Fechar Caixa] Valor real (string): $valorRealStr');
                
                final valorEsperado = double.tryParse(valorEsperadoStr) ?? 0.0;
                final valorReal = double.tryParse(valorRealStr) ?? 0.0;
                
                print('>>> [Fechar Caixa] Valor esperado (double): $valorEsperado');
                print('>>> [Fechar Caixa] Valor real (double): $valorReal');
                
                // Calcular diferença
                final diferenca = valorReal - valorEsperado;
                final responsavel = responsavelController.text.trim().isEmpty 
                    ? null 
                    : responsavelController.text.trim();
                
                print('>>> [Fechar Caixa] Responsável: ${responsavel ?? "Não informado"}');
                print('>>> [Fechar Caixa] Diferença: $diferenca');

                // Confirmar fechamento se houver diferença significativa
                if (diferenca.abs() > 0.01) {
                  print('>>> [Fechar Caixa] Diferença detectada, mostrando diálogo de confirmação');
                  final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (confirmContext) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: Row(
                          children: [
                            Icon(
                              diferenca > 0 ? Icons.add_circle : Icons.remove_circle,
                              color: diferenca > 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Diferença Detectada',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Foi detectada uma diferença no fechamento:',
                              style: TextStyle(color: Colors.white.withOpacity(0.8)),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (diferenca > 0 ? Colors.green : Colors.red)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: (diferenca > 0 ? Colors.green : Colors.red)
                                      .withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    diferenca > 0 ? 'Sobra:' : 'Falta:',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    formatoMoeda.format(diferenca.abs()),
                                    style: TextStyle(
                                      color: diferenca > 0
                                          ? Colors.greenAccent
                                          : Colors.redAccent,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Deseja continuar com o fechamento?',
                              style: TextStyle(color: Colors.white.withOpacity(0.8)),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmContext, false),
                            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(confirmContext, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: diferenca > 0 ? Colors.green : Colors.red,
                            ),
                            child: const Text('Confirmar Fechamento'),
                          ),
                        ],
                      ),
                    );

                  if (confirmar != true) {
                    print('>>> [Fechar Caixa] Fechamento cancelado pelo usuário');
                    return;
                  }
                  print('>>> [Fechar Caixa] Confirmação recebida');
                }

                print('>>> [Fechar Caixa] Chamando registrarFechamentoCaixa...');
                  
                  final fechamento = await dataService.registrarFechamentoCaixa(
                    valorEsperado: valorEsperado,
                    valorReal: valorReal,
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavel,
                  );
                  
                  print('>>> [Fechar Caixa] Fechamento registrado: ${fechamento != null ? "SUCESSO" : "FALHOU"}');

                  if (fechamento == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Erro: Não foi possível fechar o caixa. Verifique se há uma abertura ativa.'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                    return;
                  }

                  if (context.mounted) {
                    print('>>> [Fechar Caixa] Fechando diálogo e mostrando mensagem de sucesso');
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                (responsavel != null && responsavel.isNotEmpty)
                                    ? 'Caixa fechado com sucesso por $responsavel!'
                                    : 'Caixa fechado com sucesso!',
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e, stackTrace) {
                  print('>>> [Fechar Caixa] ERRO: $e');
                  print('>>> [Fechar Caixa] StackTrace: $stackTrace');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao fechar caixa: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Fechar Caixa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSangria(BuildContext context, DataService dataService) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.remove_circle, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Registrar Sangria', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSangria(
                    valor: valor,
                    motivo: motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Sangria registrada: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar sangria: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSuprimento(BuildContext context, DataService dataService) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text('Registrar Suprimento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSuprimento(
                    valor: valor,
                    motivo: motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Suprimento registrado: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar suprimento: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }
}

