from decimal import Decimal
import base64
import os
import re
import tempfile
import traceback
from datetime import datetime
from lxml import etree
from pynfe.processamento.comunicacao import ComunicacaoSefaz
from pynfe.processamento.serializacao import SerializacaoXML, SerializacaoQrcode
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.notafiscal import NotaFiscalProduto
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
    # O pynfe original tem um bug: re.sub("([0])", "", token) que limpa todos os zeros do ID!
    # Esta versão corrigida mantém o token (IdToken) intacto.
    from pynfe.utils.flags import NFCE
    from pynfe.utils import so_numeros
    
    nfe = xml
    ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
    sig = {"sig": "http://www.w3.org/2000/09/xmldsig#"}
    
    chave = nfe.xpath("ns:infNFe/@Id", namespaces=ns)[0][3:]
    v_nf = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vNF/text()", namespaces=ns)[0]
    digest = nfe.xpath("sig:Signature/sig:SignedInfo/sig:Reference/sig:DigestValue/text()", namespaces=sig)[0]
    
    tpamb = nfe.xpath("ns:infNFe/ns:ide/ns:tpAmb/text()", namespaces=ns)[0]
    uf = nfe.xpath("ns:infNFe/ns:ide/ns:cUF/text()", namespaces=ns)[0]
    
    # O PYNFE original apaga os zeros aqui, o que é um ERRO. Vamos manter o token original.
    # token = re.sub("([0])", lambda m: {"0": ""}[m.group()], token) <-- Removido o bug
    
    import hashlib
    # NFC-e 4.00 exige concatenação de dados para o hash
    # chNFe + nVersao + tpAmb + [cDest] + dhEmi + vNF + vICMS + digVal + cIdToken
    # Para simplificar e garantir compatibilidade, usamos a lógica do pynfe mas sem o bug do zero
    
    # Parâmetros padrão do QR-Code 2.0
    cIdToken = token
    
    # Montar a URL do QR Code conforme NT 2015.002
    from pynfe.utils.flags import VERSAO_QRCODE
    
    if online:
        # Lógica simplificada de hash conforme pynfe mas preservando o token
        # p=chNFe|nVersao|tpAmb|cIdToken|cHashQRCode
        str_hash = f"{chave}|{VERSAO_QRCODE}|{tpamb}|{cIdToken}{csc}"
        hash_qr = hashlib.sha1(str_hash.encode()).hexdigest().upper()
        url_params = f"p={chave}|{VERSAO_QRCODE}|{tpamb}|{cIdToken}|{hash_qr}"
        
        qrcode_base = NFCE[uf]["HTTPS"] if tpamb == "1" else NFCE[uf]["HOMOLOGACAO"]
        qrcode_url = qrcode_base + NFCE[uf]["QR"] + url_params
        url_chave = NFCE[uf]["HTTPS"] if tpamb == "1" else NFCE[uf]["HOMOLOGACAO"]
        url_chave += NFCE[uf]["URL"]
    else:
        # Offline não implementado aqui por brevidade, mas o pynfe usa online por padrão
        return xml

    # Inserir infNFeSupl (Remover se já existir para não duplicar)
    ns_nfe = "http://www.portalfiscal.inf.br/nfe"
    for tag in ["infNFeSupl", f"{{{ns_nfe}}}infNFeSupl"]:
        old = nfe.find(f".//{tag}")
        if old is not None:
            nfe.remove(old)

    info = etree.Element(f"{{{ns_nfe}}}infNFeSupl")
    etree.SubElement(info, f"{{{ns_nfe}}}qrCode").text = etree.CDATA(qrcode_url.strip())
    etree.SubElement(info, f"{{{ns_nfe}}}urlChave").text = url_chave
    
    # Inserir na posição correta (após infNFe e antes de Signature)
    nfe.insert(1, info)
    
    if return_qr:
        return nfe, qrcode_url.strip()
    return nfe

# Aplicar o monkeypatch para o QR Code
SerializacaoQrcode.gerar_qrcode = _new_gerar_qrcode

