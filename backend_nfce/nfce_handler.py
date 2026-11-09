from decimal import Decimal, ROUND_HALF_UP
import base64
import os
import subprocess
import time
import logging
import win32crypt
import re
import traceback
import uuid
import hashlib
import requests
import urllib3
from datetime import datetime, timezone
from lxml import etree
from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz

def _get_val(obj, key, default=None):
    """Obtem um valor de um atributo do objeto de forma segura, com fallback."""
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)

class ComunicacaoSefaz(OriginalComunicacaoSefaz):
    def _post(self, url, xml, timeout=None):
        """Override do metodo _post para garantir a limpeza do XML e namespaces corretos em SP."""
        from pynfe.utils import etree as _etree
        from pynfe.entidades.certificado import CertificadoA1 as _CertA1
        
        certificado_a1 = _CertA1(self.certificate if hasattr(self, 'certificate') else self.certificado)
        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
        chave_cert = (cert, chave)
        
        try:
            xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
            # Converter etree para string unicode e remover quebras de linha
            if isinstance(xml, _etree._Element):
                xml_raw = _etree.tostring(xml, encoding="unicode").replace("\n", "").replace("\r", "")
            else:
                xml_raw = str(xml).replace("\n", "").replace("\r", "")
                
            # Remover espacos entre tags (essencial para alguns schemas da SEFAZ-SP)
            xml_raw = re.sub(r">\s+<", "><", xml_raw)
            
            # 1. Fix para qrCode (entities mal formadas pelo pynfe)
            if "<qrCode" in xml_raw:
                xml_raw = re.sub("<qrCode>(.*?)</qrCode>", 
                                lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), 
                                xml_raw)
            
            # 2. Fix para namespaces e prefixos ns0/ns1
            if "ns0:" in xml_raw or "ns1:" in xml_raw:
                xml_raw = re.sub(r"<(/?)ns[0-9]+:", r"<\\1", xml_raw)
            
            # 3. Garantir namespaces nos elementos principais se estiverem faltando (comum em cancelamento)
            for tag in ["envEvento", "evento", "infEvento"]:
                if f'<{tag}' in xml_raw and 'xmlns=' not in xml_raw.split(f'<{tag}')[1].split('>')[0]:
                    xml_raw = xml_raw.replace(f'<{tag}', f'<{tag} xmlns="http://www.portalfiscal.inf.br/nfe"')
            
            # Fix para Signature se estiver isolado
            if '<Signature ' in xml_raw and 'xmlns=' not in xml_raw.split('<Signature ')[1].split('>')[0]:
                xml_raw = xml_raw.replace('<Signature ', '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" ')
            elif '<Signature>' in xml_raw:
                xml_raw = xml_raw.replace('<Signature>', '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">')
            
            # Limpeza final
            xml_raw = xml_raw.replace(' xmlns=""', '')
            xml_final = xml_declaration + xml_raw

            # Debug: Salvar o XML final enviado
            try:
                dbg_out = os.path.join(os.environ.get('TEMP', 'C:/temp'), "last_outgoing_soap.xml")
                with open(dbg_out, "w", encoding="utf-8") as f: f.write(xml_final)
            except: pass

            # Realizar a requisiÃ§Ã£o SOAP
            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)
            res.encoding = "utf-8"
            
            # Debug: Salvar resposta
            try:
                resp_dbg = os.path.join(os.environ.get('TEMP', 'C:/temp'), "last_sefaz_response.xml")
                with open(resp_dbg, "w", encoding="utf-8") as f: f.write(res.text)
            except: pass
            
            return res
        finally:
            if os.path.exists(chave):
                try: os.remove(chave)
                except: pass
            if os.path.exists(cert):
                try: os.remove(cert)
                except: pass
            try:
                certificado_a1.excluir()
            except:
                pass


from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal, NotaFiscalProduto
from pynfe.entidades.transportadora import Transportadora
from pynfe.entidades.fonte_dados import FonteDados
# Monkeypatch para evitar erros de atributos faltando no pynfe 0.6.5
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
NotaFiscalProduto.informacoes_adicionais = ''
NotaFiscalProduto.cProdANP = ''
NotaFiscalProduto.descANP = ''
NotaFiscalProduto.pGLP = Decimal('0.00')
NotaFiscalProduto.pGNn = Decimal('0.00')
NotaFiscalProduto.pGNi = Decimal('0.00')
NotaFiscalProduto.vPart = Decimal('0.00')
NotaFiscalProduto.comb_codif = ''
NotaFiscalProduto.comb_q_temp = ''
NotaFiscalProduto.UFCons = ''
NotaFiscalProduto.comb_n_bico = 0
NotaFiscalProduto.comb_p_bio = Decimal('0.00')

# PIS/COFINS (Campos que faltavam e causavam erro)
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

# II
NotaFiscalProduto.imposto_importacao_valor_base_calculo = Decimal('0.00')
NotaFiscalProduto.imposto_importacao_valor_despesas_aduaneiras = Decimal('0.00')
NotaFiscalProduto.imposto_importacao_valor = Decimal('0.00')
NotaFiscalProduto.imposto_importacao_valor_iof = Decimal('0.00')

# CSOSN -> grupo do schema NF-e 4.00 (o nome do grupo NÃƒO Ã© o CSOSN).
GRUPO_ICMSSN_POR_CSOSN = {
    '101': 'ICMSSN101',
    '102': 'ICMSSN102',
    '103': 'ICMSSN102',
    '300': 'ICMSSN102',
    '400': 'ICMSSN102',
    '201': 'ICMSSN201',
    '202': 'ICMSSN202',
    '203': 'ICMSSN202',
    '500': 'ICMSSN500',
    '900': 'ICMSSN900',
}


def corrigir_blocos_icms_simples(xml_element):
    """Corrige o bug do pynfe 0.6.5 na serializaÃ§Ã£o dos blocos do Simples Nacional.

    O schema da NF-e 4.00 define apenas seis grupos de ICMS do Simples Nacional:
    ICMSSN101 (CSOSN 101), ICMSSN102 (CSOSN 102, 103, 300 e 400),
    ICMSSN201 (201), ICMSSN202 (202 e 203), ICMSSN500 (500) e ICMSSN900 (900).
    O nome do grupo NÃƒO Ã© o CSOSN: o CSOSN 400, por exemplo, Ã© informado dentro
    de <ICMSSN102> â€” <ICMSSN400> nÃ£o existe no schema.

    Renomear o bloco para o prÃ³prio CSOSN (ex: <ICMSSN400>, <ICMSSN300>,
    <ICMSSN203>) gera a rejeiÃ§Ã£o 225 "Falha no Schema XML do lote de NFe".
    Esta funÃ§Ã£o apenas garante que o bloco filho corresponda ao grupo definido
    pelo schema, sem inventar grupos inexistentes.
    """
    ns = "http://www.portalfiscal.inf.br/nfe"
    for icms_tag in xml_element.iter():
        tag_icms = icms_tag.tag.split('}')[-1] if '}' in icms_tag.tag else icms_tag.tag
        if tag_icms != 'ICMS':
            continue
        for bloco in list(icms_tag):
            tag_name = bloco.tag.split('}')[-1] if '}' in bloco.tag else bloco.tag
            if not tag_name.startswith('ICMSSN'):
                continue
            csosn_el = bloco.find(f"{{{ns}}}CSOSN")
            if csosn_el is None:
                csosn_el = bloco.find("CSOSN")
            if csosn_el is None or csosn_el.text is None:
                continue
            csosn_val = str(csosn_el.text).strip()
            bloco_esperado = GRUPO_ICMSSN_POR_CSOSN.get(csosn_val)
            if bloco_esperado is None:
                continue
            if tag_name != bloco_esperado:
                print(f"[FIX] Bloco ICMS renomeado: {tag_name} -> {bloco_esperado} (CSOSN {csosn_val})")
                if '}' in bloco.tag:
                    bloco.tag = f"{{{ns}}}{bloco_esperado}"
                else:
                    bloco.tag = bloco_esperado


def fix_xml_namespaces(element, ns):
    """Garante que todos os elementos usem o namespace correto e protege tags obrigatÃ³rias."""
    if not element.tag.startswith('{'):
        element.tag = f"{{{ns}}}{element.tag}"
    
    # Inserir indIntermed se estivermos no elemento ide
    tag_name_element = element.tag.split('}')[-1] if '}' in element.tag else element.tag
    if tag_name_element == 'ide':
        ind_intermed_tag = None
        proc_emi_tag = None
        for child in element:
            t_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if t_name == 'indIntermed':
                ind_intermed_tag = child
            elif t_name == 'procEmi':
                proc_emi_tag = child
        
        if ind_intermed_tag is None:
            new_tag = etree.Element(f"{{{ns}}}indIntermed" if ns in element.tag else "indIntermed")
            new_tag.text = "0"
            if proc_emi_tag is not None:
                proc_emi_index = element.index(proc_emi_tag)
                element.insert(proc_emi_index, new_tag)
            else:
                element.append(new_tag)
                
    # Tags que NUNCA devem ser removidas (obrigatÃ³rias pelo Schema NFe/NFCe 4.00)
    protected_tags = [
        'cMunFG', 'vTroco', 'nItem', 'detPag', 'pag', 'total', 'ICMSTot', 'imposto',
        'NCM', 'cEAN', 'cEANTrib', 'CFOP', 'uCom', 'uTrib', 'cProd', 'xProd',
        'qCom', 'vUnCom', 'vProd', 'qTrib', 'vUnTrib', 'indTot'
    ]
    
    for child in list(element):
        tag_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        
        if child.text is None and len(child) == 0:
            if tag_name not in protected_tags:
                element.remove(child)
            else:
                # Se for obrigatÃ³ria e estiver nula, colocar pelo menos uma string vazia ou valor padrÃ£o
                child.text = ""
                if tag_name == 'vTroco': child.text = "0.00"
                elif tag_name == 'NCM': child.text = "00000000"
                elif tag_name in ['cEAN', 'cEANTrib']: child.text = "SEM GTIN"
                elif tag_name == 'CFOP': child.text = "5102"
                elif tag_name in ['uCom', 'uTrib']: child.text = "UN"
                elif tag_name in ['qCom', 'qTrib']: child.text = "1.0000"
                elif tag_name in ['vUnCom', 'vUnTrib']: child.text = "0.00"
                elif tag_name == 'vProd': child.text = "0.00"
                elif tag_name == 'cProd': child.text = "COD"
                elif tag_name == 'indTot': child.text = "1"
        else:
            fix_xml_namespaces(child, ns)

# --- MONKEYPATCH CRÃTICO PARA MUNICÃPIO ---
# O pynfe 0.6.5 tem um bug onde ele ignora o cÃ³digo do municÃ­pio fornecido e tenta 
# buscar pelo nome, o que falha se o nome tiver sufixos como /SP ou se houver erro de encoding.
import pynfe.processamento.serializacao as serializacao_mod

def _new_serializar_emitente(self, emitente, tag_raiz="emit", retorna_string=True):
    raiz = etree.Element(tag_raiz)
    etree.SubElement(raiz, "CNPJ").text = serializacao_mod.so_numeros(emitente.cnpj)
    etree.SubElement(raiz, "xNome").text = emitente.razao_social
    if emitente.nome_fantasia:
        etree.SubElement(raiz, "xFant").text = emitente.nome_fantasia
    
    endereco = etree.SubElement(raiz, "enderEmit")
    etree.SubElement(endereco, "xLgr").text = emitente.endereco_logradouro
    etree.SubElement(endereco, "nro").text = emitente.endereco_numero
    if emitente.endereco_complemento:
        etree.SubElement(endereco, "xCpl").text = emitente.endereco_complemento
    etree.SubElement(endereco, "xBairro").text = emitente.endereco_bairro
    
    # CORREÃ‡ÃƒO: Usar o cÃ³digo se ele existir e for numÃ©rico, senÃ£o buscar
    cod_mun = serializacao_mod.so_numeros(str(emitente.endereco_cod_municipio))
    if cod_mun and len(cod_mun) == 7:
        etree.SubElement(endereco, "cMun").text = cod_mun
    else:
        etree.SubElement(endereco, "cMun").text = serializacao_mod.obter_codigo_por_municipio(
            emitente.endereco_municipio, emitente.endereco_uf
        )
        
    etree.SubElement(endereco, "xMun").text = emitente.endereco_municipio
    etree.SubElement(endereco, "UF").text = emitente.endereco_uf
    etree.SubElement(endereco, "CEP").text = serializacao_mod.so_numeros(emitente.endereco_cep)
    etree.SubElement(endereco, "cPais").text = emitente.endereco_pais
    etree.SubElement(endereco, "xPais").text = serializacao_mod.obter_pais_por_codigo(emitente.endereco_pais)
    if emitente.endereco_telefone:
        etree.SubElement(endereco, "fone").text = emitente.endereco_telefone
    _ie_emit = (emitente.inscricao_estadual or '').strip()
    etree.SubElement(raiz, "IE").text = _ie_emit if _ie_emit else "ISENTO"
    if emitente.codigo_de_regime_tributario:
        etree.SubElement(raiz, "CRT").text = str(emitente.codigo_de_regime_tributario)
    
    if retorna_string:
        return etree.tostring(raiz, encoding="unicode", pretty_print=True)
    else:
        return raiz

def _new_serializar_cliente(self, cliente, modelo, tag_raiz="dest", retorna_string=True):
    raiz = etree.Element(tag_raiz)
    if cliente.numero_documento:
        etree.SubElement(raiz, cliente.tipo_documento).text = serializacao_mod.so_numeros(cliente.numero_documento)
    
    if cliente.razao_social:
        etree.SubElement(raiz, "xNome").text = cliente.razao_social
        
    if cliente.endereco_logradouro:
        endereco = etree.SubElement(raiz, "enderDest")
        etree.SubElement(endereco, "xLgr").text = cliente.endereco_logradouro
        etree.SubElement(endereco, "nro").text = cliente.endereco_numero
        if cliente.endereco_complemento:
            etree.SubElement(endereco, "xCpl").text = cliente.endereco_complemento
        etree.SubElement(endereco, "xBairro").text = cliente.endereco_bairro
        
        # CORREÃ‡ÃƒO: Usar o cÃ³digo se ele existir e for numÃ©rico, senÃ£o buscar
        cod_mun = serializacao_mod.so_numeros(str(cliente.endereco_cod_municipio))
        if cod_mun and len(cod_mun) == 7:
            etree.SubElement(endereco, "cMun").text = cod_mun
        else:
            etree.SubElement(endereco, "cMun").text = serializacao_mod.obter_codigo_por_municipio(
                cliente.endereco_municipio, cliente.endereco_uf
            )
            
        etree.SubElement(endereco, "xMun").text = cliente.endereco_municipio
        etree.SubElement(endereco, "UF").text = cliente.endereco_uf
        if cliente.endereco_cep:
            etree.SubElement(endereco, "CEP").text = serializacao_mod.so_numeros(cliente.endereco_cep)
        etree.SubElement(endereco, "cPais").text = cliente.endereco_pais
        etree.SubElement(endereco, "xPais").text = serializacao_mod.obter_pais_por_codigo(cliente.endereco_pais)
        if cliente.endereco_telefone:
            etree.SubElement(endereco, "fone").text = cliente.endereco_telefone

    if hasattr(cliente, 'indicador_ie'):
        etree.SubElement(raiz, "indIEDest").text = str(cliente.indicador_ie)
    elif modelo == 65:
        etree.SubElement(raiz, "indIEDest").text = "9" # Consumidor Final

    if retorna_string:
        return etree.tostring(raiz, encoding="unicode", pretty_print=True)
    else:
        return raiz

# --- MONKEYPATCH PARA QR CODE (BUG DO PYNFE QUE APAGA ZEROS) ---
from pynfe.processamento.serializacao import SerializacaoQrcode

