from decimal import Decimal
import base64
import os
import re
import tempfile
import traceback
from datetime import datetime
from lxml import etree
from pynfe.processamento.comunicacao import ComunicacaoSefaz
from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal, NotaFiscalProduto
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

def fix_xml_namespaces(element, ns):
    """Garante que todos os elementos usem o namespace correto e remove tags vazias irrelevantes."""
    if not element.tag.startswith('{'):
        element.tag = f"{{{ns}}}{element.tag}"
    
    # Remover tags vazias opcionais que podem quebrar o schema
    for child in list(element):
        if child.text is None and len(child) == 0:
            # Lista de tags que NÃO podem ser removidas mesmo vazias (se houver alguma)
            # No geral, se está vazia e sem filhos, é lixo ou erro no pynfe
            element.remove(child)
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
    import hashlib
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

    # Identificador do CSC (IdToken) deve ter de 1 a 6 dígitos decimais.
    # Se for maior que 6, pegamos apenas os últimos 6 para não quebrar o Schema 225.
    cIdToken = str(token)
    if len(cIdToken) > 6:
        cIdToken = cIdToken[-6:]
    elif len(cIdToken) < 1:
        cIdToken = "000001"
    
    if online:
        # Formato NT 2015.002 versão online:
        # url = chNFe|nVersao|tpAmb|cIdToken
        url = "{}|{}|{}|{}".format(chave, VERSAO_QRCODE, tpamb, cIdToken)
        # Hash = SHA1(url + csc), em hex maiúsculo
        string_hash = url + csc
        print(f"[DEBUG] String para Hash QR Code: {string_hash}")
        url_hash = hashlib.sha1(string_hash.encode()).digest()
        import base64 as _b64
        url_hash_hex = _b64.b16encode(url_hash).decode()
        url_params = "p={}|{}".format(url, url_hash_hex)
    else:
        # Versão offline não é usada para NFC-e no Brasil normalmente
        return xml

    # Montar URL completa de acordo com a UF
    lista_uf_padrao = ["PR", "CE", "RS", "RJ", "RO", "DF"]
    if uf in lista_uf_padrao:
        qrcode_url = NFCE[uf]["QR"] + url_params
        url_chave  = NFCE[uf]["URL"]
    elif uf == "SP":
        if tpamb == "1":  # Produção
            qrcode_url = NFCE[uf]["HTTPS"] + "www." + NFCE[uf]["QR"] + url_params
            url_chave  = NFCE[uf]["HTTPS"] + "www." + NFCE[uf]["URL"]
        else:  # Homologação
            qrcode_url = NFCE[uf]["HTTPS"] + "www.homologacao." + NFCE[uf]["QR"] + url_params
            url_chave  = NFCE[uf]["HTTPS"] + "www.homologacao." + NFCE[uf]["URL"]
    elif uf == "BA":
        if tpamb == "1":
            qrcode_url = NFCE[uf]["HTTPS"] + NFCE[uf]["QR"] + url_params
        else:
            qrcode_url = NFCE[uf]["HOMOLOGACAO"] + NFCE[uf]["QR"] + url_params
        url_chave = NFCE[uf]["URL"]
    elif uf == "MG":
        qrcode_url = NFCE[uf]["QR"] + url_params
        if tpamb == "1":
            url_chave = NFCE[uf]["HTTPS"] + NFCE[uf]["URL"]
        else:
            url_chave = NFCE[uf]["HOMOLOGACAO"] + NFCE[uf]["URL"]
    else:  # Demais estados (AC, AM, RR, PA, SE, etc.)
        if tpamb == "1":
            qrcode_url = NFCE[uf]["HTTPS"] + NFCE[uf]["QR"] + url_params
            url_chave  = NFCE[uf]["HTTPS"] + NFCE[uf]["URL"]
        else:
            qrcode_url = NFCE[uf]["HOMOLOGACAO"] + NFCE[uf]["QR"] + url_params
            url_chave  = NFCE[uf]["HOMOLOGACAO"] + NFCE[uf]["URL"]

    # Remover infNFeSupl existente para não duplicar
    for tag in [f"{{{ns_nfe}}}infNFeSupl", "infNFeSupl"]:
        old = nfe.find(f".//{tag}")
        if old is not None:
            nfe.remove(old)

    # ORDEM CRÍTICA (NFC-e 4.00): 1. infNFe, 2. infNFeSupl, 3. Signature
    # Vamos remontar os filhos da NFe para garantir que nada saia da ordem
    signature_tag = None
    inf_nfe_tag = None
    
    for child in list(nfe):
        tag_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
        if tag_name == "Signature":
            signature_tag = child
            nfe.remove(child)
        elif tag_name == "infNFe":
            inf_nfe_tag = child
        elif tag_name == "infNFeSupl":
            nfe.remove(child)

    # Novo elemento infNFeSupl
    info = etree.Element("infNFeSupl") 
    # O MOC 4.00 dita que o QRCode é literal (CDATA mode) na viagem do envelope HTTP
    etree.SubElement(info, "qrCode").text = etree.CDATA(qrcode_url.strip())
    etree.SubElement(info, "urlChave").text = url_chave
    
    # Adicionar na ordem correta exigida pelo XSD da NF-e 4.00:
    # 1. infNFe (já está lá no índice 0)
    # 2. infNFeSupl (insere no índice 1)
    nfe.insert(1, info)
    
    # 3. Signature (por último)
    if signature_tag is not None:
        nfe.append(signature_tag)

    if return_qr:
        return nfe, qrcode_url.strip()
    return nfe