# Aplicar os outros monkeypatches
SerializacaoXML._serializar_emitente = _new_serializar_emitente
SerializacaoXML._serializar_cliente = _new_serializar_cliente

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
        # Limpar nome do emitente (remover caracteres especiais suspeitos como :)
        razao_limpa = re.sub(r'[:]', ' ', emp.razao_social)[:60].strip()
        
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

        # Cliente (Destinatário)
        cliente = None
        if req.cpf_cliente:
            cliente = Cliente(
                numero_documento=req.cpf_cliente,
                razao_social='Consumidor Final',
                indicador_ie='9', # 9=Não Contribuinte
                endereco_uf=emp.uf
            )

        # Nota Fiscal
        numero_nf_str = str(req.venda_numero or int(datetime.now().timestamp()))
        # Limpar qualquer caractere não numérico (como 'None')
        numero_nf_limpo = re.sub(r'[^0-9]', '', numero_nf_str)
        if not numero_nf_limpo: numero_nf_limpo = "1"

        nota_fiscal = NotaFiscal(
            emitente=emitente,
            destinatario_remetente=cliente,
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
        
        # Garantir que o atributo 'cliente' exista para o serializador APENAS se houver cliente
        if cliente:
            nota_fiscal.cliente = cliente
        
        # Data de emissão (precisa ser um datetime object no pynfe)
        nota_fiscal.data_emissao = datetime.now()
        
        # Pagamento (obrigatório para NFC-e 4.00 - Falha no Schema se faltar)
        nota_fiscal.valor_troco = Decimal('0.00')
        nota_fiscal.adicionar_pagamento(
            t_pag='01', # 01=Dinheiro
            v_pag=Decimal(str(req.valor_total)),
            ind_pag='0' # 0=Pagamento à vista
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
        
        # Tratamento de erro comum: usuário inverte as bolas ou deixa um vazio
        # Se um estiver vazio, mas o outro tiver o ID (geralmente '1' ou '000001')
        if not id_token_db and csc_db and len(csc_db) <= 3:
            id_token_db = csc_db
            csc_db = "" # Força erro de CSC vazio abaixo
            
        if not id_token_db: 
            id_token_db = "1" # Tenta '1' como padrão se estiver vazio
            
        if csc_db and id_token_db:
            try:
                # Limpar CSC (remover espaços e quebras de linha) e IdToken
                csc_limpo = csc_db.replace(' ', '').replace('\n', '').replace('\r', '').replace('-', '')
                id_token_limpo = re.sub(r'[^0-9]', '', id_token_db).zfill(1)
                
                qrcode_gen = SerializacaoQrcode()
                # O nosso monkeypatch já cuida de inserir o infNFeSupl corretamente no XML assinado
                # Se CSC for inválido, o pynfe/SEFAZ vai reclamar do HASH, mas pelo menos a tag QR Code vai existir
                xml_assinado = qrcode_gen.gerar_qrcode(
                    token=id_token_limpo,
                    csc=csc_limpo,
                    xml=xml_assinado
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

        # Transmissão SÍNCRONA (indSinc=1) para NFC-e em SP
        con = ComunicacaoSefaz(
            uf=emp.uf, 
            certificado=caminho_cert, 
            certificado_senha=senha_cert, 
            homologacao=is_homologacao
        )
        
        # Enviar XML Assinado com indSinc=1
        # O pynfe espera o Element Tree assinado
        sucesso, retorno, _ = con.autorizacao(
            modelo='nfce',
            nota_fiscal=xml_assinado,
            id_lote=1,
            ind_sinc=1 # Síncrono
        )

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
                "xml": xml_final,
                "mensagem": "NFC-e Autorizada com Sucesso!"
            }
        else:
            # Em caso de erro 'retorno' é o objeto response do requests ou similar
            try:
                # Se for response do requests
                corpo_erro = retorno.text
                return {"status": "erro", "mensagem": f"Erro SEFAZ: {corpo_erro}"}
            except:
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
            