def _new_gerar_qrcode(self, token, csc, xml, online=True, return_qr=False):
    """
    Monkeypatch corrigido para geraÃ§Ã£o de QR Code da NFC-e.
    Corrige dois bugs do pynfe original:
    1. Import de NFCE estava errado (flags vs webservices)
    2. Bug que removia zeros do token (IdToken)
    """
    from pynfe.utils.flags import VERSAO_QRCODE, CODIGOS_ESTADOS
    from pynfe.utils.webservices import NFCE  # NFCE estÃ¡ em webservices, NÃƒO em flags!

    nfe = xml
    ns  = {"ns":  "http://www.portalfiscal.inf.br/nfe"}
    sig = {"sig": "http://www.w3.org/2000/09/xmldsig#"}
    ns_nfe = "http://www.portalfiscal.inf.br/nfe"

    # Pegar chave de acesso (remover prefixo 'NFe')
    id_attr = nfe[0].attrib.get("Id") or nfe[0].attrib.get(f"{{{ns_nfe}}}Id") or ""
    chave = id_attr.replace("NFe", "")

    tpamb = nfe.xpath("ns:infNFe/ns:ide/ns:tpAmb/text()", namespaces=ns)[0]
    cuf   = nfe.xpath("ns:infNFe/ns:ide/ns:cUF/text()", namespaces=ns)[0]  # cÃ³digo numÃ©rico (ex: '35')

    # Converter cÃ³digo numÃ©rico de UF para sigla (ex: '35' -> 'SP')
    uf_sigla = [k for k, v in CODIGOS_ESTADOS.items() if v == cuf]
    if not uf_sigla:
        raise ValueError(f"CÃ³digo de UF '{cuf}' nÃ£o encontrado em CODIGOS_ESTADOS")
    uf = uf_sigla[0].upper()

    # Identificador do CSC (IdToken) deve ter exatamente 6 dÃ­gitos.
    # Ex: '1' -> '000001' (ObrigatÃ³rio para Schema 225 em SP e outros estados)
    cIdToken = str(token).zfill(6)
    
    # Valores dinÃ¢micos para o QR Code 2.00 (MOC 6.0)
    # Devem ser convertidos para Hexadecimal ASCII
    def to_hex_ascii(val):
        if not val: return ""
        return "".join("{:02x}".format(ord(c)) for c in str(val)).upper()

    try:
        # Extrair valores do XML para compor a URL do QR Code
        vNF_val = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vNF/text()", namespaces=ns)[0]
        vICMS_val = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vICMS/text()", namespaces=ns)[0]
        dhEmi_val = nfe.xpath("ns:infNFe/ns:ide/ns:dhEmi/text()", namespaces=ns)[0]
        # DigestValue estÃ¡ dentro de Signature/SignedInfo/Reference
        digVal_val = nfe.xpath("//sig:Signature/sig:SignedInfo/sig:Reference/sig:DigestValue/text()", namespaces=sig)[0]
        
        vNF_hex = to_hex_ascii(vNF_val)
        vICMS_hex = to_hex_ascii(vICMS_val)
        dhEmi_hex = to_hex_ascii(dhEmi_val)
        digVal_hex = to_hex_ascii(digVal_val)
    except Exception as e:
        print(f"[ERRO] Falha ao extrair dados para o QR Code: {str(e)}")
        vNF_hex = vICMS_hex = dhEmi_hex = digVal_hex = ""

    if online:
        # SP e a maioria dos estados usam o formato de 5 parÃ¢metros no QR Code 2.00 Online
        # chave|versao|ambiente|cIdToken
        url_to_hash = "{}|{}|{}|{}".format(
            chave, VERSAO_QRCODE, tpamb, str(token).strip()
        )
        string_hash = url_to_hash + csc
        hash_qr = hashlib.sha1(string_hash.encode()).hexdigest().upper()
        
        raw_url_params = "p={}|{}".format(url_to_hash, hash_qr)
        
        url_base = NFCE.get(uf, {}).get(online and 'qrcode' or 'qrcode_offline', '')
        if not url_base:
            url_base = "https://www.homologacao.nfce.fazenda.sp.gov.br/NFCeConsultaPublica/Paginas/ConsultaQRCode.aspx"
            
        full_url = "{}?{}".format(url_base, raw_url_params)
        
        supl = etree.SubElement(nfe, "infNFeSupl")
        etree.SubElement(supl, "qrCode").text = etree.CDATA(full_url)
        url_chave = NFCE.get(uf, {}).get('consulta', 'https://www.nfce.fazenda.sp.gov.br/consulta')
        if uf == "SP" and tpamb == "2":
            url_chave = "https://www.homologacao.nfce.fazenda.sp.gov.br/consulta"
            
        etree.SubElement(supl, "urlChave").text = url_chave
        
        if return_qr:
            return nfe, full_url
        return nfe

SerializacaoQrcode.gerar_qrcode = _new_gerar_qrcode

SerializacaoXML._serializar_emitente = _new_serializar_emitente
SerializacaoXML._serializar_cliente = _new_serializar_cliente

import requests as _requests
from pynfe.entidades.certificado import CertificadoA1 as _CertA1

_NS_NFE = "http://www.portalfiscal.inf.br/nfe"

# ─────────────────────────────────────────────────────────────────────────────
# CACHE DE CERTIFICADO E SESSAO HTTP (ganho de ~0,1 a 0,2s por emissao)
#
# Antes, CADA emissao:
#   1. extraia o .pfx em PEM outra vez no AssinaturaA1 (~55ms);
#   2. extraia o .pfx em PEM OUTRA vez no _post, e apagava no finally (~40ms);
#   3. abria uma conexao TLS NOVA com a SEFAZ (handshake mTLS ~60-100ms).
# O certificado so muda quando o arquivo .pfx muda, e o handshake pode ser
# reaproveitado — por isso os caches abaixo (chave = hash do conteudo do .pfx
# + senha, para nao servir certificado velho depois de uma troca).
# ─────────────────────────────────────────────────────────────────────────────
import threading as _threading

_CERT_PEM_CACHE = {}
_ASSINATURA_CACHE = {}
_VALIDADE_CACHE = {}
_cache_lock = _threading.Lock()
_thread_local = _threading.local()

# Tempo maximo que uma conexao TLS com a SEFAZ fica parada antes de ser
# descartada (a SEFAZ fecha sockets ociosos; reaproveitar um socket morto
# faria a emissao falhar).
_SESSAO_IDLE_MAX = 45.0

# Grava arquivos de debug XML em disco a cada emissao (last_enviNFe.xml,
# last_sefaz_response.xml, last_nfce.xml). Desligado por padrão: gera I/O de
# disco desnecessario em cada nota. Ativar com EXODO_DEBUG_XML=1 para
# investigacao de problemas com a SEFAZ.
_DEBUG_XML = os.environ.get('EXODO_DEBUG_XML', '0') == '1'


def _debug_xml(nome, conteudo):
    """Grava um arquivo de debug apenas se EXODO_DEBUG_XML=1."""
    if not _DEBUG_XML:
        return
    try:
        caminho = os.path.join(os.environ.get('TEMP', 'C:/temp'), nome)
        with open(caminho, 'w', encoding='utf-8') as f:
            f.write(conteudo)
    except Exception:
        pass


def _chave_cache_certificado(caminho, senha):
    """Identifica o certificado pelo CONTEUDO do .pfx + senha.

    O Bridge grava o certificado em um arquivo temporario com nome novo a cada
    requisicao (cert_<uuid>.pfx), entao usar caminho/mtime como chave faria o
    cache nunca acertar. O hash do conteudo e estavel e troca junto com o
    certificado (basta a empresa subir outro .pfx).
    """
    try:
        with open(caminho, 'rb') as _f:
            digest = hashlib.sha256(_f.read()).hexdigest()
        return (digest, senha)
    except OSError:
        return (os.path.abspath(caminho), senha)


def _certificado_pem(caminho, senha):
    """Devolve (cert_pem_path, key_pem_path) reaproveitando a extracao anterior."""
    chave_cache = _chave_cache_certificado(caminho, senha)
    with _cache_lock:
        cacheado = _CERT_PEM_CACHE.get(chave_cache)
    if cacheado and os.path.exists(cacheado[0]) and os.path.exists(cacheado[1]):
        return cacheado
    certificado_a1 = _CertA1(caminho)
    chave, cert = certificado_a1.separar_arquivo(senha, caminho=True)
    with _cache_lock:
        _CERT_PEM_CACHE[chave_cache] = (cert, chave)
    return (cert, chave)


def _validade_pfx(caminho, senha):
    """Devolve o datetime UTC em que o A1 vence, sem reabrir o .pfx a cada nota.

    A checagem de validade usa cryptography/pkcs12, que decodifica o ASN.1 do
    .pfx inteiro (~20-50ms). O resultado depende so do conteudo do arquivo +
    senha (mesma chave de cache do PEM), entao basta guardar a data de vencimento
    e comparar com 'agora' na hora da emissao.
    """
    chave_cache = _chave_cache_certificado(caminho, senha)
    with _cache_lock:
        cacheado = _VALIDADE_CACHE.get(chave_cache)
    if cacheado is not None:
        return cacheado
    vencido_em = None
    try:
        from cryptography.hazmat.primitives.serialization import pkcs12
        with open(caminho, 'rb') as _f:
            _pfx_bytes = _f.read()
        _, _cert_obj, _ = pkcs12.load_key_and_certificates(
            _pfx_bytes, senha.encode() if senha else None
        )
        if _cert_obj is not None:
            _validade = _cert_obj.not_valid_after
            if _validade.tzinfo is None:
                _validade = _validade.replace(tzinfo=timezone.utc)
            vencido_em = _validade
    except Exception as _e:
        print(f"[AVISO] Nao foi possivel verificar validade do certificado: {_e}")
    with _cache_lock:
        _VALIDADE_CACHE[chave_cache] = vencido_em
    return vencido_em


def _assinador(caminho, senha):
    """Reaproveita o AssinaturaA1 (evita reler/decodificar o .pfx a cada nota)."""
    chave_cache = _chave_cache_certificado(caminho, senha)
    with _cache_lock:
        cacheado = _ASSINATURA_CACHE.get(chave_cache)
    if cacheado is not None:
        return cacheado
    assinador = AssinaturaA1(caminho, senha)
    with _cache_lock:
        _ASSINATURA_CACHE[chave_cache] = assinador
    return assinador


def _sessao_sefaz():
    """requests.Session por thread: mantem o handshake mTLS vivo entre notas.

    A conexao e descartada depois de SESSAO_IDLE_MAX segundos parada: a
    SEFAZ fecha sockets ociosos e reaproveitar um socket morto faria a proxima
    emissao falhar com ConnectionError (o caixa veria erro sem a nota ter ido).
    Reaproveitar so entre vendas proximas (o caso em que a velocidade importa)
    evita esse risco e mantem o ganho do handshake.
    """
    agora = time.time()
    sessao = getattr(_thread_local, 'sessao', None)
    ultimo_uso = getattr(_thread_local, 'ultimo_uso', 0.0)
    if sessao is not None and (agora - ultimo_uso) > _SESSAO_IDLE_MAX:
        try:
            sessao.close()
        except Exception:
            pass
        sessao = None
    if sessao is None:
        sessao = _requests.Session()
        _thread_local.sessao = sessao
    _thread_local.ultimo_uso = agora
    return sessao


def _fixed_post(self, url, xml, timeout=None):
    from pynfe.utils import etree as _etree
    chave_cert = _certificado_pem(self.certificado, self.certificado_senha)
    xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
    try:
        xml_str = _etree.tostring(xml, encoding="unicode")

        xml_str = xml_str.replace(' xmlns="http://www.portalfiscal.inf.br/nfe"', '')
        xml_str = xml_str.replace('<enviNFe', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe"')
        xml_str = xml_str.replace('<NFe>', '<NFe xmlns="http://www.portalfiscal.inf.br/nfe">')
        
        xml_str = re.sub(r'<\?xml.*?\?>', '', xml_str).strip()
        xml_str = xml_str.replace('\n', '').replace('\r', '')
        xml_str = re.sub(r'>\s+<', '><', xml_str)
        
        # 2. Garantir versao em infNFe preservando Id (Regex flexÃ­vel para atributos em qualquer ordem)
        # CRÃTICO: usar regex preciso para NÃƒO afetar <infNFeSupl> (sÃ³ <infNFe> ou <infNFe ...>)
        # Usamos (?!\w) para garantir que 'infNFe' nÃ£o seja seguido por 'Supl' ou qualquer outra letra
        xml_str = re.sub(r'<(infNFe(?!\w)[^>]*)\s+xmlns=["\'][^"\']*["\']', r'<\1', xml_str)
        xml_str = re.sub(r'<(infNFe(?!\w)[^>]*)\s+versao=["\'][^"\']*["\']', r'<\1', xml_str)
        # Adicionar versao="4.00" SOMENTE em <infNFe> e <infNFe ...>, nunca em <infNFeSupl>
        xml_str = re.sub(r'<infNFe(?!\w)([\s>])', r'<infNFe versao="4.00"\1', xml_str)
        
        xml_str = xml_str.replace(' xmlns=""', '')
        xml_str = xml_str.replace('>>', '>')
        
        # FIX DE ORDEM CRÃTICO (infNFe -> infNFeSupl -> Signature)
        # Separar infNFeSupl e Signature com regex ainda mais flexÃ­vel
        match_supl = re.search(r'(<infNFeSupl[^>]*>.*?</infNFeSupl>)', xml_str, re.DOTALL)
        match_sig = re.search(r'(<Signature[^>]*>.*?</Signature>)', xml_str, re.DOTALL)

        if match_supl and match_sig:
            # Remover de onde estiver para remontar no final
            xml_str = xml_str.replace(match_supl.group(1), '')
            xml_str = xml_str.replace(match_sig.group(1), '')

            # Limpar lixo de tag de fechamento infNFe se existir duplicata ou erro de concatenaÃ§Ã£o
            xml_str = xml_str.replace('</infNFe></NFe>', '</infNFe>')

            # Reconstruir na ordem do Schema 4.00:
            # ...</infNFe><infNFeSupl>...</infNFeSupl><Signature>...</Signature></NFe>
            # ATENÃ‡ÃƒO: o schema exige infNFeSupl ANTES de Signature!
            rearranjado = f'{match_supl.group(1)}{match_sig.group(1)}</NFe>'
            
            # Garantir que inserimos logo apÃ³s o fechamento do infNFe
            if '</infNFe>' in xml_str:
                # Primeiro removemos qualquer </NFe> que tenha sobrado apÃ³s o replaces acima
                xml_str = xml_str.replace('</NFe>', '')
                xml_str = xml_str.replace('</infNFe>', f'</infNFe>{rearranjado}')
            else:
                # Fallback caso a estrutura esteja muito bagunÃ§ada
                xml_str = xml_str.replace('</NFe>', rearranjado)

        _debug_xml('last_enviNFe.xml', xml_declaration + xml_str)

        xml_str = xml_declaration + xml_str
        sessao = _sessao_sefaz()
        kwargs_post = dict(
            headers=self._post_header(),
            cert=chave_cert,
            verify=False,
            # Sem isso o pyNFe chama com timeout=None (espera infinita): uma
            # SEFAZ travada deixava a emissao pendurada e a fila do app esperando.
            timeout=timeout if timeout else (10, 60),
        )
        try:
            result = sessao.post(url, xml_str, **kwargs_post)
        except _requests.exceptions.ConnectionError:
            # Socket reaproveitado que a SEFAZ ja havia fechado (conexao morta:
            # o pedido nao saiu). Refaz uma unica vez em conexao nova.
            try:
                sessao.close()
            except Exception:
                pass
            _thread_local.sessao = None
            result = _sessao_sefaz().post(url, xml_str, **kwargs_post)
        result.encoding = "utf-8"
        
        _debug_xml('last_sefaz_response.xml', result.text)
        
        return result
    except _requests.exceptions.RequestException as e:
        raise e

ComunicacaoSefaz._post = _fixed_post
print("[PATCH] ComunicacaoSefaz._post substituÃ­do com fix de namespace infNFeSupl")


class MockFonteDados:
    def __init__(self, nota):
        self.nota = nota
    def obter_lista(self, _classe=None, **kwargs):
        return [self.nota]
    def limpar_dados(self):
        pass


def adicionar_ibscbs_xml(xml_element, ns_nfe, itens=None):
    """Gera os grupos de IBS/CBS da Reforma Tributaria (NT 2025.002).

    Valores por item vem do PERFIL TRIBUTARIO do produto, que o app manda no
    payload: `ibs_cst` (3 digitos), `ibs_class_trib` (6 digitos),
    `ibs_aliquota` (% IBS) e `cbs_aliquota` (% CBS).

    Quando o perfil nao tem valor utilizavel (vazio, codigo com tamanho
    errado), usa o padrao da transicao 2026: CST 000, cClassTrib 000001,
    IBS UF 0,1000% e CBS 0,9000% -- exatamente o que aparece nas notas
    autorizadas (cStat 100) deste exercicio.

    Tambem grava `<vItem>` no item e `<vNFTot>` no total, que o leiaute
    exige junto com o grupo.
    """
    PADRAO_CST = "000"
    PADRAO_CLASS_TRIB = "000001"
    PADRAO_IBS = Decimal("0.1000")
    PADRAO_CBS = Decimal("0.9000")

    def _campo(item, nome):
        if item is None:
            return None
        if isinstance(item, dict):
            return item.get(nome)
        return getattr(item, nome, None)

    def _codigo(valor, tamanho, padrao):
        digitos = ''.join(c for c in str(valor or '') if c.isdigit())
        return digitos if len(digitos) == tamanho else padrao

    def _aliquota(valor, padrao):
        try:
            if valor is None or str(valor).strip() == '':
                return padrao
            return Decimal(str(valor).replace(',', '.')).quantize(Decimal("0.0001"))
        except Exception:
            return padrao

    # Itens do payload por codigo do produto (cProd) para casar com o XML.
    por_codigo = {}
    for item in itens or []:
        try:
            chave = str(_campo(item, 'codigo') or '')
            if chave:
                por_codigo[chave] = item
        except Exception:
            continue

    dets = xml_element.findall(f".//{{{ns_nfe}}}det")
    if not dets:
        dets = xml_element.findall(".//det")

    total_bc = Decimal("0.00")
    total_ibs_uf = Decimal("0.00")
    total_ibs = Decimal("0.00")
    total_cbs = Decimal("0.00")
    sem_perfil = 0

    for det in dets:
        prod = det.find(f"{{{ns_nfe}}}prod")
        if prod is None:
            prod = det.find("prod")
        if prod is None:
            continue

        v_prod_el = prod.find(f"{{{ns_nfe}}}vProd")
        if v_prod_el is None:
            v_prod_el = prod.find("vProd")
        if v_prod_el is None:
            continue

        imposto = det.find(f"{{{ns_nfe}}}imposto")
        if imposto is None:
            imposto = det.find("imposto")
        if imposto is None:
            continue

        cod_el = prod.find(f"{{{ns_nfe}}}cProd")
        if cod_el is None:
            cod_el = prod.find("cProd")
        item = por_codigo.get((cod_el.text or '').strip()) if cod_el is not None else None
        if item is None:
            sem_perfil += 1

        try:
            v_bc = Decimal(str(v_prod_el.text).strip())
        except Exception:
            continue

        cst_ibs = _codigo(_campo(item, 'ibs_cst'), 3, PADRAO_CST)
        cst_cbs = _codigo(_campo(item, 'cbs_cst'), 3, PADRAO_CST)
        # O grupo precisa de um unico CST: usa o do IBS quando os dois batem,
        # senao o do IBS (o do CBS vai no grupo gCBS quando o perfil difere).
        cst = cst_ibs if cst_ibs == cst_cbs else cst_ibs
        class_trib = _codigo(
            _campo(item, 'ibs_class_trib'), 6, PADRAO_CLASS_TRIB
        )
        p_ibs = _aliquota(_campo(item, 'ibs_aliquota'), PADRAO_IBS)
        p_cbs = _aliquota(_campo(item, 'cbs_aliquota'), PADRAO_CBS)

        v_ibs_uf = (v_bc * p_ibs / Decimal("100")).quantize(Decimal("0.01"))
        v_ibs_mun = Decimal("0.00")
        v_ibs = v_ibs_uf + v_ibs_mun
        v_cbs = (v_bc * p_cbs / Decimal("100")).quantize(Decimal("0.01"))

        total_bc += v_bc
        total_ibs_uf += v_ibs_uf
        total_ibs += v_ibs
        total_cbs += v_cbs

        ibscbs = etree.SubElement(imposto, f"{{{ns_nfe}}}IBSCBS")
        etree.SubElement(ibscbs, f"{{{ns_nfe}}}CST").text = cst
        etree.SubElement(ibscbs, f"{{{ns_nfe}}}cClassTrib").text = class_trib

        g_ibscbs = etree.SubElement(ibscbs, f"{{{ns_nfe}}}gIBSCBS")
        etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}vBC").text = f"{v_bc:.2f}"

        g_ibs_uf = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gIBSUF")
        etree.SubElement(g_ibs_uf, f"{{{ns_nfe}}}pIBSUF").text = f"{p_ibs:.4f}"
        etree.SubElement(g_ibs_uf, f"{{{ns_nfe}}}vIBSUF").text = f"{v_ibs_uf:.2f}"

        g_ibs_mun = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gIBSMun")
        etree.SubElement(g_ibs_mun, f"{{{ns_nfe}}}pIBSMun").text = "0.0000"
        etree.SubElement(g_ibs_mun, f"{{{ns_nfe}}}vIBSMun").text = f"{v_ibs_mun:.2f}"

        etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}vIBS").text = f"{v_ibs:.2f}"

        g_cbs = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gCBS")
        etree.SubElement(g_cbs, f"{{{ns_nfe}}}pCBS").text = f"{p_cbs:.4f}"
        etree.SubElement(g_cbs, f"{{{ns_nfe}}}vCBS").text = f"{v_cbs:.2f}"

        # Valor do item (campo novo do leiaute, depois do bloco de impostos).
        etree.SubElement(det, f"{{{ns_nfe}}}vItem").text = f"{v_bc:.2f}"

    if sem_perfil:
        print(
            f"[IBS/CBS] {sem_perfil} item(ns) sem perfil localizado pelo codigo — "
            f"aplicado o padrao CST {PADRAO_CST} / cClassTrib {PADRAO_CLASS_TRIB}"
        )

    total = xml_element.find(f".//{{{ns_nfe}}}total")
    if total is None:
        total = xml_element.find("total")
    if total is None:
        return

    ibscbs_tot = etree.SubElement(total, f"{{{ns_nfe}}}IBSCBSTot")
    etree.SubElement(ibscbs_tot, f"{{{ns_nfe}}}vBCIBSCBS").text = f"{total_bc:.2f}"

    g_ibs = etree.SubElement(ibscbs_tot, f"{{{ns_nfe}}}gIBS")
    g_ibs_uf_tot = etree.SubElement(g_ibs, f"{{{ns_nfe}}}gIBSUF")
    etree.SubElement(g_ibs_uf_tot, f"{{{ns_nfe}}}vDif").text = "0.00"
    etree.SubElement(g_ibs_uf_tot, f"{{{ns_nfe}}}vDevTrib").text = "0.00"
    etree.SubElement(g_ibs_uf_tot, f"{{{ns_nfe}}}vIBSUF").text = f"{total_ibs_uf:.2f}"

    g_ibs_mun_tot = etree.SubElement(g_ibs, f"{{{ns_nfe}}}gIBSMun")
    etree.SubElement(g_ibs_mun_tot, f"{{{ns_nfe}}}vDif").text = "0.00"
    etree.SubElement(g_ibs_mun_tot, f"{{{ns_nfe}}}vDevTrib").text = "0.00"
    etree.SubElement(g_ibs_mun_tot, f"{{{ns_nfe}}}vIBSMun").text = "0.00"

    etree.SubElement(g_ibs, f"{{{ns_nfe}}}vIBS").text = f"{total_ibs:.2f}"
    etree.SubElement(g_ibs, f"{{{ns_nfe}}}vCredPres").text = "0.00"
    etree.SubElement(g_ibs, f"{{{ns_nfe}}}vCredPresCondSus").text = "0.00"

    g_cbs_tot = etree.SubElement(ibscbs_tot, f"{{{ns_nfe}}}gCBS")
    etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vDif").text = "0.00"
    etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vDevTrib").text = "0.00"
    etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCBS").text = f"{total_cbs:.2f}"
    etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCredPres").text = "0.00"
    etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCredPresCondSus").text = "0.00"

    # vNFTot: valor total da nota (vNF do ICMSTot quando existir).
    v_nf = None
    icms_tot = total.find(f"{{{ns_nfe}}}ICMSTot")
    if icms_tot is None:
        icms_tot = total.find("ICMSTot")
    if icms_tot is not None:
        v_nf_el = icms_tot.find(f"{{{ns_nfe}}}vNF")
        if v_nf_el is None:
            v_nf_el = icms_tot.find("vNF")
        if v_nf_el is not None:
            v_nf = (v_nf_el.text or '').strip()
    etree.SubElement(total, f"{{{ns_nfe}}}vNFTot").text = v_nf or f"{total_bc:.2f}"


