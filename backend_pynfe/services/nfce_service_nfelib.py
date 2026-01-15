"""
Serviço de NFC-e usando nfelib
Gera XML correto automaticamente a partir dos XSDs oficiais da SEFAZ
Sem problemas de SOAP, prefixos ou schema
"""

import os
import sys
from datetime import datetime
from decimal import Decimal
import re

# Adicionar diretório raiz ao path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
    from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
    from lxml import etree
    import requests
    from signxml import XMLSigner
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.hazmat.backends import default_backend
    import base64
    print("[OK] nfelib e dependencias importadas com sucesso")
except ImportError as e:
    print(f"❌ Erro ao importar dependências: {e}")
    print("Execute: pip install nfelib signxml cryptography")
    raise


class NFCeServiceNfelib:
    """
    Serviço para emissão de NFC-e usando nfelib
    Gera XML correto automaticamente, validado pelo schema da SEFAZ
    """
    
    def __init__(self):
        self.debug = True
    
    def debug_print(self, message):
        """Print de debug"""
        if self.debug:
            print(message)
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e usando nfelib
        
        Args:
            data: Dicionário com dados da NFC-e:
                - empresa_data: dados da empresa
                - produtos: lista de produtos
                - pagamentos: lista de pagamentos
                - ambiente_homologacao: bool
                - certificado: dados do certificado
                - etc.
        
        Returns:
            dict com resultado da emissão
        """
        try:
            self.debug_print("=" * 60)
            self.debug_print(">>> [nfelib] Iniciando emissão de NFC-e")
            self.debug_print("=" * 60)
            
            # Extrair dados
            empresa_data = data.get('empresa', {})
            produtos_data = data.get('produtos', [])
            pagamentos_data = data.get('pagamentos', [])
            ambiente_homologacao = data.get('ambiente_homologacao', True)
            certificado_data = data.get('certificado', {})
            
            # 1. Criar estrutura enviNFe
            self.debug_print(">>> [nfelib] Criando estrutura enviNFe...")
            envi_nfe_obj = envi_nfe.TEnviNfe()
            envi_nfe_obj.versao = "4.00"
            envi_nfe_obj.id_lote = "000000000000001"  # 15 dígitos obrigatório
            envi_nfe_obj.ind_sinc = 1  # 1 = síncrono (obrigatório para NFC-e)
            
            # 2. Criar NFe
            self.debug_print(">>> [nfelib] Criando estrutura NFe...")
            nfe_obj = nfe.TNfe()
            nfe_obj.inf_nfe = nfe.TInfNfe()
            nfe_obj.inf_nfe.versao = "4.00"
            
            # Gerar chave de acesso (será usado no Id)
            numero_nfce = data.get('numero', '1')
            serie = data.get('serie', '1')
            cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
            uf = empresa_data.get('uf', 'SP')
            codigo_uf = self._obter_codigo_uf(uf)
            data_emissao = datetime.now()
            codigo_numerico = self._gerar_codigo_numerico()
            
            # Gerar chave de acesso (44 dígitos)
            chave_acesso = self._gerar_chave_acesso(
                codigo_uf, codigo_numerico, numero_nfce, serie,
                data_emissao, cnpj
            )
            
            # Id da NFe
            nfe_obj.inf_nfe.id = f"NFe{chave_acesso}"
            
            # 3. Preencher ide
            self.debug_print(">>> [nfelib] Preenchendo ide...")
            nfe_obj.inf_nfe.ide = nfe.TIde()
            nfe_obj.inf_nfe.ide.c_uf = codigo_uf
            nfe_obj.inf_nfe.ide.c_nf = self._gerar_codigo_numerico_8_digitos()
            nfe_obj.inf_nfe.ide.nat_op = data.get('natureza_operacao', 'VENDA')
            nfe_obj.inf_nfe.ide.mod = 65  # NFC-e
            nfe_obj.inf_nfe.ide.serie = int(serie) if serie.isdigit() else 1
            nfe_obj.inf_nfe.ide.n_nf = int(numero_nfce) if numero_nfce.isdigit() else 1
            nfe_obj.inf_nfe.ide.dh_emi = data_emissao
            nfe_obj.inf_nfe.ide.tp_nf = 1  # 1 = Saída
            nfe_obj.inf_nfe.ide.id_dest = 1  # 1 = Operação interna
            nfe_obj.inf_nfe.ide.c_mun_fg = int(empresa_data.get('codigo_ibge', '3549904'))
            nfe_obj.inf_nfe.ide.tp_imp = 4  # 4 = NFC-e
            nfe_obj.inf_nfe.ide.tp_emis = 1  # 1 = Normal
            nfe_obj.inf_nfe.ide.c_dv = int(chave_acesso[-1])
            nfe_obj.inf_nfe.ide.tp_amb = 2 if ambiente_homologacao else 1
            nfe_obj.inf_nfe.ide.fin_nfe = 1  # 1 = Normal
            nfe_obj.inf_nfe.ide.ind_final = 1  # 1 = Sim (consumidor final)
            nfe_obj.inf_nfe.ide.ind_pres = 1  # 1 = Presencial
            nfe_obj.inf_nfe.ide.proc_emi = 0  # 0 = Aplicativo do contribuinte
            nfe_obj.inf_nfe.ide.ver_proc = "Sistema Exodo"
            
            # 4. Preencher emitente
            self.debug_print(">>> [nfelib] Preenchendo emitente...")
            nfe_obj.inf_nfe.emit = nfe.TEmit()
            nfe_obj.inf_nfe.emit.cnpj = cnpj
            nfe_obj.inf_nfe.emit.x_nome = empresa_data.get('razao_social', '')
            nfe_obj.inf_nfe.emit.x_fant = empresa_data.get('nome_fantasia', '')
            
            # Endereço emitente
            nfe_obj.inf_nfe.emit.ender_emit = nfe.TEndeEmi()
            nfe_obj.inf_nfe.emit.ender_emit.x_lgr = empresa_data.get('logradouro', '')
            nfe_obj.inf_nfe.emit.ender_emit.nro = empresa_data.get('numero', '')
            nfe_obj.inf_nfe.emit.ender_emit.x_bairro = empresa_data.get('bairro', '')
            nfe_obj.inf_nfe.emit.ender_emit.c_mun = int(empresa_data.get('codigo_ibge', '3549904'))
            nfe_obj.inf_nfe.emit.ender_emit.x_mun = empresa_data.get('cidade', 'Sao Jose dos Campos')
            nfe_obj.inf_nfe.emit.ender_emit.uf = empresa_data.get('uf', 'SP')
            nfe_obj.inf_nfe.emit.ender_emit.cep = empresa_data.get('cep', '').replace('-', '')
            nfe_obj.inf_nfe.emit.ender_emit.c_pais = 1058  # Brasil
            nfe_obj.inf_nfe.emit.ender_emit.x_pais = "Brasil"
            
            nfe_obj.inf_nfe.emit.ie = empresa_data.get('inscricao_estadual', '')
            nfe_obj.inf_nfe.emit.crt = int(empresa_data.get('crt', '1'))  # 1 = Simples Nacional
            
            # 5. Preencher destinatário (opcional para NFC-e)
            if data.get('cpf_consumidor') or data.get('nome_consumidor'):
                self.debug_print(">>> [nfelib] Preenchendo destinatário...")
                nfe_obj.inf_nfe.dest = nfe.TDest()
                if data.get('cpf_consumidor'):
                    nfe_obj.inf_nfe.dest.cpf = data.get('cpf_consumidor').replace('.', '').replace('-', '')
                if data.get('nome_consumidor'):
                    nfe_obj.inf_nfe.dest.x_nome = data.get('nome_consumidor')
                nfe_obj.inf_nfe.dest.ind_ie_dest = 9  # 9 = Não contribuinte
            
            # 6. Preencher produtos
            self.debug_print(f">>> [nfelib] Preenchendo {len(produtos_data)} produtos...")
            nfe_obj.inf_nfe.det = []
            valor_total_produtos = Decimal('0.00')
            
            for idx, produto in enumerate(produtos_data, 1):
                det = nfe.TDet()
                det.n_item = idx
                
                # Produto
                det.prod = nfe.TProd()
                det.prod.c_prod = produto.get('codigo', f'PROD-{idx}')
                det.prod.c_ean = produto.get('ean', 'SEM GTIN')
                det.prod.x_prod = produto.get('descricao', '')
                det.prod.ncm = produto.get('ncm', '00000000')
                det.prod.cfop = produto.get('cfop', '5405')
                det.prod.u_com = produto.get('unidade', 'UN')
                det.prod.q_com = Decimal(str(produto.get('quantidade', 1)))
                det.prod.v_un_com = Decimal(str(produto.get('valor_unitario', 0)))
                det.prod.v_prod = Decimal(str(produto.get('valor_total', 0)))
                det.prod.c_ean_trib = produto.get('ean', 'SEM GTIN')
                det.prod.u_trib = produto.get('unidade', 'UN')
                det.prod.q_trib = Decimal(str(produto.get('quantidade', 1)))
                det.prod.v_un_trib = Decimal(str(produto.get('valor_unitario', 0)))
                det.prod.ind_tot = 1  # 1 = Valor total do item compõe valor total da NF-e
                
                # Impostos
                det.imposto = nfe.TImp()
                det.imposto.v_tot_trib = Decimal(str(produto.get('valor_impostos', 0)))
                
                # ICMS
                det.imposto.icms = nfe.TIcms()
                icms_item = nfe.TIcmssn500()  # Simples Nacional - ICMS cobrado anteriormente por substituição tributária
                icms_item.orig = 0
                icms_item.csosn = produto.get('csosn', '500')
                det.imposto.icms.icmssn500 = icms_item
                
                # PIS
                det.imposto.pis = nfe.TPis()
                pis_item = nfe.TPisOutr()
                pis_item.cst = "99"
                pis_item.v_bc = Decimal('0.00')
                pis_item.p_pis = Decimal('0.00')
                pis_item.v_pis = Decimal('0.00')
                det.imposto.pis.pis_outr = pis_item
                
                # COFINS
                det.imposto.cofins = nfe.TCofins()
                cofins_item = nfe.TCofinsOutr()
                cofins_item.cst = "99"
                cofins_item.v_bc = Decimal('0.00')
                cofins_item.p_cofins = Decimal('0.00')
                cofins_item.v_cofins = Decimal('0.00')
                det.imposto.cofins.cofins_outr = cofins_item
                
                nfe_obj.inf_nfe.det.append(det)
                valor_total_produtos += Decimal(str(produto.get('valor_total', 0)))
            
            # 7. Preencher totais
            self.debug_print(">>> [nfelib] Preenchendo totais...")
            nfe_obj.inf_nfe.total = nfe.TTotal()
            nfe_obj.inf_nfe.total.icms_tot = nfe.TIcmsTot()
            nfe_obj.inf_nfe.total.icms_tot.v_bc = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_icms = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_icms_deson = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_fcp = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_bcst = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_st = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_fcpst = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_prod = valor_total_produtos
            nfe_obj.inf_nfe.total.icms_tot.v_frete = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_seg = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_desc = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_ii = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_ipi = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_ipi_devol = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_pis = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_cofins = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_outro = Decimal('0.00')
            nfe_obj.inf_nfe.total.icms_tot.v_nf = valor_total_produtos
            
            # 8. Transporte
            self.debug_print(">>> [nfelib] Preenchendo transporte...")
            nfe_obj.inf_nfe.transp = nfe.TTransp()
            nfe_obj.inf_nfe.transp.mod_frete = 9  # 9 = Sem frete
            
            # 9. Pagamento
            self.debug_print(">>> [nfelib] Preenchendo pagamento...")
            nfe_obj.inf_nfe.pag = nfe.TPag()
            nfe_obj.inf_nfe.pag.det_pag = []
            
            for pagamento in pagamentos_data:
                det_pag = nfe.TDetPag()
                det_pag.ind_pag = 0  # 0 = Pagamento à vista
                det_pag.t_pag = pagamento.get('tipo', '01')  # 01 = Dinheiro
                det_pag.v_pag = Decimal(str(pagamento.get('valor', 0)))
                if pagamento.get('descricao'):
                    det_pag.x_pag = pagamento.get('descricao')
                nfe_obj.inf_nfe.pag.det_pag.append(det_pag)
            
            # 10. Informações adicionais (opcional)
            if data.get('observacoes'):
                self.debug_print(">>> [nfelib] Adicionando informações adicionais...")
                nfe_obj.inf_nfe.inf_adic = nfe.TInfAdic()
                nfe_obj.inf_nfe.inf_adic.inf_cpl = f"NFC-e emitida pelo Sistema Exodo\n{data.get('observacoes', '')}"
            
            # 11. Adicionar NFe ao enviNFe
            envi_nfe_obj.nfe = [nfe_obj]
            
            # 12. Gerar XML do enviNFe (já está correto, sem SOAP, sem prefixos)
            self.debug_print(">>> [nfelib] Gerando XML do enviNFe...")
            xml_str = envi_nfe_obj.to_xml(pretty_print=False)
            
            # Salvar XML gerado (para debug)
            try:
                empresa_dir = self._obter_diretorio_empresa(empresa_data)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                xml_file = os.path.join(empresa_dir, f'enviNFe_nfelib_{timestamp}.xml')
                os.makedirs(empresa_dir, exist_ok=True)
                with open(xml_file, 'w', encoding='utf-8') as f:
                    f.write(xml_str)
                self.debug_print(f">>> [nfelib] XML gerado salvo em: {xml_file}")
            except Exception as e:
                self.debug_print(f">>> [nfelib] ⚠️ Erro ao salvar XML: {e}")
            
            # 13. Assinar XML
            self.debug_print(">>> [nfelib] Assinando XML...")
            xml_assinado = self._assinar_xml(xml_str, certificado_data, chave_acesso)
            
            # 14. Enviar para SEFAZ
            self.debug_print(">>> [nfelib] Enviando para SEFAZ...")
            resposta = self._enviar_para_sefaz(xml_assinado, ambiente_homologacao, uf)
            
            return resposta
            
        except Exception as e:
            self.debug_print(f">>> [nfelib] ❌ ERRO: {e}")
            import traceback
            self.debug_print(traceback.format_exc())
            return {
                'success': False,
                'error': str(e),
                'autorizada': False
            }
    
    def _obter_codigo_uf(self, uf):
        """Obtém código da UF"""
        codigos = {
            'AC': 12, 'AL': 27, 'AP': 16, 'AM': 13, 'BA': 29,
            'CE': 23, 'DF': 53, 'ES': 32, 'GO': 52, 'MA': 21,
            'MT': 51, 'MS': 50, 'MG': 31, 'PA': 15, 'PB': 25,
            'PR': 41, 'PE': 26, 'PI': 22, 'RJ': 33, 'RN': 24,
            'RS': 43, 'RO': 11, 'RR': 14, 'SC': 42, 'SP': 35,
            'SE': 28, 'TO': 17
        }
        return codigos.get(uf.upper(), 35)
    
    def _gerar_codigo_numerico(self):
        """Gera código numérico de 8 dígitos"""
        import random
        return str(random.randint(10000000, 99999999))
    
    def _gerar_codigo_numerico_8_digitos(self):
        """Gera código numérico de 8 dígitos para cNF"""
        import random
        return str(random.randint(10000000, 99999999))
    
    def _gerar_chave_acesso(self, codigo_uf, codigo_numerico, numero, serie, data_emissao, cnpj):
        """Gera chave de acesso de 44 dígitos"""
        # Formato: cUF (2) + AAMM (4) + CNPJ (14) + mod (2) + serie (3) + nNF (9) + tpEmis (1) + cNF (8) + cDV (1)
        aamm = data_emissao.strftime('%y%m')
        mod = '65'  # NFC-e
        serie_formatada = str(serie).zfill(3)
        n_nf_formatado = str(numero).zfill(9)
        tp_emis = '1'  # Normal
        c_nf = codigo_numerico[:8].zfill(8)
        
        chave_43 = f"{codigo_uf:02d}{aamm}{cnpj}{mod}{serie_formatada}{n_nf_formatado}{tp_emis}{c_nf}"
        
        # Calcular dígito verificador
        multiplicadores = [2, 3, 4, 5, 6, 7, 8, 9]
        soma = 0
        for i, digito in enumerate(reversed(chave_43)):
            soma += int(digito) * multiplicadores[i % len(multiplicadores)]
        resto = soma % 11
        dv = 0 if resto < 2 else 11 - resto
        
        return f"{chave_43}{dv}"
    
    def _assinar_xml(self, xml_str, certificado_data, chave_acesso):
        """Assina XML com certificado digital"""
        try:
            # Carregar certificado
            if certificado_data.get('arquivo'):
                cert_path = certificado_data['arquivo']
                cert_password = certificado_data.get('senha', '').encode()
                
                # Ler certificado
                with open(cert_path, 'rb') as f:
                    cert_data = f.read()
                
                # Carregar certificado PKCS12
                private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
                    cert_data, cert_password, backend=default_backend()
                )
                
                # Assinar XML
                signer = XMLSigner(
                    method=XMLSigner.RSA_SHA1,
                    signature_algorithm='rsa-sha1',
                    digest_algorithm='sha1',
                    c14n_algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
                )
                
                root = etree.fromstring(xml_str.encode('utf-8'))
                
                # Encontrar elemento NFe para assinar
                nfe_elem = root.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                if nfe_elem is None:
                    nfe_elem = root.find('.//NFe')
                
                if nfe_elem is None:
                    raise ValueError("Elemento NFe não encontrado para assinatura")
                
                # Assinar
                signed_root = signer.sign(nfe_elem, key=private_key, cert=certificate)
                
                # Substituir NFe no enviNFe
                if root.tag.endswith('enviNFe'):
                    # Remover NFe antiga
                    for child in list(root):
                        if child.tag.endswith('NFe'):
                            root.remove(child)
                    # Adicionar NFe assinada
                    root.append(signed_root)
                
                xml_assinado = etree.tostring(root, encoding='unicode', xml_declaration=False)
                
                self.debug_print(">>> [nfelib] ✅ XML assinado com sucesso")
                return xml_assinado
            else:
                raise ValueError("Certificado não fornecido")
                
        except Exception as e:
            self.debug_print(f">>> [nfelib] ❌ Erro ao assinar XML: {e}")
            raise
    
    def _enviar_para_sefaz(self, xml_assinado, ambiente_homologacao, uf):
        """Envia XML para SEFAZ"""
        try:
            # URL do webservice
            if uf == 'SP':
                if ambiente_homologacao:
                    url = "https://homologacao.nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx"
            else:
                # Outros estados - usar SVRS
                if ambiente_homologacao:
                    url = "https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
            
            # Montar envelope SOAP (apenas para envio, nfelib gera o XML correto)
            soap_envelope = f"""<?xml version="1.0" encoding="UTF-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <nfeAutorizacaoLote xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
      <nfeDadosMsg>{self._escape_xml(xml_assinado)}</nfeDadosMsg>
    </nfeAutorizacaoLote>
  </soap12:Body>
