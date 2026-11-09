/// Chave, dentro de `empresa.configuracoes`, que guarda QUANDO a lista de
/// perfis tributários foi salva pela última vez.
///
/// É o carimbo que permite comparar duas cópias da mesma lista (PC e site) sem
/// depender da data da empresa inteira: qualquer outra configuração salva
/// (ecommerce, PDV, mensalidade...) também atualiza `empresa.updatedAt` e
/// faria a cópia errada parecer a mais nova.
const String chavePerfisTributariosAtualizadoEm =
    'perfis_tributarios_atualizado_em';

/// Mesmo carimbo, para a lista de perfis de preço.
const String chavePerfisPrecoAtualizadoEm = 'perfis_preco_atualizado_em';

/// Chave, dentro de `empresa.configuracoes`, que guarda QUANDO a lista de
/// departamentos foi salva pela última vez.
const String chaveDepartamentosAtualizadoEm = 'departamentos_atualizado_em';

/// Chave, dentro de `empresa.configuracoes`, que guarda QUANDO a lista de
/// estoques por produto foi salva pela última vez.
const String chaveEstoquesAtualizadoEm = 'estoques_atualizado_em';

/// Lê o carimbo de atualização de uma lista de configuração.
DateTime? configAtualizadaEm(
  Map<String, dynamic> config,
  String chaveCarimbo,
) {
  final bruto = config[chaveCarimbo];
  if (bruto == null) return null;
  return DateTime.tryParse(bruto.toString())?.toUtc();
}

/// Decide qual lista de configuração (identificada por [chave]) deve
/// prevalecer quando a configuração LOCAL e a da NUVEM são mescladas.
///
/// Antes disso o merge dava prioridade absoluta ao local (regra criada quando
/// só o desktop editava, para o cache não "sumir" com as listas). O efeito
/// colateral: a alteração feita no computador chegava na nuvem, mas o site
/// reaplicava a cópia antiga do navegador em cada login — impostos e preços
/// pareciam nunca atualizar no site.
///
/// Regra agora:
///  1. lista vazia em um dos lados → vence o outro;
///  2. o carimbo [chaveCarimbo] mais recente vence;
///  3. sem carimbo nos dois lados (dados de versões antigas), vence a empresa
///     com `updatedAt` maior.
///
/// Retorna `null` quando nenhum dos lados tem a lista — nesse caso o chamador
/// não deve escrever a chave.
List<dynamic>? configListaVencedora({
  required String chave,
  required String chaveCarimbo,
  required Map<String, dynamic> configLocal,
  required Map<String, dynamic> configRemota,
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  final local = configLocal[chave];
  final remota = configRemota[chave];
  final temLocal = local is List;
  final temRemota = remota is List;
  if (!temLocal && !temRemota) return null;

  final carimboLocal = configAtualizadaEm(configLocal, chaveCarimbo);
  final carimboRemoto = configAtualizadaEm(configRemota, chaveCarimbo);

  // Quando existe carimbo, quem salvou por último manda — INCLUSIVE quando a
  // lista está vazia. Antes a regra "lista vazia perde" fazia o último perfil
  // excluído (ou todos) voltar da nuvem no próximo sync.
  if (carimboLocal != null && carimboRemoto != null) {
    return carimboRemoto.isAfter(carimboLocal) ? remota : local;
  }
  if (carimboLocal != null) return local;
  if (carimboRemoto != null) return remota;

  // Dados de versões antigas (sem carimbo): mantém a regra anterior.
  final listaLocal = local is List && local.isNotEmpty ? local : null;
  final listaRemota = remota is List && remota.isNotEmpty ? remota : null;
  if (listaLocal == null && listaRemota == null) return null;
  if (listaLocal == null) return listaRemota;
  if (listaRemota == null) return listaLocal;

  return updatedAtRemota.isAfter(updatedAtLocal) ? listaRemota : listaLocal;
}

/// Aplica em [destino] (normalmente o mapa mesclado) a lista vencedora e o
/// carimbo correspondente, para a próxima comparação ser feita contra a versão
/// correta.
void aplicarConfigListaMaisRecente(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required String chave,
  required String chaveCarimbo,
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  final vencedores = configListaVencedora(
    chave: chave,
    chaveCarimbo: chaveCarimbo,
    configLocal: configLocal,
    configRemota: configRemota,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
  if (vencedores == null) return;

  destino[chave] = vencedores;
  // Copia o carimbo da cópia que venceu (o mais recente), para a próxima
  // comparação ser feita contra a versão correta.
  final carimboLocal = configAtualizadaEm(configLocal, chaveCarimbo);
  final carimboRemoto = configAtualizadaEm(configRemota, chaveCarimbo);
  final DateTime? carimbo;
  if (carimboLocal != null && carimboRemoto != null) {
    carimbo = carimboRemoto.isAfter(carimboLocal) ? carimboRemoto : carimboLocal;
  } else {
    carimbo = carimboRemoto ?? carimboLocal;
  }
  if (carimbo != null) {
    destino[chaveCarimbo] = carimbo.toIso8601String();
  }
}

/// Atalho para os perfis tributários (impostos).
void aplicarPerfisTributariosMaisRecentes(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigListaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'perfis_tributarios',
    chaveCarimbo: chavePerfisTributariosAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}

/// Atalho para os perfis de preço — tinham a mesma regra "local vence sempre"
/// e, por isso, o preço por perfil alterado no desktop também não chegava ao
/// site.
void aplicarPerfisPrecoMaisRecentes(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigListaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'perfis_preco',
    chaveCarimbo: chavePerfisPrecoAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}

/// Atalho para os departamentos (setores de preparo: Cozinha, Bar, ...).
void aplicarDepartamentosMaisRecentes(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigListaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'departamentos',
    chaveCarimbo: chaveDepartamentosAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}

/// Atalho para os estoques por produto (listas dentro de `empresa.configuracoes['estoques']`).
void aplicarEstoquesMaisRecentes(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigListaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'estoques',
    chaveCarimbo: chaveEstoquesAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}