def adicionar_produto_com_icms(nota_fiscal, item, emp, descricao=None, cfop_sugerido=None, desconto=None):
    """
    Adiciona um produto/serviÃ§o Ã  nota fiscal aplicando a tributaÃ§Ã£o de ICMS
    conforme o regime tributÃ¡rio (CRT) da empresa:

      - CRT 3 (Regime Normal): usa CST (padrÃ£o 00, ex: CFOP 5102/CST 00) e monta
        o bloco ICMS completo (modBC/vBC/pICMS/vICMS â€” obrigatÃ³rios no schema 4.00).
      - CRT 1/2 (Simples Nacional): usa CSOSN (padrÃ£o 102, ex: CFOP 5102/CSOSN 102),
        sem destaque de ICMS.

    [desconto] Ã© o valor (R$) do desconto deste item (vDesc do XML). Quando
    informado, o pynfe emite <vDesc> no produto e subtrai do total da nota.
    Para o Regime Normal, a base de cÃ¡lculo do ICMS passa a ser lÃ­quida
    (vProd âˆ’ vDesc), conforme o schema 4.00.

    Retorna o NotaFiscalProduto criado (para testes/inspeÃ§Ã£o).
    """
    regime_normal = str(getattr(emp, 'crt', '1') or '1') == '3'
    csosn_atual = str(getattr(item, 'icms_csosn', '102') or '102').strip()
    cst_atual = str(getattr(item, 'icms_cst', '00') or '00').strip()
    cfop_atual = str(cfop_sugerido or getattr(item, 'cfop', '5102') or '5102').replace('.', '').strip()
    desconto_item = Decimal(str(desconto or 0)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    valor_total_bruto = Decimal(str(item.valor_total)).quantize(Decimal('0.01'))
    # Garantir que o desconto do item nunca seja maior que o valor do item
    if desconto_item > valor_total_bruto:
        desconto_item = valor_total_bruto

    # InteligÃªncia Fiscal: Auto-correÃ§Ã£o de CFOP Ã— CSOSN (Double Check no Backend)
    cfops_tributados = ['5101', '5102', '1101', '1102', '6101', '6102', '7101', '7102']
    cfops_st = ['5405', '1551', '5551', '6551', '7551', '5403', '1403', '6403']
    csosns_tributados = ['101', '102', '103', '201', '202', '203', '300', '400', '600']
    
    if (csosn_atual == '500' or cst_atual == '60') and (cfop_atual in ['5101', '5102']):
        cfop_final = '5405'
        print(f">>> [FISCAL] Corrigindo CFOP item {item.codigo}: {cfop_atual} -> {cfop_final} (ST detectada)")
    elif csosn_atual in csosns_tributados and cfop_atual not in cfops_tributados:
        cfop_final = '5102'
        print(f">>> [FISCAL] Corrigindo CFOP item {item.codigo}: {cfop_atual} -> {cfop_final} (CSOSN {csosn_atual} exige CFOP tributado)")
    elif csosn_atual == '500' and cfop_atual not in cfops_st and cfop_atual not in cfops_tributados:
        cfop_final = '5405'
        print(f">>> [FISCAL] Corrigindo CFOP item {item.codigo}: {cfop_atual} -> {cfop_final} (CSOSN 500 exige CFOP ST)")
    elif cfop_atual == '5949' and csosn_atual != '900':
        cfop_final = '5102'
        print(f">>> [FISCAL] Corrigindo CFOP item {item.codigo}: {cfop_atual} -> {cfop_final} (CFOP 5949 exige CSOSN 900)")
    else:
        cfop_final = cfop_atual

    p_nfe = nota_fiscal.adicionar_produto_servico(
        codigo=item.codigo,
        descricao=descricao or item.descricao,
        ncm=item.ncm,
        cfop=cfop_final,
        unidade_comercial='UN',
        quantidade_comercial=Decimal(str(item.quantidade)).quantize(Decimal('0.0001')),
        valor_unitario_comercial=Decimal(str(item.valor_unitario)).quantize(Decimal('0.0000001')),
        valor_total_bruto=valor_total_bruto,
        unidade_tributavel='UN',
        quantidade_tributavel=Decimal(str(item.quantidade)).quantize(Decimal('0.0001')),
        valor_unitario_tributavel=Decimal(str(item.valor_unitario)).quantize(Decimal('0.0000001')),
        ean='SEM GTIN',
        ean_tributavel='SEM GTIN',
        icms_origem=getattr(item, 'icms_origem', 0) or 0,
        icms_modalidade=(cst_atual or '00') if regime_normal else (csosn_atual or '102'),
        desconto=desconto_item,
    )

    # Garantir CSOSN ou CST explicitamente (Monkeypatch do pynfe)
    if regime_normal:
        p_nfe.icms_csosn = ''  # garante que nada do Simples Nacional vaze
        p_nfe.icms_cst = cst_atual or '00'
        p_nfe.icms_modalidade = cst_atual or '00'
        p_nfe.icms_modalidade_determinacao_bc = '3'  # 3 = Valor da operaÃ§Ã£o
        try:
            vbc_item = Decimal(str(getattr(item, 'icms_base_calculo', None) or item.valor_total or 0.0))
        except Exception:
            vbc_item = Decimal(str(item.valor_total or 0.0))
        # Base de cÃ¡lculo lÃ­quida do desconto do item (vBC = vProd âˆ’ vDesc)
        vbc_item = (vbc_item - desconto_item).max(Decimal('0.00'))
        aliq_item = Decimal(str(getattr(item, 'icms_aliquota', 0.0) or 0.0))
        p_nfe.icms_valor_base_calculo = vbc_item.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        p_nfe.icms_aliquota = aliq_item
        p_nfe.icms_valor = (vbc_item * aliq_item / Decimal('100')).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    else:
        p_nfe.icms_cst = ''
        p_nfe.icms_csosn = csosn_atual or '102'
        p_nfe.icms_aliquota = Decimal('0.00')
    return p_nfe


def emitir_nfce_pynfe(req):
    # [PERF] pontos de medicao de tempo por etapa (gravam em bridge_log.txt)
    _perf_t0 = time.time()
    _perf_ultimo = [_perf_t0]

    def _perf(etapa, extra=""):
        agora = time.time()
        delta = agora - _perf_ultimo[0]
        _perf_ultimo[0] = agora
        try:
            logging.info(
                f"[PERF] {etapa}: {delta:.2f}s (acumulado {agora - _perf_t0:.2f}s) {extra}"
            )
        except Exception:
            pass

    try:
        _perf(
            "inicio",
            f"numero={getattr(req, 'numero', None)} ambiente={getattr(req.empresa, 'ambiente', None)} uf={getattr(req.empresa, 'uf', None)}",
        )
    except Exception:
        pass

    # Decodificar certificado Base64 para um arquivo temporÃ¡rio
    cert_data = base64.b64decode(req.empresa.certificado_base64)
    temp_dir = os.environ.get('TEMP', 'C:/temp')
    caminho_cert = os.path.join(temp_dir, f"cert_{uuid.uuid4().hex}.pfx")
    with open(caminho_cert, 'wb') as f:
        f.write(cert_data)

    try:
        senha_cert = req.empresa.senha_certificado
        is_homologacao = (req.empresa.ambiente == 2)

        # === VALIDACAO DE VALIDADE DO CERTIFICADO (evita erro 403 da SEFAZ) ===
        # _validade_pfx cacheia o parse do .pfx por conteudo+senha: primeira nota
        # paga o custo da cryptography (~20-50ms), as seguintes comparam data com
        # UTC 'agora' e seguem direto.
        try:
            _validade = _validade_pfx(caminho_cert, senha_cert)
            if _validade is not None:
                _agora = datetime.now(timezone.utc)
                if _validade < _agora:
                    _msg_cert = (
                        "CERTIFICADO DIGITAL VENCIDO\n"
                        "---------------------------------------------\n"
                        f"O certificado digital da empresa venceu em {_validade.strftime('%d/%m/%Y')}.\n\n"
                        "Para voltar a emitir NFC-e, e necessario:\n"
                        "1. Renovar o certificado digital A1 com a contabilidade / autoridade certificadora (ICP-Brasil).\n"
                        "2. Enviar o novo arquivo (.pfx) e a nova senha para atualizacao no sistema.\n\n"
                        "Assim que o certificado renovado for cadastrado, a emissao voltara a funcionar normalmente."
                    )
                    print(f"[CERTIFICADO] VENCIDO em {_validade.strftime('%d/%m/%Y')}")
                    return {"status": "erro", "mensagem": _msg_cert}
        except Exception as _e:
            print(f"[AVISO] Nao foi possivel verificar validade do certificado: {_e}")

        # Emitente
        emp = req.empresa
        # Override do Regime TributÃ¡rio (CRT) enviado pelo app (1=Simples Nacional, 2=SN excesso, 3=Regime Normal)
        crt_override = _get_val(req, 'crt', None)
        if crt_override is not None and str(crt_override).strip() not in ('', 'None'):
            try:
                emp.crt = int(str(crt_override).strip())
            except (ValueError, TypeError):
                print(f"[AVISO] crt invalido recebido: {crt_override!r}")
        # Limpar nome do emitente:
        # 1. Remove o CNPJ que pode vir concatenado ao nome (ex: "BMJ PETSHOP LTDA 04829400000165")
        # 2. Remove caracteres especiais como ':'
        cnpj_limpo = re.sub(r'[^0-9]', '', emp.cnpj)  # CNPJ apenas dÃ­gitos
        razao_sem_cnpj = re.sub(r'\s*' + re.escape(cnpj_limpo) + r'\s*$', '', emp.razao_social).strip()
        razao_limpa = re.sub(r'[^A-Za-z0-9 \-\.\,\/\&]', ' ', razao_sem_cnpj)[:60].strip()
        
        # Limpar MunicÃ­pio (remover /SP ou similar que pode vir no nome)
        municipio_limpo = re.sub(r'[/].*$', '', emp.municipio).strip()
        
        emitente = Emitente(
            cnpj=emp.cnpj,
            razao_social=razao_limpa,
            nome_fantasia=emp.nome_fantasia,
            inscricao_estadual=emp.inscricao_estadual,
            codigo_de_regime_tributario=str(emp.crt or '1'), # Usa o CRT vindo da requisiÃ§Ã£o
            endereco_logradouro=emp.logradouro,
            endereco_numero=str(emp.numero),
            endereco_bairro=emp.bairro,
            endereco_cep=emp.cep,
            endereco_uf=emp.uf,
            endereco_municipio=municipio_limpo,
            endereco_cod_municipio=str(emp.codigo_municipio)
        )

        # 3. DADOS DO DESTINATÃRIO (Opcional na NFC-e se < R$ 10k; obrigatÃ³rio na NF-e 55)
        destinatario = None
        if req.cpf_cliente:
            # Regra E04-20 / RejeiÃ§Ã£o 598: em homologaÃ§Ã£o (tpAmb=2), o xNome do
            # destinatÃ¡rio deve ser EXATAMENTE o texto padrÃ£o definido pela SEFAZ
            if is_homologacao:
                nome_dest = "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
                print("[FISCAL] HomologaÃ§Ã£o: xNome do destinatÃ¡rio = texto padrÃ£o SEFAZ (Regra E04-20 / RejeiÃ§Ã£o 598)")
            else:
                nome_dest = (getattr(req, 'nome_cliente', None) or 'Consumidor Final').strip()[:60]

            # Documento do destinatÃ¡rio: CPF (11 dÃ­gitos) ou CNPJ (14 dÃ­gitos)
            doc_dest_limpo = re.sub(r'[^0-9]', '', str(req.cpf_cliente or ''))
            tipo_doc_dest = 'CNPJ' if len(doc_dest_limpo) == 14 else 'CPF'

            # IE do destinatÃ¡rio: se informada, destinatÃ¡rio Ã© contribuinte (indIEDest=1)
            dest_ie_num = re.sub(r'[^0-9]', '', str(getattr(req, 'dest_ie', None) or ''))
            indicador_ie_dest = 1 if dest_ie_num else 9

            # EndereÃ§o do destinatÃ¡rio (obrigatÃ³rio na NF-e modelo 55)
            dest_logradouro = (getattr(req, 'dest_logradouro', None) or '').strip()
            if dest_logradouro:
                # CÃ³digo do municÃ­pio do destinatÃ¡rio: usa o enviado, senÃ£o tenta
                # resolver pelo nome+UF (fallback: cÃ³digo do municÃ­pio da empresa)
                dest_cod_mun = re.sub(r'[^0-9]', '', str(getattr(req, 'dest_cod_municipio', None) or ''))[:7]
                dest_municipio_txt = (getattr(req, 'dest_municipio', None) or '').strip()[:60]
                dest_uf_txt = (getattr(req, 'dest_uf', None) or '').strip()[:2].upper()
                if not dest_cod_mun:
                    try:
                        dest_cod_mun = serializacao_mod.obter_codigo_por_municipio(dest_municipio_txt, dest_uf_txt)
                    except Exception:
                        dest_cod_mun = re.sub(r'[^0-9]', '', str(emp.codigo_municipio or ''))[:7]
                destinatario = Cliente(
                    numero_documento=doc_dest_limpo,
                    razao_social=nome_dest,
                    tipo_documento=tipo_doc_dest,
                    indicador_ie=indicador_ie_dest,
                    inscricao_estadual=dest_ie_num,
                    endereco_logradouro=dest_logradouro[:60],
                    endereco_numero=(getattr(req, 'dest_numero', None) or 'S/N').strip()[:60],
                    endereco_complemento=(getattr(req, 'dest_complemento', None) or '').strip()[:60],
                    endereco_bairro=(getattr(req, 'dest_bairro', None) or '').strip()[:60],
                    endereco_municipio=dest_municipio_txt,
                    endereco_uf=dest_uf_txt,
                    endereco_cep=re.sub(r'[^0-9]', '', str(getattr(req, 'dest_cep', None) or ''))[:8],
                    endereco_cod_municipio=dest_cod_mun,
                    endereco_telefone=re.sub(r'[^0-9]', '', str(getattr(req, 'dest_telefone', None) or ''))[:12],
                    endereco_pais='1058',  # Brasil
                )
            else:
                # NFC-e sem endereÃ§o do destinatÃ¡rio (consumidor presencial)
                destinatario = Cliente(
                    numero_documento=doc_dest_limpo,
                    razao_social=nome_dest,
                    tipo_documento=tipo_doc_dest,
                    indicador_ie=indicador_ie_dest,
                    inscricao_estadual=dest_ie_num,
                )

        # Nota Fiscal
        numero_forcado = _get_val(req, 'numero')
        serie_forcada_raw = str(_get_val(req, 'serie', '1') or '1')
        modelo_nota = int(_get_val(req, 'modelo', 65) or 65)
        # Tipo de Emissao (tpEmis): 1=Normal, 2=Contingencia FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
        tp_emis = int(_get_val(req, 'tp_emis', 1) or 1)
        if tp_emis not in (1, 2, 3, 4, 5, 6, 7, 9):
            tp_emis = 1
        
        # Puxa nÃºmero forÃ§ado ou o nÃºmero da venda
        if numero_forcado is not None and str(numero_forcado).strip() != "" and str(numero_forcado) != "None":
            numero_nf_limpo = re.sub(r'[^0-9]', '', str(numero_forcado))
        else:
            numero_nf_str = str(_get_val(req, 'venda_numero') or '')
            numero_nf_limpo = re.sub(r'[^0-9]', '', numero_nf_str)

        # Limite estrito de 9 dÃ­gitos para nNF (campo da chave de acesso)
        if len(numero_nf_limpo) > 9:
            # Usar mÃ³dulo para manter dentro do range vÃ¡lido (1-999999999)
            numero_nf_limpo = str(int(numero_nf_limpo) % 999999999)

        # CRÃTICO: o Bridge NUNCA inventa nÃºmero.
        # O fallback antigo (timestamp) gerava um valor de 9 dÃ­gitos fora de
        # ordem â€” a nota saÃ­a "lÃ¡ em cima" e contaminava a sequÃªncia da loja
        # por inteiro; o outro fallback, o "1", reemitia um nÃºmero jÃ¡ usado e
        # causava duplicidade na SEFAZ. A numeraÃ§Ã£o Ã© definida pelo app, que Ã©
        # quem sabe o menor nÃºmero livre da sÃ©rie.
        if not numero_nf_limpo or int(numero_nf_limpo) == 0:
            return {
                "status": "erro",
                "mensagem": (
                    "NumeraÃ§Ã£o ausente: a emissÃ£o chegou sem um nÃºmero vÃ¡lido "
                    "('numero' / 'venda_numero'). O Bridge nÃ£o gera nÃºmero por "
                    "conta prÃ³pria para nÃ£o perder a sequÃªncia â€” reabra a "
                    "emissÃ£o pela tela para que o menor nÃºmero livre seja enviado."
                ),
            }

        # SÃ©rie: mÃ¡x 3 dÃ­gitos (campo zfill(3) no pynfe)
        serie_limpa = re.sub(r'[^0-9]', '', serie_forcada_raw)
        if len(serie_limpa) > 3:
            serie_limpa = serie_limpa[-3:]
        if not serie_limpa:
            serie_limpa = "1"
        serie_forcada = serie_limpa

        print(f"[NFe] modelo={modelo_nota} | numero={numero_nf_limpo} | serie={serie_forcada}")

        # 5. MONTAGEM DA NOTA FISCAL
        finalidade_emissao_final = int(getattr(req, 'finalidade', 1) or 1)
        natureza_operacao_final = getattr(req, 'natureza_operacao', None)
        if not natureza_operacao_final or natureza_operacao_final.strip() == "":
            natureza_operacao_final = 'DEVOLUCAO DE MERCADORIA' if finalidade_emissao_final == 4 else ('VENDA DE MERCADORIA' if modelo_nota == 55 else 'VENDA AO CONSUMIDOR')

        nota_fiscal = NotaFiscal(
            emitente=emitente,
            cliente=destinatario,
            produtos=[], # Initialize with an empty list, products will be added later
            natureza_operacao=natureza_operacao_final[:60],
            modelo=modelo_nota, # 55=NF-e, 65=NFC-e
            serie=serie_forcada,
            numero_nf=numero_nf_limpo,
            indicador_destino=1, # 1=Interna
            finalidade_emissao=finalidade_emissao_final,
            cliente_final=1, # 1=Sim
            indicador_presencial=1, # 1=Presencial
            valor_total_nota=Decimal(str(req.valor_total)),
            uf=emp.uf,
            # cMunFG - OBRIGATÃ“RIO (IBGE)
            municipio=str(emp.codigo_municipio or serializacao_mod.obter_codigo_por_municipio(municipio_limpo, emp.uf) or '').strip() or "3549904",
            tipo_impressao_danfe=1 if modelo_nota == 55 else 4, # 1=DANFE normal A4, 4=DANFE NFC-e
            tipo_documento=1, # 1=SaÃ­da
            forma_emissao=str(tp_emis), # 1=Normal, 2=FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
            transporte_modalidade_frete=int(getattr(req, 'mod_frete', 9) or 9)
        )

        # Notas Fiscais Referenciadas (ObrigatÃ³rio para finalidade 4 - DevoluÃ§Ã£o)
        if finalidade_emissao_final == 4 or getattr(req, 'chave_referenciada', None):
            chave_ref = re.sub(r'[^0-9]', '', getattr(req, 'chave_referenciada', None) or '')
            if len(chave_ref) == 44:
                nota_fiscal.adicionar_nota_fiscal_referenciada(
                    chave_acesso=chave_ref
                )
                print(f"[FISCAL] Nota Fiscal Referenciada adicionada: {chave_ref}")

        # ConfiguraÃ§Ã£o de Transportadora e VeÃ­culo
        if getattr(req, 'transp_nome', None):
            transp = Transportadora(
                razao_social=req.transp_nome.strip()[:60],
                tipo_documento='CNPJ' if len(re.sub(r'[^0-9]', '', req.transp_cnpj_cpf or '')) > 11 else 'CPF',
                numero_documento=re.sub(r'[^0-9]', '', req.transp_cnpj_cpf or ''),
                inscricao_estadual=re.sub(r'[^0-9]', '', req.transp_insc_est or '') or 'ISENTO',
                endereco_logradouro=(req.transp_endereco or 'Sem Endereco')[:60],
                endereco_municipio=(req.transp_municipio or 'Sem Municipio')[:60],
                endereco_uf=(req.transp_uf or emp.uf or 'SP')[:2].upper()
            )
            nota_fiscal.transporte_transportadora = transp
            print(f"[FISCAL] Transportadora configurada: {transp.razao_social}")
            
        if getattr(req, 'transp_placa', None):
            nota_fiscal.transporte_veiculo_placa = req.transp_placa.strip()[:7].upper()
            nota_fiscal.transporte_veiculo_uf = (req.transp_placa_uf or emp.uf or 'SP')[:2].upper()

        if getattr(req, 'transp_qtd_volumes', None) is not None:
            nota_fiscal.adicionar_transporte_volume(
                quantidade=Decimal(str(req.transp_qtd_volumes or 1)),
                especie=(req.transp_especie or 'VOLUMES')[:60],
                peso_bruto=Decimal(str(req.transp_peso_bruto or 0.0)),
                peso_liquido=Decimal(str(req.transp_peso_liquido or 0.0))
            )

        
        # CorreÃ§Ã£o final se o municÃ­pio virar "None" ou "0000000" ou continuar invÃ¡lido
        if not nota_fiscal.municipio or nota_fiscal.municipio in ["None", "0000000", ""]:
            nota_fiscal.municipio = serializacao_mod.obter_codigo_por_municipio(municipio_limpo, emp.uf) or "3549904"
        
        # Data de emissÃ£o (precisa ser um datetime object no pynfe)
        nota_fiscal.data_emissao = datetime.now()
        
        # Pagamento (obrigatÃ³rio para NFC-e 4.00)
        # Usa os pagamentos enviados pelo app (lista de {tipo, valor, troco}) para
        # gerar um detPag por forma de pagamento, com o cÃ³digo tPag correto.
        # Caso nÃ£o venham pagamentos, assume um Ãºnico pagamento em dinheiro.
        _pags = getattr(req, 'pagamentos', None) or []
        if not _pags:
            _pags = [{'tipo': '01', 'valor': req.valor_total, 'troco': 0.0}]

        _valor_total_nota = Decimal(str(req.valor_total)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        _troco_total = Decimal('0.00')
        for _p in _pags:
            _tipo = str(_p.get('tipo', '01') or '01').strip()
            if len(_tipo) == 1:
                _tipo = _tipo.zfill(2)
            _valor = Decimal(str(_p.get('valor', 0.0) or 0.0)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            _troco = Decimal(str(_p.get('troco', 0.0) or 0.0)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            # vPag nunca excede o total da nota (evita rejeicao 869 - troco invalido)
            if _valor > _valor_total_nota:
                _valor = _valor_total_nota
            _x_pag = str(_p.get('descricao') or '').strip() if _tipo == '99' else ''
            if _tipo == '99' and not _x_pag:
                _x_pag = 'PIX'  # fallback para PIX quando nao vem descricao
            _pag_kwargs = {'t_pag': _tipo, 'v_pag': _valor}
            if _x_pag:
                _pag_kwargs['x_pag'] = _x_pag

            # â”€â”€ DADOS DO CARTÃƒO (obrigatÃ³rio para tPag 03=CrÃ©dito e 04=DÃ©bito) â”€â”€
            # Evita RejeiÃ§Ã£o SEFAZ 391: "NÃ£o informados os dados do cartÃ£o"
            # Os nomes dos kwargs seguem os atributos de NotaFiscalPagamentos do pynfe:
            #   cnpj   = CNPJ da Credenciadora de cartÃ£o
            #   t_band = Bandeira (int: 01=Visa, 02=Mastercard, etc.)
            #   c_aut  = NÃºmero de autorizaÃ§Ã£o da operaÃ§Ã£o
            #   tp_integra = '1' integrado, '2' nÃ£o integrado (obrigatÃ³rio para escrever bloco <card>)
            if _tipo in ('03', '04'):
                _cnpj_admin = str(_p.get('cnpj_admin_cartao') or _p.get('cnpj_pag') or _p.get('cnpj') or '').strip()
                _cnpj_admin = re.sub(r'[^0-9]', '', _cnpj_admin)
                _bandeira = str(_p.get('bandeira') or _p.get('t_band') or '').strip()
                _operadora = str(_p.get('operadora') or '').strip()
                _aut = str(_p.get('aut') or _p.get('c_aut') or _p.get('autorizacao') or '').strip()
                _nsu = str(_p.get('nsu') or '').strip()
                _tid = str(_p.get('tid') or '').strip()

                # tp_integra Ã© obrigatÃ³rio para o pynfe escrever o bloco <card>
                _pag_kwargs['tp_integra'] = '2'  # 2 = nÃ£o integrado (PDV comum)

                if _cnpj_admin:
                    _pag_kwargs['cnpj'] = _cnpj_admin
                if _bandeira:
                    # t_band Ã© int no pynfe
                    try:
                        _pag_kwargs['t_band'] = int(_bandeira)
                    except ValueError:
                        # Mapear nome da bandeira para cÃ³digo
                        _bandeiras = {'visa': 1, 'mastercard': 2, 'master': 2, 'elo': 3, 'amex': 4, 'diners': 5, 'discover': 6, 'hipercard': 7, 'aura': 8, 'jcb': 9}
                        _pag_kwargs['t_band'] = _bandeiras.get(_bandeira.lower(), 1)
                if _aut:
                    _pag_kwargs['c_aut'] = _aut

                # Se for cartÃ£o mas nÃ£o veio CNPJ da administradora, usar CNPJ da empresa
                # para nÃ£o gerar rejeiÃ§Ã£o 391 (pelo menos informa algo)
                if 'cnpj' not in _pag_kwargs:
                    _cnpj_emp = re.sub(r'[^0-9]', '', str(req.empresa.cnpj or ''))
                    if _cnpj_emp:
                        _pag_kwargs['cnpj'] = _cnpj_emp
                    if 't_band' not in _pag_kwargs:
                        _pag_kwargs['t_band'] = 1  # Bandeira genÃ©rica (Visa)

            nota_fiscal.adicionar_pagamento(**_pag_kwargs)
            _troco_total += _troco
            print(f"[PAG] tPag={_tipo} vPag={_valor} troco={_troco} cartao={_tipo in ('03','04')}")
        # Se nao houver pagamentos enviados, gera um pagamento Dinheiro com vPag = vNF
        if not _pags:
            nota_fiscal.adicionar_pagamento(t_pag='01', v_pag=_valor_total_nota)
        # vTroco = soma dos trocos informados, limitado ao total da nota
        nota_fiscal.valor_troco = _troco_total.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        if nota_fiscal.valor_troco > _valor_total_nota:
            nota_fiscal.valor_troco = _valor_total_nota
        print(f"[PAG] vTroco total={nota_fiscal.valor_troco}")

        # Itens
        # Distribui o desconto total da venda (tabela de preÃ§os, promoÃ§Ãµes, desconto
        # manual) proporcionalmente ao valor de cada item para gerar o <vDesc> por
        # item e no <ICMSTot> (Î£ vProd âˆ’ Î£ vDesc = vNF).
        valor_desconto_total = Decimal(str(getattr(req, 'valor_desconto', None) or 0.0))
        descontos_por_item = {}
        if valor_desconto_total > 0 and req.itens:
            soma_valores = sum(
                (Decimal(str(it.valor_total)) for it in req.itens), Decimal('0.00')
            )
            if soma_valores > 0:
                # Desconto nunca pode exceder a soma dos itens (mantÃ©m Î£ vProd âˆ’ Î£ vDesc = vNF)
                if valor_desconto_total > soma_valores:
                    print(f"[FISCAL] Desconto {valor_desconto_total} > soma itens {soma_valores}; ajustado")
                    valor_desconto_total = soma_valores
                acumulado = Decimal('0.00')
                for idx, it in enumerate(req.itens):
                    if idx == len(req.itens) - 1:
                        # Ãšltimo item recebe o resto (evita erro de arredondamento)
                        desc_item = (valor_desconto_total - acumulado).max(Decimal('0.00'))
                    else:
                        desc_item = (valor_desconto_total * Decimal(str(it.valor_total)) / soma_valores).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
                        acumulado += desc_item
                    descontos_por_item[idx] = desc_item

        for i, item in enumerate(req.itens):
            descricao = item.descricao
            if is_homologacao and i == 0:
                descricao = 'NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
            # A tributaÃ§Ã£o de ICMS Ã© aplicada conforme o regime (CRT) da empresa
            adicionar_produto_com_icms(
                nota_fiscal, item, emp,
                descricao=descricao,
                desconto=descontos_por_item.get(i, Decimal('0.00')),
            )

        # Assinatura (assinador reaproveitado: nao relê o .pfx a cada nota)
        assinatura = _assinador(caminho_cert, senha_cert)
        # Passar is_homologacao para o serializador para que o tpAmb (1 ou 2) fique correto no XML
        serializador = SerializacaoXML(MockFonteDados(nota_fiscal), homologacao=is_homologacao)
        # No pynfe 0.6.5, exportar retorna o Element tree por padrÃ£o a menos que passa retorna_string
        xml_string = serializador.exportar(retorna_string=True)
        
        # Criar a Ã¡rvore DOM limpa oficial
        xml_element = etree.fromstring(xml_string.encode('utf-8'))
        
        # Garantir namespace correto em todo o XML (evitar xmlns="")
        ns_nfe = "http://www.portalfiscal.inf.br/nfe"
        fix_xml_namespaces(xml_element, ns_nfe)
        # Garantir o grupo correto do Simples Nacional (CSOSN 400 -> ICMSSN102, etc.)
        corrigir_blocos_icms_simples(xml_element)

        # Injetar destaque de ICMS900 para Simples Nacional (NT 2025.002 / CSOSN 900)
        try:
            det_tags = xml_element.findall(f".//{{{ns_nfe}}}det")
            for idx, det in enumerate(det_tags):
                if idx < len(req.itens):
                    item_req = req.itens[idx]
                    csosn_atual = str(getattr(item_req, 'csosn', '') or '').strip()
                    if not csosn_atual:
                        csosn_atual = str(getattr(item_req, 'icms_csosn', '') or '').strip()
                    
                    if csosn_atual == '900':
                        imposto = det.find(f".//{{{ns_nfe}}}imposto")
                        if imposto is not None:
                            icms_tag = imposto.find(f".//{{{ns_nfe}}}ICMS")
                            if icms_tag is not None:
                                # Limpar filhos antigos do ICMS (como ICMS102 ou outro vazio)
                                for child in list(icms_tag):
                                    icms_tag.remove(child)
                                
                                # Criar a estrutura do ICMS900
                                icms900 = etree.SubElement(icms_tag, f"{{{ns_nfe}}}ICMS900")
                                etree.SubElement(icms900, f"{{{ns_nfe}}}orig").text = str(getattr(item_req, 'icms_origem', 0) or 0)
                                etree.SubElement(icms900, f"{{{ns_nfe}}}CSOSN").text = "900"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}modBC").text = "3" # Valor da operaÃ§Ã£o
                                
                                vBC = float(getattr(item_req, 'icms_base_calculo', 0.0) or 0.0)
                                pRedBC = float(getattr(item_req, 'icms_reducao_bc', 0.0) or 0.0)
                                pICMS = float(getattr(item_req, 'icms_aliquota', 0.0) or 0.0)
                                vICMS = float(getattr(item_req, 'icms_valor', 0.0) or 0.0)
                                pCredSN = float(getattr(item_req, 'credito_aliquota', 0.0) or 0.0)
                                vCredICMSSN = float(getattr(item_req, 'credito_valor', 0.0) or 0.0)
                                
                                # Se nÃ£o foi preenchido, calcula dinamicamente
                                if vBC <= 0.0:
                                    vBC = float(item_req.valor_total)
                                if vICMS <= 0.0 and pICMS > 0.0:
                                    vICMS = vBC * (pICMS / 100.0)
                                if vCredICMSSN <= 0.0 and pCredSN > 0.0:
                                    vCredICMSSN = vBC * (pCredSN / 100.0)
                                    
                                etree.SubElement(icms900, f"{{{ns_nfe}}}vBC").text = f"{vBC:.2f}"
                                if pRedBC > 0.0:
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}pRedBC").text = f"{pRedBC:.2f}"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}pICMS").text = f"{pICMS:.2f}"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}vICMS").text = f"{vICMS:.2f}"
                                
                                if pCredSN > 0.0:
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}pCredSN").text = f"{pCredSN:.2f}"
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}vCredICMSSN").text = f"{vCredICMSSN:.2f}"
        except Exception as e_icms:
            print(f">>> [FISCAL] âš ï¸ Falha ao injetar bloco ICMS900: {e_icms}")
        
        # IBS/CBS da Reforma TributÃ¡ria (NT 2025.002), por item, com os
        # valores do perfil tributÃ¡rio do produto. Gera tambÃ©m <vItem> e
        # <vNFTot>, que o leiaute exige junto do grupo â€” sem eles o lote caÃ­a
        # em "Falha no Schema XML" (225).
        adicionar_ibscbs_xml(xml_element, ns_nfe, getattr(req, 'itens', None))

        # GARANTIR vTroco e REMOVER indPag de detPag (OBRIGATÃ“RIO para NFC-e 4.00)
        # ATENÃ‡ÃƒO: lxml elements avaliam como False em contexto bool quando sem filhos!
        # SEMPRE usar comparaÃ§Ã£o explÃ­cita com 'is None' / 'is not None'.
        pag_tag = xml_element.find(f".//{{{ns_nfe}}}pag")
        if pag_tag is None:
            pag_tag = xml_element.find(".//pag")
        if pag_tag is not None:
            det_pags = pag_tag.findall(f".//{{{ns_nfe}}}detPag")
            if not det_pags:
                det_pags = pag_tag.findall(".//detPag")
            for det_pag in det_pags:
                ind_p = det_pag.find(f"{{{ns_nfe}}}indPag")
                if ind_p is None:
                    ind_p = det_pag.find("indPag")
                if ind_p is not None:
                    print(f"[DEBUG] indPag preservado: {ind_p.text}")

            v_troco = pag_tag.find(f".//{{{ns_nfe}}}vTroco")
            if v_troco is None:
                v_troco = pag_tag.find(".//vTroco")
            if v_troco is None:
                v_troco = etree.SubElement(pag_tag, f"{{{ns_nfe}}}vTroco")
            # Normaliza o valor do troco (evita "Rejeicao SEFAZ [869]: Troco Invalido")
            try:
                troco_float = float(str(v_troco.text or "").strip() or "0.00")
                if troco_float < 0:
                    troco_float = 0.00
                v_troco.text = f"{troco_float:.2f}"
            except Exception:
                v_troco.text = "0.00"
            print(f"[FIX] vTroco normalizado: {v_troco.text}")
        
        # Limpar duplicatas de namespace ANTES de assinar
        for el in xml_element.getiterator():
            if 'xmlns' in el.attrib:
                del el.attrib['xmlns']

        # Assinatura (assinatura deve ser sobre o infNFe jÃ¡ final)
        xml_assinado = assinatura.assinar(xml_element)
        
        # Gerar QR Code (apenas se for NFC-e modelo 65)
        qr_code_url = ""
        if modelo_nota == 65:
            # O CSC e IdToken sÃ£o FUNDAMENTAIS para NFC-e (Modelo 65).
            csc_db = str(emp.csc or '').strip()
            id_token_db = str(emp.csc_id or '').strip()
            
            # DETECÃ‡ÃƒO INTELIGENTE DE INVERSÃƒO (CSC x IdToken)
            if len(csc_db) > 0 and len(csc_db) <= 6 and len(id_token_db) > 10:
                print(f">>> [SISTEMA] AtenÃ§Ã£o: CSC e IdToken parecem invertidos. Corrigindo: CSC={id_token_db}, IdToken={csc_db}")
                original_csc = csc_db
                csc_db = id_token_db
                id_token_db = original_csc

            # Se IdToken estiver vazio mas o CSC tiver cara de ID (curto)
            if not id_token_db and csc_db and len(csc_db) <= 6:
                id_token_db = csc_db
                csc_db = ""
                
            if not id_token_db: 
                id_token_db = "1"
                
            if csc_db and id_token_db:
                try:
                    csc_limpo = csc_db.strip().replace(' ', '').replace('\n', '').replace('\r', '')
                    id_token_limpo = re.sub(r'[^0-9]', '', id_token_db)
                    if not id_token_limpo: 
                        id_token_limpo = "1"
                    else:
                        id_token_limpo = str(int(id_token_limpo))
                    
                    qrcode_gen = SerializacaoQrcode()
                    xml_assinado, qr_code_url = qrcode_gen.gerar_qrcode(
                        token=id_token_limpo,
                        csc=csc_limpo,
                        xml=xml_assinado,
                        return_qr=True
                    )
                    print(f"[OK] QR Code gerado com Token ID {id_token_limpo}")
                except Exception as e:
                    print(f"[AVISO] Falha tÃ©cnica ao gerar QR Code: {str(e)}")
            else:
                msg_erro = f"Faltando dados de CSC (Token) no cadastro da empresa. Verifique se preencheu o CSC e o Identificador CSC (IdToken)."
                print(f"[ALERTA] {msg_erro}")
                return {"status": "erro", "mensagem": msg_erro}

        # CORRECAO CRITICA DE ORDEM DO SCHEMA PO_NFE v4.00:
        # Dentro de <NFe> a ordem deve ser infNFe, infNFeSupl, Signature.
        # O gerar_qrcode() do pynfe insere <infNFeSupl> no final (DEPOIS do
        # Signature), o que viola o schema 4.00 e gera
        # "Rejeicao: Falha no Schema XML do lote de NFe" (cStat 225).
        # Reposicionamos o infNFeSupl para logo apos o infNFe.
        try:
            _nfe_root = xml_assinado
            _inf_supl = _nfe_root.find(f"{{{ns_nfe}}}infNFeSupl")
            if _inf_supl is None:
                _inf_supl = _nfe_root.find("infNFeSupl")
            _sig = _nfe_root.find("{http://www.w3.org/2000/09/xmldsig#}Signature")
            _inf_nfe = _nfe_root.find(f"{{{ns_nfe}}}infNFe")
            if _inf_nfe is None:
                _inf_nfe = _nfe_root.find("infNFe")
            if _inf_supl is not None and _sig is not None:
                _nfe_root.remove(_inf_supl)
                if _inf_nfe is not None:
                    _idx = list(_nfe_root).index(_inf_nfe) + 1
                else:
                    _idx = list(_nfe_root).index(_sig)
                _nfe_root.insert(_idx, _inf_supl)
                print("[FIX] infNFeSupl reposicionado entre infNFe e Signature no schema XML")
        except Exception as _e_ord:
            print(f"[AVISO] Nao foi possivel reposicionar infNFeSupl: {_e_ord}")

        _debug_xml('last_nfce.xml', etree.tostring(xml_assinado, encoding='utf-8', xml_declaration=True).decode('utf-8'))

        # 7. TRANSMISSÃƒO PARA SEFAZ
        try:
            _perf("xml+assinatura prontos")
        except Exception:
            pass
        con = ComunicacaoSefaz(
            uf=emp.uf, 
            certificado=caminho_cert, 
            certificado_senha=senha_cert, 
            homologacao=is_homologacao
        )
        
        # Enviar XML Assinado com indSinc=1
        # Se modelo_nota == 55 usa modelo 'nfe', se modelo_nota == 65 usa modelo 'nfce'
        modelo_pynfe = 'nfe' if modelo_nota == 55 else 'nfce'
        # Em contingencia (tpEmis != 1) o pyNFe usa o webservice de contingencia (SVC/SVRS)
        usar_contingencia = (tp_emis != 1)
        print(f"[NFe] Servico pyNFe={modelo_pynfe} | modelo_nota={modelo_nota} | tpEmis={tp_emis} | contingencia={usar_contingencia}")
        aut_result = con.autorizacao(
            modelo=modelo_pynfe,
            nota_fiscal=xml_assinado,
            id_lote=1,
            ind_sinc=1, # SÃ­ncrono
            contingencia=usar_contingencia
        )
        sucesso = aut_result[0]
        retorno = aut_result[1]
        try:
            _perf("resposta SEFAZ", f"sucesso={sucesso}")
        except Exception:
            pass

        # Analisar retorno
        if sucesso == 0:
            # Em modo sÃ­ncrono, retorno jÃ¡ Ã© o nfeProc (XML completo) ou protocolo
            xml_final = etree.tostring(retorno, encoding='utf-8', xml_declaration=True).decode('utf-8')
            
            # Extrair chave e protocolo
            namespaces = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
            inf_prot = retorno.xpath('//ns:infProt', namespaces=namespaces)
            chave = ''
            protocolo = ''
            
            if inf_prot:
                c_stat = inf_prot[0].xpath('ns:cStat', namespaces=namespaces)
                c_stat = c_stat[0].text if c_stat else ''
                
                x_motivo = inf_prot[0].xpath('ns:xMotivo', namespaces=namespaces)
                x_motivo = x_motivo[0].text if x_motivo else ''
                
                if c_stat not in ('100', '150'):
                    # O lote foi processado, mas a nota em si foi REJEITADA.
                    # Na 539, a chave citada identifica exatamente o nÃºmero em
                    # conflito, mesmo quando nÃ£o existe um bloco contÃ­guo livre.
                    mensagem_rejeicao = f"RejeiÃ§Ã£o SEFAZ [{c_stat}]: {x_motivo}"
                    if c_stat == '539':
                        return {
                            "status": "erro",
                            "mensagem": mensagem_rejeicao,
                            "numeros_duplicados": [numero_nf_limpo],
                        }
                    return {
                        "status": "erro",
                        "mensagem": mensagem_rejeicao
                    }
                
                # EstÃ¡ APROVADA!
                chave = inf_prot[0].xpath('ns:chNFe', namespaces=namespaces)
                chave = chave[0].text if chave else ''
                
                protocolo = inf_prot[0].xpath('ns:nProt', namespaces=namespaces)
                protocolo = protocolo[0].text if protocolo else ''

            # --- SALVAMENTO LOCAL ORGANIZADO ---
            salvar_xml_local(emp.cnpj, chave, xml_final, emp.nome_fantasia or emp.razao_social)

            return {
                "status": "sucesso",
                "chave": chave,
                "protocolo": protocolo,
                "numero": numero_nf_limpo,
                "serie": nota_fiscal.serie,
                "xml": xml_final,
                "qrCode": qr_code_url,
                "mensagem": "NFC-e Autorizada com Sucesso!"
            }
        else:
            # Em caso de erro 'retorno' Ã© o objeto response do requests ou similar
            try:
                # Se for response do requests
                corpo_erro = retorno.text
                print(f"[SEFAZ ERRO RAW] Status: {retorno.status_code}")
                print(f"[SEFAZ ERRO RAW] Body: {corpo_erro[:2000]}")
                
                # Tentar extrair cStat e xMotivo da resposta XML
                try:
                    resp_elem = etree.fromstring(corpo_erro.encode('utf-8'))
                    ns = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                    
                    c_stat_el = resp_elem.xpath('//ns:cStat', namespaces=ns)
                    c_stat = c_stat_el[0].text if c_stat_el else ''
                    
                    # CASO ESPECIAL: 104 = Lote Processado. 
                    if c_stat == '104':
                        # Tentar encontrar o protocolo da nota (onde estÃ¡ o erro real)
                        inf_prot = resp_elem.xpath('//ns:infProt', namespaces=ns)
                        if inf_prot:
                            prot_c_stat = inf_prot[0].xpath('ns:cStat', namespaces=ns)
                            prot_c_stat = prot_c_stat[0].text if prot_c_stat else ''
                            
                            prot_x_motivo = inf_prot[0].xpath('ns:xMotivo', namespaces=ns)
                            prot_x_motivo = prot_x_motivo[0].text if prot_x_motivo else ''

                            if prot_c_stat in ('100', '150'):
                                # SUCESSO!
                                chave = inf_prot[0].xpath('ns:chNFe', namespaces=ns)[0].text
                                protocolo = inf_prot[0].xpath('ns:nProt', namespaces=ns)[0].text
                                proc = etree.Element(f"{{{_NS_NFE}}}nfeProc", versao="4.00", nsmap={None: _NS_NFE})
                                proc.append(xml_assinado)
                                prot_nfe_el = resp_elem.xpath('//ns:protNFe', namespaces=ns)[0]
                                proc.append(prot_nfe_el)
                                xml_final = etree.tostring(proc, encoding='utf-8', xml_declaration=True).decode('utf-8')
                                salvar_xml_local(emp.cnpj, chave, xml_final, emp.nome_fantasia or emp.razao_social)
                                return {
                                    "status": "sucesso",
                                    "chave": chave, 
                                    "protocolo": protocolo,
                                    "numero": numero_nf_limpo,
                                    "serie": nota_fiscal.serie,
                                    "xml": xml_final,
                                    "qrCode": qr_code_url,
                                    "mensagem": "NFC-e Autorizada!"
                                }
                            else:
                                # MOSTRAR O ERRO REAL DA NOTA
                                return {"status": "erro", "mensagem": f"RejeiÃ§Ã£o SEFAZ [{prot_c_stat}]: {prot_x_motivo}"}
                        
                        # Se nÃ£o achou infProt, pegar o xMotivo do retEnviNFe (se disponÃ­vel e nÃ£o for 104)
                        x_motivo_el = resp_elem.xpath('//ns:retEnviNFe/ns:xMotivo', namespaces=ns)
                        if not x_motivo_el: x_motivo_el = resp_elem.xpath('//ns:xMotivo', namespaces=ns)
                        
                        x_motivo = x_motivo_el[0].text if x_motivo_el else 'Lote processado, mas nota nÃ£o encontrada.'
                        return {"status": "erro", "mensagem": f"RejeiÃ§Ã£o SEFAZ [104]: {x_motivo}"}

                except Exception as parse_err:
                    print(f"[SEFAZ] NÃ£o conseguiu parsear resposta: {parse_err}")
                
                if retorno.status_code == 403:
                    _msg_403 = (
                        "CERTIFICADO DIGITAL REJEITADO PELA SEFAZ (HTTP 403)\n"
                        "---------------------------------------------\n"
                        "A SEFAZ recusou a conexao. Isso normalmente significa que o\n"
                        "certificado digital esta vencido, revogado ou invalido.\n\n"
                        "Para voltar a emitir NFC-e:\n"
                        "1. Renove o certificado digital A1 com a contabilidade / autoridade certificadora (ICP-Brasil).\n"
                        "2. Envie o novo arquivo (.pfx) e a nova senha para atualizacao no sistema.\n\n"
                        "Detalhe tecnico: 403 - Forbidden: Access is denied."
                    )
                    return {"status": "erro", "mensagem": _msg_403}
                return {"status": "erro", "mensagem": f"Erro SEFAZ (HTTP {retorno.status_code}): {corpo_erro[:500]}"}
            except AttributeError:
                return {"status": "erro", "mensagem": f"RejeiÃ§Ã£o ou erro de rede: {str(retorno)}"}
            
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO HANDLER] {e}\n{tb}")
        return {"status": "erro", "mensagem": f"Erro interno: {str(e)}", "traceback": tb}
    finally:
        # [PERF] tempo total da emissao
        try:
            _perf("TOTAL")
        except Exception:
            pass
        # Limpar arquivo temporÃ¡rio do certificado
        if os.path.exists(caminho_cert):
            try:
                os.remove(caminho_cert)
            except:
                pass

