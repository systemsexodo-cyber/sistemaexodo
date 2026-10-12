// Testes do importador de CLIENTES (com saldo devedor/fiado).
//
// Cobrem o caminho que o usuário usa: um Excel com cabeçalho variável é lido,
// os clientes viram registros com o saldo devedor correto e o saldo pode ser
// lançado como um fiado em aberto (pedido pendente com pagamento fiado).
//
// Rodar: flutter test test/cliente_import_service_test.dart

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/services/cliente_import_service.dart';

/// Gera um .xlsx em memória a partir de linhas de valores.
Uint8List _xlsx(List<List<dynamic>> rows) {
  final excel = Excel.createExcel();
  final sheetName = excel.sheets.keys.first;
  for (int r = 0; r < rows.length; r++) {
    for (int c = 0; c < rows[r].length; c++) {
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        rows[r][c],
      );
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

Cliente _cliente({
  required String id,
  required String nome,
  String? cpfCnpj,
  double saldoDevedor = 0,
}) {
  return Cliente(
    id: id,
    nome: nome,
    cpfCnpj: cpfCnpj,
    telefone: '',
    saldoDevedor: saldoDevedor,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('lê clientes novos com saldo devedor (vírgula e ponto)', () {
    final bytes = _xlsx([
      ['Nome', 'CPF/CNPJ', 'Celular', 'Cidade', 'Saldo Devedor'],
      ['João da Silva', '111.444.777-35', '(11) 98888-1111', 'São Paulo', '150,50'],
      ['Mercado Bom Preço', '12.345.678/0001-95', '11 3333-2222', 'Campinas', 320.0],
    ]);

    final plano = ClienteImportService.planejar(bytes, existentes: []);

    expect(plano.novos, hasLength(2));
    expect(plano.saldoTotal, closeTo(470.50, 0.001));

    final joao = plano.novos.firstWhere((c) => c.nome == 'João da Silva');
    expect(joao.saldoDevedor, closeTo(150.50, 0.001));
    expect(joao.telefone, '(11) 98888-1111');
    expect(joao.cidade, 'São Paulo');
    expect(joao.cpfCnpj, '11144477735');
    expect(joao.tipoPessoa, TipoPessoa.fisica);

    final mercado = plano.novos.firstWhere((c) => c.nome == 'Mercado Bom Preço');
    expect(mercado.tipoPessoa, TipoPessoa.juridica);
    expect(mercado.saldoDevedor, closeTo(320.0, 0.001));

    // Só os que têm saldo viram fiado.
    expect(plano.comSaldoDevedor, hasLength(2));
  });

  test('não duplica cliente existente e preserva o saldo já lançado', () {
    final existente = _cliente(
      id: 'cli-1',
      nome: 'Maria Souza',
      cpfCnpj: '12345678909',
      saldoDevedor: 80.0,
    );

    final bytes = _xlsx([
      ['Nome', 'CPF', 'Telefone', 'Saldo'],
      ['Maria Souza', '123.456.789-09', '(21) 97777-0000', '999,00'],
    ]);

    final plano = ClienteImportService.planejar(bytes, existentes: [existente]);

    expect(plano.novos, isEmpty);
    expect(plano.atualizados, hasLength(1));
    expect(plano.comSaldoDevedor, isEmpty, reason: 'fiado não pode ser lançado em dobro');

    final atualizada = plano.atualizados.single;
    expect(atualizada.id, 'cli-1');
    expect(atualizada.telefone, '(21) 97777-0000');
    expect(atualizada.saldoDevedor, 80.0, reason: 'saldo existente preservado');
  });

  test('ignora linhas duplicadas no mesmo arquivo e linhas sem nome', () {
    final bytes = _xlsx([
      ['Nome', 'Documento', 'Valor devido'],
      ['Cliente A', '11111111111', '10'],
      ['Cliente A', '11111111111', '10'], // duplicado no arquivo
      ['', '99999999999', '20'], // sem nome
      ['Cliente B', '22222222222', '5,25'],
    ]);

    final plano = ClienteImportService.planejar(bytes, existentes: []);

    expect(plano.novos.map((c) => c.nome), containsAll(['Cliente A', 'Cliente B']));
    expect(plano.novos, hasLength(2));
    expect(plano.ignorados, 2);
    // "Valor devido" é reconhecido como saldo devedor.
    expect(
      plano.novos.firstWhere((c) => c.nome == 'Cliente B').saldoDevedor,
      closeTo(5.25, 0.001),
    );
  });

  test('aceita título variado da coluna de saldo e formato 1.234,56', () {
    final bytes = _xlsx([
      ['CLIENTE', 'FIADO (R\$)'],
      ['Zé do Bar', '1.234,56'],
    ]);

    final plano = ClienteImportService.planejar(bytes, existentes: []);

    expect(plano.novos, hasLength(1));
    expect(plano.novos.single.nome, 'Zé do Bar');
    expect(plano.novos.single.saldoDevedor, closeTo(1234.56, 0.001));
  });

  test('montarPedidoFiado cria um pedido pendente com pagamento fiado', () {
    final cliente = _cliente(
      id: 'cli-9',
      nome: 'Freguês',
      cpfCnpj: '11144477735',
      saldoDevedor: 145.90,
    );

    final pedido =
        ClienteImportService.montarPedidoFiado(cliente, numero: 'PED-0007');

    expect(pedido.numero, 'PED-0007');
    expect(pedido.clienteId, 'cli-9');
    expect(pedido.clienteNome, 'Freguês');
    expect(pedido.status, 'Pendente');
    expect(pedido.total, closeTo(145.90, 0.001));
    expect(pedido.pagamentos, hasLength(1));

    final pag = pedido.pagamentos.single;
    expect(pag.tipo, TipoPagamento.fiado);
    expect(pag.recebido, isFalse);
    expect(pag.valor, closeTo(145.90, 0.001));
    expect(pedido.valorPendente, closeTo(145.90, 0.001));
  });
}
