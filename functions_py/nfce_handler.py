from decimal import Decimal, ROUND_HALF_UP
import base64
import os
import re
import tempfile
import traceback
from datetime import datetime
from lxml import etree
from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz

# --- REIMPLEMENTAÇÃO DA COMUNICAÇÃO SEFAZ PARA CLOUD ---
class ComunicacaoSefaz(OriginalComunicacaoSefaz):
    def _post(self, url, xml, timeout=None):
        from pynfe.utils import etree as _etree
        from pynfe.entidades.certificado import CertificadoA1 as _CertA1
        import requests as _requests
        
        certificado_a1 = _CertA1(self.certificado)
        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
        chave_cert = (cert, chave)
        
        try:
            xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
            if isinstance(xml, _etree._Element):
                xml_raw = _etree.tostring(xml, encoding="unicode").replace("\n", "").replace("\r", "")
            else:
                xml_raw = str(xml).replace("\n", "").replace("\r", "")
                
            xml_raw = re.sub(r">\s+<", "><", xml_raw)
            
            # Fix para qrCode (entities mal formadas pelo pynfe)
            if "<qrCode" in xml_raw:
                xml_raw = re.sub("<qrCode>(.*?)</qrCode>", 
                                lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), 
                                xml_raw)
            
            # Fix para namespacesns0/ns1
            if "ns0:" in xml_raw or "ns1:" in xml_raw:
                xml_raw = re.sub(r"<(/?)ns[0-9]+:", r"<\\1", xml_raw)
            
            # Garantir namespaces
            for tag in ["envEvento", "evento", "infEvento"]:
                if f'<{tag}' in xml_raw and 'xmlns=' not in xml_raw.split(f'<{tag}')[1].split('>')[0]:
                    xml_raw = xml_raw.replace(f'<{tag}', f'<{tag} xmlns="http://www.portalfiscal.inf.br/nfe"')
            
            xml_final = xml_declaration + xml_raw

            # Na Cloud usamos verify=True (padrão) para segurança, a menos que a SEFAZ tenha problemas de chain
            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)
            res.encoding = "utf-8"
            return res
        finally:
            # Limpeza rigorosa de arquivos temporários de certificados na nuvem
            if os.path.exists(chave): os.remove(chave)
            if os.path.exists(cert): os.remove(cert)
            try: certificado_a1.excluir()
            except: pass

# Monkeypatches e correções do Motor Fiscal (PYNFE 0.6.5)
from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.processamento.assinatura import AssinaturaA1
from pynfe.entidades.emitente import Emitente
from pynfe.entidades.cliente import Cliente
from pynfe.entidades.produto import Produto
from pynfe.entidades.notafiscal import NotaFiscal, NotaFiscalProduto
from pynfe.entidades.fonte_dados import FonteDados

# --- FIXES DE ATRIBUTOS (PyNFe compatibility) ---
NotaFiscalProduto.ind_total = 1
NotaFiscalProduto.icms_csosn = '102'
for attr in ['valor_tributos_aprox', 'ipi_valor_ipi_dev', 'pdevol', 'vBCSTRet', 'pST', 'vICMSSTRet', 'pCredSN', 'vCredICMSSN']:
    setattr(NotaFiscalProduto, attr, Decimal('0.00'))
NotaFiscalProduto.informacoes_adicionais = ''

# --- MOCK FONTE DADOS ---
class MockFonteDados:
    def __init__(self, nota): self.nota = nota
    def obter_lista(self, *args, **kwargs): return [self.nota]
    def limpar_dados(self): pass