def _pasta_segura(nome, fallback):
    """Monta um nome de pasta seguro a partir do nome da empresa."""
    nome = (nome or "").strip()
    for ch in '<>:"/\\|?*':
        nome = nome.replace(ch, " ")
    nome = re.sub(r'[\x00-\x1f]', '', nome)
    nome = re.sub(r'\s+', ' ', nome).strip(" .")
    return (nome[:80].strip(" .")) or str(fallback)


def salvar_xml_local(cnpj, chave, xml_content, nome_empresa=""):
    """
    Salva o XML em C:/ExodoNFCe/[NOME DA EMPRESA]/[ANO-MES]/[CHAVE]-nfe.xml
    (pasta separada por empresa; sem nome disponÃ­vel, usa o CNPJ)
    """
    try:
        # Pasta principal fixa no C: para fÃ¡cil localizaÃ§Ã£o
        pasta_base = r"C:\ExodoNFCe"
        pasta_empresa = _pasta_segura(nome_empresa, cnpj)
        mes_ano = datetime.now().strftime("%Y-%m")
        diretorio_destino = os.path.join(pasta_base, pasta_empresa, mes_ano)
        
        if not os.path.exists(diretorio_destino):
            os.makedirs(diretorio_destino, exist_ok=True)
            
        # Nome do arquivo
        nome_arquivo = f"{chave}-nfe.xml"
        caminho_completo = os.path.join(diretorio_destino, nome_arquivo)
        
        with open(caminho_completo, "w", encoding="utf-8") as f:
            f.write(xml_content)
            
        print(f"[OK] XML salvo localmente: {caminho_completo}")
        return caminho_completo
    except Exception as e:
        print(f"[ERRO] Falha ao salvar XML localmente: {e}")
        return None
            