# Aplicar o monkeypatch para o QR Code
SerializacaoQrcode.gerar_qrcode = _new_gerar_qrcode

# Aplicar os outros monkeypatches
SerializacaoXML._serializar_emitente = _new_serializar_emitente
SerializacaoXML._serializar_cliente = _new_serializar_cliente


# ─────────────────────────────────────────────────────────────────────────────
# MONKEYPATCH: ComunicacaoSefaz._post
# Problema: o lxml serializa o infNFeSupl sem namespace explícito (ou com
# xmlns="" vazio) quando inserido dentro de NFe que já declara o mesmo namespace.
# Isso viola o XSD do enviNFe e causa erro 225 no SEFAZ.
# Fix: pós-processar a string XML para garantir que infNFeSupl tenha o namespace.
# ─────────────────────────────────────────────────────────────────────────────
import requests as _requests
from pynfe.entidades.certificado import CertificadoA1 as _CertA1

_NS_NFE = "http://www.portalfiscal.inf.br/nfe"

def _fixed_post(self, url, xml, timeout=None):
    """_post com fix completo para schema NFC-e 4.00."""
    from pynfe.utils import etree as _etree
    certificado_a1 = _CertA1(self.certificado)
    chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
    chave_cert = (cert, chave)
    try:
        xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'

        # Serialize to string
        xml_str = _etree.tostring(xml, encoding="unicode").replace("\n", "")

        # --- FIX ROBUSTO PARA SEFAZ SP (Schema 225 / HTTP 400) ---
        # 1. Limpar namespaces repetidos em tags internas
        tags_internas = ['infNFe', 'ide', 'emit', 'dest', 'det', 'prod', 'imposto', 'total', 'transp', 'pag', 'infAdic', 'infNFeSupl']
        for tag in tags_internas:
            # Remover xmlns se ele estiver sozinho na tag ou seguido de espaço
            xml_str = re.sub(rf'<{tag}\s+xmlns=["\'][^"\']*["\']', f'<{tag}', xml_str)
            xml_str = xml_str.replace(f'<{tag} xmlns="">', f'<{tag}>')

        # 2. Garantir namespace oficial em enviNFe E NFe preservando atributos
        if '<enviNFe' in xml_str:
            # Remover xmlns e versao existentes para evitar duplicidade
            xml_str = re.sub(r'<enviNFe\s+xmlns=["\'][^"\']*["\']', '<enviNFe', xml_str)
            xml_str = re.sub(r'<enviNFe\s+versao=["\'][^"\']*["\']', '<enviNFe', xml_str)
            # Adicionar xmlns e versao padrão
            xml_str = xml_str.replace('<enviNFe', f'<enviNFe xmlns="{_NS_NFE}" versao="4.00"')
        
        if '<NFe' in xml_str:
            # Remover xmlns preservando outros atributos (como Id)
            xml_str = re.sub(r'<NFe\s+xmlns=["\'][^"\']*["\']', '<NFe', xml_str)
            # Adicionar xmlns sem fechar a tag precocemente
            xml_str = xml_str.replace('<NFe', f'<NFe xmlns="{_NS_NFE}"')
        
        # 3. Garantir versao em infNFe preservando Id
        if '<infNFe' in xml_str:
            # Remover xmlns e versao existentes
            xml_str = re.sub(r'<infNFe\s+xmlns=["\'][^"\']*["\']', '<infNFe', xml_str)
            xml_str = re.sub(r'<infNFe\s+versao=["\'][^"\']*["\']', '<infNFe', xml_str)
            # Adicionar versao 4.00 (lookahead para não alterar a tag <infNFeSupl>)
            xml_str = re.sub(r'<infNFe(?=\s|>)', '<infNFe versao="4.00"', xml_str)
        
        # Correção final de lixo e namespaces vazios
        xml_str = xml_str.replace(' xmlns=""', '')
        # Garantir que não existam tags de fechamento duplicadas ou mal formadas
        xml_str = xml_str.replace('>>', '>')
        
        # FIX DE ORDEM CRÍTICO (infNFe -> infNFeSupl -> Signature)
        # 1. Separar a tag infNFeSupl e Signature
        match_supl = re.search(r'(<infNFeSupl>.*?</infNFeSupl>)', xml_str, re.DOTALL)
        match_sig = re.search(r'(<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">.*?</Signature>)', xml_str, re.DOTALL)
        
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
            dbg_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_enviNFe.xml')
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
            resp_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_sefaz_response.xml')
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


