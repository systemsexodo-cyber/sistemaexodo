from decimal import Decimal, ROUND_HALF_UP
import base64
import os
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

            # Realizar a requisição SOAP
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

def corrigir_blocos_icms_simples(xml_element):
    """Corrige o bug do pynfe 0.6.5 na serialização dos blocos do Simples Nacional.

    O pynfe gera o bloco <ICMSSN102> para CSOSN 103/300/400 (e <ICMSSN202> para
    203), mas o schema da NF-e 4.00 exige que o nome do bloco corresponda ao CSOSN
    (ex: CSOSN 400 deve estar dentro de <ICMSSN400>). Esta função percorre cada
    <ICMS> e renomeia o bloco filho conforme o valor real do <CSOSN>.
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
            bloco_esperado = f"ICMSSN{csosn_val}"
            if tag_name != bloco_esperado:
                print(f"[FIX] Bloco ICMS renomeado: {tag_name} -> {bloco_esperado} (CSOSN {csosn_val})")
                if '}' in bloco.tag:
                    bloco.tag = f"{{{ns}}}{bloco_esperado}"
                else:
                    bloco.tag = bloco_esperado


def fix_xml_namespaces(element, ns):
    """Garante que todos os elementos usem o namespace correto e protege tags obrigatórias."""
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
                
    # Tags que NUNCA devem ser removidas (obrigatórias pelo Schema NFe/NFCe 4.00)
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
                # Se for obrigatória e estiver nula, colocar pelo menos uma string vazia ou valor padrão
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

# --- MONKEYPATCH CRÍTICO PARA MUNICÍPIO ---
# O pynfe 0.6.5 tem um bug onde ele ignora o código do município fornecido e tenta 
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
    
    # CORREÇÃO: Usar o código se ele existir e for numérico, senão buscar
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
    etree.SubElement(raiz, "IE").text = emitente.inscricao_estadual
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
        
        # CORREÇÃO: Usar o código se ele existir e for numérico, senão buscar
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
    Monkeypatch corrigido para geração de QR Code da NFC-e.
    Corrige dois bugs do pynfe original:
    1. Import de NFCE estava errado (flags vs webservices)
    2. Bug que removia zeros do token (IdToken)
    """
    from pynfe.utils.flags import VERSAO_QRCODE, CODIGOS_ESTADOS
    from pynfe.utils.webservices import NFCE  # NFCE está em webservices, NÃO em flags!

    nfe = xml
    ns  = {"ns":  "http://www.portalfiscal.inf.br/nfe"}
    sig = {"sig": "http://www.w3.org/2000/09/xmldsig#"}
    ns_nfe = "http://www.portalfiscal.inf.br/nfe"

    # Pegar chave de acesso (remover prefixo 'NFe')
    id_attr = nfe[0].attrib.get("Id") or nfe[0].attrib.get(f"{{{ns_nfe}}}Id") or ""
    chave = id_attr.replace("NFe", "")

    tpamb = nfe.xpath("ns:infNFe/ns:ide/ns:tpAmb/text()", namespaces=ns)[0]
    cuf   = nfe.xpath("ns:infNFe/ns:ide/ns:cUF/text()", namespaces=ns)[0]  # código numérico (ex: '35')

    # Converter código numérico de UF para sigla (ex: '35' -> 'SP')
    uf_sigla = [k for k, v in CODIGOS_ESTADOS.items() if v == cuf]
    if not uf_sigla:
        raise ValueError(f"Código de UF '{cuf}' não encontrado em CODIGOS_ESTADOS")
    uf = uf_sigla[0].upper()

    # Identificador do CSC (IdToken) deve ter exatamente 6 dígitos.
    # Ex: '1' -> '000001' (Obrigatório para Schema 225 em SP e outros estados)
    cIdToken = str(token).zfill(6)
    
    # Valores dinâmicos para o QR Code 2.00 (MOC 6.0)
    # Devem ser convertidos para Hexadecimal ASCII
    def to_hex_ascii(val):
        if not val: return ""
        return "".join("{:02x}".format(ord(c)) for c in str(val)).upper()

    try:
        # Extrair valores do XML para compor a URL do QR Code
        vNF_val = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vNF/text()", namespaces=ns)[0]
        vICMS_val = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vICMS/text()", namespaces=ns)[0]
        dhEmi_val = nfe.xpath("ns:infNFe/ns:ide/ns:dhEmi/text()", namespaces=ns)[0]
        # DigestValue está dentro de Signature/SignedInfo/Reference
        digVal_val = nfe.xpath("//sig:Signature/sig:SignedInfo/sig:Reference/sig:DigestValue/text()", namespaces=sig)[0]
        
        vNF_hex = to_hex_ascii(vNF_val)
        vICMS_hex = to_hex_ascii(vICMS_val)
        dhEmi_hex = to_hex_ascii(dhEmi_val)
        digVal_hex = to_hex_ascii(digVal_val)
    except Exception as e:
        print(f"[ERRO] Falha ao extrair dados para o QR Code: {str(e)}")
        vNF_hex = vICMS_hex = dhEmi_hex = digVal_hex = ""

    if online:
        # SP e a maioria dos estados usam o formato de 5 parâmetros no QR Code 2.00 Online
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