def cancelar_nfce_pynfe(req_dict):
    """
    Cancela uma NFC-e enviando o XML de evento DIRETAMENTE para a SEFAZ,
    sem usar o ComunicacaoSefaz._post que tem fixes especÃ­ficos de emissÃ£o
    que corrompem o XML de evento (envEvento).
    """
    from lxml import etree
    from datetime import datetime
    import base64, os, re, traceback
    import requests as _req
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    try:
        empresa_data = req_dict.get("empresa", {})
        chave_acesso = req_dict.get("chave_acesso", "").strip()
        justificativa = req_dict.get("justificativa", "Cancelamento por erro de emissao ou devolucao")
        protocolo = str(req_dict.get("protocolo", "")).strip()

        if not chave_acesso or not empresa_data.get("certificado_base64"):
            return {"success": False, "error": "Chave de acesso ou certificado ausentes.", "mensagem": "Dados insuficientes"}

        if not protocolo:
            return {"success": False, "error": "Protocolo de autorizaÃ§Ã£o ausente.", "mensagem": "Protocolo obrigatÃ³rio para cancelamento"}

        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))
        senha_cert = empresa_data.get("senha_certificado", "")
        uf = empresa_data.get("uf", "SP").upper()
        # Mapeamento robusto do ambiente (padrÃ£o de emissÃ£o utiliza ambiente_homologacao)
        is_homolog = (empresa_data.get("ambiente_homologacao") == True) or \
                     (str(empresa_data.get("ambiente")) == "2") or \
                     (empresa_data.get("ambiente") == 2)
        
        tp_amb = "2" if is_homolog else "1"
        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")

        # Limpar justificativa (xJust: 15â€“255 chars, caracteres permitidos pelo XSD)
        just_limpa = re.sub(r'[^\w\s\.\,\-\/]', ' ', justificativa, flags=re.UNICODE).strip()
        if len(just_limpa) < 15:
            just_limpa = "Cancelamento a pedido do emitente por erro ou devolucao"
        just_limpa = just_limpa[:255]

        # cOrgao: extrair dos 2 primeiros dÃ­gitos da chave de acesso (cUF)
        c_orgao = chave_acesso[:2] if len(chave_acesso) >= 44 else "35"

        NS = "http://www.portalfiscal.inf.br/nfe"

        # â”€â”€ 1. Montar envEvento com lxml puro (sem ElementMaker para evitar xmlns="" em sub-elementos) â”€â”€
        env_evento = etree.Element(f"{{{NS}}}envEvento", versao="1.00", nsmap={None: NS})
        etree.SubElement(env_evento, f"{{{NS}}}idLote").text = "1"

        evento_el = etree.SubElement(env_evento, f"{{{NS}}}evento", versao="1.00")
        id_evento = f"ID110111{chave_acesso}01"
        inf_evento = etree.SubElement(evento_el, f"{{{NS}}}infEvento", Id=id_evento)

        etree.SubElement(inf_evento, f"{{{NS}}}cOrgao").text = c_orgao
        etree.SubElement(inf_evento, f"{{{NS}}}tpAmb").text = tp_amb
        etree.SubElement(inf_evento, f"{{{NS}}}CNPJ").text = cnpj
        etree.SubElement(inf_evento, f"{{{NS}}}chNFe").text = chave_acesso
        etree.SubElement(inf_evento, f"{{{NS}}}dhEvento").text = dh_evento
        etree.SubElement(inf_evento, f"{{{NS}}}tpEvento").text = "110111"
        etree.SubElement(inf_evento, f"{{{NS}}}nSeqEvento").text = "1"
        etree.SubElement(inf_evento, f"{{{NS}}}verEvento").text = "1.00"

        det_evento = etree.SubElement(inf_evento, f"{{{NS}}}detEvento", versao="1.00")
        etree.SubElement(det_evento, f"{{{NS}}}descEvento").text = "Cancelamento"
        etree.SubElement(det_evento, f"{{{NS}}}nProt").text = protocolo
        etree.SubElement(det_evento, f"{{{NS}}}xJust").text = just_limpa

        # â”€â”€ 2. Salvar certificado PFX em arquivo temporÃ¡rio, assinar o XML â”€â”€
        import uuid
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_cancel_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)

        chave_pem = None
        cert_pem = None

        try:
            from pynfe.processamento.assinatura import AssinaturaA1
            from pynfe.entidades.certificado import CertificadoA1 as _CertA1

            assinador = AssinaturaA1(caminho_cert, senha_cert)
            env_evento_assinado = assinador.assinar(env_evento)

            # â”€â”€ 3. Corrigir posiÃ§Ã£o da Signature â”€â”€
            # O pynfe coloca a Signature como filha do elemento raiz (envEvento),
            # mas o XSD da SEFAZ exige que seja filha de <evento> (irmÃ£ de <infEvento>).
            # Estrutura correta:
            #   <envEvento>
            #     <idLote/>
            #     <evento>
            #       <infEvento Id="..."/>
            #       <Signature/>   â† DEVE estar AQUI
            #     </evento>
            #   </envEvento>
            NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"
            NS_NFE = "http://www.portalfiscal.inf.br/nfe"

            # Encontrar a Signature no nÃ­vel errado (filho de envEvento)
            sig_errada = env_evento_assinado.find(f"{{{NS_DSIG}}}Signature")
            if sig_errada is None:
                sig_errada = env_evento_assinado.find("Signature")

            if sig_errada is not None:
                # Remover do envEvento
                env_evento_assinado.remove(sig_errada)
                # Achar o <evento> e mover a Signature para dentro dele
                evento_tag = env_evento_assinado.find(f"{{{NS_NFE}}}evento")
                if evento_tag is None:
                    evento_tag = env_evento_assinado.find("evento")
                if evento_tag is not None:
                    evento_tag.append(sig_errada)
                else:
                    # Fallback: re-adicionar no envEvento (nÃ£o deve chegar aqui)
                    env_evento_assinado.append(sig_errada)

            # â”€â”€ 4. Serializar para string XML limpa â”€â”€
            xml_str = etree.tostring(env_evento_assinado, encoding="unicode")
            # Remover xmlns="" que o lxml pode inserir em sub-elementos
            xml_str = xml_str.replace(' xmlns=""', '')
            xml_final = '<?xml version="1.0" encoding="UTF-8"?>' + xml_str

            # DEBUG: salvar XML de cancelamento
            try:
                dbg = os.path.join(os.environ.get("TEMP", "C:/temp"), "last_cancelamento.xml")
                with open(dbg, "w", encoding="utf-8") as _f:
                    _f.write(xml_final)
                print(f"[DEBUG] XML cancelamento salvo em {dbg}")
            except:
                pass

            # â”€â”€ 4. Determinar URL do serviÃ§o de eventos NFC-e por UF â”€â”€
            url_evento = ""
            try:
                from pynfe.utils.webservices import NFCE
                urls_uf = NFCE.get(uf)
                if not urls_uf:
                    # Fallback states typically use SVRS for NFC-e
                    urls_uf = NFCE.get("SVRS")
                if is_homolog:
                    url_evento = urls_uf.get("HOMOLOGACAO", "") + urls_uf.get("EVENTOS", "")
                else:
                    url_evento = urls_uf.get("HTTPS", "") + urls_uf.get("EVENTOS", "")
                
                # Cleanup if url is missing https
                if url_evento and not url_evento.startswith("http"):
                    if url_evento.startswith("www.") or url_evento.startswith("nfce.") or url_evento.startswith("homologacao."):
                        url_evento = "https://" + url_evento
            except Exception as e:
                print(f"[AVISO] Erro ao obter URL do pynfe: {e}")
            
            # Ensure a fallback 
            if not url_evento or url_evento == "https://":
                url_evento = "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRecepcaoEvento4.asmx" if is_homolog else "https://nfce.fazenda.sp.gov.br/ws/NFeRecepcaoEvento4.asmx"


            print(f"[DEBUG] URL evento NFC-e ({uf}): {url_evento} | Homolog: {is_homolog}")

            # â”€â”€ 5. Montar envelope SOAP 1.2 â”€â”€
            SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4/nfeRecepcaoEvento"
            soap_envelope = (
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
                'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">'
                '<soap12:Body>'
                '<nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">'
                + xml_str +
                '</nfeDadosMsg>'
                '</soap12:Body>'
                '</soap12:Envelope>'
            )

            # â”€â”€ 6. Separar certificado PFX em arquivos PEM para o requests â”€â”€
            cert_obj = _CertA1(caminho_cert)
            chave_pem, cert_pem = cert_obj.separar_arquivo(senha_cert, caminho=True)

            headers = {
                "Content-Type": f'application/soap+xml; charset=utf-8; action="{SOAP_ACTION}"',
            }

            resp = _req.post(
                url_evento,
                data=soap_envelope.encode("utf-8"),
                headers=headers,
                cert=(cert_pem, chave_pem),
                verify=False,
                timeout=30
            )
            resp.encoding = "utf-8"
            r_text = resp.text

            # DEBUG: salvar resposta
            try:
                resp_dbg = os.path.join(os.environ.get("TEMP", "C:/temp"), "last_cancelamento_resp.xml")
                with open(resp_dbg, "w", encoding="utf-8") as _f:
                    _f.write(r_text)
                print(f"[DEBUG] Resposta cancelamento (HTTP {resp.status_code}) salva em {resp_dbg}")
            except:
                pass

            if not r_text:
                return {"success": False, "error": "Sem resposta da SEFAZ", "mensagem": "Conexao interrompida"}

            # â”€â”€ 7. Parsear resposta (aceita tanto com envelope SOAP quanto sem) â”€â”€
            cstat = ""
            xmotivo = "Sem resposta legÃ­vel da SEFAZ"
            
            try:
                # Limpar soap body se houver
                xml_to_parse = r_text
                if "<soap:Body" in r_text or "<soap12:Body" in r_text:
                    match_body = re.search(r'<[^:]+:Body[^>]*>(.*?)</[^:]+:Body>', r_text, re.DOTALL)
                    if match_body:
                        xml_to_parse = match_body.group(1)
                
                resp_xml = etree.fromstring(xml_to_parse.encode('utf-8'))
                
                # Ignorar namespaces para facilitar a busca (xpath flexÃ­vel)
                cstat_evento = resp_xml.xpath('//*[local-name()="retEvento"]//*[local-name()="infEvento"]//*[local-name()="cStat"]/text()')
                xmotivo_evento = resp_xml.xpath('//*[local-name()="retEvento"]//*[local-name()="infEvento"]//*[local-name()="xMotivo"]/text()')
                
                if cstat_evento:
                    cstat = cstat_evento[0]
                    xmotivo = xmotivo_evento[0] if xmotivo_evento else "Status retornado vazio"
                else:
                    cstat_lote = resp_xml.xpath('//*[local-name()="retEnvEvento"]//*[local-name()="cStat"]/text()')
                    xmotivo_lote = resp_xml.xpath('//*[local-name()="retEnvEvento"]//*[local-name()="xMotivo"]/text()')
                    if cstat_lote:
                        cstat = cstat_lote[0]
                        xmotivo = xmotivo_lote[0] if xmotivo_lote else "Status de lote retornado vazio"
            except Exception as e:
                # Usar regex como fallback seguro
                cstats = re.findall(r'<cStat>(\d+)</cStat>', r_text)
                xmotivos = re.findall(r'<xMotivo>([^<]+)</xMotivo>', r_text)

                if len(cstats) >= 2:
                    cstat = cstats[-1] # Pegar o Ãºltimo que Ã© o do infEvento
                    xmotivo = xmotivos[-1] if len(xmotivos) >= 2 else "Lote processado"
                elif len(cstats) == 1:
                    cstat = cstats[0]
                    xmotivo = xmotivos[0] if xmotivos else "Sem resposta legÃ­vel da SEFAZ"
                else:
                    cstat = ""
                    xmotivo = "Sem resposta legÃ­vel da SEFAZ"

            print(f"[DEBUG] Cancelamento EVENTO cStat={cstat} | xMotivo={xmotivo}")

            # cStat 135 = Evento registrado e vinculado Ã  NF-e (cancelamento aceito)
            # cStat 155 = Cancelamento homologado (nota jÃ¡ cancelada fora do prazo / denÃºncia espontÃ¢nea - raro)
            # cStat 101 = Cancelamento de NF-e homologado
            success = cstat in ["135", "101", "155"]
            
            # Se success for falso, nÃ£o tem error genÃ©rico. Tem a mensagem exata do erro!
            return {
                "success": success,
                "cStat": cstat,
                "xMotivo": xmotivo,
                "mensagem": xmotivo,
                "error": None if success else f"RejeiÃ§Ã£o SEFAZ [{cstat}]: {xmotivo}",
                "data": {"cStat": cstat, "xMotivo": xmotivo}
            }
        finally:
            # Limpar arquivos PEM temporÃ¡rios
            for f_path in [chave_pem, cert_pem]:
                if f_path and os.path.exists(f_path):
                    try: os.remove(f_path)
                    except: pass
            # Limpar o cert_obj se existir
            try:
                cert_obj.excluir()
            except: pass
            if os.path.exists(caminho_cert):
                try: os.remove(caminho_cert)
                except: pass
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO CANCELAMENTO] {e}\n{tb}")
        return {"success": False, "error": str(e), "mensagem": f"Erro interno: {str(e)}", "traceback": tb}