</soap12:Envelope>"""
            
            headers = {
                'Content-Type': 'application/soap+xml; charset=utf-8',
                'SOAPAction': 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote'
            }
            
            response = requests.post(url, data=soap_envelope.encode('utf-8'), headers=headers, timeout=30)
            
            self.debug_print(f">>> [nfelib] Resposta SEFAZ: {response.status_code}")
            
            if response.status_code == 200:
                # Processar resposta
                return self._processar_resposta_sefaz(response.text, ambiente_homologacao)
            else:
                return {
                    'success': False,
                    'error': f'Erro HTTP {response.status_code}',
                    'autorizada': False
                }
                
        except Exception as e:
            self.debug_print(f">>> [nfelib] ❌ Erro ao enviar para SEFAZ: {e}")
            return {
                'success': False,
                'error': str(e),
                'autorizada': False
            }
    
    def _escape_xml(self, xml_str):
        """Escapa XML para dentro do envelope SOAP"""
        return xml_str.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    
    def _processar_resposta_sefaz(self, xml_resposta, ambiente_homologacao):
        """Processa resposta da SEFAZ"""
        try:
            root = etree.fromstring(xml_resposta.encode('utf-8'))
            
            # Procurar retEnviNFe
            ret_envinfe = root.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
            if ret_envinfe is None:
                ret_envinfe = root.find('.//retEnviNFe')
            
            if ret_envinfe is not None:
                c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                if c_stat is None:
                    c_stat = ret_envinfe.find('.//cStat')
                
                x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                if x_motivo is None:
                    x_motivo = ret_envinfe.find('.//xMotivo')
                
                if c_stat is not None:
                    c_stat_valor = c_stat.text
                    
                    if c_stat_valor == '100':  # Autorizada
                        # Buscar protocolo
                        n_prot = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                        if n_prot is None:
                            n_prot = ret_envinfe.find('.//nProt')
                        
                        return {
                            'success': True,
                            'autorizada': True,
                            'cstat': c_stat_valor,
                            'motivo': x_motivo.text if x_motivo is not None else 'Autorizado',
                            'protocolo': n_prot.text if n_prot is not None else '',
                            'chave_acesso': '',  # Será preenchido
                            'numero': '',
                            'serie': '',
                            'qr_code': ''
                        }
                    else:
                        return {
                            'success': False,
                            'autorizada': False,
                            'cstat': c_stat_valor,
                            'motivo': x_motivo.text if x_motivo is not None else 'Rejeitada',
                            'error': f"cStat {c_stat_valor}: {x_motivo.text if x_motivo is not None else 'Rejeitada'}"
                        }
            
            return {
                'success': False,
                'autorizada': False,
                'error': 'Resposta da SEFAZ não reconhecida'
            }
            
        except Exception as e:
            self.debug_print(f">>> [nfelib] ❌ Erro ao processar resposta: {e}")
            return {
                'success': False,
                'autorizada': False,
                'error': f'Erro ao processar resposta: {str(e)}'
            }
    
    def _obter_diretorio_empresa(self, empresa_data=None):
        """Obtém diretório para salvar XMLs"""
        try:
            base_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'logs', 'empresas')
            
            if empresa_data:
                cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
                if cnpj:
                    return os.path.join(base_dir, cnpj)
            
            return os.path.join(base_dir, 'sem_empresa')
        except:
            return os.path.join(os.path.dirname(os.path.dirname(__file__)), 'logs', 'empresas', 'sem_empresa')

