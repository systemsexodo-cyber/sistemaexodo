#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Teste automatizado do motor fiscal (pynfe): valida o bloco de ICMS gerado
para cada regime tributário (CRT) da empresa na emissão de NFC-e/NF-e.

Cobre as regras aplicadas em `adicionar_produto_com_icms`:
  - CRT 1 (Simples Nacional)      -> bloco <ICMSSN102><CSOSN>102</CSOSN>  (sem destaque)
  - CRT 2 (Simples SN - excesso)  -> mesmo comportamento do CRT 1
  - CRT 3 (Regime Normal, CST 00) -> bloco <ICMS00><CST>00</CST><modBC>3</modBC>
                                     <vBC>..</vBC><pICMS>..</pICMS><vICMS>..</vICMS> (completo)
  - CRT 3 (Regime Normal, CST 40) -> bloco <ICMS40><CST>40</CST> (isenta, sem modBC/vBC)

Uso (na raiz do projeto):
    backend_nfce/venv/Scripts/python.exe backend_nfce/test_regime_icms.py
    backend_nfce/venv/Scripts/python.exe backend_nfce/test_regime_icms.py --cloud

    --cloud  roda as mesmas asserções contra o motor em functions_py/nfce_handler.py.
             (os dois motores não podem ser importados no mesmo processo — os
             monkeypatches do pynfe se sobrescreveriam)