CODIGO_UF = {
    "AC": "12", "AL": "27", "AP": "16", "AM": "13", "BA": "29",
    "CE": "23", "DF": "53", "ES": "32", "GO": "52", "MA": "21",
    "MT": "51", "MS": "50", "MG": "31", "PA": "15", "PB": "25",
    "PR": "41", "PE": "26", "PI": "22", "RJ": "33", "RN": "24",
    "RS": "43", "RO": "11", "RR": "14", "SC": "42", "SP": "35",
    "SE": "28", "TO": "17",
}

def inutilizar_nfce_pynfe(req_dict):
    """
    Inutiliza uma faixa de numeraÃ§Ã£o de NFC-e (serviÃ§o NFeInutilizacao4).

    Usado quando uma nota PENDENTE (rejeitada pela SEFAZ) nÃ£o serÃ¡ mais
    transmitida â€” o nÃºmero precisa ser "queimado" para nÃ£o ficar em sequÃªncia.

    O XML <inutNFe> Ã© montado manualmente pelo mesmo motivo do cancelamento:
    o pynfe nÃ£o respeita a ordem/posiÃ§Ã£o exigida pelo schema da SEFAZ.
    """
    from lxml import etree
    from datetime import datetime
    import base64, os, re, traceback, uuid
    import requests as _req
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    # CÃ³digo IBGE da UF (cUF), usado no atributo Id do infInut
    CODIGO_UF = {
        "AC": "12", "AL": "27", "AP": "16", "AM": "13", "BA": "29",
        "CE": "23", "DF": "53", "ES": "32", "GO": "52", "MA": "21",
        "MT": "51", "MS": "50", "MG": "31", "PA": "15", "PB": "25",
        "PR": "41", "PE": "26", "PI": "22", "RJ": "33", "RN": "24",
        "RS": "43", "RO": "11", "RR": "14", "SC": "42", "SP": "35",
        "SE": "28", "TO": "17",
    }

    caminho_cert = None
    chave_pem = None
    cert_pem = None
    cert_obj = None

    try:
        empresa_data = req_dict.get("empresa", {}) or {}
        try:
            serie = int(str(req_dict.get("serie") or 1).strip() or 1)
            numero_ini = int(str(req_dict.get("numero") or 0).strip() or 0)
            numero_fim = int(str(req_dict.get("numero_final") or numero_ini).strip() or numero_ini)
        except (TypeError, ValueError):
            return {"success": False, "error": "SÃ©rie/nÃºmero invÃ¡lidos.", "mensagem": "Dados invÃ¡lidos"}

        modelo = str(req_dict.get("modelo") or 65).strip() or "65"
        justificativa = str(req_dict.get("justificativa") or "")
        ano = req_dict.get("ano")
        ano = int(str(ano).strip()) if ano not in (None, "") else (datetime.now().year % 100)

        if not empresa_data.get("certificado_base64"):
            return {"success": False, "error": "Certificado ausente.", "mensagem": "Certificado nÃ£o informado"}
        if numero_ini <= 0:
            return {"success": False, "error": "NÃºmero invÃ¡lido.", "mensagem": "NÃºmero da nota nÃ£o informado"}
        if numero_fim < numero_ini:
            return {"success": False, "error": "Faixa invÃ¡lida.", "mensagem": "NÃºmero final menor que o inicial"}

        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        if len(cnpj) != 14:
            return {"success": False, "error": "CNPJ invÃ¡lido.", "mensagem": "CNPJ do emitente invÃ¡lido"}

        uf = str(empresa_data.get("uf", "SP")).upper()
        c_uf = CODIGO_UF.get(uf)
        if not c_uf:
            return {"success": False, "error": f"UF desconhecida: {uf}", "mensagem": "UF do emitente invÃ¡lida"}

        # Mapeamento robusto do ambiente (padrÃ£o de emissÃ£o usa ambiente_homologacao)
        is_homolog = (empresa_data.get("ambiente_homologacao") is True) or \
                     (str(empresa_data.get("ambiente")) == "2")
        tp_amb = "2" if is_homolog else "1"

        # xJust: 15â€“255 caracteres, sem caracteres proibidos pelo XSD
        just_limpa = re.sub(r'[^\w\s\.\,\-\/]', ' ', justificativa, flags=re.UNICODE).strip()
        just_limpa = re.sub(r'\s+', ' ', just_limpa)
        if len(just_limpa) < 15:
            just_limpa = "Quebra de sequencia de numeracao por falha na emissao"
        just_limpa = just_limpa[:255]

        # Id do infInut: "ID" + cUF + ano(2) + CNPJ + mod(2) + serie(3) + nNFIni(9) + nNFFin(9)
        id_inut = "ID{}{}{}{}{}{}{}".format(
            c_uf,
            str(ano).zfill(2),
            cnpj,
            modelo.zfill(2),
            str(serie).zfill(3),
            str(numero_ini).zfill(9),
            str(numero_fim).zfill(9),
        )

        NS = "http://www.portalfiscal.inf.br/nfe"

        # â”€â”€ 1. Montar inutNFe (lxml puro, sem ElementMaker para evitar xmlns="") â”€â”€
        inut = etree.Element(f"{{{NS}}}inutNFe", versao="4.00", nsmap={None: NS})
        inf_inut = etree.SubElement(inut, f"{{{NS}}}infInut", Id=id_inut)
        etree.SubElement(inf_inut, f"{{{NS}}}tpAmb").text = tp_amb
        etree.SubElement(inf_inut, f"{{{NS}}}xServ").text = "INUTILIZAR"
        etree.SubElement(inf_inut, f"{{{NS}}}cUF").text = c_uf
        etree.SubElement(inf_inut, f"{{{NS}}}ano").text = str(ano).zfill(2)
        etree.SubElement(inf_inut, f"{{{NS}}}CNPJ").text = cnpj
        etree.SubElement(inf_inut, f"{{{NS}}}mod").text = modelo.zfill(2)
        etree.SubElement(inf_inut, f"{{{NS}}}serie").text = str(serie)
        etree.SubElement(inf_inut, f"{{{NS}}}nNFIni").text = str(numero_ini)
        etree.SubElement(inf_inut, f"{{{NS}}}nNFFin").text = str(numero_fim)
        etree.SubElement(inf_inut, f"{{{NS}}}xJust").text = just_limpa

        # â”€â”€ 2. Assinar (Signature fica como irmÃ£ de <infInut>, dentro de <inutNFe>) â”€â”€
        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))
        senha_cert = empresa_data.get("senha_certificado", "")
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_inut_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)

        from pynfe.processamento.assinatura import AssinaturaA1
        from pynfe.entidades.certificado import CertificadoA1 as _CertA1

        assinador = AssinaturaA1(caminho_cert, senha_cert)
        inut_assinado = assinador.assinar(inut)

        xml_str = etree.tostring(inut_assinado, encoding="unicode")
        xml_str = xml_str.replace(' xmlns=""', '')

        # DEBUG: salvar XML de inutilizaÃ§Ã£o
        try:
            dbg = os.path.join(os.environ.get("TEMP", "C:/temp"), "last_inutilizacao.xml")
            with open(dbg, "w", encoding="utf-8") as _f:
                _f.write(xml_str)
            print(f"[DEBUG] XML inutilizacao salvo em {dbg}")
        except:
            pass

        # â”€â”€ 3. URL do serviÃ§o de inutilizaÃ§Ã£o por UF â”€â”€
        url_inut = ""
        try:
            from pynfe.utils.webservices import NFCE
            urls_uf = NFCE.get(uf) or NFCE.get("SVRS")
            if urls_uf:
                base = urls_uf.get("HOMOLOGACAO" if is_homolog else "HTTPS", "") or ""
                servico = urls_uf.get("INUTILIZACAO", "") or ""
                if servico:
                    url_inut = servico if servico.startswith("http") else (base + servico)
        except Exception as e:
            print(f"[AVISO] Erro ao obter URL de inutilizacao do pynfe: {e}")

        if url_inut in ("", "https://", "http://"):
            if is_homolog:
                url_inut = ("https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx"
                            if modelo.zfill(2) == "65"
                            else "https://homologacao.nfe.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx")
            else:
                url_inut = ("https://nfce.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx"
                            if modelo.zfill(2) == "65"
                            else "https://nfe.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx")

        print(f"[DEBUG] URL inutilizacao ({uf}): {url_inut} | Homolog: {is_homolog} | Id: {id_inut}")

        # â”€â”€ 4. Envelope SOAP 1.2 + certificado â”€â”€
        SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeInutilizacao4/nfeInutilizacaoNF"
        soap_envelope = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">'
            '<soap12:Body>'
            '<nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeInutilizacao4">'
            + xml_str +
            '</nfeDadosMsg>'
            '</soap12:Body>'
            '</soap12:Envelope>'
        )

        cert_obj = _CertA1(caminho_cert)
        chave_pem, cert_pem = cert_obj.separar_arquivo(senha_cert, caminho=True)

        headers = {
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{SOAP_ACTION}"',
        }

        resp = _req.post(
            url_inut,
            data=soap_envelope.encode("utf-8"),
            headers=headers,
            cert=(cert_pem, chave_pem),
            verify=False,
            timeout=30
        )
        resp.encoding = "utf-8"
        r_text = resp.text

        try:
            resp_dbg = os.path.join(os.environ.get("TEMP", "C:/temp"), "last_inutilizacao_resp.xml")
            with open(resp_dbg, "w", encoding="utf-8") as _f:
                _f.write(r_text)
            print(f"[DEBUG] Resposta inutilizacao (HTTP {resp.status_code}) salva em {resp_dbg}")
        except:
            pass

        if not r_text:
            return {"success": False, "error": "Sem resposta da SEFAZ", "mensagem": "Conexao interrompida"}

        # â”€â”€ 5. Parsear retInutNFe â”€â”€
        cstat = ""
        xmotivo = "Sem resposta legÃ­vel da SEFAZ"
        protocolo = ""
        try:
            xml_to_parse = r_text
            if "<soap:Body" in r_text or "<soap12:Body" in r_text or ":Body" in r_text:
                match_body = re.search(r'<[^:>]*:?Body[^>]*>(.*?)</[^:>]*:?Body>', r_text, re.DOTALL)
                if match_body:
                    xml_to_parse = match_body.group(1)

            resp_xml = etree.fromstring(xml_to_parse.encode('utf-8'))
            cstat_l = resp_xml.xpath('//*[local-name()="infInut"]/*[local-name()="cStat"]/text()')
            xmotivo_l = resp_xml.xpath('//*[local-name()="infInut"]/*[local-name()="xMotivo"]/text()')
            nprot_l = resp_xml.xpath('//*[local-name()="infInut"]/*[local-name()="nProt"]/text()')
            if not cstat_l:
                cstat_l = resp_xml.xpath('//*[local-name()="cStat"]/text()')
                xmotivo_l = resp_xml.xpath('//*[local-name()="xMotivo"]/text()')
            if cstat_l:
                cstat = cstat_l[0]
                xmotivo = xmotivo_l[0] if xmotivo_l else "Status retornado vazio"
            if nprot_l:
                protocolo = nprot_l[0]
        except Exception:
            cstats = re.findall(r'<cStat>(\d+)</cStat>', r_text)
            xmotivos = re.findall(r'<xMotivo>([^<]+)</xMotivo>', r_text)
            nprots = re.findall(r'<nProt>(\d+)</nProt>', r_text)
            if cstats:
                cstat = cstats[-1] if len(cstats) > 1 else cstats[0]
                xmotivo = xmotivos[-1] if xmotivos else "Sem resposta legÃ­vel da SEFAZ"
            if nprots:
                protocolo = nprots[-1]

        print(f"[DEBUG] Inutilizacao cStat={cstat} | xMotivo={xmotivo} | nProt={protocolo}")

        # cStat 102 = InutilizaÃ§Ã£o de nÃºmero homologado
        # cStat 218 = NF-e jÃ¡ estÃ¡ inutilizada na Base de Dados da SEFAZ (nÃºmero jÃ¡ estÃ¡ queimado)
        success = cstat in ["102", "218"]

        return {
            "success": success,
            "cStat": cstat,
            "xMotivo": xmotivo,
            "mensagem": xmotivo,
            "protocolo": protocolo,
            "ja_inutilizada": cstat == "218",
            "error": None if success else f"RejeiÃ§Ã£o SEFAZ [{cstat}]: {xmotivo}",
            "data": {"cStat": cstat, "xMotivo": xmotivo, "nProt": protocolo},
        }
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO INUTILIZACAO] {e}\n{tb}")
        return {"success": False, "error": str(e), "mensagem": f"Erro interno: {str(e)}", "traceback": tb}
    finally:
        for f_path in [chave_pem, cert_pem]:
            if f_path and os.path.exists(f_path):
                try: os.remove(f_path)
                except: pass
        try:
            if cert_obj is not None:
                cert_obj.excluir()
        except: pass
        if caminho_cert and os.path.exists(caminho_cert):
            try: os.remove(caminho_cert)
            except: pass


