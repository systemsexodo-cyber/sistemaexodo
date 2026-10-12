// Disponibilidade temporária do produto: o produto fica VISÍVEL no catálogo,
// mas só pode ser vendido dentro da janela (dia/hora). Fora dela o PDV bloqueia
// e a loja pública esconde.
//
// Rodar: flutter test test/produto_disponibilidade_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/produto.dart';

Produto _produto({
  DateTime? disponivelDe,
  DateTime? disponivelAte,
  bool ativo = true,
}) =>
    Produto(
      id: 'P1',
      nome: 'Coca-Cola 2L',
      unidade: 'un',
      grupo: 'Bebidas',
      preco: 10,
      estoque: 5,
      ativo: ativo,
      disponivelDe: disponivelDe,
      disponivelAte: disponivelAte,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('sem janela: sempre disponível', () {
    final p = _produto();
    expect(p.temDisponibilidadeTemporaria, isFalse);
    expect(p.disponivelAgora, isTrue);
    expect(p.podeVenderAgora, isTrue);
    expect(p.indisponibilidadeTemporariaLabel, isNull);
  });

  test('dentro da janela: disponível', () {
    final agora = DateTime.now();
    final p = _produto(
      disponivelDe: agora.subtract(const Duration(hours: 1)),
      disponivelAte: agora.add(const Duration(hours: 1)),
    );
    expect(p.disponivelEm(agora), isTrue);
    expect(p.podeVenderAgora, isTrue);
  });

  test('antes do início: indisponível, com rótulo de início', () {
    final p = _produto(disponivelDe: DateTime.now().add(const Duration(days: 1)));
    expect(p.disponivelAgora, isFalse);
    expect(p.podeVenderAgora, isFalse);
    expect(p.indisponibilidadeTemporariaLabel, startsWith('Disponível a partir de'));
  });

  test('depois do fim: indisponível, com rótulo de fim', () {
    final p = _produto(disponivelAte: DateTime.now().subtract(const Duration(days: 1)));
    expect(p.disponivelAgora, isFalse);
    expect(p.podeVenderAgora, isFalse);
    expect(p.indisponibilidadeTemporariaLabel, startsWith('Disponível até'));
  });

  test('só início (sem fim): volta a vender a partir da data', () {
    final p = _produto(disponivelDe: DateTime(2099, 1, 1, 8));
    expect(p.disponivelEm(DateTime(2098, 12, 31, 23)), isFalse);
    expect(p.disponivelEm(DateTime(2099, 1, 1, 12)), isTrue);
  });

  test('só fim (sem início): disponível até a data', () {
    final p = _produto(disponivelAte: DateTime(2099, 1, 1, 18));
    expect(p.disponivelEm(DateTime(2099, 1, 1, 12)), isTrue);
    expect(p.disponivelEm(DateTime(2099, 1, 2, 0)), isFalse);
  });

  test('ativo=false continua bloqueando mesmo dentro da janela', () {
    final agora = DateTime(2026, 6, 10, 12);
    final p = _produto(
      ativo: false,
      disponivelDe: DateTime(2026, 6, 10, 8),
      disponivelAte: DateTime(2026, 6, 10, 18),
    );
    expect(p.disponivelEm(agora), isTrue);
    expect(p.podeVenderAgora, isFalse, reason: 'produto desativado nunca vende');
  });

  test('toMap/fromMap preservam a janela', () {
    final de = DateTime(2026, 6, 10, 8, 30);
    final ate = DateTime(2026, 6, 10, 18, 45);
    final p = _produto(disponivelDe: de, disponivelAte: ate);

    final mapa = p.toMap();
    expect(mapa['disponivel_de'], de.toIso8601String());
    expect(mapa['disponivel_ate'], ate.toIso8601String());

    final lido = Produto.fromMap(mapa);
    expect(lido.disponivelDe, de);
    expect(lido.disponivelAte, ate);
  });

  test('copyWith limparDisponibilidade apaga os dois lados', () {
    final p = _produto(
      disponivelDe: DateTime(2026, 6, 10, 8),
      disponivelAte: DateTime(2026, 6, 10, 18),
    );
    final limpo = p.copyWith(limparDisponibilidade: true);
    expect(limpo.disponivelDe, isNull);
    expect(limpo.disponivelAte, isNull);
    expect(limpo.temDisponibilidadeTemporaria, isFalse);
  });
}