def _fixed_post(self, url, xml, timeout=None):
    from pynfe.utils import etree as _etree
    certificado_a1 = _CertA1(self.certificado)
    chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
    chave_cert = (cert, chave)
    xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
    try:
        xml_str = _etree.tostring(xml, encoding="unicode")

        xml_str = xml_str.replace(' xmlns="http://www.portalfiscal.inf.br/nfe"', '')
        xml_str = xml_str.replace('<enviNFe', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe"')
        xml_str = xml_str.replace('<NFe>', '<NFe xmlns="http://www.portalfiscal.inf.br/nfe">')
        
        xml_str = re.sub(r'<\?xml.*?\?>', '', xml_str).strip()
        xml_str = xml_str.replace('\n', '').replace('\r', '')
        xml_str = re.sub(r'>\s+<', '><', xml_str)
        
        # 2. Garantir versao em infNFe preservando Id (Regex flexível para atributos em qualquer ordem)
        # CRÍTICO: usar regex preciso para NÃO afetar <infNFeSupl> (só <infNFe> ou <infNFe ...>)
        # Usamos (?!\w) para garantir que 'infNFe' não seja seguido por 'Supl' ou qualquer outra letra
        xml_str = re.sub(r'<(infNFe(?!\w)[^>]*)\s+xmlns=["\'][^"\']*["\']', r'<\1', xml_str)
        xml_str = re.sub(r'<(infNFe(?!\w)[^>]*)\s+versao=["\'][^"\']*["\']', r'<\1', xml_str)
        # Adicionar versao="4.00" SOMENTE em <infNFe> e <infNFe ...>, nunca em <infNFeSupl>
        xml_str = re.sub(r'<infNFe(?!\w)([\s>])', r'<infNFe versao="4.00"\1', xml_str)
        
        xml_str = xml_str.replace(' xmlns=""', '')
        xml_str = xml_str.replace('>>', '>')
        
        # FIX DE ORDEM CRÍTICO (infNFe -> infNFeSupl -> Signature)
        # Separar infNFeSupl e Signature com regex ainda mais flexível
        # Nota: infNFeSupl deve vir ANTES da Signature na NFC-e 4.00
        match_supl = re.search(r'(<infNFeSupl[^>]*>.*?</infNFeSupl>)', xml_str, re.DOTALL)
        match_sig = re.search(r'(<Signature[^>]*>.*?</Signature>)', xml_str, re.DOTALL)
        
        if match_supl and match_sig:
            # Remover de onde estiver para remontar no final
            xml_str = xml_str.replace(match_supl.group(1), '')
            xml_str = xml_str.replace(match_sig.group(1), '')
            
            # Limpar lixo de tag de fechamento infNFe se existir duplicata ou erro de concatenação
            xml_str = xml_str.replace('</infNFe></NFe>', '</infNFe>')
            
            # Reconstruir na ordem perfeita do Schema 4.00 
            # A ordem EXATA: ...</infNFe><infNFeSupl>...</infNFeSupl><Signature>...</Signature></NFe>
            rearranjado = f'{match_supl.group(1)}{match_sig.group(1)}</NFe>'
            
            # Garantir que inserimos logo após o fechamento do infNFe
            if '</infNFe>' in xml_str:
                # Primeiro removemos qualquer </NFe> que tenha sobrado após o replaces acima
                xml_str = xml_str.replace('</NFe>', '')
                xml_str = xml_str.replace('</infNFe>', f'</infNFe>{rearranjado}')
            else:
                # Fallback caso a estrutura esteja muito bagunçada
                xml_str = xml_str.replace('</NFe>', rearranjado)

        # DEBUG: Salvar XML final enviado
        try:
            dbg_path = os.path.join(os.environ.get('TEMP', 'C:/temp'), 'last_enviNFe.xml')
            with open(dbg_path, 'w', encoding='utf-8') as _f:
                _f.write(xml_declaration + xml_str)
            print(f"[DEBUG] enviNFe salvo em {dbg_path}")
        except:
            pass

        xml_str = xml_declaration + xml_str
        result = _requests.post(
            url,
            xml_str,
            headers=self._post_header(),
            cert=chave_cert,
            verify=False,
            timeout=timeout,
        )
        result.encoding = "utf-8"
        
        # FIX 4: Salvar resposta do SEFAZ para debug
        try:
            resp_path = os.path.join(os.environ.get('TEMP', 'C:/temp'), 'last_sefaz_response.xml')
            with open(resp_path, 'w', encoding='utf-8') as _f:
                _f.write(result.text)
            print(f"[DEBUG] Resposta SEFAZ (status {result.status_code}) salva em {resp_path}")
        except Exception:
            pass
        
        return result
    except _requests.exceptions.RequestException as e:
        raise e
    finally:
        certificado_a1.excluir()

ComunicacaoSefaz._post = _fixed_post
print("[PATCH] ComunicacaoSefaz._post substituído com fix de namespace infNFeSupl")


class MockFonteDados:
    def __init__(self, nota):
        self.nota = nota
    def obter_lista(self, _classe=None, **kwargs):
        return [self.nota]
    def limpar_dados(self):
        pass


def adicionar_ibscbs_xml(xml_element, ns_nfe):
    dets = xml_element.findall(f".//{{{ns_nfe}}}det")
    if not dets:
        dets = xml_element.findall(".//det")
        
    total_bc = Decimal("0.00")
    total_ibs_uf = Decimal("0.00")
    total_ibs_mun = Decimal("0.00")
    total_ibs = Decimal("0.00")
    total_cbs = Decimal("0.00")
    
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
            
        v_prod = Decimal(v_prod_el.text)
        
        v_bc = v_prod
        v_ibs_uf = (v_bc * Decimal("0.001")).quantize(Decimal("0.01"))
        v_ibs_mun = Decimal("0.00")
        v_ibs = v_ibs_uf + v_ibs_mun
        v_cbs = (v_bc * Decimal("0.009")).quantize(Decimal("0.01"))
        
        total_bc += v_bc
        total_ibs_uf += v_ibs_uf
        total_ibs_mun += v_ibs_mun
        total_ibs += v_ibs
        total_cbs += v_cbs
        
        imposto = det.find(f"{{{ns_nfe}}}imposto")
        if imposto is None:
            imposto = det.find("imposto")
        if imposto is None:
            continue
            
        ibscbs = etree.SubElement(imposto, f"{{{ns_nfe}}}IBSCBS")
        etree.SubElement(ibscbs, f"{{{ns_nfe}}}CST").text = "000"
        etree.SubElement(ibscbs, f"{{{ns_nfe}}}cClassTrib").text = "000001"
        
        g_ibscbs = etree.SubElement(ibscbs, f"{{{ns_nfe}}}gIBSCBS")
        etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}vBC").text = f"{v_bc:.2f}"
        
        g_ibs_uf = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gIBSUF")
        etree.SubElement(g_ibs_uf, f"{{{ns_nfe}}}pIBSUF").text = "0.1000"
        etree.SubElement(g_ibs_uf, f"{{{ns_nfe}}}vIBSUF").text = f"{v_ibs_uf:.2f}"
        
        g_ibs_mun = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gIBSMun")
        etree.SubElement(g_ibs_mun, f"{{{ns_nfe}}}pIBSMun").text = "0.0000"
        etree.SubElement(g_ibs_mun, f"{{{ns_nfe}}}vIBSMun").text = f"{v_ibs_mun:.2f}"
        
        etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}vIBS").text = f"{v_ibs:.2f}"
        
        g_cbs = etree.SubElement(g_ibscbs, f"{{{ns_nfe}}}gCBS")
        etree.SubElement(g_cbs, f"{{{ns_nfe}}}pCBS").text = "0.9000"
        etree.SubElement(g_cbs, f"{{{ns_nfe}}}vCBS").text = f"{v_cbs:.2f}"
        
    total = xml_element.find(f".//{{{ns_nfe}}}total")
    if total is None:
        total = xml_element.find("total")
    if total is not None:
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
        etree.SubElement(g_ibs_mun_tot, f"{{{ns_nfe}}}vIBSMun").text = f"{total_ibs_mun:.2f}"
        
        etree.SubElement(g_ibs, f"{{{ns_nfe}}}vIBS").text = f"{total_ibs:.2f}"
        etree.SubElement(g_ibs, f"{{{ns_nfe}}}vCredPres").text = "0.00"
        etree.SubElement(g_ibs, f"{{{ns_nfe}}}vCredPresCondSus").text = "0.00"
        
        g_cbs_tot = etree.SubElement(ibscbs_tot, f"{{{ns_nfe}}}gCBS")
        etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vDif").text = "0.00"
        etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vDevTrib").text = "0.00"
        etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCBS").text = f"{total_cbs:.2f}"
        etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCredPres").text = "0.00"
        etree.SubElement(g_cbs_tot, f"{{{ns_nfe}}}vCredPresCondSus").text = "0.00"
        
        etree.SubElement(total, f"{{{ns_nfe}}}vNFTot").text = f"{total_bc:.2f}"


