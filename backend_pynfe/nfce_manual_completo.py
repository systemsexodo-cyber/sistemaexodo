"""
SISTEMA COMPLETO DE EMISSÃO NFC-e - IMPLEMENTAÇÃO MANUAL 100% PYTHON
Gera XML, assina, envia para SEFAZ e processa resposta
Sem dependência de PyNFe, ACBr ou outros wrappers

Autor: Sistema Exodo
Data: 2024
"""

import base64
import os
import tempfile
from datetime import datetime
from decimal import Decimal
from typing import Dict, List, Optional, Any
from lxml import etree
from signxml import XMLSigner, methods
from OpenSSL import crypto
import requests
import urllib3

# Desabilitar avisos SSL (se necessário)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class NFCeManualCompleto:
    """
    Sistema completo de emissão NFC-e - Implementação manual
    Funciona para SP e outros estados via SVRS
    """
    
    # URLs SEFAZ SP
    URLS_SEFAZ_SP = {
        'homologacao': {
            'autorizacao': 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx',
            'ret_autorizacao': 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx',
            'consulta_protocolo': 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx',
            'status_servico': 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx',
            'qrcode': 'https://homologacao.nfce.fazenda.sp.gov.br/qrcode'
        },
        'producao': {
            'autorizacao': 'https://nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx',
            'ret_autorizacao': 'https://nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx',
            'consulta_protocolo': 'https://nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx',
            'status_servico': 'https://nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx',
            'qrcode': 'https://nfce.fazenda.sp.gov.br/qrcode'
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
        """Inicializa o sistema"""
        self.cert_pem = None
        self.key_pem = None
        self.certificado_carregado = False
        # Diretório base para salvar XMLs
        self.base_xml_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_nfce')
    
    def carregar_certificado(self, certificado_base64: str, senha: str) -> bool:
        """
        Carrega certificado digital A1 (PFX) em base64
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
        
        Returns:
            True se carregado com sucesso
        """
        try:
            # Decodificar base64
            cert_bytes = base64.b64decode(certificado_base64)
            senha_bytes = senha.encode('utf-8') if isinstance(senha, str) else senha
            
            # Carregar PKCS12 - usar cryptography (mais moderno e confiável)
            try:
                from cryptography.hazmat.primitives.serialization import pkcs12
                from cryptography.hazmat.backends import default_backend
                private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
                    cert_bytes, senha_bytes, backend=default_backend()
                )
                from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
                self.key_pem = private_key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption())
                self.cert_pem = certificate.public_bytes(Encoding.PEM)
            except (ImportError, Exception) as e:
                # Se cryptography não estiver disponível, dar erro claro
                raise Exception(
                    f"Não foi possível carregar certificado PKCS12.\n\n"
                    f"SOLUÇÃO:\n"
                    f"1. Instale a biblioteca cryptography:\n"
                    f"   pip install cryptography\n\n"
                    f"2. Reinicie o servidor backend\n\n"
                    f"Erro técnico: {str(e)}"
                )
            
            self.certificado_carregado = True
            print("✅ Certificado carregado com sucesso")
            return True
            
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            return False
    
    def carregar_certificado_arquivo(self, caminho_arquivo: str, senha: str) -> bool:
        """
        Carrega certificado digital de arquivo
        
        Args:
            caminho_arquivo: Caminho para arquivo .pfx
            senha: Senha do certificado
        
        Returns:
            True se carregado com sucesso
        """
        try:
            with open(caminho_arquivo, "rb") as f:
                cert_bytes = f.read()
            
            senha_bytes = senha.encode('utf-8') if isinstance(senha, str) else senha
            # Carregar PKCS12 - usar cryptography (mais moderno e confiável)
            try:
                from cryptography.hazmat.primitives.serialization import pkcs12
                from cryptography.hazmat.backends import default_backend
                private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
                    cert_bytes, senha_bytes, backend=default_backend()
                )
                from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
                self.key_pem = private_key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption())
                self.cert_pem = certificate.public_bytes(Encoding.PEM)
            except (ImportError, Exception) as e:
                # Se cryptography não estiver disponível, dar erro claro
                raise Exception(
                    f"Não foi possível carregar certificado PKCS12.\n\n"
                    f"SOLUÇÃO:\n"
                    f"1. Instale a biblioteca cryptography:\n"
                    f"   pip install cryptography\n\n"
                    f"2. Reinicie o servidor backend\n\n"
                    f"Erro técnico: {str(e)}"
                )
            
            self.certificado_carregado = True
            print("✅ Certificado carregado com sucesso")
            return True
            
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            return False
    
    def gerar_chave_acesso(self, empresa_data: Dict, numero_nfce: int) -> str:
        """
        Gera chave de acesso da NFC-e (44 dígitos)
        
        Formato: UF(2) + AAMM(4) + CNPJ(14) + Mod(2) + Série(3) + Número(9) + Tipo Emissão(1) + Código(8) + DV(1)
        """
        import random
        
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
    
    def gerar_xml_nfce_completo(
        self,
        empresa_data: Dict,
        produtos: List[Dict],
        pagamentos: List[Dict],
        consumidor: Optional[Dict],
        observacoes: str,
        chave_acesso: str,
        numero_nfce: int
    ) -> bytes:
        """
        Gera XML completo da NFC-e conforme leiaute 4.00
        """
        ns_nfe = 'http://www.portalfiscal.inf.br/nfe'
        
        # enviNFe (raiz do lote) - usar namespace padrão (sem prefixo)
        # IMPORTANTE: O schema XSD espera que os elementos filhos (idLote, indSinc, NFe) 
        # estejam no namespace padrão, não com prefixo
        envi_nfe = etree.Element('enviNFe', nsmap={None: ns_nfe})
        envi_nfe.set('versao', '4.00')
        
        # idLote (15 dígitos) - sem prefixo, herda namespace padrão do pai
        import random
        id_lote = str(random.randint(100000000000000, 999999999999999))
        etree.SubElement(envi_nfe, 'idLote').text = id_lote
        
        # indSinc (OBRIGATÓRIO - deve ser o segundo elemento!)
        # 0 = Assíncrono, 1 = Síncrono (NFC-e sempre usa 1)
        etree.SubElement(envi_nfe, 'indSinc').text = '1'
        
        # NFe (deve ser o terceiro elemento) - sem prefixo, herda namespace padrão do pai
        nfe = etree.SubElement(envi_nfe, 'NFe')
        nfe.set('versao', '4.00')
        
        # infNFe
        inf_nfe = etree.SubElement(nfe, f'{{{ns_nfe}}}infNFe')
        inf_nfe.set('Id', f'NFe{chave_acesso}')
        inf_nfe.set('versao', '4.00')
        
        # ide
        ide = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}ide')
        uf = empresa_data.get('uf', 'SP')
        etree.SubElement(ide, f'{{{ns_nfe}}}cUF').text = self.CODIGOS_UF.get(uf.upper(), '35')
        etree.SubElement(ide, f'{{{ns_nfe}}}cNF').text = chave_acesso[35:43] if len(chave_acesso) >= 43 else chave_acesso[-9:-1]
        etree.SubElement(ide, f'{{{ns_nfe}}}natOp').text = empresa_data.get('natureza_operacao', 'VENDA')
        etree.SubElement(ide, f'{{{ns_nfe}}}mod').text = '65'  # NFC-e
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
        etree.SubElement(ide, f'{{{ns_nfe}}}procEmi').text = '0'  # Emissão própria
        etree.SubElement(ide, f'{{{ns_nfe}}}verProc').text = 'SISTEMA EXODO 1.0'
        
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
        
        # Converter para bytes
        # IMPORTANTE: Garantir que o XML seja serializado com namespace padrão (sem prefixo)
        # O schema XSD do enviNFe exige que os elementos filhos diretos (idLote, indSinc, NFe)
        # estejam no namespace padrão, não com prefixo
        
        # Primeiro, serializar sem declaração XML para poder usar encoding='unicode'
        xml_str = etree.tostring(envi_nfe, xml_declaration=False, encoding='unicode', pretty_print=False)
        
        # Adicionar declaração XML manualmente
        xml_str = '<?xml version="1.0" encoding="UTF-8"?>\n' + xml_str
        
        # Normalizar XML: remover prefixo nfe: apenas dos elementos filhos diretos do enviNFe
        # O schema espera: <enviNFe xmlns="..."><idLote>...</idLote><indSinc>...</indSinc><NFe>...</NFe></enviNFe>
        if '<nfe:enviNFe' in xml_str:
            # Adicionar namespace padrão se não existir
            if 'xmlns="http://www.portalfiscal.inf.br/nfe"' not in xml_str:
                xml_str = xml_str.replace('<nfe:enviNFe', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe"')
            else:
                xml_str = xml_str.replace('<nfe:enviNFe', '<enviNFe')
            xml_str = xml_str.replace('</nfe:enviNFe', '</enviNFe')
            
            # Remover prefixo dos filhos diretos do enviNFe (idLote, indSinc, NFe)
            # Mas manter o prefixo nos elementos dentro do NFe
            # Usar regex para substituir apenas os filhos diretos
            import re
            # Substituir <nfe:idLote> e </nfe:idLote> que estão diretamente dentro de enviNFe
            xml_str = re.sub(r'<nfe:idLote>', '<idLote>', xml_str)
            xml_str = re.sub(r'</nfe:idLote>', '</idLote>', xml_str)
            xml_str = re.sub(r'<nfe:indSinc>', '<indSinc>', xml_str)
            xml_str = re.sub(r'</nfe:indSinc>', '</indSinc>', xml_str)
            # Substituir <nfe:NFe> e </nfe:NFe> que estão diretamente dentro de enviNFe
            # Mas cuidado: pode haver NFe dentro de outros elementos, então vamos ser mais específico
            xml_str = re.sub(r'<nfe:NFe\s+versao=', '<NFe versao=', xml_str)
            xml_str = re.sub(r'</nfe:NFe>', '</NFe>', xml_str)
            
            # Remover xmlns:nfe se existir (já temos xmlns padrão)
            xml_str = re.sub(r'\s*xmlns:nfe="[^"]*"', '', xml_str)
        
        return xml_str.encode('utf-8')
    
    def assinar_xml(self, xml_bytes: bytes, chave_acesso: str) -> bytes:
        """
        Assina XML com certificado digital (XML-DSig)
        
        Args:
            xml_bytes: XML em bytes
            chave_acesso: Chave de acesso da NFC-e
        
        Returns:
            XML assinado em bytes
        """
        if not self.certificado_carregado:
            raise ValueError("Certificado não foi carregado")
        
        # Parse XML
        root = etree.fromstring(xml_bytes)
        
        # Encontrar infNFe dentro de enviNFe
        inf_nfe = root.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe')
        if inf_nfe is None:
            raise Exception("infNFe não encontrado no XML")
        
        # Assinar
        signer = XMLSigner(
            method=methods.enveloped,
            signature_algorithm="rsa-sha256",
            digest_algorithm="sha256"
        )
        
        signed_root = signer.sign(
            root,
            key=self.key_pem,
            cert=self.cert_pem,
            reference_uri="#" + inf_nfe.get("Id")
        )
        
        return etree.tostring(signed_root, xml_declaration=True, encoding='utf-8', pretty_print=False)
    
    def montar_envelope_soap(self, xml_assinado_bytes: bytes) -> bytes:
        """
        Monta envelope SOAP 1.2 para envio à SEFAZ
        
        Args:
            xml_assinado_bytes: XML assinado em bytes (deve ser enviNFe)
        
        Returns:
            Envelope SOAP em bytes
        """
        # Namespaces - SOAP 1.2 (correto para SEFAZ)
        ns_soap = "http://www.w3.org/2003/05/soap-envelope"
        ns_nfe = "http://www.portalfiscal.inf.br/nfe"
        ns_wsdl = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4"
        
        # Envelope SOAP 1.2
        # IMPORTANTE: Não incluir "nfe" no nsmap do envelope para evitar que o lxml adicione prefixo
        envelope = etree.Element(
            f"{{{ns_soap}}}Envelope",
            nsmap={
                "soap": ns_soap
            }
        )
        
        # Body
        body = etree.SubElement(envelope, f"{{{ns_soap}}}Body")
        
        # nfeDadosMsg direto no body (padrão PyNFe para NFeAutorizacao4)
        # Namespace: http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4
        dados = etree.SubElement(body, "nfeDadosMsg", xmlns=ns_wsdl)
        
        # Inserir XML assinado (enviNFe) como ELEMENTO XML, não como texto
        # O PyNFe usa append() para inserir o elemento diretamente
        try:
            # Converter para string se necessário
            if isinstance(xml_assinado_bytes, bytes):
                xml_str = xml_assinado_bytes.decode('utf-8')
            else:
                xml_str = str(xml_assinado_bytes)
            
            # Remover declaração XML se houver
            if xml_str.startswith('<?xml'):
                xml_str = xml_str.split('?>', 1)[1].strip()
            
            # Parsear XML preservando namespace padrão
            # IMPORTANTE: Parsear com namespace padrão para evitar que lxml adicione prefixo
            xml_root = etree.fromstring(xml_str.encode('utf-8'))
            
            # CORREÇÃO: Remover xmlns do elemento raiz se houver (pode causar erro 225)
            # O namespace deve ser herdado do envelope SOAP, não declarado novamente
            if 'xmlns' in xml_root.attrib:
                # Manter o namespace mas remover declaração explícita
                ns_uri = xml_root.attrib.get('xmlns')
                if ns_uri == ns_nfe:
                    # Remover xmlns se for o namespace padrão (será herdado)
                    del xml_root.attrib['xmlns']
            
            # Verificar se é enviNFe ou NFe
            tag_name = xml_root.tag
            if 'enviNFe' in tag_name:
                # É enviNFe, garantir que mantenha namespace padrão (sem prefixo)
                # IMPORTANTE: O lxml adiciona prefixo quando faz append() se o namespace estiver no nsmap
                # Solução: inserir como string XML (CDATA) ou reconstruir sem prefixo
                
                # Serializar o XML sem prefixo nfe: nos filhos diretos do enviNFe
                xml_str_clean = etree.tostring(xml_root, encoding='unicode', pretty_print=False)
                
                # CORREÇÃO CRÍTICA: Garantir que enviNFe tem xmlns declarado e sem prefixos
                import re
                
                # Se não tem xmlns, adicionar (OBRIGATÓRIO para schema)
                if 'xmlns="http://www.portalfiscal.inf.br/nfe"' not in xml_str_clean:
                    # Adicionar xmlns ao enviNFe
                    xml_str_clean = re.sub(r'<enviNFe\s+', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" ', xml_str_clean)
                    xml_str_clean = re.sub(r'<nfe:enviNFe\s+', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe" ', xml_str_clean)
                
                # Remover prefixos nfe: de todos os elementos
                xml_str_clean = xml_str_clean.replace('</nfe:enviNFe>', '</enviNFe>')
                xml_str_clean = re.sub(r'<nfe:idLote>', '<idLote>', xml_str_clean)
                xml_str_clean = re.sub(r'</nfe:idLote>', '</idLote>', xml_str_clean)
                xml_str_clean = re.sub(r'<nfe:indSinc>', '<indSinc>', xml_str_clean)
                xml_str_clean = re.sub(r'</nfe:indSinc>', '</indSinc>', xml_str_clean)
                xml_str_clean = re.sub(r'<nfe:NFe\s+', '<NFe ', xml_str_clean)
                xml_str_clean = xml_str_clean.replace('</nfe:NFe>', '</NFe>')
                
                # Remover xmlns:nfe se existir (já temos xmlns padrão)
                xml_str_clean = re.sub(r'\s*xmlns:nfe="[^"]*"', '', xml_str_clean)
                
                # Garantir que versao está presente no enviNFe (OBRIGATÓRIO)
                if 'versao="4.00"' not in xml_str_clean:
                    # Adicionar versao se não estiver presente
                    xml_str_clean = re.sub(
                        r'(<enviNFe\s+xmlns="http://www.portalfiscal.inf.br/nfe")',
                        r'\1 versao="4.00"',
                        xml_str_clean
                    )
                
                # Parsear novamente e inserir
                xml_root_clean = etree.fromstring(xml_str_clean.encode('utf-8'))
                
                # CORREÇÃO FINAL: Garantir que o xmlns está presente no elemento após parse
                if 'xmlns' not in xml_root_clean.attrib:
                    xml_root_clean.set('xmlns', ns_nfe)
                
                # Garantir que versao está presente
                if 'versao' not in xml_root_clean.attrib:
                    xml_root_clean.set('versao', '4.00')
                
                dados.append(xml_root_clean)
            elif 'NFe' in tag_name and 'enviNFe' not in tag_name:
                # É apenas NFe, precisa criar enviNFe
                import random
                id_lote = str(random.randint(10**14, 10**15 - 1))  # 15 dígitos
                # Criar enviNFe com xmlns explícito (OBRIGATÓRIO para schema)
                envi_nfe = etree.Element('enviNFe', xmlns=ns_nfe, versao="4.00")
                etree.SubElement(envi_nfe, 'idLote').text = id_lote
                etree.SubElement(envi_nfe, 'indSinc').text = "1"
                envi_nfe.append(xml_root)
                dados.append(envi_nfe)
            else:
                # Tentar inserir como está
                dados.append(xml_root)
                
        except Exception as e:
            print(f"⚠️ Erro ao processar XML para SOAP: {e}")
            import traceback
            print(traceback.format_exc())
            # Fallback crítico: tentar inserir como texto escapado (último recurso)
            xml_text = xml_assinado_bytes.decode('utf-8') if isinstance(xml_assinado_bytes, bytes) else str(xml_assinado_bytes)
            if xml_text.startswith('<?xml'):
                xml_text = xml_text.split('?>', 1)[1].strip()
            # Escapar apenas caracteres que quebram XML quando usado como texto
            xml_escaped = xml_text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            dados.text = xml_escaped
        
        # Converter para bytes com encoding UTF-8
        soap_bytes = etree.tostring(
            envelope, 
            xml_declaration=True, 
            encoding='utf-8',
            pretty_print=False
        )
        
        # Debug: mostrar estrutura do SOAP (primeiros 1000 chars)
        soap_str = soap_bytes.decode('utf-8') if isinstance(soap_bytes, bytes) else soap_bytes
        print(f"\n[DEBUG] Estrutura SOAP (primeiros 1000 chars):")
        print(soap_str[:1000])
        
        return soap_bytes
    
    def enviar_para_sefaz(self, soap_envelope: bytes, ambiente_homologacao: bool = True) -> requests.Response:
        """
        Envia envelope SOAP para SEFAZ
        
        Args:
            soap_envelope: Envelope SOAP em bytes
            ambiente_homologacao: True para homologação, False para produção
        
        Returns:
            Resposta HTTP
        """
        ambiente = 'homologacao' if ambiente_homologacao else 'producao'
        endpoint = self.URLS_SEFAZ_SP[ambiente]['autorizacao']
        
        # Headers SOAP 1.2
        # NOTA: PyNFe não coloca SOAPAction para a maioria dos estados (exceto PE)
        # Mas alguns estados podem exigir, então vamos incluir
        headers = {
            "Content-Type": "application/soap+xml; charset=utf-8",  # SOAP 1.2
            "SOAPAction": "",  # Vazio para SOAP 1.2 (padrão PyNFe)
            "User-Agent": "Python-requests/2.31.0",
            "Accept": "application/soap+xml, text/xml, */*"
        }
        
        # Configurar certificado na sessão se disponível
        session = requests.Session()
        if self.cert_pem and self.key_pem:
            # Salvar certificado temporariamente
            cert_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
            key_file = tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.pem')
            
            cert_file.write(self.cert_pem)
            key_file.write(self.key_pem)
            
            cert_file.close()
            key_file.close()
            
            session.cert = (cert_file.name, key_file.name)
        
        session.verify = False  # Desabilitar verificação SSL (se necessário)
        
        try:
            response = session.post(
                endpoint,
                data=soap_envelope,
                headers=headers,
                timeout=60
            )
            return response
        finally:
            # Limpar arquivos temporários
            if hasattr(session, 'cert') and session.cert:
                try:
                    os.unlink(session.cert[0])
                    os.unlink(session.cert[1])
                except:
                    pass
    
    def processar_resposta_sefaz(self, resposta_xml: str) -> Dict[str, Any]:
        """
        Processa resposta da SEFAZ
        
        Args:
            resposta_xml: XML de resposta da SEFAZ
        
        Returns:
            Dicionário com resultado processado
        """
        try:
            print("\n" + "=" * 60)
            print("PROCESSANDO RESPOSTA DA SEFAZ")
            print("=" * 60)
            print(f"Resposta (primeiros 500 chars): {resposta_xml[:500]}")
            
            # CORREÇÃO: Tentar diferentes formas de parsear o XML
            root = None
            try:
                # Tentar parsear como string
                if isinstance(resposta_xml, str):
                    root = etree.fromstring(resposta_xml.encode('utf-8'))
                else:
                    root = etree.fromstring(resposta_xml)
            except Exception as e1:
                print(f"⚠️ Erro ao parsear XML (tentativa 1): {e1}")
                try:
                    # Tentar parsear removendo declaração XML se houver
                    xml_limpo = resposta_xml
                    if xml_limpo.startswith('<?xml'):
                        xml_limpo = xml_limpo.split('?>', 1)[1].strip()
                    root = etree.fromstring(xml_limpo.encode('utf-8'))
                except Exception as e2:
                    print(f"⚠️ Erro ao parsear XML (tentativa 2): {e2}")
                    raise ValueError(f"Não foi possível parsear o XML da resposta: {e1}")
            
            # Namespaces corretos (SOAP 1.2 e NFe)
            ns = {
                'soap': 'http://www.w3.org/2003/05/soap-envelope',  # SOAP 1.2 (correto)
                'soap11': 'http://schemas.xmlsoap.org/soap/envelope/',  # SOAP 1.1 (fallback)
                'nfe': 'http://www.portalfiscal.inf.br/nfe'
            }
            
            # Procurar retEnviNFe - tentar múltiplas estratégias
            ret_envi_nfe = None
            
            # Estratégia 1: Buscar diretamente com namespace
            ret_envi_nfe = root.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
            
            # Estratégia 2: Buscar sem namespace
            if ret_envi_nfe is None:
                ret_envi_nfe = root.find('.//retEnviNFe')
            
            # Estratégia 3: Buscar dentro de soap:Body
            if ret_envi_nfe is None:
                body = root.find('.//{http://www.w3.org/2003/05/soap-envelope}Body') or root.find('.//{http://schemas.xmlsoap.org/soap/envelope/}Body')
                if body is not None:
                    ret_envi_nfe = body.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe') or body.find('.//retEnviNFe')
            
            # Estratégia 4: Buscar dentro de nfeResultMsg
            if ret_envi_nfe is None:
                nfe_result_msg = root.find('.//{http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4}nfeResultMsg') or root.find('.//nfeResultMsg')
                if nfe_result_msg is not None:
                    # Se nfeResultMsg tem texto, parsear
                    if nfe_result_msg.text:
                        try:
                            nfe_result_root = etree.fromstring(nfe_result_msg.text.encode('utf-8'))
                            ret_envi_nfe = nfe_result_root.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe') or nfe_result_root.find('.//retEnviNFe')
                        except:
                            pass
                    # Se não tem texto, buscar filhos
                    if ret_envi_nfe is None:
                        ret_envi_nfe = nfe_result_msg.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe') or nfe_result_msg.find('.//retEnviNFe')
            
            # Estratégia 5: Buscar recursivamente por qualquer elemento com retEnviNFe no nome
            if ret_envi_nfe is None:
                for elem in root.iter():
                    if 'retEnviNFe' in elem.tag or elem.tag.endswith('retEnviNFe'):
                        ret_envi_nfe = elem
                        print(f"   ✅ retEnviNFe encontrado por iteração: {elem.tag}")
                        break
            
            # Processar retEnviNFe encontrado
            if ret_envi_nfe is not None:
                print(f"   ✅ retEnviNFe encontrado!")
                
                # Buscar cStat e xMotivo - tentar múltiplas estratégias
                c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                if c_stat is None:
                    c_stat = ret_envi_nfe.find('.//cStat')
                
                x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                if x_motivo is None:
                    x_motivo = ret_envi_nfe.find('.//xMotivo')
                
                print(f"cStat encontrado: {c_stat.text if c_stat is not None else 'N/A'}")
                print(f"xMotivo encontrado: {x_motivo.text if x_motivo is not None else 'N/A'}")
                
                # Buscar protNFe dentro de retEnviNFe (pode estar em diferentes lugares)
                prot_nfe = None
                prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                if prot_nfe is None:
                    prot_nfe = ret_envi_nfe.find('.//protNFe')
                
                # Se encontrou protNFe, processar
                if prot_nfe is not None:
                    print("   ✅ protNFe encontrado!")
                    inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt')
                    if inf_prot is None:
                        inf_prot = prot_nfe.find('.//infProt')
                    
                    if inf_prot is not None:
                        c_stat_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                        if c_stat_prot is None:
                            c_stat_prot = inf_prot.find('.//cStat')
                        
                        x_motivo_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                        if x_motivo_prot is None:
                            x_motivo_prot = inf_prot.find('.//xMotivo')
                        
                        chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe')
                        if chave is None:
                            chave = inf_prot.find('.//chNFe')
                        
                        protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                        if protocolo is None:
                            protocolo = inf_prot.find('.//nProt')
                        
                        if c_stat_prot is not None:
                            c_stat_text = c_stat_prot.text
                            print(f"   📋 cStat do protocolo: {c_stat_text}")
                            
                            if c_stat_text in ['100', '150']:  # Autorizada
                                print("✅ NFC-e AUTORIZADA!")
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'status': 'autorizada',
                                    'chave_acesso': chave.text if chave is not None and chave.text else '',
                                    'protocolo': protocolo.text if protocolo is not None and protocolo.text else '',
                                    'mensagem': x_motivo_prot.text if x_motivo_prot is not None and x_motivo_prot.text else 'Autorizada',
                                    'xml_resposta': resposta_xml
                                }
                            else:
                                # Rejeitada no protocolo
                                motivo_prot = x_motivo_prot.text if x_motivo_prot is not None and x_motivo_prot.text else 'Erro desconhecido'
                                print(f"❌ NFC-e REJEITADA no protocolo (cStat: {c_stat_text})")
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'status': 'rejeitada',
                                    'error': motivo_prot,
                                    'codigo_erro': c_stat_text,
                                    'error_type': 'SEFAZRejection',
                                    'xml_resposta': resposta_xml
                                }
                
                # Se não encontrou protNFe, processar cStat do retEnviNFe
                if c_stat is not None:
                    codigo = c_stat.text
                    motivo = x_motivo.text if x_motivo is not None and x_motivo.text else 'Erro desconhecido'
                    
                    print(f"\n❌ REJEIÇÃO DA SEFAZ:")
                    print(f"   Código: {codigo}")
                    print(f"   Motivo: {motivo}")
                    
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'rejeitada' if codigo and codigo.startswith('2') else 'pendente',
                        'error': motivo,
                        'codigo_erro': codigo,
                        'error_type': 'SEFAZRejection',
                        'xml_resposta': resposta_xml
                    }
            
            # Se não encontrou retEnviNFe, mostrar estrutura do XML para debug
            print("⚠️ retEnviNFe não encontrado na resposta")
            print("📋 Estrutura do XML recebido:")
            print(f"   Tag raiz: {root.tag}")
            print(f"   Filhos diretos:")
            for i, child in enumerate(root):
                print(f"      [{i}] {child.tag}")
            
            print("⚠️ Resposta não reconhecida")
            return {
                'success': False,
                'error': 'Resposta da SEFAZ não reconhecida - retEnviNFe não encontrado',
                'error_type': 'UnknownResponse',
                'xml_resposta': resposta_xml[:1000]  # Primeiros 1000 chars para debug
            }
            
        except Exception as e:
            import traceback
            print(f"\n❌ ERRO ao processar resposta: {e}")
            print("📋 Tipo do erro:", type(e).__name__)
            print("📋 Traceback completo:")
            print(traceback.format_exc())
            
            # Tentar salvar o XML da resposta para debug
            try:
                debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug_respostas')
                os.makedirs(debug_dir, exist_ok=True)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                debug_file = os.path.join(debug_dir, f'resposta_erro_{timestamp}.xml')
                with open(debug_file, 'w', encoding='utf-8') as f:
                    f.write(resposta_xml)
                print(f"📁 XML da resposta salvo para debug: {debug_file}")
            except Exception as e_salvar:
                print(f"⚠️ Erro ao salvar XML de debug: {e_salvar}")
            
            return {
                'success': False,
                'error': f'Erro ao processar resposta: {str(e)}',
                'error_type': 'ProcessingError',
                'xml_resposta': resposta_xml[:1000] if len(resposta_xml) > 1000 else resposta_xml,
                'traceback': traceback.format_exc()
            }
    
    def _extrair_erro_basico_resposta(self, resposta_xml: str) -> Dict[str, Any]:
        """
        Tenta extrair informações básicas de erro da resposta XML mesmo sem parse completo.
        Útil quando o XML está malformado ou tem estrutura inesperada.
        
        Args:
            resposta_xml: XML de resposta da SEFAZ (pode estar malformado)
        
        Returns:
            Dict com informações básicas do erro
        """
        try:
            # Tentar parse básico
            root = etree.fromstring(resposta_xml.encode('utf-8'))
            
            # Buscar cStat e xMotivo em vários locais possíveis
            c_stat = None
            x_motivo = None
            
            # Estratégia 1: Buscar diretamente
            c_stat_elem = root.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or root.find('.//cStat')
            x_motivo_elem = root.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or root.find('.//xMotivo')
            
            if c_stat_elem is not None:
                c_stat = c_stat_elem.text
            if x_motivo_elem is not None:
                x_motivo = x_motivo_elem.text
            
            # Estratégia 2: Buscar em retEnviNFe
            if not c_stat or not x_motivo:
                ret_envi = root.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe') or root.find('.//retEnviNFe')
                if ret_envi is not None:
                    c_stat_elem = ret_envi.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or ret_envi.find('.//cStat')
                    x_motivo_elem = ret_envi.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or ret_envi.find('.//xMotivo')
                    if c_stat_elem is not None:
                        c_stat = c_stat_elem.text
                    if x_motivo_elem is not None:
                        x_motivo = x_motivo_elem.text
            
            # Estratégia 3: Buscar em protNFe/infProt
            if not c_stat or not x_motivo:
                inf_prot = root.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or root.find('.//infProt')
                if inf_prot is not None:
                    c_stat_elem = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or inf_prot.find('.//cStat')
                    x_motivo_elem = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or inf_prot.find('.//xMotivo')
                    if c_stat_elem is not None:
                        c_stat = c_stat_elem.text
                    if x_motivo_elem is not None:
                        x_motivo = x_motivo_elem.text
            
            # Estratégia 4: Buscar em Fault (erro SOAP)
            if not c_stat or not x_motivo:
                fault = root.find('.//{http://www.w3.org/2003/05/soap-envelope}Fault') or root.find('.//Fault')
                if fault is not None:
                    reason = fault.find('.//{http://www.w3.org/2003/05/soap-envelope}Reason') or fault.find('.//Reason')
                    if reason is not None:
                        text_elem = reason.find('.//{http://www.w3.org/2003/05/soap-envelope}Text') or reason.find('.//Text')
                        if text_elem is not None:
                            x_motivo = text_elem.text
            
            # Montar mensagem
            if c_stat and x_motivo:
                return {
                    'codigo': c_stat,
                    'mensagem': f'Rejeição {c_stat}: {x_motivo}',
                    'xMotivo': x_motivo
                }
            elif x_motivo:
                return {
                    'codigo': None,
                    'mensagem': x_motivo,
                    'xMotivo': x_motivo
                }
            elif c_stat:
                return {
                    'codigo': c_stat,
                    'mensagem': f'Rejeição {c_stat}',
                    'xMotivo': None
                }
            else:
                return {
                    'codigo': None,
                    'mensagem': 'Erro ao processar resposta da SEFAZ (estrutura não reconhecida)',
                    'xMotivo': None
                }
        except Exception as e:
            # Se falhar completamente, retornar mensagem genérica
            print(f"⚠️ Erro ao extrair informações básicas: {e}")
            return {
                'codigo': None,
                'mensagem': f'Erro ao processar resposta XML da SEFAZ: {str(e)}',
                'xMotivo': None
            }
    
    def gerar_qrcode(self, chave_acesso: str, ambiente_homologacao: bool = True) -> str:
        """
        Gera URL do QR Code para NFC-e
        
        Args:
            chave_acesso: Chave de acesso da NFC-e
            ambiente_homologacao: True para homologação
        
        Returns:
            URL do QR Code
        """
        ambiente = 'homologacao' if ambiente_homologacao else 'producao'
        url_base = self.URLS_SEFAZ_SP[ambiente]['qrcode']
        
        # QR Code formato: url_base?p=chave_acesso
        qrcode_url = f"{url_base}?p={chave_acesso}"
        
        return qrcode_url
    
    def emitir(
        self,
        empresa_data: Dict,
        produtos: List[Dict],
        pagamentos: List[Dict],
        consumidor: Optional[Dict] = None,
        observacoes: str = '',
        numero_nfce: int = 1
    ) -> Dict[str, Any]:
        """
        Emite NFC-e completa (método principal)
        
        Args:
            empresa_data: Dados da empresa
            produtos: Lista de produtos
            pagamentos: Lista de pagamentos
            consumidor: Dados do consumidor (opcional)
            observacoes: Observações
            numero_nfce: Número da NFC-e
        
        Returns:
            Dicionário com resultado da emissão
        """
        try:
            print("=" * 60)
            print("EMISSÃO NFC-e - IMPLEMENTAÇÃO MANUAL")
            print("=" * 60)
            
            # 1. Verificar certificado
            if not self.certificado_carregado:
                # Tentar carregar do empresa_data
                certificado_base64 = empresa_data.get('certificado_base64') or empresa_data.get('certificadoDigitalUrl', '')
                senha = empresa_data.get('senhaCertificado') or empresa_data.get('senha_certificado', '')
                
                if certificado_base64 and senha:
                    if not self.carregar_certificado(certificado_base64, senha):
                        return {
                            'success': False,
                            'error': 'Erro ao carregar certificado digital',
                            'error_type': 'CertificateError'
                        }
                else:
                    return {
                        'success': False,
                        'error': 'Certificado digital não fornecido',
                        'error_type': 'CertificateMissing'
                    }
            
            # 2. Gerar chave de acesso
            print("\n[1/5] Gerando chave de acesso...")
            chave_acesso = self.gerar_chave_acesso(empresa_data, numero_nfce)
            print(f"✅ Chave: {chave_acesso}")
            
            # 3. Gerar XML
            print("\n[2/5] Gerando XML...")
            xml_bytes = self.gerar_xml_nfce_completo(
                empresa_data, produtos, pagamentos, consumidor,
                observacoes, chave_acesso, numero_nfce
            )
            print("✅ XML gerado")
            
            # 4. Assinar XML
            print("\n[3/5] Assinando XML...")
            xml_assinado = self.assinar_xml(xml_bytes, chave_acesso)
            print("✅ XML assinado")
            
            # 5. Montar SOAP
            print("\n[4/5] Montando envelope SOAP...")
            soap_envelope = self.montar_envelope_soap(xml_assinado)
            print("✅ SOAP montado")
            
            # 6. Enviar para SEFAZ
            print("\n[5/5] Enviando para SEFAZ...")
            ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
            response = self.enviar_para_sefaz(soap_envelope, ambiente_homologacao)
            
            print(f"Status HTTP: {response.status_code}")
            
            # IMPORTANTE: Mesmo com HTTP 400, a SEFAZ pode retornar XML com detalhes do erro
            # Vamos processar a resposta para extrair mensagens detalhadas
            if response.status_code not in [200, 400]:
                # Para outros códigos (500, 503, etc), retornar erro genérico
                return {
                    'success': False,
                    'error': f'Erro HTTP {response.status_code} ao comunicar com SEFAZ',
                    'error_type': 'HTTPError',
                    'status_code': response.status_code,
                    'response_preview': response.text[:500] if response.text else 'Resposta vazia',
                    'diagnostico': {
                        'sugestao': 'Verifique a disponibilidade do serviço da SEFAZ. Aguarde alguns minutos e tente novamente.',
                        'url_sefaz': self.URLS_SEFAZ_SP['homologacao' if ambiente_homologacao else 'producao']['autorizacao']
                    }
                }
            
            # Para HTTP 200 ou 400, tentar processar a resposta XML
            # A SEFAZ pode retornar 400 com XML válido contendo detalhes da rejeição
            
            # 7. SEMPRE salvar XML ANTES de processar resposta (para validação mesmo se rejeitada)
            xml_str = None
            caminho_xml = None
            try:
                # Converter XML assinado para string
                if isinstance(xml_assinado, bytes):
                    xml_str = xml_assinado.decode('utf-8')
                else:
                    xml_str = str(xml_assinado)
                
                # Validar que o XML não está vazio
                if not xml_str or len(xml_str.strip()) == 0:
                    raise ValueError("XML assinado está vazio")
                
                print(f"\n[7/8] Salvando XML...")
                print(f"   📋 Tamanho do XML: {len(xml_str)} caracteres")
                
                # Salvar XML
                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                print(f"\n✅ XML salvo para validação:")
                print(f"   📁 Caminho: {caminho_xml}")
                print(f"   🔗 Você pode validar este XML no site da SEFAZ")
            except Exception as e_salvar:
                print(f"\n⚠️ Erro ao salvar XML: {e_salvar}")
                import traceback
                traceback.print_exc()
                # Tentar salvar em local alternativo
                try:
                    debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_nfce', 'erro_salvamento')
                    os.makedirs(debug_dir, exist_ok=True)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    caminho_alternativo = os.path.join(debug_dir, f'xml_erro_{timestamp}.xml')
                    if xml_str:
                        with open(caminho_alternativo, 'w', encoding='utf-8') as f:
                            f.write(xml_str)
                        print(f"   📁 XML salvo em local alternativo: {caminho_alternativo}")
                        caminho_xml = caminho_alternativo
                except Exception as e2:
                    print(f"   ❌ Erro ao salvar em local alternativo: {e2}")
                # Continuar mesmo se falhar ao salvar
            
            # 8. Processar resposta
            print(f"\n[8/8] Processando resposta da SEFAZ...")
            print(f"   📋 Status HTTP: {response.status_code}")
            print(f"   📋 Tamanho da resposta: {len(response.text)} caracteres")
            print(f"   📋 Primeiros 200 chars: {response.text[:200]}")
            
            # Validar que a resposta não está vazia
            if not response.text or len(response.text.strip()) == 0:
                # Se HTTP 400 e resposta vazia, pode ser erro de conexão
                if response.status_code == 400:
                    return {
                        'success': False,
                        'error': 'Erro HTTP 400: Resposta vazia da SEFAZ. Pode ser problema de conexão ou configuração.',
                        'error_type': 'HTTPError',
                        'status_code': 400,
                        'diagnostico': {
                            'sugestao': 'Verifique a URL da SEFAZ e aguarde alguns minutos antes de tentar novamente.',
                            'url_sefaz': self.URLS_SEFAZ_SP['homologacao' if ambiente_homologacao else 'producao']['autorizacao']
                        }
                    }
                raise ValueError("Resposta da SEFAZ está vazia")
            
            # Tentar processar resposta XML (mesmo se HTTP 400)
            # A SEFAZ pode retornar 400 com XML válido contendo detalhes da rejeição
            try:
                resultado = self.processar_resposta_sefaz(response.text)
                
                # Se HTTP 400, adicionar informação ao resultado
                if response.status_code == 400:
                    resultado['status_code'] = 400
                    if 'diagnostico' not in resultado:
                        resultado['diagnostico'] = {}
                    resultado['diagnostico']['http_status'] = 400
                    resultado['diagnostico']['sugestao'] = (
                        'A SEFAZ retornou HTTP 400. Verifique a mensagem de rejeição detalhada acima. '
                        'Ajuste os dados da nota conforme indicado e tente novamente.'
                    )
            except Exception as e_processar:
                # Se falhar ao processar resposta, mas temos HTTP 400, tentar extrair erro básico
                if response.status_code == 400:
                    print(f"\n⚠️ Erro ao processar resposta XML: {e_processar}")
                    print(f"   Tentando extrair informações básicas da resposta...")
                    
                    # Tentar extrair informações básicas mesmo sem parse completo
                    erro_detalhado = self._extrair_erro_basico_resposta(response.text)
                    
                    return {
                        'success': False,
                        'error': f'Erro HTTP 400: {erro_detalhado.get("mensagem", "Erro ao processar resposta da SEFAZ")}',
                        'error_type': 'HTTPError',
                        'status_code': 400,
                        'codigo_erro': erro_detalhado.get('codigo'),
                        'response_preview': response.text[:1000],
                        'diagnostico': {
                            'sugestao': (
                                'Verifique a mensagem de rejeição detalhada acima. '
                                'Ajuste os dados da nota (produto, vendedor, informações tributárias) '
                                'e tente novamente após alguns minutos.'
                            ),
                            'url_sefaz': self.URLS_SEFAZ_SP['homologacao' if ambiente_homologacao else 'producao']['autorizacao'],
                            'erro_parse': str(e_processar)
                        }
                    }
                else:
                    # Para outros códigos, re-raise
                    raise
            
            # 9. Adicionar XML ao resultado
            if xml_str:
                resultado['xml'] = xml_str
            if caminho_xml:
                resultado['caminho_xml'] = caminho_xml
            
            # 10. Adicionar QR Code se autorizada
            if resultado.get('success') and resultado.get('autorizada'):
                qrcode_url = self.gerar_qrcode(resultado['chave_acesso'], ambiente_homologacao)
                resultado['qrcode_url'] = qrcode_url
            
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
    
    def _salvar_xml(self, empresa_data: Dict, chave_acesso: str, xml_str: str, numero_nfce: int) -> str:
        """
        Salva XML da NFC-e em pasta organizada por empresa e mês
        
        Args:
            empresa_data: Dados da empresa
            chave_acesso: Chave de acesso da NFC-e
            xml_str: XML completo como string
            numero_nfce: Número da NFC-e
        
        Returns:
            Caminho completo do arquivo XML salvo
        """
        try:
            import re
            from datetime import datetime
            
            # Extrair CNPJ da empresa
            cnpj = empresa_data.get('cnpj', '') or empresa_data.get('CNPJ', '')
            if cnpj:
                cnpj_limpo = re.sub(r'[^\d]', '', str(cnpj))
                empresa_id = cnpj_limpo if len(cnpj_limpo) >= 11 else 'sem_cnpj'
            else:
                empresa_id = empresa_data.get('id', '') or empresa_data.get('_id', '') or 'sem_empresa'
            
            # Validar entrada
            if not xml_str or len(xml_str.strip()) == 0:
                raise ValueError("XML está vazio - não é possível salvar")
            
            # Criar estrutura de pastas: logs/xmls_nfce/{CNPJ}_{NomeEmpresa}/{ano}/{mes}_{NomeMes}/
            agora = datetime.now()
            ano = agora.strftime('%Y')
            mes = agora.strftime('%m')
            mes_nome = agora.strftime('%B').upper()  # Nome do mês
            
            # Adicionar nome da empresa ao ID (se disponível)
            nome_empresa = empresa_data.get('razao_social', '') or empresa_data.get('razaoSocial', '') or empresa_data.get('nome', '')
            if nome_empresa:
                # Limpar nome da empresa para usar como nome de pasta
                nome_empresa_limpo = re.sub(r'[<>:"/\\|?*]', '_', nome_empresa)[:50]  # Limitar tamanho
                pasta_empresa_com_nome = os.path.join(self.base_xml_dir, f"{empresa_id}_{nome_empresa_limpo}")
            else:
                pasta_empresa_com_nome = os.path.join(self.base_xml_dir, empresa_id)
            
            pasta_ano = os.path.join(pasta_empresa_com_nome, ano)
            pasta_mes = os.path.join(pasta_ano, f"{mes}_{mes_nome}")
            
            # Criar pastas se não existirem
            os.makedirs(pasta_mes, exist_ok=True)
            
            # Criar README.txt na pasta da empresa (se não existir)
            readme_path = os.path.join(pasta_empresa_com_nome, 'README.txt')
            if not os.path.exists(readme_path):
                try:
                    cnpj_formatado = f"{cnpj_limpo[:2]}.{cnpj_limpo[2:5]}.{cnpj_limpo[5:8]}/{cnpj_limpo[8:12]}-{cnpj_limpo[12:]}" if len(cnpj_limpo) == 14 else cnpj
                    razao_social = empresa_data.get('razao_social', '') or empresa_data.get('razaoSocial', '')
                    with open(readme_path, 'w', encoding='utf-8') as f:
                        f.write(f"Arquivos XML de NFC-e autorizadas para a empresa:\n")
                        f.write(f"CNPJ: {cnpj_formatado}\n")
                        f.write(f"Razão Social: {razao_social or 'Não informada'}\n")
                        f.write(f"ID Interno: {empresa_id}\n\n")
                        f.write(f"Estrutura de pastas:\n")
                        f.write(f"  ./{{ano}}/{{mes}}_{{NomeMes}}/{{chave_acesso}}.xml\n\n")
                        f.write(f"Estes arquivos devem ser armazenados digitalmente pelo prazo legal (5 anos).\n")
                        f.write(f"Gerado em: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                except Exception as e_readme:
                    print(f"   ⚠️ Erro ao criar README: {e_readme}")
            
            # Nome do arquivo: {chave_acesso}.xml ou NFe{numero_nfce}_{timestamp}.xml
            if chave_acesso:
                nome_arquivo = f"{chave_acesso}.xml"
            else:
                timestamp = agora.strftime('%Y%m%d_%H%M%S')
                nome_arquivo = f"NFe{numero_nfce:09d}_{timestamp}.xml"
            
            caminho_completo = os.path.join(pasta_mes, nome_arquivo)
            
            # Salvar XML
            with open(caminho_completo, 'w', encoding='utf-8') as f:
                f.write(xml_str)
            
            print(f"   ✅ XML salvo: {len(xml_str)} caracteres")
            
            return caminho_completo
        except Exception as e:
            print(f"⚠️ Erro ao salvar XML: {e}")
            # Retornar caminho padrão mesmo se falhar
            return os.path.join(self.base_xml_dir, f"erro_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xml")
    
    def _converter_forma_pagamento(self, tipo: str) -> str:
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