def emitir_nfce_pynfe(req):
    # Decodificar certificado Base64 para um arquivo temporário
    cert_data = base64.b64decode(req.empresa.certificado_base64)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp_cert:
        tmp_cert.write(cert_data)
        caminho_cert = tmp_cert.name

    try:
        senha_cert = req.empresa.senha_certificado
        is_homologacao = (req.empresa.ambiente == 2)

        # Emitente
        emp = req.empresa
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
            codigo_de_regime_tributario='1', # 1=Simples Nacional
            endereco_logradouro=emp.logradouro,
            endereco_numero=str(emp.numero),
            endereco_bairro=emp.bairro,
            endereco_cep=emp.cep,
            endereco_uf=emp.uf,
            endereco_municipio=municipio_limpo,
            endereco_cod_municipio=str(emp.codigo_municipio)
        )

        # 3. DADOS DO DESTINATÁRIO (Opcional na NFC-e se < R$ 10k)
        destinatario = None
        if req.cpf_cliente:
            destinatario = Cliente(
                numero_documento=req.cpf_cliente,
                razao_social='Consumidor Final', # Ou nome real se tiver
                tipo_documento='CPF',
                indicador_ie=9, # Não contribuinte
                # Endereço é opcional na NFC-e presencial
            )

        # Nota Fiscal
        numero_nf_str = str(req.venda_numero or int(datetime.now().timestamp()))
        # Limpar qualquer caractere não numérico (como 'None')
        numero_nf_limpo = re.sub(r'[^0-9]', '', numero_nf_str)
        if not numero_nf_limpo: numero_nf_limpo = "1"

        # 5. MONTAGEM DA NOTA FISCAL
        nota_fiscal = NotaFiscal(
            emitente=emitente,
            cliente=destinatario,
            produtos=[], # Initialize with an empty list, products will be added later
            natureza_operacao='VENDA AO CONSUMIDOR',
            modelo=65, # 65=NFC-e (como int)
            serie='1',
            numero_nf=numero_nf_limpo,
            indicador_destino=1, # 1=Interna (como int)
            finalidade_emissao=1, # 1=Normal (como int)
            cliente_final=1, # 1=Sim (como int)
            indicador_presencial=1, # 1=Presencial (como int)
            valor_total_nota=Decimal(str(req.valor_total)),
            uf=emp.uf,
            municipio=str(emp.codigo_municipio), # cMunFG - OBRIGATÓRIO (IBGE)
            tipo_impressao_danfe=4, # 4=DANFE NFC-e - OBRIGATÓRIO
            tipo_documento=1, # 1=Saída - OBRIGATÓRIO para NFC-e
            forma_emissao='1', # 1=Normal (string conforme esperado)
            transporte_modalidade_frete=9 # 9=Sem Ocorrência de Transporte (OBRIGATÓRIO para NFC-e)
        )
        
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
        for i, item in enumerate(req.itens):
            descricao = item.descricao
            if is_homologacao and i == 0:
                descricao = 'NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL'
            
            # No pynfe 0.6.5 use adicionar_produto_servico diretamente da NotaFiscal
            nota_fiscal.adicionar_produto_servico(
                codigo=item.codigo,
                descricao=descricao,
                ncm=item.ncm,
                cfop=item.cfop,
                unidade_comercial='UN',
                quantidade_comercial=Decimal(str(item.quantidade)).quantize(Decimal('0.0001')),
                valor_unitario_comercial=Decimal(str(item.valor_unitario)).quantize(Decimal('0.0000001')),
                valor_total_bruto=Decimal(str(item.valor_total)).quantize(Decimal('0.01')),
                unidade_tributavel='UN',
                quantidade_tributavel=Decimal(str(item.quantidade)).quantize(Decimal('0.0001')),
                valor_unitario_tributavel=Decimal(str(item.valor_unitario)).quantize(Decimal('0.0000001')),
                ean='SEM GTIN',
                ean_tributavel='SEM GTIN',
                icms_origem=0,
                icms_modalidade='102'
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

        # GARANTIR vTroco ANTES de assinar (Mudar o XML após assinar quebra a assinatura - Erro 297)
        pag_tag = xml_element.find(f".//{{{ns_nfe}}}pag") or xml_element.find(".//pag")
        if pag_tag is not None:
            v_troco = pag_tag.find(f".//{{{ns_nfe}}}vTroco") or pag_tag.find(".//vTroco")
            if v_troco is None:
                # vTroco deve vir após detPag
                etree.SubElement(pag_tag, f"{{{ns_nfe}}}vTroco").text = "0.00"
        
        # Limpar duplicatas de namespace ANTES de assinar
        for el in xml_element.getiterator():
            if 'xmlns' in el.attrib:
                del el.attrib['xmlns']

        # Assinatura (assinatura deve ser sobre o infNFe já final)
        xml_assinado = assinatura.assinar(xml_element)
        
        # Gerar QR Code
        # O CSC e IdToken são FUNDAMENTAIS. Se faltarem, SEFAZ rejeita com erro 394 (Sem QR Code).
        csc_db = str(emp.csc or '').strip()
        id_token_db = str(emp.csc_id or '').strip()
        
        # DETECÇÃO INTELIGENTE DE INVERSÃO (CSC x IdToken)
        # CSC (Token) é uma chave longa (geralmente > 20 chars).
        # IdToken é um identificador curto (geralmente 1 a 6 dígitos).
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
            
        qr_code_url = ""
        if csc_db and id_token_db:
            try:
                # Limpar CSC (remover espaços e quebras de linha) e IdToken
                # CSC (Token): Manter como no DB, apenas remover espaços. 
                csc_limpo = csc_db.strip().replace(' ', '').replace('\n', '').replace('\r', '')
                
                # SEFAZ SP Schema requires NO leading zeros in IdToken for QR Code Version 2
                # e.g., '000001' must be '1' in the URL, otherwise XSD pattern rejects it (cStat 225).
                id_token_limpo = re.sub(r'[^0-9]', '', id_token_db)
                if not id_token_limpo: 
                    id_token_limpo = "1"
                else:
                    # Strip leading zeros, but keep at least '0' if it's all zeros
                    id_token_limpo = str(int(id_token_limpo))
                
                qrcode_gen = SerializacaoQrcode()
                # O nosso monkeypatch já cuida de inserir o infNFeSupl corretamente no XML assinado
                # Se CSC for inválido, o pynfe/SEFAZ vai reclamar do HASH, mas pelo menos a tag QR Code vai existir
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
            temp_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_nfce.xml')
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
        # O pynfe espera o Element Tree assinado
        aut_result = con.autorizacao(
            modelo='nfce',
            nota_fiscal=xml_assinado,
            id_lote=1,
            ind_sinc=1 # Síncrono
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
    Salva o XML em uma pasta organizada por CNPJ e Mês.
    Caminho: ./XML_EMITIDOS/[CNPJ]/[ANO-MES]/[CHAVE]-nfe.xml
    """
    try:
        # Obter diretório base (onde está o executável ou script)
        import sys
        if getattr(sys, 'frozen', False):
            base_dir = os.path.dirname(sys.executable)
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))
            
        # Criar estrutura de pastas
        pasta_base = os.path.join(base_dir, "XML_EMITIDOS")
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
            

