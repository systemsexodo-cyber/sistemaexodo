/// Utilidades de unidades de medida para conversão de baixa em produtos compostos.
///
/// Normaliza unidades escritas de formas diferentes (ex.: "ML", "ml",
/// "mililitro") para uma forma canônica e fornece rótulos legíveis.
library;

/// Lista de unidades reconhecidas, na ordem exibida nos seletores.
const List<String> unidadesConhecidas = [
  'UN', 'ML', 'L', 'KG', 'G', 'METRO', 'CM', 'SACO', 'CAIXA', 'PACOTE',
];

/// Normaliza uma unidade para a forma canônica curta.
///
/// Ex.: "mililitro" -> "ML", "litro(s)" -> "L", "metro" -> "METRO",
/// "quilograma" -> "KG". Retorna null se vazio; retorna o texto original
/// (trimado, maiúsculo) se não reconhecer.
String? normalizarUnidade(String? unidade) {
  if (unidade == null) return null;
  final u = unidade.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  if (u.isEmpty) return null;

  if (u == 'UN' || u == 'UND' || u == 'UNIDADE' || u == 'UNIDADES' || u == 'UNID') return 'UN';
  if (u == 'ML' || u == 'MILILITRO' || u == 'MILILITROS') return 'ML';
  if (u == 'L' || u == 'LT' || u == 'LITRO' || u == 'LITROS') return 'L';
  if (u == 'KG' || u == 'KILO' || u == 'KILOS' || u == 'KILOGRAMA' || u == 'KILOGRAMAS' || u == 'QUILO' || u == 'QUILOS' || u == 'QUILOGRAMA') return 'KG';
  if (u == 'G' || u == 'GR' || u == 'GRAMA' || u == 'GRAMAS') return 'G';
  if (u == 'METRO' || u == 'METROS' || u == 'M') return 'METRO';
  if (u == 'CM' || u == 'CENTIMETRO' || u == 'CENTIMETROS') return 'CM';
  if (u == 'SACO' || u == 'SACOS') return 'SACO';
  if (u == 'CAIXA' || u == 'CAIXAS') return 'CAIXA';
  if (u == 'PACOTE' || u == 'PACOTES' || u == 'PACOTE FECHADO') return 'PACOTE';
  return u;
}

/// Rótulo por extenso para exibição (ex.: "ML" -> "ml", "L" -> "litro(s)").
String rotuloUnidade(String? unidade, {bool plural = false}) {
  switch (normalizarUnidade(unidade)) {
    case 'UN':
      return 'un';
    case 'ML':
      return 'ml';
    case 'L':
      return plural ? 'litros' : 'litro';
    case 'KG':
      return plural ? 'kg' : 'kg';
    case 'G':
      return plural ? 'g' : 'g';
    case 'METRO':
      return plural ? 'metros' : 'metro';
    case 'CM':
      return plural ? 'cm' : 'cm';
    case 'SACO':
      return plural ? 'sacos' : 'saco';
    case 'CAIXA':
      return plural ? 'caixas' : 'caixa';
    case 'PACOTE':
      return plural ? 'pacotes' : 'pacote';
    default:
      final u = (unidade ?? '').trim();
      return u.isEmpty ? 'un' : u.toLowerCase();
  }
}

/// Formata um número removendo zeros desnecessários (1.0 -> "1", 0.5 -> "0,5").
String formatarNumero(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
}

/// Monta o texto de conversão ex.: "1 litro a cada 1000 ml" ou
/// "1 saco a cada 15 kg", usando as unidades quando disponíveis.
String textoConversao(
  double baixa,
  double aCada, {
  String? unidadeBaixa,
  String? unidadeVenda,
}) {
  final bTxt = formatarNumero(baixa);
  final aTxt = formatarNumero(aCada);
  final bUn = unidadeBaixa != null && unidadeBaixa.trim().isNotEmpty
      ? rotuloUnidade(unidadeBaixa, plural: baixa != 1)
      : '';
  final vUn = unidadeVenda != null && unidadeVenda.trim().isNotEmpty
      ? rotuloUnidade(unidadeVenda, plural: aCada != 1)
      : '';
  return '$bTxt${bUn.isNotEmpty ? ' $bUn' : ''} a cada $aTxt${vUn.isNotEmpty ? ' $vUn' : ''}';
}
