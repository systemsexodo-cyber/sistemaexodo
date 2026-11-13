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

/// Chave, dentro de `empresa.configuracoes`, que guarda os MODELOS de
/// etiqueta salvos pelo operador (nome + layout).
const String chaveEtiquetas = 'etiquetas';

/// Carimbo de atualização da lista de modelos de etiqueta.
const String chaveEtiquetasAtualizadoEm = 'etiquetas_atualizado_em';

/// Chave, dentro de `empresa.configuracoes`, que guarda QUANDO a lista de
/// departamentos foi salva pela última vez.
const String chaveDepartamentosAtualizadoEm = 'departamentos_atualizado_em';

/// Chave, dentro de `empresa.configuracoes`, que guarda QUANDO a lista de
/// estoques por produto foi salva pela última vez.
const String chaveEstoquesAtualizadoEm = 'estoques_atualizado_em';

/// Carimbo de atualização da personalização da LOJA
/// (`configuracoes['ecommerce']`).
///
/// Sem ele, a seção `ecommerce` era sempre resolvida pela regra "a nuvem
/// manda": como a nuvem sempre tem a chave, a alteração salva no PC era
/// revertida no boot/seleção da empresa e a tela "Personalização da loja"
/// voltava ao valor antigo.
const String chaveEcommerceAtualizadoEm = 'ecommerce_atualizado_em';

/// Carimbo de atualização das configurações de AGENDAMENTO
/// (`configuracoes['agendamento']`).
const String chaveAgendamentoAtualizadoEm = 'agendamento_atualizado_em';

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

/// Atalho para os modelos de etiqueta salvos pelo operador
/// (`configuracoes['etiquetas']`).
void aplicarEtiquetasMaisRecentes(
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
    chave: chaveEtiquetas,
    chaveCarimbo: chaveEtiquetasAtualizadoEm,
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

/// Versão de [configListaVencedora] para as seções guardadas como MAPA
/// (`ecommerce`, `agendamento`) em vez de lista.
///
/// A seção vencedora é escolhida pelo carimbo. As chaves que existem só na
/// seção perdedora são preenchidas a partir dela — assim uma tela/versão antiga
/// que não conhece um campo novo não apaga esse campo.
Map<String, dynamic>? configMapaVencedor({
  required String chave,
  required String chaveCarimbo,
  required Map<String, dynamic> configLocal,
  required Map<String, dynamic> configRemota,
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  final local = configLocal[chave];
  final remota = configRemota[chave];
  final temLocal = local is Map;
  final temRemota = remota is Map;
  if (!temLocal && !temRemota) return null;

  final carimboLocal = configAtualizadaEm(configLocal, chaveCarimbo);
  final carimboRemoto = configAtualizadaEm(configRemota, chaveCarimbo);

  final bool remotaVence;
  if (carimboLocal != null && carimboRemoto != null) {
    remotaVence = carimboRemoto.isAfter(carimboLocal);
  } else if (carimboLocal != null) {
    remotaVence = false;
  } else if (carimboRemoto != null) {
    remotaVence = true;
  } else {
    // Dados de versões antigas (sem carimbo): mantém a regra anterior.
    remotaVence = updatedAtRemota.isAfter(updatedAtLocal);
  }

  final vencedor = remotaVence ? remota : local;
  final perdedor = remotaVence ? local : remota;
  if (vencedor is! Map) {
    return perdedor is Map ? Map<String, dynamic>.from(perdedor) : null;
  }

  final resultado = Map<String, dynamic>.from(vencedor);
  if (perdedor is Map) {
    for (final entry in perdedor.entries) {
      if (!resultado.containsKey(entry.key) || resultado[entry.key] == null) {
        resultado[entry.key] = entry.value;
      }
    }
  }
  return resultado;
}

/// Aplica em [destino] a seção em MAPA vencedora e o carimbo correspondente,
/// para a próxima comparação ser feita contra a versão correta.
void aplicarConfigMapaMaisRecente(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required String chave,
  required String chaveCarimbo,
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  final vencedor = configMapaVencedor(
    chave: chave,
    chaveCarimbo: chaveCarimbo,
    configLocal: configLocal,
    configRemota: configRemota,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
  if (vencedor == null) return;

  destino[chave] = vencedor;
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

/// Atalho para a personalização da loja (`configuracoes['ecommerce']`).
void aplicarEcommerceMaisRecente(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigMapaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'ecommerce',
    chaveCarimbo: chaveEcommerceAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}

/// Atalho para as configurações de agendamento
/// (`configuracoes['agendamento']`).
void aplicarAgendamentoMaisRecente(
  Map<String, dynamic> destino,
  Map<String, dynamic> configLocal,
  Map<String, dynamic> configRemota, {
  required DateTime updatedAtLocal,
  required DateTime updatedAtRemota,
}) {
  aplicarConfigMapaMaisRecente(
    destino,
    configLocal,
    configRemota,
    chave: 'agendamento',
    chaveCarimbo: chaveAgendamentoAtualizadoEm,
    updatedAtLocal: updatedAtLocal,
    updatedAtRemota: updatedAtRemota,
  );
}