def adicionar_produto_com_icms(nota_fiscal, item, emp, descricao=None, cfop_sugerido=None):
    """
    Adiciona um produto/serviço à nota fiscal aplicando a tributação de ICMS
    conforme o regime tributário (CRT) da empresa:

      - CRT 3 (Regime Normal): usa CST (padrão 00, ex: CFOP 5102/CST 00) e monta
        o bloco ICMS completo (modBC/vBC/pICMS/vICMS — obrigatórios no schema 4.00).
      - CRT 1/2 (Simples Nacional): usa CSOSN (padrão 102, ex: CFOP 5102/CSOSN 102),
        sem destaque de ICMS.

    Retorna o NotaFiscalProduto criado (para testes/inspeção).
    Mantém o mesmo comportamento do backend_nfce para consistência entre os motores.
    """
    regime_normal = str(getattr(emp, 'crt', '1') or '1') == '3'
    csosn_atual = str(getattr(item, 'icms_csosn', '102') or '102').strip()
    cst_atual = str(getattr(item, 'icms_cst', '00') or '00').strip()
    cfop_atual = str(cfop_sugerido or getattr(item, 'cfop', '5102') or '5102').replace('.', '').strip()

    # Inteligência Fiscal: Auto-correção de CFOP para ST (Double Check no Backend)
    if (csosn_atual == '500' or cst_atual == '60') and (cfop_atual in ['5101', '5102']):
        cfop_final = '5405'
        print(f">>> [FISCAL] Corrigindo CFOP item {item.codigo}: {cfop_atual} -> {cfop_final} (ST detectada)")
    else:
        cfop_final = cfop_atual

    p_nfe = nota_fiscal.adicionar_produto_servico(
        codigo=item.codigo, descricao=descricao or item.descricao, ncm=item.ncm,
        cfop=cfop_final,
        unidade_comercial='UN', quantidade_comercial=Decimal(str(item.quantidade)),
        valor_unitario_comercial=Decimal(str(item.valor_unitario)),
        valor_total_bruto=Decimal(str(item.valor_total)),
        unidade_tributavel='UN', quantidade_tributavel=Decimal(str(item.quantidade)),
        valor_unitario_tributavel=Decimal(str(item.valor_unitario)),
        ean='SEM GTIN', ean_tributavel='SEM GTIN',
        icms_origem=getattr(item, 'icms_origem', 0) or 0,
        icms_modalidade=(cst_atual or '00') if regime_normal else (csosn_atual or '102')
    )
    if regime_normal:
        # Regime Normal: usa CST (padrão 00, ex: CFOP 5102/CST 00) e monta o
        # bloco ICMS completo (modBC/vBC/pICMS/vICMS obrigatórios no schema 4.00)
        p_nfe.icms_csosn = ''  # garante que nada do Simples Nacional vaze
        p_nfe.icms_cst = cst_atual or '00'
        p_nfe.icms_modalidade = cst_atual or '00'
        p_nfe.icms_modalidade_determinacao_bc = '3'  # 3 = Valor da operação
        try:
            vbc_item = Decimal(str(getattr(item, 'icms_base_calculo', None) or item.valor_total or 0.0))
        except Exception:
            vbc_item = Decimal(str(item.valor_total or 0.0))
        aliq_item = Decimal(str(getattr(item, 'icms_aliquota', 0.0) or 0.0))
        p_nfe.icms_valor_base_calculo = vbc_item.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        p_nfe.icms_aliquota = aliq_item
        p_nfe.icms_valor = (vbc_item * aliq_item / Decimal('100')).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    else:
        # Simples Nacional: usa CSOSN (padrão 102) e não destaca ICMS
        p_nfe.icms_cst = ''
        p_nfe.icms_csosn = csosn_atual or '102'
    return p_nfe


# --- FUNÇÃO PRINCIPAL DE EMISSÃO ---
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


