"""
SISTEMA COMPLETO DE EMISSÃO NFC-e
100% Local - Funciona em Produção e Homologação
Sem dependência de APIs de terceiros

OPÇÃO 1: SOAP Manual (implementação atual)
OPÇÃO 2: ACBrLib (mais robusto - usar nfce_acbrlib.py)

Autor: Sistema Exodo
Data: 2024
"""

import os
import base64
import tempfile
import random
from datetime import datetime
from decimal import Decimal
from lxml import etree
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.serialization import pkcs12
try:
    import zeep
    from zeep.wsse import BinarySignature
    import requests
    import urllib3
    ZEEP_DISPONIVEL = True
except ImportError:
    ZEEP_DISPONIVEL = False
    print("[AVISO] zeep não está instalado. Instale com: pip install zeep requests urllib3")


class NFCeCompleto:
    """
    Sistema completo para emissão de NFC-e
    Funciona em produção e homologação
    """
    
    # URLs SEFAZ por estado
    # IMPORTANTE: SP usa SVRS para NFC-e (não tem WSDL próprio)
    # SP não usa webservice próprio, usa o SVRS do RS
    URLS_SEFAZ = {
        'SP': {
            # SP usa SVRS para NFC-e (modelo 65)
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'RJ': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'MG': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'PR': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'RS': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'SC': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'BA': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'GO': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        },
        'DF': {
            'homologacao': 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
            'producao': 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        }
    }
    
    # Códigos UF
    CODIGOS_UF = {
        'AC': '12', 'AL': '27', 'AP': '16', 'AM': '13', 'BA': '29',
        'CE': '23', 'DF': '53', 'ES': '32', 'GO': '52', 'MA': '21',
        'MT': '51', 'MS': '50', 'MG': '31', 'PA': '15', 'PB': '25',
        'PR': '41', 'PE': '26', 'PI': '22', 'RJ': '33', 'RN': '24',
        'RS': '43', 'RO': '11', 'RR': '14', 'SC': '42', 'SP': '35',
        'SE': '28', 'TO': '17'
    }
    
    def __init__(self):
        """Inicializa o sistema de emissão NFC-e"""
        self.certificado = None
        self.private_key = None
        self._temp_cert_files = []
    
    def carregar_certificado(self, certificado_base64, senha):
        """
        Carrega certificado digital
        
        Args:
            certificado_base64: Certificado em base64 (arquivo .pfx)
            senha: Senha do certificado
        
        Returns:
            True se carregado com sucesso, False caso contrário
        """
        try:
            cert_bytes = base64.b64decode(certificado_base64)
            senha_bytes = senha.encode('utf-8') if isinstance(senha, str) else senha
            
            self.private_key, self.certificado, additional_certificates = pkcs12.load_key_and_certificates(
                cert_bytes, senha_bytes, backend=default_backend()
            )
            
            if not self.certificado or not self.private_key:
                return False
            
            print(f"✅ Certificado carregado: Válido até {self.certificado.not_valid_after}")
            return True
            
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            return False
    
    def gerar_chave_acesso(self, empresa_data, numero_nfce):
        """
        Gera chave de acesso da NFC-e
        
        Formato: UF(2) + AAMM(4) + CNPJ(14) + Mod(2) + Série(3) + Número(9) + Tipo Emissão(1) + Código(8) + DV(1)
        """
        uf = empresa_data.get('uf', 'SP')
        uf_codigo = self.CODIGOS_UF.get(uf.upper(), '35')
        
        now = datetime.now()
        aamm = now.strftime('%y%m')
        
        cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
        if len(cnpj) != 14:
            raise ValueError("CNPJ deve ter 14 dígitos")
        
        modelo = '65'  # NFC-e
        serie = str(empresa_data.get('serie_nfce', 1)).zfill(3)
        numero = str(numero_nfce).zfill(9)
        tipo_emissao = '1'  # Normal
        codigo_numerico = str(random.randint(10000000, 99999999))
        
        chave_sem_dv = f"{uf_codigo}{aamm}{cnpj}{modelo}{serie}{numero}{tipo_emissao}{codigo_numerico}"
        
        # Calcular dígito verificador
        multiplicadores = [4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        
        soma = sum(int(chave_sem_dv[i]) * multiplicadores[i] for i in range(len(chave_sem_dv)))
        resto = soma % 11
        dv = 0 if resto < 2 else 11 - resto
        
        return f"{chave_sem_dv}{dv}"
    
    def gerar_xml_nfce(self, empresa_data, produtos, pagamentos, consumidor, observacoes, chave_acesso, numero_nfce):
        """
        Gera XML da NFC-e conforme layout oficial da SEFAZ
        """
        ns_nfe = 'http://www.portalfiscal.inf.br/nfe'
        
        # EnviNFe (raiz)
        root = etree.Element(f'{{{ns_nfe}}}enviNFe', nsmap={'nfe': ns_nfe})
        root.set('versao', '4.00')
        
        # idLote (obrigatório - 15 dígitos)
        id_lote = str(random.randint(100000000000000, 999999999999999))
        etree.SubElement(root, f'{{{ns_nfe}}}idLote').text = id_lote
        
        # NFe
        nfe = etree.SubElement(root, f'{{{ns_nfe}}}NFe')
        nfe.set('versao', '4.00')
        
        # infNFe
        inf_nfe = etree.SubElement(nfe, f'{{{ns_nfe}}}infNFe')
        inf_nfe.set('Id', f'NFe{chave_acesso}')
        inf_nfe.set('versao', '4.00')
        
        # ide
        ide = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}ide')
        uf = empresa_data.get('uf', 'SP')
        etree.SubElement(ide, f'{{{ns_nfe}}}cUF').text = self.CODIGOS_UF.get(uf.upper(), '35')
        # cNF são os últimos 8 dígitos antes do DV (posições 35-42 da chave)
        etree.SubElement(ide, f'{{{ns_nfe}}}cNF').text = chave_acesso[35:43] if len(chave_acesso) >= 43 else chave_acesso[-9:-1]
        etree.SubElement(ide, f'{{{ns_nfe}}}natOp').text = 'VENDA'
        etree.SubElement(ide, f'{{{ns_nfe}}}mod').text = '65'
        etree.SubElement(ide, f'{{{ns_nfe}}}serie').text = str(empresa_data.get('serie_nfce', 1))
        etree.SubElement(ide, f'{{{ns_nfe}}}nNF').text = str(numero_nfce)
        
        now = datetime.now()
        dh_emi = now.strftime('%Y-%m-%dT%H:%M:%S-03:00')
        etree.SubElement(ide, f'{{{ns_nfe}}}dhEmi').text = dh_emi
        etree.SubElement(ide, f'{{{ns_nfe}}}dhSaiEnt').text = dh_emi
        etree.SubElement(ide, f'{{{ns_nfe}}}tpNF').text = '1'  # Saída
        etree.SubElement(ide, f'{{{ns_nfe}}}idDest').text = '1'  # Operação interna
        etree.SubElement(ide, f'{{{ns_nfe}}}cMunFG').text = empresa_data.get('codigoIBGE', empresa_data.get('codigo_municipio_ibge', '3550308'))
        etree.SubElement(ide, f'{{{ns_nfe}}}tpImp').text = '4'  # DANFE NFC-e
        etree.SubElement(ide, f'{{{ns_nfe}}}tpEmis').text = '1'  # Normal
        etree.SubElement(ide, f'{{{ns_nfe}}}cDV').text = chave_acesso[-1]
        ambiente = '2' if empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True)) else '1'
        etree.SubElement(ide, f'{{{ns_nfe}}}tpAmb').text = ambiente
        etree.SubElement(ide, f'{{{ns_nfe}}}finNFe').text = '1'  # Normal
        etree.SubElement(ide, f'{{{ns_nfe}}}indFinal').text = '1'  # Consumidor final
        etree.SubElement(ide, f'{{{ns_nfe}}}indPres').text = '1'  # Presencial
        
        # emit
        emit = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}emit')
        cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
        etree.SubElement(emit, f'{{{ns_nfe}}}CNPJ').text = cnpj
        etree.SubElement(emit, f'{{{ns_nfe}}}xNome').text = empresa_data.get('razaoSocial', empresa_data.get('razao_social', ''))
        etree.SubElement(emit, f'{{{ns_nfe}}}xFant').text = empresa_data.get('nomeFantasia', empresa_data.get('nome_fantasia', ''))
        
        # enderEmit
        ender_emit = etree.SubElement(emit, f'{{{ns_nfe}}}enderEmit')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}xLgr').text = empresa_data.get('endereco', '')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}nro').text = empresa_data.get('numero', '')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}xBairro').text = empresa_data.get('bairro', '')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}cMun').text = empresa_data.get('codigoIBGE', empresa_data.get('codigo_municipio_ibge', '3550308'))
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}xMun').text = empresa_data.get('cidade', '')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}UF').text = uf
        cep = empresa_data.get('cep', '').replace('-', '')
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}CEP').text = cep
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}cPais').text = '1058'
        etree.SubElement(ender_emit, f'{{{ns_nfe}}}xPais').text = 'BRASIL'
        telefone = empresa_data.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', '')
        if telefone:
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}fone').text = telefone
        
        etree.SubElement(emit, f'{{{ns_nfe}}}IE').text = empresa_data.get('inscricaoEstadual', empresa_data.get('inscricao_estadual', ''))
        
        # CRT
        crt = empresa_data.get('crt', '3')
        if isinstance(crt, str):
            crt = int(crt) if crt.isdigit() else 3
        etree.SubElement(emit, f'{{{ns_nfe}}}CRT').text = str(crt)
        
        # dest
        dest = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}dest')
        if consumidor and consumidor.get('cpf'):
            cpf = consumidor.get('cpf', '').replace('.', '').replace('-', '')
            etree.SubElement(dest, f'{{{ns_nfe}}}CPF').text = cpf
        else:
            etree.SubElement(dest, f'{{{ns_nfe}}}indIEDest').text = '9'
        
        nome_consumidor = consumidor.get('nome', 'CONSUMIDOR FINAL') if consumidor else 'CONSUMIDOR FINAL'
        etree.SubElement(dest, f'{{{ns_nfe}}}xNome').text = nome_consumidor
        
        # det (produtos)
        valor_total_produtos = Decimal('0.00')
        for idx, produto in enumerate(produtos, 1):
            det = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}det')
            det.set('nItem', str(idx))
            
            prod = etree.SubElement(det, f'{{{ns_nfe}}}prod')
            etree.SubElement(prod, f'{{{ns_nfe}}}cProd').text = str(produto.get('codigo', produto.get('id', '')))
            etree.SubElement(prod, f'{{{ns_nfe}}}cEAN').text = produto.get('codigoBarras', produto.get('codigo_barras', 'SEM GTIN'))
            etree.SubElement(prod, f'{{{ns_nfe}}}xProd').text = produto.get('descricao', produto.get('nome', ''))
            etree.SubElement(prod, f'{{{ns_nfe}}}NCM').text = produto.get('ncm', '00000000')
            if produto.get('cest'):
                etree.SubElement(prod, f'{{{ns_nfe}}}CEST').text = produto.get('cest')
            etree.SubElement(prod, f'{{{ns_nfe}}}CFOP').text = produto.get('cfop', '5102')
            etree.SubElement(prod, f'{{{ns_nfe}}}uCom').text = produto.get('unidade', 'UN')
            etree.SubElement(prod, f'{{{ns_nfe}}}qCom').text = f"{produto.get('quantidade', 1.0):.4f}"
            etree.SubElement(prod, f'{{{ns_nfe}}}vUnCom').text = f"{produto.get('valorUnitario', produto.get('valor_unitario', 0.0)):.4f}"
            valor_produto = Decimal(str(produto.get('valorTotal', produto.get('valor_total', 0.0))))
            etree.SubElement(prod, f'{{{ns_nfe}}}vProd').text = f"{valor_produto:.2f}"
            etree.SubElement(prod, f'{{{ns_nfe}}}cEANTrib').text = produto.get('codigoBarras', produto.get('codigo_barras', 'SEM GTIN'))
            etree.SubElement(prod, f'{{{ns_nfe}}}uTrib').text = produto.get('unidade', 'UN')
            etree.SubElement(prod, f'{{{ns_nfe}}}qTrib').text = f"{produto.get('quantidade', 1.0):.4f}"
            etree.SubElement(prod, f'{{{ns_nfe}}}vUnTrib').text = f"{produto.get('valorUnitario', produto.get('valor_unitario', 0.0)):.4f}"
            etree.SubElement(prod, f'{{{ns_nfe}}}indTot').text = '1'
            
            valor_total_produtos += valor_produto
            
            # imposto
            imposto = etree.SubElement(det, f'{{{ns_nfe}}}imposto')
            etree.SubElement(imposto, f'{{{ns_nfe}}}vTotTrib').text = '0.00'
            
            # ICMS
            icms = etree.SubElement(imposto, f'{{{ns_nfe}}}ICMS')
            icms_item = etree.SubElement(icms, f'{{{ns_nfe}}}ICMS00')
            icms_data = produto.get('icms', {})
            etree.SubElement(icms_item, f'{{{ns_nfe}}}orig').text = str(icms_data.get('origem', '0'))
            etree.SubElement(icms_item, f'{{{ns_nfe}}}CST').text = str(icms_data.get('cst', '102'))
            etree.SubElement(icms_item, f'{{{ns_nfe}}}modBC').text = '0'
            etree.SubElement(icms_item, f'{{{ns_nfe}}}vBC').text = '0.00'
            etree.SubElement(icms_item, f'{{{ns_nfe}}}pICMS').text = f"{icms_data.get('aliquota', 0.0):.2f}"
            etree.SubElement(icms_item, f'{{{ns_nfe}}}vICMS').text = '0.00'
        
        # total
        total = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}total')
        icms_tot = etree.SubElement(total, f'{{{ns_nfe}}}ICMSTot')
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vBC').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vICMS').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vICMSDeson').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vFCP').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vBCST').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vST').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vFCPST').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vFCPSTRet').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vProd').text = f"{valor_total_produtos:.2f}"
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vFrete').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vSeg').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vDesc').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vII').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vIPI').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vIPIDevol').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vPIS').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vCOFINS').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vOutro').text = '0.00'
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vNF').text = f"{valor_total_produtos:.2f}"
        etree.SubElement(icms_tot, f'{{{ns_nfe}}}vTotTrib').text = '0.00'
        
        # pag
        pag = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}pag')
        valor_total_pag = Decimal('0.00')
        for pagamento in pagamentos:
            det_pag = etree.SubElement(pag, f'{{{ns_nfe}}}detPag')
            tipo_pag = self._converter_forma_pagamento(pagamento.get('tipo', '01'))
            etree.SubElement(det_pag, f'{{{ns_nfe}}}tPag').text = tipo_pag
            valor_pag = Decimal(str(pagamento.get('valor', 0.0)))
            etree.SubElement(det_pag, f'{{{ns_nfe}}}vPag').text = f"{valor_pag:.2f}"
            valor_total_pag += valor_pag
        etree.SubElement(pag, f'{{{ns_nfe}}}vTroco').text = '0.00'
        
        # infAdic
        if observacoes:
            inf_adic = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}infAdic')
            etree.SubElement(inf_adic, f'{{{ns_nfe}}}infCpl').text = observacoes
        
        # Quando usar encoding='unicode', não pode usar xml_declaration=True
        # Vamos usar encoding='utf-8' e depois decodificar para ter a declaração XML
        xml_bytes = etree.tostring(root, encoding='utf-8', xml_declaration=True, pretty_print=False)
        return xml_bytes.decode('utf-8')
    
    def assinar_xml(self, xml_str, chave_acesso):
        """
        Assina XML da NFC-e usando certificado digital
        """
        if not self.certificado or not self.private_key:
            raise ValueError("Certificado não carregado")
        
        root = etree.fromstring(xml_str.encode('utf-8'))
        
        # Encontrar NFe
        nfe_elem = None
        for elem in root.iter():
            if 'NFe' in elem.tag and 'enviNFe' not in elem.tag:
                nfe_elem = elem
                break
        
        if nfe_elem is None:
            raise ValueError("Elemento NFe não encontrado")
        
        # Encontrar infNFe
        inf_nfe = None
        for elem in nfe_elem.iter():
            if 'infNFe' in elem.tag:
                inf_nfe = elem
                break
        
        if inf_nfe is None:
            raise ValueError("Elemento infNFe não encontrado")
        
        # Canonicalizar infNFe
        c14n_xml = etree.tostring(inf_nfe, method='c14n', exclusive=True, with_comments=False)
        
        # Hash SHA1
        hash_obj = hashes.Hash(hashes.SHA1(), backend=default_backend())
        hash_obj.update(c14n_xml)
        hash_value = hash_obj.finalize()
        hash_base64 = base64.b64encode(hash_value).decode('utf-8')
        
        # Montar Signature
        ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
        signature_elem = etree.Element(f'{{{ns_ds}}}Signature')
        
        signed_info = etree.SubElement(signature_elem, f'{{{ns_ds}}}SignedInfo')
        
        canon_method = etree.SubElement(signed_info, f'{{{ns_ds}}}CanonicalizationMethod')
        canon_method.set('Algorithm', 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315')
        
        sig_method = etree.SubElement(signed_info, f'{{{ns_ds}}}SignatureMethod')
        sig_method.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#rsa-sha1')
        
        reference = etree.SubElement(signed_info, f'{{{ns_ds}}}Reference')
        reference.set('URI', f'#NFe{chave_acesso}')
        
        transforms = etree.SubElement(reference, f'{{{ns_ds}}}Transforms')
        transform1 = etree.SubElement(transforms, f'{{{ns_ds}}}Transform')
        transform1.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#enveloped-signature')
        transform2 = etree.SubElement(transforms, f'{{{ns_ds}}}Transform')
        transform2.set('Algorithm', 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315')
        
        digest_method = etree.SubElement(reference, f'{{{ns_ds}}}DigestMethod')
        digest_method.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#sha1')
        
        digest_value = etree.SubElement(reference, f'{{{ns_ds}}}DigestValue')
        digest_value.text = hash_base64
        
        # Canonicalizar SignedInfo e assinar
        c14n_signed_info = etree.tostring(signed_info, method='c14n', exclusive=True, with_comments=False)
        
        signature_bytes = self.private_key.sign(
            c14n_signed_info,
            padding.PKCS1v15(),
            hashes.SHA1()
        )
        signature_base64 = base64.b64encode(signature_bytes).decode('utf-8')
        
        signature_value = etree.SubElement(signature_elem, f'{{{ns_ds}}}SignatureValue')
        signature_value.text = signature_base64
        
        # KeyInfo
        key_info = etree.SubElement(signature_elem, f'{{{ns_ds}}}KeyInfo')
        x509_data = etree.SubElement(key_info, f'{{{ns_ds}}}X509Data')
        
        cert_pem = self.certificado.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')
        cert_clean = cert_pem.replace('-----BEGIN CERTIFICATE-----', '').replace('-----END CERTIFICATE-----', '').replace('\n', '').replace('\r', '').strip()
        
        x509_cert = etree.SubElement(x509_data, f'{{{ns_ds}}}X509Certificate')
        x509_cert.text = cert_clean
        
        # Adicionar Signature ao NFe
        nfe_elem.append(signature_elem)
        
        # Quando usar encoding='unicode', não pode usar xml_declaration=True
        # Vamos usar encoding='utf-8' e depois decodificar para ter a declaração XML
        xml_bytes = etree.tostring(root, encoding='utf-8', xml_declaration=True, pretty_print=False)
        return xml_bytes.decode('utf-8')
    
    def enviar_sefaz(self, xml_assinado, empresa_data):
        """
        Envia XML assinado para SEFAZ via SOAP manual (sem WSDL)
        SP não usa WSDL para NFC-e, então fazemos requisição SOAP direta
        """
        
        uf = empresa_data.get('uf', 'SP')
        ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
        
        # Determinar URL
        # IMPORTANTE: SP usa SVRS (Sistema Virtual RS) para NFC-e, não webservice próprio
        if uf in self.URLS_SEFAZ:
            url = self.URLS_SEFAZ[uf]['homologacao' if ambiente_homologacao else 'producao']
            # Remover ?wsdl se presente
            url = url.split('?')[0]
        else:
            # Usar SVRS como padrão
            if ambiente_homologacao:
                url = 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
            else:
                url = 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
        
        print(f"Enviando para SEFAZ (SOAP manual): {url}")
        
        # Criar sessão com SSL verificação desabilitada
        session = requests.Session()
        session.verify = False  # Desabilitar verificação SSL
        
        # Configurar certificado digital na sessão (OBRIGATÓRIO para SEFAZ)
        if self.certificado and self.private_key:
            try:
                cert_pem = self.certificado.public_bytes(encoding=serialization.Encoding.PEM)
                key_pem = self.private_key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption()
                )
                
                # Criar arquivos temporários
                cert_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
                key_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
                
                cert_file.write(cert_pem)
                key_file.write(key_pem)
                
                cert_file.close()
                key_file.close()
                
                # Configurar certificado na sessão
                session.cert = (cert_file.name, key_file.name)
                
                # Armazenar nomes dos arquivos para limpeza posterior
                self._temp_cert_files = [cert_file.name, key_file.name]
                print("✅ Certificado configurado na sessão")
            except Exception as e:
                print(f"❌ Erro ao configurar certificado: {e}")
                self._limpar_arquivos_temporarios()
                return {
                    'success': False,
                    'error': f'Erro ao configurar certificado digital: {str(e)}',
                    'error_type': 'CertificateError'
                }
        else:
            print("⚠️ Aviso: Certificado não carregado!")
            return {
                'success': False,
                'error': 'Certificado digital não foi carregado',
                'error_type': 'CertificateMissing'
            }
        
        # Suprimir avisos de SSL
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Montar envelope SOAP manualmente (sem WSDL)
        # Escapar XML para dentro do envelope SOAP
        xml_escaped = xml_assinado.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace("'", '&apos;')
        
        # Envelope SOAP 1.2 conforme padrão SEFAZ
        soap_envelope = f'''<?xml version="1.0" encoding="UTF-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <nfeAutorizacaoLote xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
      <nfeDadosMsg>
        {xml_escaped}
      </nfeDadosMsg>
    </nfeAutorizacaoLote>
  </soap12:Body>
</soap12:Envelope>'''
        
        # Headers para requisição SOAP
        headers = {
            'Content-Type': 'text/xml; charset=utf-8',
            'SOAPAction': 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote',
        }
        
        try:
            print("Enviando requisição SOAP...")
            # Fazer requisição POST direta
            response = session.post(url, data=soap_envelope.encode('utf-8'), headers=headers, timeout=30)
            
            print(f"Status HTTP: {response.status_code}")
            
            if response.status_code != 200:
                self._limpar_arquivos_temporarios()
                return {
                    'success': False,
                    'error': f'Erro HTTP {response.status_code}: {response.text[:200]}',
                    'error_type': 'HTTPError',
                    'status_code': response.status_code
                }
            
            # Processar resposta SOAP
            resposta_xml = response.text
            print("Processando resposta da SEFAZ...")
            
            # Parsear XML da resposta
            resposta_root = etree.fromstring(resposta_xml.encode('utf-8'))
            
            # Namespaces
            ns = {
                'soap': 'http://www.w3.org/2003/05/soap-envelope',
                'nfe': 'http://www.portalfiscal.inf.br/nfe'
            }
            
            # Procurar retEnviNFe na resposta
            ret_envi_nfe = resposta_root.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe', ns)
            
            if ret_envi_nfe is not None:
                # Extrair dados do retEnviNFe
                c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat', ns)
                x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo', ns)
                
                if c_stat is not None and c_stat.text == '103':  # Lote recebido com sucesso
                    # Buscar protNFe dentro de nfeResultMsg
                    nfe_result_msg = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nfeResultMsg', ns)
                    if nfe_result_msg is not None and nfe_result_msg.text:
                        # Parsear o XML dentro de nfeResultMsg
                        try:
                            prot_xml = etree.fromstring(nfe_result_msg.text.encode('utf-8'))
                            prot_nfe = prot_xml.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe', ns)
                            
                            if prot_nfe is not None:
                                inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt', ns)
                                if inf_prot is not None:
                                    c_stat_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat', ns)
                                    x_motivo_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo', ns)
                                    chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe', ns)
                                    protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt', ns)
                                    
                                    if c_stat_prot is not None and c_stat_prot.text == '100':
                                        self._limpar_arquivos_temporarios()
                                        return {
                                            'success': True,
                                            'autorizada': True,
                                            'status': 'autorizada',
                                            'chave_acesso': chave.text if chave is not None else '',
                                            'protocolo': protocolo.text if protocolo is not None else '',
                                            'mensagem': x_motivo_prot.text if x_motivo_prot is not None else 'Autorizada',
                                            'xml': xml_assinado
                                        }
                                    else:
                                        self._limpar_arquivos_temporarios()
                                        return {
                                            'success': False,
                                            'autorizada': False,
                                            'status': 'rejeitada',
                                            'error': x_motivo_prot.text if x_motivo_prot is not None else 'Erro desconhecido',
                                            'codigo_erro': c_stat_prot.text if c_stat_prot is not None else '',
                                            'error_type': 'SEFAZRejection'
                                        }
                        except Exception as e:
                            print(f"Erro ao processar protNFe: {e}")
            
            # Se chegou aqui, processar resposta padrão
            if c_stat is not None:
                self._limpar_arquivos_temporarios()
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'rejeitada' if c_stat.text.startswith('2') else 'pendente',
                    'error': x_motivo.text if x_motivo is not None else 'Erro desconhecido',
                    'codigo_erro': c_stat.text,
                    'error_type': 'SEFAZRejection'
                }
            
            self._limpar_arquivos_temporarios()
            return {
                'success': False,
                'error': 'Resposta da SEFAZ não reconhecida',
                'error_type': 'UnknownResponse',
                'resposta': resposta_xml[:500]
            }
            
        except Exception as e:
            self._limpar_arquivos_temporarios()
            return {
                'success': False,
                'error': f'Erro ao comunicar com SEFAZ: {str(e)}',
                'error_type': 'SEFAZError'
            }
    
    def emitir(self, empresa_data, produtos, pagamentos, consumidor=None, observacoes='', numero_nfce=1):
        """
        Emite NFC-e completa
        
        Args:
            empresa_data: Dados da empresa (deve incluir certificado_base64 e senhaCertificado)
            produtos: Lista de produtos
            pagamentos: Lista de pagamentos
            consumidor: Dados do consumidor (opcional)
            observacoes: Observações (opcional)
            numero_nfce: Número da NFC-e
        
        Returns:
            Dicionário com resultado da emissão
        """
        try:
            print("=" * 60)
            print("EMISSÃO NFC-e - SISTEMA COMPLETO")
            print("=" * 60)
            
            # 1. Carregar certificado
            print("\n[1/5] Carregando certificado...")
            certificado_base64 = empresa_data.get('certificado_base64') or empresa_data.get('certificadoDigitalUrl', '')
            senha = empresa_data.get('senhaCertificado') or empresa_data.get('senha_certificado', '')
            
            if not certificado_base64 or not senha:
                return {
                    'success': False,
                    'error': 'Certificado digital não fornecido',
                    'error_type': 'CertificateMissing'
                }
            
            if not self.carregar_certificado(certificado_base64, senha):
                return {
                    'success': False,
                    'error': 'Erro ao carregar certificado digital',
                    'error_type': 'CertificateError'
                }
            
            # 2. Gerar chave de acesso
            print("\n[2/5] Gerando chave de acesso...")
            chave_acesso = self.gerar_chave_acesso(empresa_data, numero_nfce)
            print(f"✅ Chave: {chave_acesso}")
            
            # 3. Gerar XML
            print("\n[3/5] Gerando XML...")
            xml_nfce = self.gerar_xml_nfce(empresa_data, produtos, pagamentos, consumidor, observacoes, chave_acesso, numero_nfce)
            print("✅ XML gerado")
            
            # 4. Assinar XML
            print("\n[4/5] Assinando XML...")
            xml_assinado = self.assinar_xml(xml_nfce, chave_acesso)
            print("✅ XML assinado")
            
            # 5. Enviar para SEFAZ
            print("\n[5/5] Enviando para SEFAZ...")
            resultado = self.enviar_sefaz(xml_assinado, empresa_data)
            
            print("\n" + "=" * 60)
            if resultado.get('success'):
                print("✅ NFC-e AUTORIZADA!")
            else:
                print("❌ NFC-e REJEITADA")
            print("=" * 60)
            
            return resultado
            
        except Exception as e:
            import traceback
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e: {str(e)}',
                'error_type': 'UnexpectedError',
                'details': traceback.format_exc()
            }
    
    def _limpar_arquivos_temporarios(self):
        """Limpa arquivos temporários de certificado se existirem"""
        for file_path in self._temp_cert_files:
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
            except Exception:
                pass  # Ignorar erros na limpeza
        self._temp_cert_files = []
    
    def _converter_forma_pagamento(self, tipo):
        """Converte tipo de pagamento para código SEFAZ"""
        conversao = {
            '01': '01',  # Dinheiro
            '02': '02',  # Cheque
            '03': '03',  # Cartão de Crédito
            '04': '04',  # Cartão de Débito
            '05': '05',  # Crédito Loja
            '10': '10',  # Vale Alimentação
            '11': '11',  # Vale Refeição
            '12': '12',  # Vale Presente
            '13': '13',  # Vale Combustível
            '99': '99',  # Outros (PIX)
        }
        return conversao.get(str(tipo), '99')