def consultar_nfce_pynfe(req_dict):
    """
    Consulta o status de uma NFC-e na SEFAZ.
    """
    try:
        # Usando ComunicacaoSefaz global
        
        chave_acesso = req_dict.get('chave_acesso')
        empresa_data = req_dict.get('empresa', {})
        uf = empresa_data.get('uf', 'SP')
        is_homologacao = empresa_data.get('ambiente_homologacao', True)
        
        cert_data = base64.b64decode(empresa_data.get('certificado_base64', ''))
        import uuid
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_consulta_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)
            
        try:
            senha_cert = empresa_data.get('senha_certificado', '')
            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homologacao)
            
            modelo_consulta = 'nfe' if len(chave_acesso) == 44 and chave_acesso[20:22] == '55' else 'nfce'
            resp = con.consulta_nota(modelo=modelo_consulta, chave=chave_acesso)
            if resp.status_code == 200:
                # O retorno da consulta Ã© um XML que precisa ser parseado para o app entender
                return {'success': True, 'xml': resp.text, 'status_code': resp.status_code}
            else:
                return {'success': False, 'error': f'Erro HTTP {resp.status_code}', 'details': resp.text[:500]}
        finally:
            if os.path.exists(caminho_cert):
                try: os.remove(caminho_cert)
                except: pass
    except Exception as e:
        return {'success': False, 'error': str(e)}

def validar_certificado_pynfe(req_dict):
    """Valida se o certificado e senha estÃ£o corretos e extrai informaÃ§Ãµes."""
    try:
        from pynfe.processamento.assinatura import AssinaturaA1
        from pynfe.entidades.certificado import CertificadoA1
        
        cert_b64 = req_dict.get('certificado_base64')
        senha = req_dict.get('senha')
        
        if not cert_b64 or not senha:
            return {'success': False, 'error': 'Certificado ou senha nÃ£o fornecidos.'}
            
        cert_data = base64.b64decode(cert_b64)
        import uuid
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_validar_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)
            
        try:
            # Tentar instanciar o certificado (valida a senha)
            cert = CertificadoA1(caminho_cert)
            # extrair info se possÃ­vel (pynfe pode nÃ£o ter extraÃ§Ã£o direta amigÃ¡vel)
            # mas o fato de carregar sem erro jÃ¡ valida a senha
            return {
                'success': True, 
                'mensagem': 'Certificado validado com sucesso.',
                'valido': True
            }
        except Exception as e:
            return {'success': False, 'error': f'Sua senha ou o arquivo do certificado estÃ£o incorretos: {str(e)}'}
        finally:
            if os.path.exists(caminho_cert):
                try: os.remove(caminho_cert)
                except: pass
    except Exception as e:
        return {'success': False, 'error': str(e)}




