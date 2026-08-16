import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """      final responseNfce = await service.emitir(
        empresa: empresa,
        produtos: listProd,
        quantidades: qtdeMap,
        pagamentos: [NFCePagamento(tipo: _tipoPagamento, valor: total)],
        valorTotal: total,
        cpfCnpjConsumidor: _docDestCtrl.text.trim(),
        nomeConsumidor: _nomeDestCtrl.text.trim(),
        ambienteHomologacao: widget.ambienteHomologacao,
        modelo: 55,
        serie: serieForcada,
        numero: numForcado,
        destLogradouro: _logradouroCtrl.text.trim(),
        destNumero: _numEndCtrl.text.trim().isEmpty ? 'S/N' : _numEndCtrl.text.trim(),
        destComplemento: _complCtrl.text.trim(),
        destBairro: _bairroCtrl.text.trim().isEmpty ? 'Centro' : _bairroCtrl.text.trim(),
        destMunicipio: _municipioCtrl.text.trim(),
        destUf: _ufCtrl.text.trim().toUpperCase(),
        destCep: _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destTelefone: _foneCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destEmail: _emailDestCtrl.text.trim(),
      );"""

replacement = """      final responseNfce = await service.emitir(
        empresa: empresa,
        produtos: listProd,
        quantidades: qtdeMap,
        pagamentos: [NFCePagamento(tipo: _tipoPagamento, valor: total)],
        valorTotal: total,
        cpfCnpjConsumidor: _docDestCtrl.text.trim(),
        nomeConsumidor: _nomeDestCtrl.text.trim(),
        ambienteHomologacao: widget.ambienteHomologacao,
        modelo: 55,
        serie: serieForcada,
        numero: numForcado,
        destLogradouro: _logradouroCtrl.text.trim(),
        destNumero: _numEndCtrl.text.trim().isEmpty ? 'S/N' : _numEndCtrl.text.trim(),
        destComplemento: _complCtrl.text.trim(),
        destBairro: _bairroCtrl.text.trim().isEmpty ? 'Centro' : _bairroCtrl.text.trim(),
        destMunicipio: _municipioCtrl.text.trim(),
        destUf: _ufCtrl.text.trim().toUpperCase(),
        destCep: _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destTelefone: _foneCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destEmail: _emailDestCtrl.text.trim(),
        // ─── Novos campos de Devolução, Impostos e Transporte ───
        finalidade: _finalidade,
        naturezaOperacao: _natOpCtrl.text.trim(),
        chaveReferenciada: _finalidade == 4 ? _chaveRefCtrl.text.trim() : null,
        freteValor: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        seguroValor: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesasValor: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,
        modFrete: int.tryParse(_modFrete) ?? 9,
        transpNome: _transpNomeCtrl.text.trim().isNotEmpty ? _transpNomeCtrl.text.trim() : null,
        transpCnpjCpf: _transpCnpjCtrl.text.trim().isNotEmpty ? _transpCnpjCtrl.text.trim() : null,
        transpInscEst: _transpInscEstCtrl.text.trim().isNotEmpty ? _transpInscEstCtrl.text.trim() : null,
        transpEndereco: _transpEndCtrl.text.trim().isNotEmpty ? _transpEndCtrl.text.trim() : null,
        transpMunicipio: _transpMunicipioCtrl.text.trim().isNotEmpty ? _transpMunicipioCtrl.text.trim() : null,
        transpUf: _transpUfCtrl.text.trim().isNotEmpty ? _transpUfCtrl.text.trim() : null,
        transpPlaca: _transpPlacaCtrl.text.trim().isNotEmpty ? _transpPlacaCtrl.text.trim() : null,
        transpPlacaUf: _transpPlacaUfCtrl.text.trim().isNotEmpty ? _transpPlacaUfCtrl.text.trim() : null,
        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
      );"""

if target in content:
    content = content.replace(target, replacement)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("EMITIR_PATCH_APLICADO_COM_SUCESSO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(normalized_content)
        print("EMITIR_PATCH_APLICADO_NORMALIZADO")
    else:
        print("ALVO_EMITIR_NAO_ENCONTRADO")
