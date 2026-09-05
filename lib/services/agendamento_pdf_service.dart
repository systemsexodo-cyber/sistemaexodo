import 'dart:typed_data';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/agendamento_servico.dart';
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../models/pet.dart';
import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../services/impressao_service.dart';

/// Serviço para geração de PDF de agendamento de serviço
class AgendamentoPdfService {
  /// Gera PDF do agendamento com dados do pedido
  static Future<Uint8List> gerarPDF({
    required AgendamentoServico agendamento,
    Pedido? pedido,
    DataService? dataService, // Opcional para buscar cliente atualizado
  }) async {
    try {
      // Buscar cliente e pet atualizados do DataService se disponível
      AgendamentoServico agendamentoComCliente = agendamento;
      if (dataService != null && agendamento.clienteId != null) {
        try {
          final clienteAtualizado = dataService.clientes.firstWhere(
            (c) => c.id == agendamento.clienteId,
          );
          
          // Buscar pet se houver petId
          Pet? petAtualizado;
          if (agendamento.petId != null && clienteAtualizado.pets.isNotEmpty) {
            try {
              petAtualizado = clienteAtualizado.pets.firstWhere(
                (p) => p.id == agendamento.petId,
              );
            } catch (e) {
              print('⚠ Pet não encontrado: ${agendamento.petId}');
            }
          }
          
          agendamentoComCliente = agendamento.copyWith(
            cliente: clienteAtualizado,
            pet: petAtualizado ?? agendamento.pet,
          );
          
          // Debug: verificar se as observações foram carregadas
          print('✓ Cliente encontrado: ${clienteAtualizado.nome}');
          print('✓ Pet encontrado: ${petAtualizado?.nome ?? "Nenhum"}');
          if (clienteAtualizado.observacoes != null && clienteAtualizado.observacoes!.trim().isNotEmpty) {
            print('✓ Observações do cliente carregadas: "${clienteAtualizado.observacoes}"');
          } else {
            print('⚠ Observações do cliente vazias ou null');
          }
          if (clienteAtualizado.dadosExtras != null && clienteAtualizado.dadosExtras!.isNotEmpty) {
            print('✓ Dados extras do cliente carregados: ${clienteAtualizado.dadosExtras}');
          } else {
            print('⚠ Dados extras do cliente vazios ou null');
          }
          
          // Debug: verificar informações do agendamento
          print('✓ Agendamento - Número: ${agendamentoComCliente.numero}');
          print('✓ Agendamento - Serviço: ${agendamentoComCliente.servico?.nome ?? "N/A"}');
          print('✓ Agendamento - Status: ${agendamentoComCliente.status}');
          print('✓ Agendamento - Data: ${agendamentoComCliente.dataAgendamento}');
          print('✓ Agendamento - Observações: ${agendamentoComCliente.observacoes ?? "N/A"}');
        } catch (e) {
          // Se não encontrar, usar o cliente do agendamento
          print('⚠ Cliente não encontrado no DataService: $e');
          if (agendamento.cliente != null) {
            print('  Usando cliente do agendamento: ${agendamento.cliente?.nome}');
            if (agendamento.cliente?.observacoes != null) {
              print('  Observações no agendamento: ${agendamento.cliente?.observacoes}');
            }
          } else {
            print('  ⚠⚠⚠ Cliente é NULL no agendamento!');
          }
        }
      } else {
        if (dataService == null) {
          print('⚠ DataService não fornecido - usando cliente do agendamento');
        }
        if (agendamento.clienteId == null) {
          print('⚠ ClienteId é null no agendamento');
        }
        if (agendamento.cliente != null) {
          // Debug mesmo sem DataService
          if (agendamento.cliente!.observacoes != null && agendamento.cliente!.observacoes!.trim().isNotEmpty) {
            print('✓ Observações do cliente no agendamento: "${agendamento.cliente!.observacoes}"');
          }
          if (agendamento.cliente!.dadosExtras != null && agendamento.cliente!.dadosExtras!.isNotEmpty) {
            print('✓ Dados extras do cliente no agendamento: ${agendamento.cliente!.dadosExtras}');
          }
        } else {
          print('⚠⚠⚠ Cliente é NULL no agendamento e DataService não disponível!');
        }
      }
      
      final pdf = pw.Document();
      final formatoData = DateFormat('dd/MM/yyyy');
      final formatoHora = DateFormat('HH:mm');
      final formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // CABEÇALHO COM NOME DO CLIENTE NO TOPO
                _buildCabecalhoComCliente(agendamentoComCliente, formatoDataHora),
                pw.SizedBox(height: 24),
                
                // DADOS DO AGENDAMENTO (completo com número)
                _buildDadosAgendamento(agendamentoComCliente, formatoData, formatoHora),
                pw.SizedBox(height: 20),
                
                // DADOS DO CLIENTE
                _buildDadosCliente(agendamentoComCliente),
                pw.SizedBox(height: 20),
                
                // DADOS DO PET (se houver)
                if (agendamentoComCliente.pet != null) ...[
                  _buildDadosPet(agendamentoComCliente.pet!),
                  pw.SizedBox(height: 20),
                ],
                
                // Informação de entrega (se houver)
                if (agendamentoComCliente.tipoEntrega != null) ...[
                  _buildInfoEntrega(agendamentoComCliente),
                  pw.SizedBox(height: 20),
                ],
                
                // DADOS DO PEDIDO (se houver)
                if (pedido != null) ...[
                  _buildDadosPedido(pedido, formatoData),
                  pw.SizedBox(height: 20),
                ],
                
                // OBSERVAÇÕES NA PARTE DE BAIXO (tudo junto) - SEMPRE MOSTRAR
                pw.SizedBox(height: 20), // Espaçamento antes das observações
                _buildSecaoObservacoes(agendamentoComCliente, pedido),
                
                // Rodapé
                pw.Spacer(),
                _buildRodape(),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF do agendamento: $e');
    }
  }

