// Regra de ouro do banco local: ele é WIN1252 (o PostgreSQL do sistema nasceu
// com o locale pt-BR do Windows), então símbolos como → e ✅ não entram nele.
// Esta é a sanitização que o app aplica antes de gravar e que a conferência usa
// ao copiar da nuvem para o local.
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/utils/win1252.dart';

void main() {
  test('mantém o que o WIN1252 guarda (incluindo acentos)', () {
    const texto = 'José da Conceição — Café, ação, coração, R\$ 12,50 (50%)';
    expect(Win1252.sanitizar(texto), texto);
    expect(Win1252.representavel('ç'.runes.first), isTrue);
    expect(Win1252.representavel('ã'.runes.first), isTrue);
  });

  test('preserva os caracteres altos que o WIN1252 tem', () {
    // Testados contra o banco real: travessão, aspas curvas, bullet, euro...
    // O WIN1252 guarda todos eles, então não há motivo para empobrecer o texto.
    const texto = 'Pagou — R\$ 10 “no ato” • item 1 … fim, 50% € 5 ™';
    expect(Win1252.sanitizar(texto), texto);
    for (final rune in '—–“”‘’•€™…†‡‰ŠœžŸƒ'.runes) {
      expect(Win1252.representavel(rune), isTrue,
          reason: 'U+${rune.toRadixString(16)} existe no WIN1252');
    }
  });

  test('converte os símbolos que não existem no WIN1252', () {
    expect(Win1252.sanitizar('Estoque: 10 → 8 unidades'),
        'Estoque: 10 -> 8 unidades');
    expect(Win1252.sanitizar('← entrou ↑ subiu ↓ desceu'), '<- entrou ^ subiu v desceu');
    expect(Win1252.sanitizar('✅ conferido ❌ recusado ⚠ atenção'),
        'OK conferido X recusado ! atenção');
    expect(Win1252.sanitizar('✓ ok ✗ não'), 'OK ok X não');
  });

  test('emojis e o que sobra viram "?" (nunca estoura o Postgres)', () {
    expect(Win1252.sanitizar('promoção 🚀 hoje'), 'promoção ? hoje');
    final resultado = Win1252.sanitizar('texto 🚀 com 😀 emojis 🎉');
    expect(resultado, 'texto ? com ? emojis ?');
    for (final rune in resultado.runes) {
      expect(Win1252.representavel(rune), isTrue,
          reason: 'nada pode sobrar fora do WIN1252');
    }
  });

  test('o resultado nunca tem caractere fora do WIN1252', () {
    const misturado = 'R\$ 10,00 → R\$ 12,00 ✅\n teste • 50% — fim 🚀';
    final limpo = Win1252.sanitizar(misturado);
    for (final rune in limpo.runes) {
      expect(Win1252.representavel(rune), isTrue,
          reason: 'U+${rune.toRadixString(16)} sobrou no texto sanitizado');
    }
    expect(limpo, contains('R\$ 10,00 -> R\$ 12,00 OK'));
    expect(limpo, contains('—')); // travessão existe no WIN1252
    expect(limpo, contains('•')); // bullet também
  });

  test('sanitizarValor só mexe em texto', () {
    expect(Win1252.sanitizarValor(null), isNull);
    expect(Win1252.sanitizarValor(10), 10);
    expect(Win1252.sanitizarValor(true), isTrue);
    expect(Win1252.sanitizarValor(DateTime.utc(2026, 1, 1)),
        DateTime.utc(2026, 1, 1));
    expect(Win1252.sanitizarValor('10 → 8'), '10 -> 8');
  });
}