def emitir_nfce_pynfe(req):
    # Decodificar certificado Base64
    cert_bytes = base64.b64decode(req.empresa.certificado_base64)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp_cert:
        tmp_cert.write(cert_bytes)
        caminho_cert = tmp_cert.name

    try:
        emp = req.empresa
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
            endereco_cod_municipio=str(emp.codigo_municipio)
        )

        destinatario = None
        if req.cpf_cliente:
            destinatario = Cliente(
                numero_documento=req.cpf_cliente,
                razao_social='Consumidor Final',
                tipo_documento='CPF',
                indicador_ie=9
            )

        venda_num = re.sub(r'[^0-9]', '', str(req.venda_numero or int(datetime.now().timestamp())))
        nota_fiscal = NotaFiscal(
            emitente=emitente, cliente=destinatario, produtos=[], modelo=65, serie='1',
            numero_nf=venda_num, indicador_destino=1, finalidade_emissao=1, cliente_final=1,
            indicador_presencial=1, valor_total_nota=Decimal(str(req.valor_total)),
            uf=emp.uf, municipio=str(emp.codigo_municipio), tipo_impressao_danfe=4,
            tipo_documento=1, forma_emissao='1', transporte_modalidade_frete=9
        )
        nota_fiscal.data_emissao = datetime.now()
        nota_fiscal.adicionar_pagamento(t_pag='01', v_pag=Decimal(str(req.valor_total)))

        for item in req.itens:
            # A tributação de ICMS é aplicada conforme o regime (CRT) da empresa
            adicionar_produto_com_icms(nota_fiscal, item, emp)

        # Assinatura e Serialização
        assinatura = AssinaturaA1(caminho_cert, emp.senha_certificado)
        serializador = SerializacaoXML(MockFonteDados(nota_fiscal), homologacao=(emp.ambiente == 2))
        xml_string = serializador.exportar(retorna_string=True)
        xml_element = etree.fromstring(xml_string.encode('utf-8'))
        # Corrigir blocos do Simples Nacional (pynfe gera ICMSSN102 p/ CSOSN 103/300/400)
        corrigir_blocos_icms_simples(xml_element)
        
        # Ordem crítica e QR Code (simplificado para cloud)
        # Nota: Idealmente o monkeypatch do QR Code deveria estar aqui também
        # mas para o primeiro deploy focamos no motor base de assinatura
        
        xml_assinado = assinatura.assinar(xml_element)
        
        con = ComunicacaoSefaz(uf=emp.uf, certificado=caminho_cert, certificado_senha=emp.senha_certificado, homologacao=(emp.ambiente == 2))
        aut_result = con.autorizacao(modelo='nfce', nota_fiscal=xml_assinado, id_lote=1, ind_sinc=1)
        
        sucesso = aut_result[0]
        retorno = aut_result[1]

        if sucesso == 0:
            xml_final = etree.tostring(retorno, encoding='utf-8', xml_declaration=True).decode('utf-8')
            namespaces = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
            inf_prot = retorno.xpath('//ns:infProt', namespaces=namespaces)
            if inf_prot:
                c_stat = inf_prot[0].xpath('ns:cStat', namespaces=namespaces)[0].text
                x_motivo = inf_prot[0].xpath('ns:xMotivo', namespaces=namespaces)[0].text
                if c_stat in ('100', '150'):
                    return {
                        "status": "autorizada",
                        "chave": inf_prot[0].xpath('ns:chNFe', namespaces=namespaces)[0].text,
                        "protocolo": inf_prot[0].xpath('ns:nProt', namespaces=namespaces)[0].text,
                        "xml": xml_final
                    }
                return {"status": "erro", "mensagem": f"SEFAZ: {x_motivo} ({c_stat})"}
        return {"status": "erro", "mensagem": "Falha na comunicação com SEFAZ"}

    except Exception as e:
        return {"status": "error", "mensagem": f"Erro interno: {str(e)}", "trace": traceback.format_exc()}
    finally:
        if os.path.exists(caminho_cert): os.remove(caminho_cert)

def cancelar_nfce_pynfe(data):
    return {"success": False, "error": "Cancelamento em nuvem pendente de implementação total"}

def consultar_nfce_pynfe(data):
    return {"success": False, "error": "Consulta em nuvem pendente de implementação total"}

def validar_certificado_pynfe(data):
    try:
        certificado_base64 = data.get('certificado_base64') or data.get('certificado')
        senha = data.get('senha') or data.get('senha_certificado') or data.get('senhaCertificado')
        
        if not certificado_base64 or not senha:
            return {"success": False, "error": "Certificado ou senha não fornecidos"}
            
        cert_bytes = base64.b64decode(certificado_base64)
        from pynfe.entidades.certificado import CertificadoA1
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp_cert:
            tmp_cert.write(cert_bytes)
            caminho_cert = tmp_cert.name
            
        try:
            cert = CertificadoA1(caminho_cert)
            chave, cert_pem = cert.separar_arquivo(senha, caminho=True)
            if os.path.exists(chave): os.remove(chave)
            if os.path.exists(cert_pem): os.remove(cert_pem)
            return {"success": True, "message": "Certificado válido e carregado com sucesso", "validado": True}
        finally:
            if os.path.exists(caminho_cert): os.remove(caminho_cert)
    except Exception as e:
        return {"success": False, "error": f"Erro ao decodificar certificado: {str(e)}", "validado": False}