  static pw.Widget _buildCabecalhoComCliente(AgendamentoServico agendamento, DateFormat formatoDataHora) {
    final nomeCliente = agendamento.cliente?.nome ?? 'Cliente não informado';
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(24),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue700,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Título
          pw.Text(
            'AGENDAMENTO DE SERVIÇO',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 16),
          // Nome do cliente em destaque
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Text(
              nomeCliente.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          // Data de geração
          pw.Text(
            'Gerado em: ${formatoDataHora.format(DateTime.now())}',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey300,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDadosAgendamento(
    AgendamentoServico agendamento,
    DateFormat formatoData,
    DateFormat formatoHora,
  ) {
    final dataTermino = agendamento.dataAgendamento.add(Duration(minutes: agendamento.duracaoMinutos));
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'INFORMAÇÕES DO AGENDAMENTO',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 16),
          // Grid de informações em 2 colunas
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildLinhaInfo('Número', agendamento.numero),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Serviço', agendamento.servico?.nome ?? 'N/A'),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Data', formatoData.format(agendamento.dataAgendamento)),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Duração', '${agendamento.duracaoMinutos} minutos'),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildLinhaInfo('Hora Início', formatoHora.format(agendamento.dataAgendamento)),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Hora Término', formatoHora.format(dataTermino)),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Status', agendamento.status),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDadosCliente(AgendamentoServico agendamento) {
    if (agendamento.cliente == null) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          color: PdfColors.grey50,
        ),
        child: pw.Text(
          'Cliente não informado',
          style: const pw.TextStyle(fontSize: 11),
        ),
      );
    }

    final cliente = agendamento.cliente!;
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DADOS DO CLIENTE',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildLinhaInfo('Nome', cliente.nome),
                    pw.SizedBox(height: 10),
                    if (cliente.telefone.isNotEmpty)
                      _buildLinhaInfo('Telefone', cliente.telefone),
                    if (cliente.telefone.isNotEmpty) pw.SizedBox(height: 10),
                    if (cliente.email != null && cliente.email!.isNotEmpty)
                      _buildLinhaInfo('E-mail', cliente.email!),
                    if (cliente.email != null && cliente.email!.isNotEmpty) pw.SizedBox(height: 10),
                    if (cliente.cpfCnpj != null && cliente.cpfCnpj!.isNotEmpty)
                      _buildLinhaInfo(
                        cliente.tipoPessoa.name == 'fisica' ? 'CPF' : 'CNPJ',
                        cliente.cpfCnpj!,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (cliente.endereco != null && cliente.endereco!.isNotEmpty) ...[
                      _buildLinhaInfo(
                        'Endereço',
                        [
                          cliente.endereco,
                          cliente.numero,
                          cliente.complemento,
                        ].where((e) => e != null && e.isNotEmpty).join(', '),
                      ),
                      pw.SizedBox(height: 10),
                    ],
                    if (cliente.bairro != null && cliente.bairro!.isNotEmpty)
                      _buildLinhaInfo('Bairro', cliente.bairro!),
                    if (cliente.bairro != null && cliente.bairro!.isNotEmpty) pw.SizedBox(height: 10),
                    if (cliente.cidade != null && cliente.cidade!.isNotEmpty)
                      _buildLinhaInfo('Cidade', cliente.cidade!),
                    if (cliente.cidade != null && cliente.cidade!.isNotEmpty) pw.SizedBox(height: 10),
                    if (cliente.estado != null && cliente.estado!.isNotEmpty)
                      _buildLinhaInfo('Estado', cliente.estado!),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDadosPet(Pet pet) {
    final formatoData = DateFormat('dd/MM/yyyy');
    final infoPet = <String>[];
    
    // Nome e espécie (sempre presentes)
    infoPet.add('${pet.nome}${pet.especie != null && pet.especie!.isNotEmpty ? ' (${pet.especie})' : ''}');
    
    // Raça
    if (pet.raca != null && pet.raca!.isNotEmpty) {
      infoPet.add('Raça: ${pet.raca}');
    }
    
    // Tamanho
    if (pet.tamanho != null && pet.tamanho!.isNotEmpty) {
      infoPet.add('Tamanho: ${pet.tamanho}');
    }
    
    // Peso
    if (pet.peso != null) {
      infoPet.add('Peso: ${pet.peso} kg');
    }
    
    // Cor
    if (pet.cor != null && pet.cor!.isNotEmpty) {
      infoPet.add('Cor: ${pet.cor}');
    }
    
    // Sexo
    if (pet.sexo != null && pet.sexo!.isNotEmpty) {
      final sexoNome = pet.sexo == 'M' ? 'Macho' : (pet.sexo == 'F' ? 'Fêmea' : pet.sexo);
      infoPet.add('Sexo: $sexoNome');
    }
    
    // Data de nascimento e idade
    if (pet.dataNascimento != null) {
      infoPet.add('Data de Nascimento: ${formatoData.format(pet.dataNascimento!)}');
      if (pet.idadeAnos != null) {
        infoPet.add('Idade: ${pet.idadeAnos} ${pet.idadeAnos == 1 ? 'ano' : 'anos'}');
      }
    }
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange700, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: PdfColors.orange50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DADOS DO PET',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.orange700,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: infoPet.map((info) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text(
                      info,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  )).toList(),
                ),
              ),
              // Foto do pet (se houver)
              if (pet.fotoPath != null && pet.fotoPath!.isNotEmpty) ...[
                pw.SizedBox(width: 16),
                pw.Container(
                  width: 100,
                  height: 100,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.orange700, width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: _buildFotoPet(pet.fotoPath!),
                ),
              ],
            ],
          ),
          if (pet.observacoes != null && pet.observacoes!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.orange300),
            pw.SizedBox(height: 8),
            pw.Text(
              'Observações do Pet:',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange700,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              pet.observacoes!,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildInfoEntrega(AgendamentoServico agendamento) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: agendamento.tipoEntrega == 'Taxi Dog' 
              ? PdfColors.green700 
              : PdfColors.blue700, 
          width: 1.5,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: agendamento.tipoEntrega == 'Taxi Dog' 
            ? PdfColors.green50 
            : PdfColors.blue50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ENTREGA DO ANIMAL',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: agendamento.tipoEntrega == 'Taxi Dog' 
                  ? PdfColors.green700 
                  : PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Tipo: ${agendamento.tipoEntrega}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          if (agendamento.tipoEntrega == 'Taxi Dog') ...[
            if (agendamento.bairroEntrega != null && agendamento.bairroEntrega!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'Bairro: ${agendamento.bairroEntrega}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            if (agendamento.valorTaxiDog != null && agendamento.valorTaxiDog! > 0)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'Taxa: R\$ ${agendamento.valorTaxiDog!.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildFotoPet(String fotoPath) {
    try {
      final file = File(fotoPath);
      if (!file.existsSync()) {
        return pw.Center(
          child: pw.Text(
            'Foto não encontrada',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        );
      }
      
      final imageBytes = file.readAsBytesSync();
      final image = pw.MemoryImage(imageBytes);
      
      return pw.Container(
        decoration: pw.BoxDecoration(
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Image(
          image,
          fit: pw.BoxFit.cover, // Redimensiona para cobrir o espaço mantendo proporção
        ),
      );
    } catch (e) {
      print('Erro ao carregar foto do pet: $e');
      return pw.Center(
        child: pw.Text(
          'Erro ao carregar foto',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.red),
        ),
      );
    }
  }

  static pw.Widget _buildDadosPedido(Pedido pedido, DateFormat formatoData) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'DADOS DO PEDIDO',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 16),
          // Informações básicas em grid
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildLinhaInfo('Número', pedido.numero),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Data', formatoData.format(pedido.dataPedido)),
                    pw.SizedBox(height: 10),
                    _buildLinhaInfo('Status', pedido.status),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (pedido.clienteTelefone != null)
                      _buildLinhaInfo('Telefone', pedido.clienteTelefone!),
                    if (pedido.clienteTelefone != null) pw.SizedBox(height: 10),
                    if (pedido.clienteEndereco != null)
                      _buildLinhaInfo('Endereço', pedido.clienteEndereco!),
                    if (pedido.clienteEndereco != null) pw.SizedBox(height: 10),
                    _buildLinhaInfo('Total', _formatarMoeda(pedido.total)),
                  ],
                ),
              ),
            ],
          ),
          // Serviços e produtos
          if (pedido.servicos.isNotEmpty || pedido.produtos.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 12),
            if (pedido.servicos.isNotEmpty) ...[
              pw.Text(
                'SERVIÇOS',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue700,
                ),
              ),
              pw.SizedBox(height: 8),
              ...pedido.servicos.map((servico) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        servico.descricao,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Text(
                      _formatarMoeda(servico.valor + servico.valorAdicional),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
              pw.SizedBox(height: 8),
            ],
            if (pedido.produtos.isNotEmpty) ...[
              pw.Text(
                'PRODUTOS',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue700,
                ),
              ),
              pw.SizedBox(height: 8),
              ...pedido.produtos.map((produto) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${produto.nome} x${produto.quantidade}',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Text(
                      _formatarMoeda(produto.preco * produto.quantidade),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
              pw.SizedBox(height: 8),
            ],
            if (pedido.pagamentos.isNotEmpty) ...[
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Text(
                'PAGAMENTOS',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue700,
                ),
              ),
              pw.SizedBox(height: 8),
              ...pedido.pagamentos.map((pagamento) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        pagamento.tipo.nome,
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.Text(
                      _formatarMoeda(pagamento.valor),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildSecaoObservacoes(AgendamentoServico agendamento, Pedido? pedido) {
    final todasObservacoes = <String>[];
    
    // Debug detalhado
    print('═══════════════════════════════════════════════════════════');
    print('🔍 INICIANDO _buildSecaoObservacoes');
    print('   Cliente: ${agendamento.cliente?.nome ?? "NULL"}');
    print('   Cliente ID: ${agendamento.clienteId ?? "NULL"}');
    print('   Cliente objeto completo: ${agendamento.cliente != null ? "EXISTE" : "NULL"}');
    
    if (agendamento.cliente != null) {
      print('   📋 Observações: "${agendamento.cliente!.observacoes ?? "NULL"}"');
      print('   📋 Observações (isEmpty): ${agendamento.cliente!.observacoes?.isEmpty ?? true}');
      print('   📋 Observações (trim().isEmpty): ${agendamento.cliente!.observacoes?.trim().isEmpty ?? true}');
      print('   📋 Dados Extras: ${agendamento.cliente!.dadosExtras ?? "NULL"}');
      print('   📋 Dados Extras (isEmpty): ${agendamento.cliente!.dadosExtras?.isEmpty ?? true}');
    }
    print('═══════════════════════════════════════════════════════════');
    
    // 1. SEMPRE incluir observações do cliente primeiro (OBRIGATÓRIO - sempre mostrar)
    // IMPORTANTE: Buscar diretamente do objeto cliente, não das observações do agendamento
    if (agendamento.cliente != null) {
      final obs = agendamento.cliente!.observacoes;
      print('   Verificando observações: "$obs" (isNotEmpty: ${obs != null && obs.trim().isNotEmpty})');
      
      // SEMPRE adicionar seção de observações do cliente
      todasObservacoes.add('OBSERVAÇÕES DO CLIENTE:');
      if (obs != null && obs.trim().isNotEmpty) {
        print('   ✓ Adicionando observações do cliente');
        todasObservacoes.add(obs.trim());
      } else {
        print('   ⚠ Observações vazias - adicionando mensagem padrão');
        todasObservacoes.add('Nenhuma observação cadastrada.');
      }
      todasObservacoes.add(''); // Linha em branco
      
      // Dados extras do cliente - SEMPRE adicionar seção
      final dadosExtras = agendamento.cliente!.dadosExtras;
      print('   Verificando dados extras: $dadosExtras (isNotEmpty: ${dadosExtras != null && dadosExtras.isNotEmpty})');
      
      todasObservacoes.add('DADOS EXTRAS DO CLIENTE:');
      if (dadosExtras != null && dadosExtras.isNotEmpty) {
        print('   ✓ Adicionando dados extras do cliente');
        dadosExtras.forEach((key, value) {
          todasObservacoes.add('• $key: $value');
        });
      } else {
        print('   ⚠ Dados extras vazios - adicionando mensagem padrão');
        todasObservacoes.add('Nenhum dado extra cadastrado.');
      }
      todasObservacoes.add(''); // Linha em branco
    } else {
      print('   ✗ Cliente é null - adicionando seções vazias');
      // Mesmo sem cliente, adicionar seções para manter consistência
      todasObservacoes.add('OBSERVAÇÕES DO CLIENTE:');
      todasObservacoes.add('Cliente não informado.');
      todasObservacoes.add('');
      todasObservacoes.add('DADOS EXTRAS DO CLIENTE:');
      todasObservacoes.add('Cliente não informado.');
      todasObservacoes.add('');
    }
    
    print('   Total de observações até agora: ${todasObservacoes.length}');
    
    // 2. Observações do agendamento (OBRIGATÓRIO - sempre incluir se existir)
    print('   🔎 Verificando observações do agendamento...');
    print('   Agendamento.observacoes: "${agendamento.observacoes ?? "NULL"}"');
    print('   Agendamento.observacoes (isEmpty): ${agendamento.observacoes?.isEmpty ?? true}');
    print('   Agendamento.observacoes (trim().isEmpty): ${agendamento.observacoes?.trim().isEmpty ?? true}');
    
    // SEMPRE adicionar seção de observações do agendamento (mesmo que vazia)
    todasObservacoes.add('OBSERVAÇÕES DO AGENDAMENTO:');
    
    if (agendamento.observacoes != null && agendamento.observacoes!.trim().isNotEmpty) {
      print('   ✅ Adicionando observações do agendamento');
      
      // Processar observações do agendamento - remover apenas seções explícitas do cliente
      final observacoesCompletas = agendamento.observacoes!.trim();
      final linhas = observacoesCompletas.split('\n');
      final observacoesAgendamento = <String>[];
      bool emSecaoCliente = false;
      bool emSecaoDadosExtras = false;
      
      for (final linha in linhas) {
        final linhaTrim = linha.trim();
        
        // Ignorar apenas linhas de separador explícitas
        if (linhaTrim.contains('=== OBSERVAÇÕES DO CLIENTE ===') || 
            linhaTrim.contains('=== DADOS DO CLIENTE ===')) {
          emSecaoCliente = true;
          emSecaoDadosExtras = false;
          continue;
        }
        if (linhaTrim.contains('=== DADOS EXTRAS DO CLIENTE ===') || 
            linhaTrim.contains('=== DADOS EXTRAS ===')) {
          emSecaoCliente = false;
          emSecaoDadosExtras = true;
          continue;
        }
        
        // Se linha vazia e estava em seção de cliente, finalizar seção
        if (linhaTrim.isEmpty && (emSecaoCliente || emSecaoDadosExtras)) {
          emSecaoCliente = false;
          emSecaoDadosExtras = false;
          continue;
        }
        
        // Se está em seção de cliente ou dados extras, ignorar (já foi incluído acima)
        if (emSecaoCliente || emSecaoDadosExtras) {
          continue;
        }
        
        // Adicionar todas as outras linhas (observações do agendamento)
        if (linhaTrim.isNotEmpty) {
          observacoesAgendamento.add(linhaTrim);
        }
      }
      
      // Se após filtrar ainda tem conteúdo, usar o filtrado
      // Se não, usar todas as observações (pode ser que não tenha separadores)
      if (observacoesAgendamento.isNotEmpty) {
        print('   ✅ Adicionando ${observacoesAgendamento.length} linha(s) de observações do agendamento (filtradas)');
        todasObservacoes.addAll(observacoesAgendamento);
      } else {
        // Se após filtrar ficou vazio, incluir todas as observações
        print('   ✅ Adicionando observações completas do agendamento (sem filtro)');
        todasObservacoes.add(observacoesCompletas);
      }
    } else {
      print('   ⚠ Agendamento não tem observações - adicionando mensagem padrão');
      todasObservacoes.add('Nenhuma observação cadastrada.');
    }
    todasObservacoes.add(''); // Linha em branco
    
    // 3. Observações do pedido (se houver) - PRIORIDADE: sempre incluir se existir
    print('   🔎 Verificando observações do pedido...');
    print('   Pedido: ${pedido != null ? "EXISTE" : "NULL"}');
    if (pedido != null) {
      print('   Pedido ID: ${pedido.id}');
      print('   Pedido Número: ${pedido.numero}');
      print('   Pedido Observações: "${pedido.observacoes ?? "NULL"}"');
      print('   Pedido Observações (isEmpty): ${pedido.observacoes?.isEmpty ?? true}');
      print('   Pedido Observações (trim().isEmpty): ${pedido.observacoes?.trim().isEmpty ?? true}');
      
      if (pedido.observacoes != null && pedido.observacoes!.trim().isNotEmpty) {
        print('   ✅ Adicionando observações do pedido');
        todasObservacoes.add('OBSERVAÇÕES DO PEDIDO:');
        todasObservacoes.add(pedido.observacoes!.trim());
        todasObservacoes.add(''); // Linha em branco
      } else {
        print('   ⚠ Pedido existe mas não tem observações');
      }
    } else {
      print('   ⚠ Pedido não encontrado');
    }
    
    // SEMPRE mostrar a seção de observações (agora sempre tem pelo menos as seções do cliente)
    print('   ✅✅✅ TOTAL FINAL DE OBSERVAÇÕES: ${todasObservacoes.length}');
    print('   📄 CONTEÚDO FINAL COMPLETO:');
    print('   ${todasObservacoes.join("\n   ")}');
    print('═══════════════════════════════════════════════════════════');
    
    // GARANTIR que sempre há conteúdo (pelo menos as seções do cliente)
    if (todasObservacoes.isEmpty) {
      print('   ⚠⚠⚠ ATENÇÃO: Nenhuma observação foi adicionada! Adicionando seções padrão.');
      todasObservacoes.add('OBSERVAÇÕES DO CLIENTE:');
      todasObservacoes.add('Nenhuma observação cadastrada.');
      todasObservacoes.add('');
      todasObservacoes.add('DADOS EXTRAS DO CLIENTE:');
      todasObservacoes.add('Nenhum dado extra cadastrado.');
      todasObservacoes.add('');
      todasObservacoes.add('OBSERVAÇÕES DO AGENDAMENTO:');
      todasObservacoes.add('Nenhuma observação cadastrada.');
    }
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OBSERVAÇÕES',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue700,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            todasObservacoes.join('\n'),
            style: const pw.TextStyle(
              fontSize: 11,
              lineSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildLinhaInfo(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  static String _formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static pw.Widget _buildRodape() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Text(
        'Documento gerado automaticamente pelo Sistema Exodo',
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
          fontStyle: pw.FontStyle.italic,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Abre o PDF para visualização/impressão
  static Future<void> visualizarPDF({
    required AgendamentoServico agendamento,
    Pedido? pedido,
    DataService? dataService,
    BuildContext? context,
  }) async {
    try {
      final pdfBytes = await gerarPDF(
        agendamento: agendamento,
        pedido: pedido,
        dataService: dataService,
      );
      if (dataService?.empresaAtual != null) {
        await ImpressaoService.imprimirPdf(
          bytes: pdfBytes,
          empresa: dataService!.empresaAtual!,
          name: 'Agendamento_${agendamento.id}',
          termico: true,
          context: context,
        );
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
        );
      }
    } catch (e) {
      throw Exception('Erro ao visualizar PDF: $e');
    }
  }
}