Exit code: 0 = sucesso, 1 = falha (útil para CI/regressão).
"""
import os
import re
import sys
from datetime import datetime
from decimal import Decimal

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)

# ── Dados falsos para o teste ──────────────────────────────────────────────────

class EmpresaFake:
    crt = 1
    cnpj = '04829400000165'
    razao_social = 'EMPRESA TESTE LTDA'
    nome_fantasia = 'TESTE'
    inscricao_estadual = '645431707119'
    logradouro = 'RUA TESTE'
    numero = '177'
    bairro = 'CENTRO'
    municipio = 'SAO JOSE DOS CAMPOS'
    codigo_municipio = '3549904'
    uf = 'SP'
    cep = '12228350'


class ItemFake:
    codigo = 'COD-1'
    descricao = 'PRODUTO TESTE'
    ncm = '00000000'
    cfop = '5102'
    quantidade = 1.0
    valor_unitario = 100.0
    valor_total = 100.0
    icms_origem = 0
    icms_csosn = '102'
    icms_cst = '00'
    icms_aliquota = 18.0

    def __init__(self, icms_csosn='102', icms_cst='00', icms_aliquota=18.0, icms_base_calculo=None):
        self.icms_csosn = icms_csosn
        self.icms_cst = icms_cst
        self.icms_aliquota = icms_aliquota
        self.icms_base_calculo = icms_base_calculo


# ── Helpers ────────────────────────────────────────────────────────────────────

def carregar_modulo(alvo):
    """Importa o módulo alvo ('backend_nfce' ou 'functions_py') e devolve o módulo."""
    if alvo == 'cloud':
        sys.path.insert(0, os.path.join(RAIZ, 'functions_py'))
    else:
        sys.path.insert(0, AQUI)
    import importlib
    mod = importlib.import_module('nfce_handler')
    # O motor cloud (functions_py) não aplica todos os monkeypatches de atributos
    # do pynfe que o backend_nfce aplica na importação. Aplicamos aqui os mesmos
    # defaults para permitir a serialização no venv (necessários p/ PIS/COFINS/II).
    if alvo == 'cloud':
        _aplicar_defaults_pynfe()
    return mod


def _aplicar_defaults_pynfe():
    """Espelha os fixes de atributos do pynfe usados pelo backend_nfce."""
    from pynfe.entidades.notafiscal import NotaFiscalProduto
    NotaFiscalProduto.ind_total = 1
    NotaFiscalProduto.valor_tributos_aprox = Decimal('0.00')
    NotaFiscalProduto.ipi_valor_ipi_dev = Decimal('0.00')
    NotaFiscalProduto.pdevol = Decimal('0.00')
    NotaFiscalProduto.vBCSTRet = Decimal('0.00')
    NotaFiscalProduto.pST = Decimal('0.00')
    NotaFiscalProduto.vICMSSTRet = Decimal('0.00')
    NotaFiscalProduto.icms_csosn = '102'
    NotaFiscalProduto.pCredSN = Decimal('0.00')
    NotaFiscalProduto.vCredICMSSN = Decimal('0.00')
    NotaFiscalProduto.icms_st_ret_base_calculo = Decimal('0.00')
    NotaFiscalProduto.icms_st_ret_aliquota = Decimal('0.00')
    NotaFiscalProduto.icms_st_ret_valor = Decimal('0.00')
    NotaFiscalProduto.fcp_st_ret_valor = Decimal('0.00')
    NotaFiscalProduto.fcp_st_ret_base_calculo = Decimal('0.00')
    NotaFiscalProduto.fcp_st_ret_aliquota = Decimal('0.00')
    NotaFiscalProduto.vBCFCPSTRet = Decimal('0.00')
    NotaFiscalProduto.pFCPSTRet = Decimal('0.00')
    NotaFiscalProduto.vFCPSTRet = Decimal('0.00')
    NotaFiscalProduto.pis_modalidade = '07'
    NotaFiscalProduto.pis_valor_base_calculo = Decimal('0.00')
    NotaFiscalProduto.pis_aliquota_percentual = Decimal('0.00')
    NotaFiscalProduto.pis_valor = Decimal('0.00')
    NotaFiscalProduto.pis_aliquota_reais = Decimal('0.00')
    NotaFiscalProduto.cofins_modalidade = '07'
    NotaFiscalProduto.cofins_valor_base_calculo = Decimal('0.00')
    NotaFiscalProduto.cofins_aliquota_percentual = Decimal('0.00')
    NotaFiscalProduto.cofins_valor = Decimal('0.00')
    NotaFiscalProduto.cofins_aliquota_reais = Decimal('0.00')
    NotaFiscalProduto.informacoes_adicionais = ''


def montar_xml(mod, crt, icms_cst='00', icms_csosn='102', icms_aliquota=18.0, icms_base_calculo=None):
    """Monta uma NFC-e de teste e devolve o XML serializado (string)."""
    from pynfe.entidades.emitente import Emitente
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.processamento.serializacao import SerializacaoXML

    emp = EmpresaFake()
    emp.crt = crt
    emitente = Emitente(
        cnpj=emp.cnpj,
        razao_social=emp.razao_social,
        nome_fantasia=emp.nome_fantasia,
        inscricao_estadual=emp.inscricao_estadual,
        codigo_de_regime_tributario=str(emp.crt or '1'),
        endereco_logradouro=emp.logradouro,
        endereco_numero=str(emp.numero),
        endereco_bairro=emp.bairro,
        endereco_cep=emp.cep,
        endereco_uf=emp.uf,
        endereco_municipio=emp.municipio,
        endereco_cod_municipio=str(emp.codigo_municipio),
    )
    nf = NotaFiscal(
        emitente=emitente, cliente=None, produtos=[], modelo=65, serie='1',
        numero_nf='1', indicador_destino=1, finalidade_emissao=1,
        cliente_final=1, indicador_presencial=1,
        valor_total_nota=Decimal('100.00'), uf=emp.uf,
        municipio=str(emp.codigo_municipio), tipo_impressao_danfe=4,
        tipo_documento=1, forma_emissao='1', transporte_modalidade_frete=9,
    )
    nf.data_emissao = datetime.now()
    nf.valor_troco = Decimal('0.00')
    nf.adicionar_pagamento(t_pag='01', v_pag=Decimal('100.00'))

    item = ItemFake(
        icms_csosn=icms_csosn,
        icms_cst=icms_cst,
        icms_aliquota=icms_aliquota,
        icms_base_calculo=icms_base_calculo,
    )
    mod.adicionar_produto_com_icms(nf, item, emp)

    ser = SerializacaoXML(mod.MockFonteDados(nf), homologacao=True)
    xml_str = ser.exportar(retorna_string=True)
    # Aplica a correção de blocos do Simples Nacional (mesmo passo do emitir_nfce_pynfe),
    # que renomeia ICMSSN102 -> ICMSSN400/300/103 e ICMSSN202 -> ICMSSN203 conforme o CSOSN.
    from lxml import etree as _etree
    xml_el = _etree.fromstring(xml_str.encode('utf-8'))
    if hasattr(mod, 'corrigir_blocos_icms_simples'):
        mod.corrigir_blocos_icms_simples(xml_el)
    return _etree.tostring(xml_el, encoding='unicode')


def extrair_icms(xml):
    m = re.search(r'<ICMS>.*?</ICMS>', xml, re.DOTALL)
    return m.group(0) if m else '(sem bloco ICMS)'


def executar_alvo(alvo):
    mod = carregar_modulo(alvo)
    nome_alvo = 'functions_py' if alvo == 'cloud' else 'backend_nfce'
    print(f'===== Testando motor: {nome_alvo} =====')

    falhas = []

    def checar(nome, cond, detalhe=''):
        status = 'OK' if cond else 'FALHOU'
        print(f'  [{status}] {nome}' + (f' — {detalhe}' if detalhe else ''))
        if not cond:
            falhas.append(nome)

    # ── CRT 1: Simples Nacional ────────────────────────────────────────────
    xml = montar_xml(mod, crt=1)
    icms = extrair_icms(xml)
    print(f'  CRT=1 -> {icms}')
    checar('CRT 1: bloco ICMSSN102', '<ICMSSN102>' in icms)
    checar('CRT 1: CSOSN 102', '<CSOSN>102</CSOSN>' in icms)
    checar('CRT 1: sem ICMS00', '<ICMS00>' not in icms)
    checar('CRT 1: sem CST', '<CST>' not in icms)

    # ── CRT 1: Simples Nacional / CSOSN 400 (não tributada) ────────────────
    xml = montar_xml(mod, crt=1, icms_csosn='400', icms_cst='00')
    icms = extrair_icms(xml)
    print(f'  CRT=1 CSOSN=400 -> {icms}')
    checar('CRT 1/400: bloco ICMSSN400', '<ICMSSN400>' in icms)
    checar('CRT 1/400: CSOSN 400', '<CSOSN>400</CSOSN>' in icms)
    checar('CRT 1/400: sem ICMS00', '<ICMS00>' not in icms)

    # ── CRT 1: Simples Nacional / CSOSN 500 (substituído - ST anterior) ────
    xml = montar_xml(mod, crt=1, icms_csosn='500', icms_cst='00')
    icms = extrair_icms(xml)
    print(f'  CRT=1 CSOSN=500 -> {icms}')
    checar('CRT 1/500: bloco ICMSSN500', '<ICMSSN500>' in icms)
    checar('CRT 1/500: CSOSN 500', '<CSOSN>500</CSOSN>' in icms)
    checar('CRT 1/500: sem ICMS00', '<ICMS00>' not in icms)

    # ── CRT 2: Simples Nacional (excesso de sublimite) ─────────────────────
    xml = montar_xml(mod, crt=2)
    icms = extrair_icms(xml)
    print(f'  CRT=2 -> {icms}')
    checar('CRT 2: bloco ICMSSN102', '<ICMSSN102>' in icms)
    checar('CRT 2: sem ICMS00', '<ICMS00>' not in icms)

    # ── CRT 3: Regime Normal / CST 00 (ICMS completo) ──────────────────────
    xml = montar_xml(mod, crt=3, icms_cst='00', icms_csosn='102', icms_aliquota=18.0)
    icms = extrair_icms(xml)
    print(f'  CRT=3 CST=00 -> {icms}')
    checar('CRT 3/00: bloco ICMS00', '<ICMS00>' in icms)
    checar('CRT 3/00: CST 00', '<CST>00</CST>' in icms)
    checar('CRT 3/00: modBC 3', '<modBC>3</modBC>' in icms)
    checar('CRT 3/00: vBC 100.00', '<vBC>100.00</vBC>' in icms)
    checar('CRT 3/00: pICMS 18.00', '<pICMS>18.00</pICMS>' in icms)
    checar('CRT 3/00: vICMS 18.00', '<vICMS>18.00</vICMS>' in icms)
    checar('CRT 3/00: sem bloco Simples', 'ICMSSN' not in icms)

    # ── CRT 3: Regime Normal / CST 00 com base de cálculo reduzida (icms_base_calculo) ──
    xml = montar_xml(mod, crt=3, icms_cst='00', icms_csosn='102', icms_aliquota=18.0, icms_base_calculo=90.0)
    icms = extrair_icms(xml)
    print(f'  CRT=3 CST=00 BC=90 -> {icms}')
    checar('CRT 3/00 BC: vBC usa icms_base_calculo (90.00)', '<vBC>90.00</vBC>' in icms)
    checar('CRT 3/00 BC: vICMS recalculado (16.20)', '<vICMS>16.20</vICMS>' in icms)

    # ── CRT 3: Regime Normal / CST 40 (isenta — sem modBC/vBC) ─────────────
    xml = montar_xml(mod, crt=3, icms_cst='40', icms_csosn='102', icms_aliquota=0.0)
    icms = extrair_icms(xml)
    print(f'  CRT=3 CST=40 -> {icms}')
    checar('CRT 3/40: bloco ICMS40', '<ICMS40>' in icms)
    checar('CRT 3/40: CST 40', '<CST>40</CST>' in icms)
    checar('CRT 3/40: sem modBC', '<modBC>' not in icms)
    checar('CRT 3/40: sem bloco Simples', 'ICMSSN' not in icms)

    # ── CRT 3: Regime Normal / CST 60 (substituído - ST anterior) ──────────
    xml = montar_xml(mod, crt=3, icms_cst='60', icms_csosn='102', icms_aliquota=0.0)
    icms = extrair_icms(xml)
    print(f'  CRT=3 CST=60 -> {icms}')
    checar('CRT 3/60: bloco ICMS60', '<ICMS60>' in icms)
    checar('CRT 3/60: CST 60', '<CST>60</CST>' in icms)
    checar('CRT 3/60: sem modBC', '<modBC>' not in icms)
    checar('CRT 3/60: sem bloco Simples', 'ICMSSN' not in icms)

    print()
    if falhas:
        print(f'ERRO: {len(falhas)} verificacao(oes) falhou(ram): {falhas}')
        return 1
    print('OK: todos os cenarios de regime tributario passaram.')
    return 0


def main():
    alvo = 'cloud' if '--cloud' in sys.argv else 'local'
    try:
        return executar_alvo(alvo)
    except Exception as e:  # noqa: BLE001
        import traceback
        print(f'ERRO ao executar o teste: {type(e).__name__}: {e}')
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
