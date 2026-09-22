#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Teste automatizado do serviço de INUTILIZAÇÃO de numeração (NFeInutilizacao4).

Cobre `inutilizar_nfce_pynfe` em backend_nfce/nfce_handler.py:
  - estrutura do XML <inutNFe> validada contra o XSD oficial (inutNFe_v4.00.xsd)
  - montagem do atributo Id (cUF+ano+CNPJ+mod+série+nNFIni+nNFFin)
  - posição da <Signature> (irmã de <infInut>, dentro de <inutNFe>)
  - envelope SOAP 1.2 e URL do serviço por UF/ambiente
  - parse do <retInutNFe>: cStat 102 (homologada), 218 (já inutilizada) e 241 (rejeição)

Sem certificado digital real e sem acesso à internet: a assinatura, o
certificado e o POST são substituídos por dublês.

Uso (na raiz do projeto):
    .venv/Scripts/python.exe backend_nfce/test_inutilizacao.py

Exit code: 0 = sucesso, 1 = falha (útil para CI/regressão).
"""
import base64
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
XSD_INUT = os.path.join(RAIZ, 'backend_pynfe', 'schemes', 'inutNFe_v4.00.xsd')

NS = 'http://www.portalfiscal.inf.br/nfe'
DS = 'http://www.w3.org/2000/09/xmldsig#'


# ── Dublês (sem certificado / sem rede) ───────────────────────────────────────

class _RespFake:
    def __init__(self, text, status_code=200):
        self.text = text
        self.status_code = status_code
        self.encoding = 'utf-8'


def instalar_dubles(resposta_xml):
    """Substitui AssinaturaA1, CertificadoA1 e requests.post por implementações fake."""
    import requests
    import pynfe.processamento.assinatura as assinatura_mod
    import pynfe.entidades.certificado as certificado_mod

    capturado = {}

    class AssinaturaFake:
        def __init__(self, caminho, senha, *args, **kwargs):
            pass

        def assinar(self, xml, retorna_string=False):
            from lxml import etree
            inf = xml.find(f'{{{NS}}}infInut')
            ref_id = inf.attrib['Id']

            sig = etree.SubElement(xml, f'{{{DS}}}Signature')
            signed = etree.SubElement(sig, f'{{{DS}}}SignedInfo')
            etree.SubElement(
                signed, f'{{{DS}}}CanonicalizationMethod',
                Algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315',
            )
            etree.SubElement(
                signed, f'{{{DS}}}SignatureMethod',
                Algorithm='http://www.w3.org/2000/09/xmldsig#rsa-sha1',
            )
            ref = etree.SubElement(signed, f'{{{DS}}}Reference', URI=f'#{ref_id}')
            tr = etree.SubElement(ref, f'{{{DS}}}Transforms')
            etree.SubElement(
                tr, f'{{{DS}}}Transform',
                Algorithm='http://www.w3.org/2000/09/xmldsig#enveloped-signature',
            )
            etree.SubElement(
                tr, f'{{{DS}}}Transform',
                Algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315',
            )
            etree.SubElement(
                ref, f'{{{DS}}}DigestMethod',
                Algorithm='http://www.w3.org/2000/09/xmldsig#sha1',
            )
            etree.SubElement(ref, f'{{{DS}}}DigestValue').text = 'ZmFrZURpZ2VzdA=='
            etree.SubElement(sig, f'{{{DS}}}SignatureValue').text = 'ZmFrZVNpZ25hdHVyZQ=='
            key_info = etree.SubElement(sig, f'{{{DS}}}KeyInfo')
            x509 = etree.SubElement(key_info, f'{{{DS}}}X509Data')
            etree.SubElement(x509, f'{{{DS}}}X509Certificate').text = 'ZmFrZUNlcnQ='

            if retorna_string:
                return etree.tostring(xml, encoding='unicode')
            return xml

    class CertificadoFake:
        def __init__(self, caminho=None):
            pass

        def separar_arquivo(self, senha, caminho=False, *args, **kwargs):
            return ('C:/fake/key.pem', 'C:/fake/cert.pem')

        def excluir(self):
            pass

    def post_fake(url, data=None, headers=None, cert=None, verify=None, timeout=None, **kwargs):
        capturado['url'] = url
        capturado['data'] = data.decode('utf-8') if isinstance(data, bytes) else data
        capturado['headers'] = headers or {}
        return _RespFake(resposta_xml)

    assinatura_mod.AssinaturaA1 = AssinaturaFake
    certificado_mod.CertificadoA1 = CertificadoFake
    requests.post = post_fake
    return capturado


# ── Helpers ───────────────────────────────────────────────────────────────────

class EmpresaFake:
    cnpj = '04829400000165'
    uf = 'SP'
    ambiente_homologacao = True
    certificado_base64 = base64.b64encode(b'pfx-fake').decode()
    senha_certificado = '1234'


def montar_requisicao(numero=248, numero_final=None, serie=2, modelo=65, ano=None,
                      justificativa=None, ambiente_homologacao=True):
    empresa = EmpresaFake()
    empresa.ambiente_homologacao = ambiente_homologacao
    req = {
        'empresa': {
            'cnpj': empresa.cnpj,
            'uf': empresa.uf,
            'ambiente_homologacao': empresa.ambiente_homologacao,
            'certificado_base64': empresa.certificado_base64,
            'senha_certificado': empresa.senha_certificado,
        },
        'serie': serie,
        'numero': numero,
        'modelo': modelo,
    }
    if numero_final is not None:
        req['numero_final'] = numero_final
    if ano is not None:
        req['ano'] = ano
    if justificativa is not None:
        req['justificativa'] = justificativa
    return req


def resposta_ret_inut(cstat='102', xmotivo='Inutilizacao de numero homologado',
                      nprot='135260000012345', com_soap=True):
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        f'<retInutNFe versao="4.00" xmlns="{NS}">'
        '<infInut Id="ID352600482940000016565002000000248000000248">'
        '<tpAmb>2</tpAmb><verAplic>SP_NFE_PL009_V4</verAplic>'
        f'<cStat>{cstat}</cStat><xMotivo>{xmotivo}</xMotivo>'
        '<cUF>35</cUF><ano>26</ano><CNPJ>04829400000165</CNPJ><mod>65</mod>'
        '<serie>2</serie><nNFIni>248</nNFIni><nNFFin>248</nNFFin>'
        '<dhRecbto>2026-09-22T10:00:00-03:00</dhRecbto>'
        + (f'<nProt>{nprot}</nProt>' if nprot else '')
        + '</infInut></retInutNFe>'
    )
    if not com_soap:
        return xml
    return (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">'
        '<soap:Body><nfeInutilizacaoNFResult xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeInutilizacao4">'
        + xml +
        '</nfeInutilizacaoNFResult></soap:Body></soap:Envelope>'
    )


def extrair_inutnfe(soap):
    """Recorta o <inutNFe>..</inutNFe> do envelope SOAP enviado."""
    ini = soap.find('<inutNFe')
    fim = soap.find('</inutNFe>')
    if ini < 0 or fim < 0:
        return ''
    return soap[ini:fim + len('</inutNFe>')]


def carregar_modulo():
    sys.path.insert(0, AQUI)
    import importlib
    return importlib.import_module('nfce_handler')


# ── Execução ──────────────────────────────────────────────────────────────────

def executar():
    from lxml import etree

    mod = carregar_modulo()
    falhas = []

    def checar(nome, cond, detalhe=''):
        marca = 'OK  ' if cond else 'FALHA'
        extra = f' -> {detalhe}' if detalhe and not cond else ''
        print(f'  [{marca}] {nome}{extra}')
        if not cond:
            falhas.append(nome)

    # ═══ 1. XML válido no XSD oficial + Id + Signature na posição certa ═══
    print('\n1) Estrutura do XML (XSD oficial inutNFe_v4.00.xsd)')
    capturado = instalar_dubles(resposta_ret_inut())
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=248, serie=2))
    soap = capturado.get('data') or ''
    chave_xml = extrair_inutnfe(soap)

    checar('retorno success', ret.get('success') is True, str(ret))
    checar('XML <inutNFe> presente no envelope', chave_xml.startswith('<inutNFe'), soap[:200])
    checar('envelope SOAP usa nfeDadosMsg do NFeInutilizacao4',
           'xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeInutilizacao4"' in soap)
    checar('SOAPAction correta',
           'NFeInutilizacao4/nfeInutilizacaoNF' in (capturado.get('headers') or {}).get('Content-Type', ''))
    checar('URL de homologação SP',
           capturado.get('url') == 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx',
           str(capturado.get('url')))

    if chave_xml:
        raiz = etree.fromstring(chave_xml.encode('utf-8'))
        inf = raiz.find(f'{{{NS}}}infInut')
        id_gerado = inf.attrib.get('Id', '')
        esperado = 'ID' + '35' + '26' + '04829400000165' + '65' + '002' + '000000248' + '000000248'
        checar('Id do infInut (cUF+ano+CNPJ+mod+série+nNFIni+nNFFin)', id_gerado == esperado,
               f'{id_gerado} != {esperado}')
        checar('ordem dos elementos do infInut',
               [etree.QName(e).localname for e in inf] ==
               ['tpAmb', 'xServ', 'cUF', 'ano', 'CNPJ', 'mod', 'serie', 'nNFIni', 'nNFFin', 'xJust'],
               str([etree.QName(e).localname for e in inf]))
        checar('tpAmb = 2 (homologação)', inf.findtext(f'{{{NS}}}tpAmb') == '2')
        checar('xServ = INUTILIZAR', inf.findtext(f'{{{NS}}}xServ') == 'INUTILIZAR')
        checar('mod = 65 (NFC-e)', inf.findtext(f'{{{NS}}}mod') == '65')

        checar('Signature é irmã de infInut (filha de inutNFe)',
               [etree.QName(e).localname for e in raiz] == ['infInut', 'Signature'],
               str([etree.QName(e).localname for e in raiz]))

        if os.path.exists(XSD_INUT):
            try:
                schema = etree.XMLSchema(etree.parse(XSD_INUT))
                valido = schema.validate(etree.fromstring(chave_xml.encode('utf-8')))
                erro = '' if valido else str(schema.error_log.filter_from_errors()[0])
                checar('XML validado contra o XSD oficial', valido, erro)
            except Exception as e:  # noqa: BLE001
                checar('XML validado contra o XSD oficial', False, f'erro ao carregar XSD: {e}')
        else:
            print(f'  [SKIP ] XSD não encontrado em {XSD_INUT}')

    # ═══ 2. Faixa de números + justificativa curta ═══
    print('\n2) Faixa de numeração e justificativa')
    capturado = instalar_dubles(resposta_ret_inut())
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(
        numero=100, numero_final=105, serie=1, ano=26, justificativa='curta'))
    chave_xml = extrair_inutnfe(capturado.get('data') or '')
    raiz = etree.fromstring(chave_xml.encode('utf-8'))
    inf = raiz.find(f'{{{NS}}}infInut')
    checar('Id da faixa usa nNFIni e nNFFin', inf.attrib['Id'].endswith('000000100000000105'),
           inf.attrib['Id'])
    checar('nNFIni = 100', inf.findtext(f'{{{NS}}}nNFIni') == '100')
    checar('nNFFin = 105', inf.findtext(f'{{{NS}}}nNFFin') == '105')
    just = inf.findtext(f'{{{NS}}}xJust') or ''
    checar('justificativa curta é substituída (>= 15 chars)', len(just) >= 15, just)

    # ═══ 3. Rejeição da SEFAZ ═══
    print('\n3) Rejeições')
    instalar_dubles(resposta_ret_inut(
        cstat='241', xmotivo='Rejeicao: Um numero da faixa ja foi utilizado', nprot=''))
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=248))
    checar('cStat 241 -> success=False', ret.get('success') is False, str(ret))
    checar('cStat 241 -> mensagem da SEFAZ no error', '241' in str(ret.get('error')), str(ret))

    instalar_dubles(resposta_ret_inut(
        cstat='218', xmotivo='Rejeicao: NF-e ja esta inutilizada na Base de Dados da SEFAZ'))
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=248))
    checar('cStat 218 -> success=True (número já queimado)', ret.get('success') is True, str(ret))
    checar('cStat 218 -> flag ja_inutilizada', ret.get('ja_inutilizada') is True, str(ret))

    # ═══ 4. Resposta sem envelope SOAP (fallback de parse) ═══
    print('\n4) Resposta sem envelope SOAP')
    instalar_dubles(resposta_ret_inut(com_soap=False))
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=248))
    checar('parse sem SOAP -> success', ret.get('success') is True, str(ret))
    checar('protocolo extraído do nProt', ret.get('protocolo') == '135260000012345', str(ret.get('protocolo')))

    # ═══ 5. Validações de entrada ═══
    print('\n5) Validações de entrada')
    instalar_dubles(resposta_ret_inut())
    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=0))
    checar('número 0 -> recusado sem chamar SEFAZ', ret.get('success') is False, str(ret))

    ret = mod.inutilizar_nfce_pynfe(montar_requisicao(numero=10, numero_final=5))
    checar('faixa invertida -> recusada', ret.get('success') is False, str(ret))

    req = montar_requisicao(numero=248)
    req['empresa']['certificado_base64'] = ''
    ret = mod.inutilizar_nfce_pynfe(req)
    checar('sem certificado -> recusado', ret.get('success') is False, str(ret))

    req = montar_requisicao(numero=248)
    req['empresa']['uf'] = 'XX'
    req['empresa']['ambiente_homologacao'] = False
    ret = mod.inutilizar_nfce_pynfe(req)
    checar('UF inválida -> recusada', ret.get('success') is False, str(ret))

    print()
    if falhas:
        print(f'ERRO: {len(falhas)} verificacao(oes) falhou(ram): {falhas}')
        return 1
    print('OK: todos os cenarios de inutilizacao passaram.')
    return 0


def main():
    try:
        return executar()
    except Exception as e:  # noqa: BLE001
        import traceback
        print(f'ERRO ao executar o teste: {type(e).__name__}: {e}')
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