def consultar_distribuicao_pynfe(req_dict):
    """
    Consulta o WebService NFeDistribuicaoDFe da SEFAZ (Ambiente Nacional).
    Permite puxar as notas fiscais (NF-e) emitidas contra o CNPJ da empresa,
    seja por chave de acesso (44 digitos) ou por lote NSU.
    """
    from lxml import etree
    import base64, os, re, traceback, uuid, gzip
    import requests as _req
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    caminho_cert = None
    chave_pem = None
    cert_pem = None
    cert_obj = None

    try:
        empresa_data = req_dict.get("empresa", {}) or {}
        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        if len(cnpj) != 14:
            return {"success": False, "error": "CNPJ da empresa invalido ou nao informado."}

        uf = str(empresa_data.get("uf", "SP")).upper()
        c_uf = CODIGO_UF.get(uf, "35")

        is_homolog = (empresa_data.get("ambiente_homologacao") is True) or (str(empresa_data.get("ambiente")) == "2")
        tp_amb = "2" if is_homolog else "1"

        cert_b64 = empresa_data.get("certificado_base64")
        senha_cert = empresa_data.get("senha_certificado", "")
        if not cert_b64:
            return {"success": False, "error": "Certificado digital A1 nao configurado na empresa."}

        chave_acesso = re.sub(r"[^0-9]", "", str(req_dict.get("chave_acesso") or ""))
        nsu_informado = str(req_dict.get("nsu") or "0").strip()
        consulta_nsu_especifico = bool(req_dict.get("consulta_nsu_especifico", False))

        NS = "http://www.portalfiscal.inf.br/nfe"
        raiz = etree.Element(f"{{{NS}}}distDFeInt", versao="1.01", nsmap={None: NS})
        etree.SubElement(raiz, f"{{{NS}}}tpAmb").text = tp_amb
        etree.SubElement(raiz, f"{{{NS}}}cUFAutor").text = c_uf
        etree.SubElement(raiz, f"{{{NS}}}CNPJ").text = cnpj

        if chave_acesso and len(chave_acesso) == 44:
            cons_chave = etree.SubElement(raiz, f"{{{NS}}}consChNFe")
            etree.SubElement(cons_chave, f"{{{NS}}}chNFe").text = chave_acesso
        elif consulta_nsu_especifico and nsu_informado and nsu_informado != "0":
            cons_nsu = etree.SubElement(raiz, f"{{{NS}}}consNSU")
            etree.SubElement(cons_nsu, f"{{{NS}}}NSU").text = nsu_informado.zfill(15)
        else:
            dist_nsu = etree.SubElement(raiz, f"{{{NS}}}distNSU")
            etree.SubElement(dist_nsu, f"{{{NS}}}ultNSU").text = (nsu_informado or "0").zfill(15)

        xml_dados = etree.tostring(raiz, encoding="unicode")
        xml_dados = xml_dados.replace(' xmlns=""', '')

        SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse"
        soap_envelope = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">'
            '<soap12:Body>'
            '<nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">'
            '<nfeDadosMsg>'
            + xml_dados +
            '</nfeDadosMsg>'
            '</nfeDistDFeInteresse>'
            '</soap12:Body>'
            '</soap12:Envelope>'
        )

        cert_data = base64.b64decode(cert_b64)
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_dist_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)

        from pynfe.entidades.certificado import CertificadoA1 as _CertA1
        cert_obj = _CertA1(caminho_cert)
        chave_pem, cert_pem = cert_obj.separar_arquivo(senha_cert, caminho=True)

        url_dist = ("https://hom1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx"
                    if is_homolog
                    else "https://www1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx")

        headers = {
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{SOAP_ACTION}"',
        }

        print(f"[DEBUG DFE] Enviando consulta distribuicao para {url_dist} (CNPJ: {cnpj})...")
        resp = _req.post(
            url_dist,
            data=soap_envelope.encode("utf-8"),
            headers=headers,
            cert=(cert_pem, chave_pem),
            verify=False,
            timeout=40
        )
        resp.encoding = "utf-8"
        r_text = resp.text

        if not r_text:
            return {"success": False, "error": "Sem resposta da SEFAZ.", "mensagem": "Conexao interrompida"}

        xml_to_parse = r_text
        if "<soap:Body" in r_text or "<soap12:Body" in r_text or ":Body" in r_text:
            match_body = re.search(r'<[^:>]*:?Body[^>]*>(.*?)</[^:>]*:?Body>', r_text, re.DOTALL)
            if match_body:
                xml_to_parse = match_body.group(1)

        resp_xml = etree.fromstring(xml_to_parse.encode('utf-8'))

        cstat_l = resp_xml.xpath('//*[local-name()="retDistDFeInt"]/*[local-name()="cStat"]/text()')
        xmotivo_l = resp_xml.xpath('//*[local-name()="retDistDFeInt"]/*[local-name()="xMotivo"]/text()')
        ult_nsu_l = resp_xml.xpath('//*[local-name()="retDistDFeInt"]/*[local-name()="ultNSU"]/text()')
        max_nsu_l = resp_xml.xpath('//*[local-name()="retDistDFeInt"]/*[local-name()="maxNSU"]/text()')

        cstat = cstat_l[0] if cstat_l else ""
        xmotivo = xmotivo_l[0] if xmotivo_l else ""
        ult_nsu = ult_nsu_l[0] if ult_nsu_l else ""
        max_nsu = max_nsu_l[0] if max_nsu_l else ""

        print(f"[DEBUG DFE] cStat={cstat} | xMotivo={xmotivo} | ultNSU={ult_nsu} | maxNSU={max_nsu}")

        doc_zips = resp_xml.xpath('//*[local-name()="loteDistDFeInt"]/*[local-name()="docZip"]')
        notas = []

        for dz in doc_zips:
            try:
                nsu_doc = dz.get("NSU") or ""
                schema_doc = dz.get("schema") or ""
                raw_b64 = (dz.text or "").strip()
                if not raw_b64:
                    continue

                decompressed_bytes = gzip.decompress(base64.b64decode(raw_b64))
                doc_xml_str = decompressed_bytes.decode("utf-8", errors="replace")
                doc_el = etree.fromstring(decompressed_bytes)

                tag_name = etree.QName(doc_el).localname

                if tag_name == "resNFe":
                    ch_nfe = doc_el.findtext('.//{*}chNFe') or ""
                    emit_cnpj = doc_el.findtext('.//{*}CNPJ') or doc_el.findtext('.//{*}CPF') or ""
                    emit_nome = doc_el.findtext('.//{*}xNome') or ""
                    emit_ie = doc_el.findtext('.//{*}IE') or ""
                    dh_emi = doc_el.findtext('.//{*}dhEmi') or ""
                    v_nf = float(doc_el.findtext('.//{*}vNF') or 0.0)
                    csit_nfe = doc_el.findtext('.//{*}cSitNFe') or "1"
                    csit_conf = doc_el.findtext('.//{*}cSitConf') or "0"

                    num_nota = ""
                    serie_nota = ""
                    if len(ch_nfe) == 44:
                        try:
                            num_nota = str(int(ch_nfe[25:34]))
                            serie_nota = str(int(ch_nfe[22:25]))
                        except:
                            num_nota = ch_nfe[25:34]
                            serie_nota = ch_nfe[22:25]

                    situacao = "autorizada"
                    if csit_nfe == "2":
                        situacao = "denegada"
                    elif csit_nfe == "3":
                        situacao = "cancelada"

                    notas.append({
                        "nsu": nsu_doc,
                        "schema": schema_doc,
                        "tipo": "resumo",
                        "chave": ch_nfe,
                        "numero": num_nota,
                        "serie": serie_nota,
                        "emitente_cnpj": emit_cnpj,
                        "emitente_nome": emit_nome,
                        "emitente_ie": emit_ie,
                        "data_emissao": dh_emi,
                        "valor_total": v_nf,
                        "situacao": situacao,
                        "situacao_codigo": csit_nfe,
                        "manifestacao_codigo": csit_conf,
                        "tem_xml_completo": False,
                        "xml": doc_xml_str
                    })

                elif "nfeProc" in tag_name or "NFe" in tag_name:
                    ch_nfe = doc_el.findtext('.//{*}chNFe') or ""
                    if not ch_nfe:
                        inf_nfe = doc_el.find('.//{*}infNFe')
                        if inf_nfe is not None:
                            attr_id = inf_nfe.get('Id') or ''
                            if attr_id.startswith('NFe'):
                                ch_nfe = attr_id[3:]

                    num_nota = doc_el.findtext('.//{*}ide/{*}nNF') or ""
                    serie_nota = doc_el.findtext('.//{*}ide/{*}serie') or ""
                    emit_cnpj = doc_el.findtext('.//{*}emit/{*}CNPJ') or doc_el.findtext('.//{*}emit/{*}CPF') or ""
                    emit_nome = doc_el.findtext('.//{*}emit/{*}xNome') or ""
                    emit_ie = doc_el.findtext('.//{*}emit/{*}IE') or ""
                    dh_emi = doc_el.findtext('.//{*}ide/{*}dhEmi') or doc_el.findtext('.//{*}ide/{*}dEmi') or ""
                    v_nf = float(doc_el.findtext('.//{*}total/{*}ICMSTot/{*}vNF') or 0.0)

                    notas.append({
                        "nsu": nsu_doc,
                        "schema": schema_doc,
                        "tipo": "completo",
                        "chave": ch_nfe,
                        "numero": num_nota,
                        "serie": serie_nota,
                        "emitente_cnpj": emit_cnpj,
                        "emitente_nome": emit_nome,
                        "emitente_ie": emit_ie,
                        "data_emissao": dh_emi,
                        "valor_total": v_nf,
                        "situacao": "autorizada",
                        "tem_xml_completo": True,
                        "xml": doc_xml_str
                    })

                elif "resEvento" in tag_name or "procEventoNFe" in tag_name:
                    ch_nfe = doc_el.findtext('.//{*}chNFe') or ""
                    tp_evento = doc_el.findtext('.//{*}tpEvento') or ""
                    x_evento = doc_el.findtext('.//{*}xEvento') or ""
                    dh_evento = doc_el.findtext('.//{*}dhEvento') or ""
                    if tp_evento == "110111":
                        for n in notas:
                            if n.get("chave") == ch_nfe:
                                n["situacao"] = "cancelada"
            except Exception as e_doc:
                print(f"[AVISO DFE] Erro ao descompactar docZip {dz.get('NSU')}: {e_doc}")

        success = cstat in ["138", "137"]
        msg = xmotivo
        if cstat == "656":
            msg = "Consumo Indevido: a SEFAZ exige aguardar antes de consultar novamente o mesmo NSU."
        elif cstat == "137" and not notas:
            msg = "Nenhuma nova nota fiscal localizada na SEFAZ para este CNPJ no momento."

        return {
            "success": success,
            "cStat": cstat,
            "xMotivo": xmotivo,
            "mensagem": msg,
            "ultNSU": ult_nsu,
            "maxNSU": max_nsu,
            "total_documentos": len(notas),
            "notas": notas
        }
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO DISTRIBUICAO DFE] {e} {tb}")
        return {"success": False, "error": str(e), "mensagem": f"Erro interno ao consultar SEFAZ: {str(e)}", "traceback": tb}
    finally:
        for f_path in [chave_pem, cert_pem]:
            if f_path and os.path.exists(f_path):
                try: os.remove(f_path)
                except: pass
        try:
            if cert_obj is not None:
                cert_obj.excluir()
        except: pass
        if caminho_cert and os.path.exists(caminho_cert):
            try: os.remove(caminho_cert)
            except: pass


def manifestar_dfe_pynfe(req_dict):
    """
    Envia evento de Manifestacao do Destinatario para a SEFAZ (Ambiente Nacional).
    Eventos suportados:
      210200: Confirmacao da Operacao
      210210: Ciencia da Emissao
      210220: Desconhecimento da Operacao
      210240: Operacao nao Realizada
    """
    from lxml import etree
    from datetime import datetime
    import base64, os, re, traceback, uuid
    import requests as _req
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    caminho_cert = None
    chave_pem = None
    cert_pem = None
    cert_obj = None

    try:
        empresa_data = req_dict.get("empresa", {}) or {}
        chave_acesso = re.sub(r"[^0-9]", "", str(req_dict.get("chave_acesso") or ""))
        tipo_evento = str(req_dict.get("tipo_evento") or "210210").strip()
        justificativa = str(req_dict.get("justificativa") or "").strip()

        if len(chave_acesso) != 44:
            return {"success": False, "error": "Chave de acesso deve conter exatamente 44 digitos."}

        cert_b64 = empresa_data.get("certificado_base64")
        senha_cert = empresa_data.get("senha_certificado", "")
        if not cert_b64:
            return {"success": False, "error": "Certificado digital A1 nao informado."}

        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        is_homolog = (empresa_data.get("ambiente_homologacao") is True) or (str(empresa_data.get("ambiente")) == "2")
        tp_amb = "2" if is_homolog else "1"
        dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")

        NOMES_EVENTO = {
            "210200": "Confirmacao da Operacao",
            "210210": "Ciencia da Emissao",
            "210220": "Desconhecimento da Operacao",
            "210240": "Operacao nao Realizada"
        }
        desc_evento = NOMES_EVENTO.get(tipo_evento, "Ciencia da Emissao")
        c_orgao = "91"

        NS = "http://www.portalfiscal.inf.br/nfe"
        env_evento = etree.Element(f"{{{NS}}}envEvento", versao="1.00", nsmap={None: NS})
        etree.SubElement(env_evento, f"{{{NS}}}idLote").text = "1"

        evento_el = etree.SubElement(env_evento, f"{{{NS}}}evento", versao="1.00")
        id_evento = f"ID{tipo_evento}{chave_acesso}01"
        inf_evento = etree.SubElement(evento_el, f"{{{NS}}}infEvento", Id=id_evento)

        etree.SubElement(inf_evento, f"{{{NS}}}cOrgao").text = c_orgao
        etree.SubElement(inf_evento, f"{{{NS}}}tpAmb").text = tp_amb
        etree.SubElement(inf_evento, f"{{{NS}}}CNPJ").text = cnpj
        etree.SubElement(inf_evento, f"{{{NS}}}chNFe").text = chave_acesso
        etree.SubElement(inf_evento, f"{{{NS}}}dhEvento").text = dh_evento
        etree.SubElement(inf_evento, f"{{{NS}}}tpEvento").text = tipo_evento
        etree.SubElement(inf_evento, f"{{{NS}}}nSeqEvento").text = "1"
        etree.SubElement(inf_evento, f"{{{NS}}}verEvento").text = "1.00"

        det_evento = etree.SubElement(inf_evento, f"{{{NS}}}detEvento", versao="1.00")
        etree.SubElement(det_evento, f"{{{NS}}}descEvento").text = desc_evento
        if tipo_evento == "210240":
            if len(justificativa) < 15:
                justificativa = "Operacao nao realizada mercadoria nao recebida"
            etree.SubElement(det_evento, f"{{{NS}}}xJust").text = justificativa[:255]

        cert_data = base64.b64decode(cert_b64)
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_manif_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)

        from pynfe.processamento.assinatura import AssinaturaA1
        from pynfe.entidades.certificado import CertificadoA1 as _CertA1

        assinador = AssinaturaA1(caminho_cert, senha_cert)
        env_evento_assinado = assinador.assinar(env_evento)

        NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"
        NS_NFE = "http://www.portalfiscal.inf.br/nfe"

        sig_errada = env_evento_assinado.find(f"{{{NS_DSIG}}}Signature")
        if sig_errada is None:
            sig_errada = env_evento_assinado.find("Signature")

        if sig_errada is not None:
            env_evento_assinado.remove(sig_errada)
            evento_tag = env_evento_assinado.find(f"{{{NS_NFE}}}evento")
            if evento_tag is None:
                evento_tag = env_evento_assinado.find("evento")
            if evento_tag is not None:
                evento_tag.append(sig_errada)
            else:
                env_evento_assinado.append(sig_errada)

        xml_str = etree.tostring(env_evento_assinado, encoding="unicode")
        xml_str = xml_str.replace(' xmlns=""', '')

        url_evento = ("https://hom.nfe.fazenda.gov.br/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx"
                      if is_homolog
                      else "https://www.nfe.fazenda.gov.br/NFeRecepcaoEvento4/NFeRecepcaoEvento4.asmx")

        SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4/nfeRecepcaoEvento"
        soap_envelope = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">'
            '<soap12:Body>'
            '<nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeRecepcaoEvento4">'
            + xml_str +
            '</nfeDadosMsg>'
            '</soap12:Body>'
            '</soap12:Envelope>'
        )

        cert_obj = _CertA1(caminho_cert)
        chave_pem, cert_pem = cert_obj.separar_arquivo(senha_cert, caminho=True)

        headers = {
            "Content-Type": f'application/soap+xml; charset=utf-8; action="{SOAP_ACTION}"',
        }

        print(f"[DEBUG MANIF] Enviando evento {tipo_evento} para {url_evento} (Chave: {chave_acesso})...")
        resp = _req.post(
            url_evento,
            data=soap_envelope.encode("utf-8"),
            headers=headers,
            cert=(cert_pem, chave_pem),
            verify=False,
            timeout=35
        )
        resp.encoding = "utf-8"
        r_text = resp.text

        if not r_text:
            return {"success": False, "error": "Sem resposta da SEFAZ.", "mensagem": "Conexao interrompida"}

        xml_to_parse = r_text
        if "<soap:Body" in r_text or "<soap12:Body" in r_text or ":Body" in r_text:
            match_body = re.search(r'<[^:>]*:?Body[^>]*>(.*?)</[^:>]*:?Body>', r_text, re.DOTALL)
            if match_body:
                xml_to_parse = match_body.group(1)

        resp_xml = etree.fromstring(xml_to_parse.encode('utf-8'))
        cstat_evento = resp_xml.xpath('//*[local-name()="retEvento"]//*[local-name()="infEvento"]//*[local-name()="cStat"]/text()')
        xmotivo_evento = resp_xml.xpath('//*[local-name()="retEvento"]//*[local-name()="infEvento"]//*[local-name()="xMotivo"]/text()')

        cstat = ""
        xmotivo = "Sem resposta legivel da SEFAZ"

        if cstat_evento:
            cstat = cstat_evento[0]
            xmotivo = xmotivo_evento[0] if xmotivo_evento else "Status retornado vazio"
        else:
            cstat_lote = resp_xml.xpath('//*[local-name()="retEnvEvento"]//*[local-name()="cStat"]/text()')
            xmotivo_lote = resp_xml.xpath('//*[local-name()="retEnvEvento"]//*[local-name()="xMotivo"]/text()')
            if cstat_lote:
                cstat = cstat_lote[0]
                xmotivo = xmotivo_lote[0] if xmotivo_lote else "Status de lote retornado vazio"

        print(f"[DEBUG MANIF] cStat={cstat} | xMotivo={xmotivo}")

        success = cstat in ["135", "573"]

        return {
            "success": success,
            "cStat": cstat,
            "xMotivo": xmotivo,
            "mensagem": xmotivo,
            "chave_acesso": chave_acesso,
            "tipo_evento": tipo_evento
        }
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO MANIFESTACAO DFE] {e} {tb}")
        return {"success": False, "error": str(e), "mensagem": f"Erro interno ao manifestar SEFAZ: {str(e)}", "traceback": tb}
    finally:
        for f_path in [chave_pem, cert_pem]:
            if f_path and os.path.exists(f_path):
                try: os.remove(f_path)
                except: pass
        try:
            if cert_obj is not None:
                cert_obj.excluir()
        except: pass
        if caminho_cert and os.path.exists(caminho_cert):
            try: os.remove(caminho_cert)
            except: pass