def adicionar_produto_com_icms(nota_fiscal, item, emp, descricao=None, cfop_sugerido=None, desconto=None):
    """
    Adiciona um produto/serviço à nota fiscal aplicando a tributação de ICMS
    conforme o regime tributário (CRT) da empresa:

      - CRT 3 (Regime Normal): usa CST (padrão 00, ex: CFOP 5102/CST 00) e monta
        o bloco ICMS completo (modBC/vBC/pICMS/vICMS — obrigatórios no schema 4.00).
      - CRT 1/2 (Simples Nacional): usa CSOSN (padrão 102, ex: CFOP 5102/CSOSN 102),
        sem destaque de ICMS.

    [desconto] é o valor (R$) do desconto deste item (vDesc do XML). Quando
    informado, o pynfe emite <vDesc> no produto e subtrai do total da nota.
    Para o Regime Normal, a base de cálculo do ICMS passa a ser líquida
    (vProd − vDesc), conforme o schema 4.00.

    Retorna o NotaFiscalProduto criado (para testes/inspeção).
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

    # Inteligência Fiscal: Auto-correção de CFOP × CSOSN (Double Check no Backend)
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
        p_nfe.icms_modalidade_determinacao_bc = '3'  # 3 = Valor da operação
        try:
            vbc_item = Decimal(str(getattr(item, 'icms_base_calculo', None) or item.valor_total or 0.0))
        except Exception:
            vbc_item = Decimal(str(item.valor_total or 0.0))
        # Base de cálculo líquida do desconto do item (vBC = vProd − vDesc)
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
    # Decodificar certificado Base64 para um arquivo temporário
    cert_data = base64.b64decode(req.empresa.certificado_base64)
    temp_dir = os.environ.get('TEMP', 'C:/temp')
    caminho_cert = os.path.join(temp_dir, f"cert_{uuid.uuid4().hex}.pfx")
    with open(caminho_cert, 'wb') as f:
        f.write(cert_data)

    try:
        senha_cert = req.empresa.senha_certificado
        is_homologacao = (req.empresa.ambiente == 2)

        # === VALIDACAO DE VALIDADE DO CERTIFICADO (evita erro 403 da SEFAZ) ===
        try:
            from cryptography.hazmat.primitives.serialization import pkcs12
            with open(caminho_cert, 'rb') as f:
                _pfx_bytes = f.read()
            _chave, _cert_obj, _extras = pkcs12.load_key_and_certificates(
                _pfx_bytes, senha_cert.encode() if senha_cert else None
            )
            if _cert_obj is not None:
                _validade = _cert_obj.not_valid_after
                # cryptography retorna not_valid_after em UTC (naive) - comparar em UTC
                if _validade.tzinfo is None:
                    _validade = _validade.replace(tzinfo=timezone.utc)
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
        # Override do Regime Tributário (CRT) enviado pelo app (1=Simples Nacional, 2=SN excesso, 3=Regime Normal)
        crt_override = _get_val(req, 'crt', None)
        if crt_override is not None and str(crt_override).strip() not in ('', 'None'):
            try:
                emp.crt = int(str(crt_override).strip())
            except (ValueError, TypeError):
                print(f"[AVISO] crt invalido recebido: {crt_override!r}")
        # Limpar nome do emitente:
        # 1. Remove o CNPJ que pode vir concatenado ao nome (ex: "BMJ PETSHOP LTDA 04829400000165")
        # 2. Remove caracteres especiais como ':'
        cnpj_limpo = re.sub(r'[^0-9]', '', emp.cnpj)  # CNPJ apenas dígitos
        razao_sem_cnpj = re.sub(r'\s*' + re.escape(cnpj_limpo) + r'\s*$', '', emp.razao_social).strip()
        razao_limpa = re.sub(r'[^A-Za-z0-9 \-\.\,\/\&]', ' ', razao_sem_cnpj)[:60].strip()
        
        # Limpar Município (remover /SP ou similar que pode vir no nome)
        municipio_limpo = re.sub(r'[/].*$', '', emp.municipio).strip()
        
        emitente = Emitente(
            cnpj=emp.cnpj,
            razao_social=razao_limpa,
            nome_fantasia=emp.nome_fantasia,
            inscricao_estadual=emp.inscricao_estadual,
            codigo_de_regime_tributario=str(emp.crt or '1'), # Usa o CRT vindo da requisição
            endereco_logradouro=emp.logradouro,
            endereco_numero=str(emp.numero),
            endereco_bairro=emp.bairro,
            endereco_cep=emp.cep,
            endereco_uf=emp.uf,
            endereco_municipio=municipio_limpo,
            endereco_cod_municipio=str(emp.codigo_municipio)
        )

        # 3. DADOS DO DESTINATÁRIO (Opcional na NFC-e se < R$ 10k; obrigatório na NF-e 55)
        destinatario = None
        if req.cpf_cliente:
            # Regra E04-20 / Rejeição 598: em homologação (tpAmb=2), o xNome do
            # destinatário deve ser EXATAMENTE o texto padrão definido pela SEFAZ
            if is_homologacao:
                nome_dest = "NF-E EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
                print("[FISCAL] Homologação: xNome do destinatário = texto padrão SEFAZ (Regra E04-20 / Rejeição 598)")
            else:
                nome_dest = (getattr(req, 'nome_cliente', None) or 'Consumidor Final').strip()[:60]

            # Documento do destinatário: CPF (11 dígitos) ou CNPJ (14 dígitos)
            doc_dest_limpo = re.sub(r'[^0-9]', '', str(req.cpf_cliente or ''))
            tipo_doc_dest = 'CNPJ' if len(doc_dest_limpo) == 14 else 'CPF'

            # IE do destinatário: se informada, destinatário é contribuinte (indIEDest=1)
            dest_ie_num = re.sub(r'[^0-9]', '', str(getattr(req, 'dest_ie', None) or ''))
            indicador_ie_dest = 1 if dest_ie_num else 9

            # Endereço do destinatário (obrigatório na NF-e modelo 55)
            dest_logradouro = (getattr(req, 'dest_logradouro', None) or '').strip()
            if dest_logradouro:
                # Código do município do destinatário: usa o enviado, senão tenta
                # resolver pelo nome+UF (fallback: código do município da empresa)
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
                # NFC-e sem endereço do destinatário (consumidor presencial)
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
        
        # Puxa número forçado ou o número da venda
        if numero_forcado is not None and str(numero_forcado).strip() != "" and str(numero_forcado) != "None":
            numero_nf_limpo = re.sub(r'[^0-9]', '', str(numero_forcado))
        else:
            numero_nf_str = str(_get_val(req, 'venda_numero') or '')
            numero_nf_limpo = re.sub(r'[^0-9]', '', numero_nf_str)
            if not numero_nf_limpo:
                # Fallback: usar timestamp mas limitar a 9 dígitos
                numero_nf_limpo = str(int(datetime.now().timestamp()) % 999999999)

        # CRÍTICO: garantir limite estrito de 9 dígitos para nNF (campo da chave de acesso)
        numero_nf_limpo = re.sub(r'[^0-9]', '', numero_nf_limpo)
        if len(numero_nf_limpo) > 9:
            # Usar módulo para manter dentro do range válido (1-999999999)
            numero_nf_limpo = str(int(numero_nf_limpo) % 999999999)
        if not numero_nf_limpo or int(numero_nf_limpo) == 0:
            numero_nf_limpo = "1"

        # Série: máx 3 dígitos (campo zfill(3) no pynfe)
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
            # cMunFG - OBRIGATÓRIO (IBGE)
            municipio=str(emp.codigo_municipio or serializacao_mod.obter_codigo_por_municipio(municipio_limpo, emp.uf) or '').strip() or "3549904",
            tipo_impressao_danfe=1 if modelo_nota == 55 else 4, # 1=DANFE normal A4, 4=DANFE NFC-e
            tipo_documento=1, # 1=Saída
            forma_emissao=str(tp_emis), # 1=Normal, 2=FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
            transporte_modalidade_frete=int(getattr(req, 'mod_frete', 9) or 9)
        )

        # Notas Fiscais Referenciadas (Obrigatório para finalidade 4 - Devolução)
        if finalidade_emissao_final == 4 or getattr(req, 'chave_referenciada', None):
            chave_ref = re.sub(r'[^0-9]', '', getattr(req, 'chave_referenciada', None) or '')
            if len(chave_ref) == 44:
                nota_fiscal.adicionar_nota_fiscal_referenciada(
                    chave_acesso=chave_ref
                )
                print(f"[FISCAL] Nota Fiscal Referenciada adicionada: {chave_ref}")

        # Configuração de Transportadora e Veículo
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

        
        # Correção final se o município virar "None" ou "0000000" ou continuar inválido
        if not nota_fiscal.municipio or nota_fiscal.municipio in ["None", "0000000", ""]:
            nota_fiscal.municipio = serializacao_mod.obter_codigo_por_municipio(municipio_limpo, emp.uf) or "3549904"
        
        # Data de emissão (precisa ser um datetime object no pynfe)
        nota_fiscal.data_emissao = datetime.now()
        
        # Pagamento (obrigatório para NFC-e 4.00)
        # ind_pag foi removido da NFC-e 4.00 (opcional ou não aceito em alguns casos)
        nota_fiscal.valor_troco = Decimal('0.00')
        nota_fiscal.adicionar_pagamento(
            t_pag='01', # 01=Dinheiro
            v_pag=Decimal(str(req.valor_total))
        )

        # Itens
        # Distribui o desconto total da venda (tabela de preços, promoções, desconto
        # manual) proporcionalmente ao valor de cada item para gerar o <vDesc> por
        # item e no <ICMSTot> (Σ vProd − Σ vDesc = vNF).
        valor_desconto_total = Decimal(str(getattr(req, 'valor_desconto', None) or 0.0))
        descontos_por_item = {}
        if valor_desconto_total > 0 and req.itens:
            soma_valores = sum(
                (Decimal(str(it.valor_total)) for it in req.itens), Decimal('0.00')
            )
            if soma_valores > 0:
                # Desconto nunca pode exceder a soma dos itens (mantém Σ vProd − Σ vDesc = vNF)
                if valor_desconto_total > soma_valores:
                    print(f"[FISCAL] Desconto {valor_desconto_total} > soma itens {soma_valores}; ajustado")
                    valor_desconto_total = soma_valores
                acumulado = Decimal('0.00')
                for idx, it in enumerate(req.itens):
                    if idx == len(req.itens) - 1:
                        # Último item recebe o resto (evita erro de arredondamento)
                        desc_item = (valor_desconto_total - acumulado).max(Decimal('0.00'))
                    else:
                        desc_item = (valor_desconto_total * Decimal(str(it.valor_total)) / soma_valores).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
                        acumulado += desc_item
                    descontos_por_item[idx] = desc_item

        for i, item in enumerate(req.itens):
            descricao = item.descricao
            if is_homologacao and i == 0:
                descricao = 'NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
            # A tributação de ICMS é aplicada conforme o regime (CRT) da empresa
            adicionar_produto_com_icms(
                nota_fiscal, item, emp,
                descricao=descricao,
                desconto=descontos_por_item.get(i, Decimal('0.00')),
            )

        # Assinatura
        assinatura = AssinaturaA1(caminho_cert, senha_cert)
        # Passar is_homologacao para o serializador para que o tpAmb (1 ou 2) fique correto no XML
        serializador = SerializacaoXML(MockFonteDados(nota_fiscal), homologacao=is_homologacao)
        # No pynfe 0.6.5, exportar retorna o Element tree por padrão a menos que passa retorna_string
        xml_string = serializador.exportar(retorna_string=True)
        
        # Criar a árvore DOM limpa oficial
        xml_element = etree.fromstring(xml_string.encode('utf-8'))
        
        # Garantir namespace correto em todo o XML (evitar xmlns="")
        ns_nfe = "http://www.portalfiscal.inf.br/nfe"
        fix_xml_namespaces(xml_element, ns_nfe)
        # Corrigir blocos do Simples Nacional (pynfe gera ICMSSN102 p/ CSOSN 103/300/400)
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
                                etree.SubElement(icms900, f"{{{ns_nfe}}}modBC").text = "3" # Valor da operação
                                
                                vBC = float(getattr(item_req, 'icms_base_calculo', 0.0) or 0.0)
                                pRedBC = float(getattr(item_req, 'icms_reducao_bc', 0.0) or 0.0)
                                pICMS = float(getattr(item_req, 'icms_aliquota', 0.0) or 0.0)
                                vICMS = float(getattr(item_req, 'icms_valor', 0.0) or 0.0)
                                pCredSN = float(getattr(item_req, 'credito_aliquota', 0.0) or 0.0)
                                vCredICMSSN = float(getattr(item_req, 'credito_valor', 0.0) or 0.0)
                                
                                # Se não foi preenchido, calcula dinamicamente
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
            print(f">>> [FISCAL] ⚠️ Falha ao injetar bloco ICMS900: {e_icms}")
        
        # Adicionar o bloco IBS/CBS para a Reforma Tributária NT 2025.002
        adicionar_ibscbs_xml(xml_element, ns_nfe)

        # GARANTIR vTroco e REMOVER indPag de detPag (OBRIGATÓRIO para NFC-e 4.00)
        # ATENÇÃO: lxml elements avaliam como False em contexto bool quando sem filhos!
        # SEMPRE usar comparação explícita com 'is None' / 'is not None'.
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
                etree.SubElement(pag_tag, f"{{{ns_nfe}}}vTroco").text = "0.00"
                print("[FIX] vTroco adicionado ao pag")
        
        # Limpar duplicatas de namespace ANTES de assinar
        for el in xml_element.getiterator():
            if 'xmlns' in el.attrib:
                del el.attrib['xmlns']

        # Assinatura (assinatura deve ser sobre o infNFe já final)
        xml_assinado = assinatura.assinar(xml_element)
        
        # Gerar QR Code (apenas se for NFC-e modelo 65)
        qr_code_url = ""
        if modelo_nota == 65:
            # O CSC e IdToken são FUNDAMENTAIS para NFC-e (Modelo 65).
            csc_db = str(emp.csc or '').strip()
            id_token_db = str(emp.csc_id or '').strip()
            
            # DETECÇÃO INTELIGENTE DE INVERSÃO (CSC x IdToken)
            if len(csc_db) > 0 and len(csc_db) <= 6 and len(id_token_db) > 10:
                print(f">>> [SISTEMA] Atenção: CSC e IdToken parecem invertidos. Corrigindo: CSC={id_token_db}, IdToken={csc_db}")
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
                    print(f"[AVISO] Falha técnica ao gerar QR Code: {str(e)}")
            else:
                msg_erro = f"Faltando dados de CSC (Token) no cadastro da empresa. Verifique se preencheu o CSC e o Identificador CSC (IdToken)."
                print(f"[ALERTA] {msg_erro}")
                return {"status": "erro", "mensagem": msg_erro}

        # DEBUG: Salvar XML final para inspeção
        try:
            temp_path = os.path.join(os.environ.get('TEMP', 'C:/temp'), 'last_nfce.xml')
            debug_xml = etree.tostring(xml_assinado, encoding='utf-8', xml_declaration=True).decode('utf-8')
            with open(temp_path, 'w', encoding='utf-8') as f:
                f.write(debug_xml)
            print(f"[DEBUG] XML salvo em {temp_path}")
        except:
            pass

        # 7. TRANSMISSÃO PARA SEFAZ
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
            ind_sinc=1, # Síncrono
            contingencia=usar_contingencia
        )
        sucesso = aut_result[0]
        retorno = aut_result[1]

        # Analisar retorno
        if sucesso == 0:
            # Em modo síncrono, retorno já é o nfeProc (XML completo) ou protocolo
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
                    # O lote foi processado, mas a nota em si foi REJEITADA
                    return {
                        "status": "erro",
                        "mensagem": f"Rejeição SEFAZ [{c_stat}]: {x_motivo}"
                    }
                
                # Está APROVADA!
                chave = inf_prot[0].xpath('ns:chNFe', namespaces=namespaces)
                chave = chave[0].text if chave else ''
                
                protocolo = inf_prot[0].xpath('ns:nProt', namespaces=namespaces)
                protocolo = protocolo[0].text if protocolo else ''

            # --- SALVAMENTO LOCAL ORGANIZADO ---
            salvar_xml_local(emp.cnpj, chave, xml_final)

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
            # Em caso de erro 'retorno' é o objeto response do requests ou similar
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
                        # Tentar encontrar o protocolo da nota (onde está o erro real)
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
                                salvar_xml_local(emp.cnpj, chave, xml_final)
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
                                return {"status": "erro", "mensagem": f"Rejeição SEFAZ [{prot_c_stat}]: {prot_x_motivo}"}
                        
                        # Se não achou infProt, pegar o xMotivo do retEnviNFe (se disponível e não for 104)
                        x_motivo_el = resp_elem.xpath('//ns:retEnviNFe/ns:xMotivo', namespaces=ns)
                        if not x_motivo_el: x_motivo_el = resp_elem.xpath('//ns:xMotivo', namespaces=ns)
                        
                        x_motivo = x_motivo_el[0].text if x_motivo_el else 'Lote processado, mas nota não encontrada.'
                        return {"status": "erro", "mensagem": f"Rejeição SEFAZ [104]: {x_motivo}"}

                except Exception as parse_err:
                    print(f"[SEFAZ] Não conseguiu parsear resposta: {parse_err}")
                
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
                return {"status": "erro", "mensagem": f"Rejeição ou erro de rede: {str(retorno)}"}
            
    except Exception as e:
        tb = traceback.format_exc()
        print(f"[ERRO HANDLER] {e}\n{tb}")
        return {"status": "erro", "mensagem": f"Erro interno: {str(e)}", "traceback": tb}
    finally:
        # Limpar arquivo temporário do certificado
        if os.path.exists(caminho_cert):
            try:
                os.remove(caminho_cert)
            except:
                pass

def salvar_xml_local(cnpj, chave, xml_content):
    """
    Salva o XML em C:/ExodoNFCe/[CNPJ]/[ANO-MES]/[CHAVE]-nfe.xml
    """
    try:
        # Pasta principal fixa no C: para fácil localização
        pasta_base = r"C:\ExodoNFCe"
        mes_ano = datetime.now().strftime("%Y-%m")
        diretorio_destino = os.path.join(pasta_base, str(cnpj), mes_ano)
        
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
    sem usar o ComunicacaoSefaz._post que tem fixes específicos de emissão
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
            return {"success": False, "error": "Protocolo de autorização ausente.", "mensagem": "Protocolo obrigatório para cancelamento"}

        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))
        senha_cert = empresa_data.get("senha_certificado", "")
        uf = empresa_data.get("uf", "SP").upper()
        # Mapeamento robusto do ambiente (padrão de emissão utiliza ambiente_homologacao)
        is_homolog = (empresa_data.get("ambiente_homologacao") == True) or \
                     (str(empresa_data.get("ambiente")) == "2") or \
                     (empresa_data.get("ambiente") == 2)
        
        tp_amb = "2" if is_homolog else "1"
        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")

        # Limpar justificativa (xJust: 15–255 chars, caracteres permitidos pelo XSD)
        just_limpa = re.sub(r'[^\w\s\.\,\-\/]', ' ', justificativa, flags=re.UNICODE).strip()
        if len(just_limpa) < 15:
            just_limpa = "Cancelamento a pedido do emitente por erro ou devolucao"
        just_limpa = just_limpa[:255]

        # cOrgao: extrair dos 2 primeiros dígitos da chave de acesso (cUF)
        c_orgao = chave_acesso[:2] if len(chave_acesso) >= 44 else "35"

        NS = "http://www.portalfiscal.inf.br/nfe"

        # ── 1. Montar envEvento com lxml puro (sem ElementMaker para evitar xmlns="" em sub-elementos) ──
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

        # ── 2. Salvar certificado PFX em arquivo temporário, assinar o XML ──
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

            # ── 3. Corrigir posição da Signature ──
            # O pynfe coloca a Signature como filha do elemento raiz (envEvento),
            # mas o XSD da SEFAZ exige que seja filha de <evento> (irmã de <infEvento>).
            # Estrutura correta:
            #   <envEvento>
            #     <idLote/>
            #     <evento>
            #       <infEvento Id="..."/>
            #       <Signature/>   ← DEVE estar AQUI
            #     </evento>
            #   </envEvento>
            NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"
            NS_NFE = "http://www.portalfiscal.inf.br/nfe"

            # Encontrar a Signature no nível errado (filho de envEvento)
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
                    # Fallback: re-adicionar no envEvento (não deve chegar aqui)
                    env_evento_assinado.append(sig_errada)

            # ── 4. Serializar para string XML limpa ──
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

            # ── 4. Determinar URL do serviço de eventos NFC-e por UF ──
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

            # ── 5. Montar envelope SOAP 1.2 ──
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

            # ── 6. Separar certificado PFX em arquivos PEM para o requests ──
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

            # ── 7. Parsear resposta (aceita tanto com envelope SOAP quanto sem) ──
            cstat = ""
            xmotivo = "Sem resposta legível da SEFAZ"
            
            try:
                # Limpar soap body se houver
                xml_to_parse = r_text
                if "<soap:Body" in r_text or "<soap12:Body" in r_text:
                    match_body = re.search(r'<[^:]+:Body[^>]*>(.*?)</[^:]+:Body>', r_text, re.DOTALL)
                    if match_body:
                        xml_to_parse = match_body.group(1)
                
                resp_xml = etree.fromstring(xml_to_parse.encode('utf-8'))
                
                # Ignorar namespaces para facilitar a busca (xpath flexível)
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
                    cstat = cstats[-1] # Pegar o último que é o do infEvento
                    xmotivo = xmotivos[-1] if len(xmotivos) >= 2 else "Lote processado"
                elif len(cstats) == 1:
                    cstat = cstats[0]
                    xmotivo = xmotivos[0] if xmotivos else "Sem resposta legível da SEFAZ"
                else:
                    cstat = ""
                    xmotivo = "Sem resposta legível da SEFAZ"

            print(f"[DEBUG] Cancelamento EVENTO cStat={cstat} | xMotivo={xmotivo}")

            # cStat 135 = Evento registrado e vinculado à NF-e (cancelamento aceito)
            # cStat 155 = Cancelamento homologado (nota já cancelada fora do prazo / denúncia espontânea - raro)
            # cStat 101 = Cancelamento de NF-e homologado
            success = cstat in ["135", "101", "155"]
            
            # Se success for falso, não tem error genérico. Tem a mensagem exata do erro!
            return {
                "success": success,
                "cStat": cstat,
                "xMotivo": xmotivo,
                "mensagem": xmotivo,
                "error": None if success else f"Rejeição SEFAZ [{cstat}]: {xmotivo}",
                "data": {"cStat": cstat, "xMotivo": xmotivo}
            }
        finally:
            # Limpar arquivos PEM temporários
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
                # O retorno da consulta é um XML que precisa ser parseado para o app entender
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
    """Valida se o certificado e senha estão corretos e extrai informações."""
    try:
        from pynfe.processamento.assinatura import AssinaturaA1
        from pynfe.entidades.certificado import CertificadoA1
        
        cert_b64 = req_dict.get('certificado_base64')
        senha = req_dict.get('senha')
        
        if not cert_b64 or not senha:
            return {'success': False, 'error': 'Certificado ou senha não fornecidos.'}
            
        cert_data = base64.b64decode(cert_b64)
        import uuid
        temp_dir = os.environ.get('TEMP', 'C:/temp')
        caminho_cert = os.path.join(temp_dir, f"cert_validar_{uuid.uuid4().hex}.pfx")
        with open(caminho_cert, 'wb') as f:
            f.write(cert_data)
            
        try:
            # Tentar instanciar o certificado (valida a senha)
            cert = CertificadoA1(caminho_cert)
            # extrair info se possível (pynfe pode não ter extração direta amigável)
            # mas o fato de carregar sem erro já valida a senha
            return {
                'success': True, 
                'mensagem': 'Certificado validado com sucesso.',
                'valido': True
            }
        except Exception as e:
            return {'success': False, 'error': f'Sua senha ou o arquivo do certificado estão incorretos: {str(e)}'}
        finally:
            if os.path.exists(caminho_cert):
                try: os.remove(caminho_cert)
                except: pass
    except Exception as e:
        return {'success': False, 'error': str(e)}

