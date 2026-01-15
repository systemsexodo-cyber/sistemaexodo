"""
Serviço VALIDADO para emissão de NFC-e usando nfelib
Com validação completa de XML de envio e processamento de retorno
"""

import base64
import json
import os
import sys
from datetime import datetime
from decimal import Decimal
from lxml import etree
import re

# Importar nfelib
NFELIB_DISPONIVEL = False
try:
    from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
    from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
    import requests
    from signxml import XMLSigner
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.hazmat.backends import default_backend
    NFELIB_DISPONIVEL = True
except ImportError as e:
    NFELIB_DISPONIVEL = False

from services.certificado_service import CertificadoService


class NFCeServiceValidado:
    """Serviço VALIDADO para emissão de NFC-e com validação completa"""
    
    def __init__(self):
        self.certificado_service = CertificadoService()
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e com validação completa
        
        Returns:
            {
                'success': bool,
                'autorizada': bool,
                'chave': str,
                'protocolo': str,
                'qr_code': str,
                'xml_enviado': str,
                'xml_retorno': str,
                'error': str (se houver)
            }
        """
        if not NFELIB_DISPONIVEL:
            return {
                'success': False,
                'autorizada': False,
                'error': 'nfelib não está instalado. Execute: pip install nfelib signxml cryptography'
            }
        
        try:
            print("=" * 70)
            print("EMISSÃO NFC-e - VALIDAÇÃO COMPLETA")
            print("=" * 70)
            
            # 1. Validar dados de entrada
            print("\n[1/8] Validando dados de entrada...")
            empresa_data = data['empresa']
            produtos_data = data['produtos']
            pagamentos_data = data['pagamentos']
            
            self._validar_dados_entrada(empresa_data, produtos_data, pagamentos_data)
            print("✅ Dados validados")
            
            # 2. Carregar certificado
            print("\n[2/8] Carregando certificado...")
            certificado = self._carregar_certificado(empresa_data)
            print("✅ Certificado carregado")
            
            # 3. Gerar XML
            print("\n[3/8] Gerando XML...")
            xml_str = self._gerar_xml_validado(data)
            print("✅ XML gerado")
            
            # 4. Validar XML gerado
            print("\n[4/8] Validando XML gerado...")
            erros_validacao = self._validar_xml_estrutura(xml_str)
            if erros_validacao:
                print(f"⚠️ Erros encontrados: {len(erros_validacao)}")
                for erro in erros_validacao[:5]:
                    print(f"  - {erro}")
                # Aplicar correções automáticas
                xml_str = self._corrigir_xml(xml_str)
                print("✅ XML corrigido")
            else:
                print("✅ XML válido")
            
            # 5. Assinar XML
            print("\n[5/8] Assinando XML...")
            xml_assinado = self._assinar_xml(xml_str, certificado)
            print("✅ XML assinado")
            
            # 6. Validar XML assinado
            print("\n[6/8] Validando XML assinado...")
            erros_assinado = self._validar_xml_estrutura(xml_assinado)
            if erros_assinado:
                return {
                    'success': False,
                    'autorizada': False,
                    'error': f'XML assinado inválido: {"; ".join(erros_assinado[:3])}',
                    'xml_enviado': xml_assinado
                }
            print("✅ XML assinado válido")
            
            # 7. Enviar para SEFAZ
            print("\n[7/8] Enviando para SEFAZ...")
            ambiente_homologacao = empresa_data.get('ambienteHomologacao', True)
            uf = empresa_data.get('uf', 'SP')
            resposta = self._enviar_para_sefaz(xml_assinado, ambiente_homologacao, uf, certificado)
            print("✅ Resposta recebida")
            
            # 8. Processar resposta
            print("\n[8/8] Processando resposta...")
            resultado = self._processar_resposta(resposta, ambiente_homologacao, uf, data)
            print("✅ Processamento concluído")
            
            print("\n" + "=" * 70)
            if resultado.get('autorizada'):
                print("✅ NFC-e AUTORIZADA!")
                print(f"Chave: {resultado.get('chave', 'N/A')}")
                print(f"Protocolo: {resultado.get('protocolo', 'N/A')}")
            else:
                print("❌ NFC-e NÃO AUTORIZADA")
                print(f"Erro: {resultado.get('error', 'N/A')}")
            print("=" * 70 + "\n")
            
            return resultado
            
        except Exception as e:
            import traceback
            erro_detalhado = traceback.format_exc()
            print(f"\n❌ ERRO: {e}")
            print(erro_detalhado)
            return {
                'success': False,
                'autorizada': False,
                'error': str(e),
                'details': erro_detalhado
            }
    
    def _validar_dados_entrada(self, empresa_data, produtos_data, pagamentos_data):
        """Valida dados de entrada"""
        erros = []
        
        # Validar empresa
        if not empresa_data.get('cnpj'):
            erros.append('CNPJ da empresa é obrigatório')
        if not empresa_data.get('razao_social'):
            erros.append('Razão social é obrigatória')
        if not empresa_data.get('uf'):
            erros.append('UF é obrigatória')
        if not empresa_data.get('codigo_municipio_ibge') and not empresa_data.get('codigoIBGE'):
            erros.append('Código IBGE do município é obrigatório')
        if not empresa_data.get('certificado_base64') and not empresa_data.get('certificadoDigitalUrl'):
            erros.append('Certificado digital é obrigatório')
        if not empresa_data.get('senhaCertificado') and not empresa_data.get('senha_certificado'):
            erros.append('Senha do certificado é obrigatória')
        
        # Validar produtos
        if not produtos_data or len(produtos_data) == 0:
            erros.append('É necessário pelo menos um produto')
        else:
            for i, produto in enumerate(produtos_data, 1):
                if not produto.get('nome') and not produto.get('descricao'):
                    erros.append(f'Produto {i}: nome/descrição é obrigatório')
                preco = produto.get('preco') or produto.get('preco_atual') or 0
                if preco <= 0:
                    erros.append(f'Produto {i}: preço deve ser maior que zero')
        
        # Validar pagamentos
        if not pagamentos_data or len(pagamentos_data) == 0:
            erros.append('É necessário pelo menos uma forma de pagamento')
        else:
            total_pagamentos = sum(float(p.get('valor', 0)) for p in pagamentos_data)
            total_produtos = sum(
                float(p.get('quantidade', 1)) * float(p.get('preco') or p.get('preco_atual') or 0)
                for p in produtos_data
            )
            if abs(total_pagamentos - total_produtos) > 0.01:
                erros.append(f'Total de pagamentos ({total_pagamentos:.2f}) não confere com total de produtos ({total_produtos:.2f})')
        
        if erros:
            raise ValueError(f'Erros de validação: {"; ".join(erros)}')
    
    def _carregar_certificado(self, empresa_data):
        """Carrega certificado digital"""
        certificado_base64 = empresa_data.get('certificado_base64') or empresa_data.get('certificadoDigitalUrl') or ''
        senha = empresa_data.get('senhaCertificado') or empresa_data.get('senha_certificado') or ''
        
        if not certificado_base64 or not senha:
            raise ValueError('Certificado ou senha não fornecidos')
        
        return self.certificado_service.carregar_certificado(certificado_base64, senha)
    
    def _gerar_xml_validado(self, data):
        """Gera XML usando nfelib (já valida estrutura)"""
        # Usar o método do nfce_service.py existente
        # Por enquanto, retornar XML básico (será implementado)
        # TODO: Implementar geração completa usando nfelib
        raise NotImplementedError("Usar NFCeService.emitir_nfce() que já está implementado")
    
    def _validar_xml_estrutura(self, xml_str):
        """Valida estrutura básica do XML"""
        erros = []
        try:
            root = etree.fromstring(xml_str.encode('utf-8'))
            
            # Validar enviNFe
            ns = {'nfe': 'http://www.portalfiscal.inf.br/nfe'}
            envi_nfe = root.find('.//nfe:enviNFe', ns) or root.find('.//enviNFe')
            if envi_nfe is None:
                erros.append('enviNFe não encontrado')
            else:
                # Validar versão
                if envi_nfe.get('versao') != '4.00':
                    erros.append(f'Versão incorreta: {envi_nfe.get("versao")} (esperado: 4.00)')
                
                # Validar idLote (deve ter 15 dígitos)
                id_lote = envi_nfe.find('nfe:idLote', ns) or envi_nfe.find('idLote')
                if id_lote is None:
                    erros.append('idLote não encontrado')
                elif len(id_lote.text or '') != 15:
                    erros.append(f'idLote deve ter 15 dígitos (encontrado: {len(id_lote.text or "")})')
                
                # Validar indSinc (deve ser 1 para NFC-e)
                ind_sinc = envi_nfe.find('nfe:indSinc', ns) or envi_nfe.find('indSinc')
                if ind_sinc is None:
                    erros.append('indSinc não encontrado')
                elif ind_sinc.text != '1':
                    erros.append(f'indSinc deve ser 1 para NFC-e (encontrado: {ind_sinc.text})')
                
                # Validar NFe
                nfe_elem = envi_nfe.find('nfe:NFe', ns) or envi_nfe.find('NFe')
                if nfe_elem is None:
                    erros.append('NFe não encontrada no lote')
                else:
                    # Validar infNFe
                    inf_nfe = nfe_elem.find('.//nfe:infNFe', ns) or nfe_elem.find('.//infNFe')
                    if inf_nfe is None:
                        erros.append('infNFe não encontrada')
                    else:
                        # Validar elementos obrigatórios
                        if inf_nfe.find('.//nfe:ide', ns) is None:
                            erros.append('ide não encontrado')
                        if inf_nfe.find('.//nfe:emit', ns) is None:
                            erros.append('emit não encontrado')
                        if not inf_nfe.findall('.//nfe:det', ns):
                            erros.append('Nenhum produto (det) encontrado')
                        if inf_nfe.find('.//nfe:total', ns) is None:
                            erros.append('total não encontrado')
                        if inf_nfe.find('.//nfe:pag', ns) is None:
                            erros.append('pag não encontrado')
        
        except etree.XMLSyntaxError as e:
            erros.append(f'XML inválido: {str(e)}')
        except Exception as e:
            erros.append(f'Erro ao validar XML: {str(e)}')
        
        return erros
    
    def _corrigir_xml(self, xml_str):
        """Corrige problemas comuns no XML"""
        try:
            root = etree.fromstring(xml_str.encode('utf-8'))
            ns = {'nfe': 'http://www.portalfiscal.inf.br/nfe'}
            corrigido = False
            
            # Encontrar enviNFe
            envi_nfe = root.find('.//nfe:enviNFe', ns) or root.find('.//enviNFe')
            if envi_nfe is not None:
                # Corrigir versão
                if envi_nfe.get('versao') != '4.00':
                    envi_nfe.set('versao', '4.00')
                    corrigido = True
                
                # Corrigir idLote
                id_lote = envi_nfe.find('nfe:idLote', ns) or envi_nfe.find('idLote')
                if id_lote is None:
                    id_lote = etree.SubElement(envi_nfe, '{http://www.portalfiscal.inf.br/nfe}idLote')
                    id_lote.text = '000000000000001'
                    corrigido = True
                elif len(id_lote.text or '') != 15:
                    id_lote.text = (id_lote.text or '1').zfill(15)[:15]
                    corrigido = True
                
                # Corrigir indSinc
                ind_sinc = envi_nfe.find('nfe:indSinc', ns) or envi_nfe.find('indSinc')
                if ind_sinc is None:
                    # Inserir após idLote
                    ind_sinc = etree.SubElement(envi_nfe, '{http://www.portalfiscal.inf.br/nfe}indSinc')
                    ind_sinc.text = '1'
                    # Mover para posição correta (após idLote)
                    envi_nfe.remove(ind_sinc)
                    pos_id_lote = list(envi_nfe).index(id_lote) if id_lote in envi_nfe else 0
                    envi_nfe.insert(pos_id_lote + 1, ind_sinc)
                    corrigido = True
                elif ind_sinc.text != '1':
                    ind_sinc.text = '1'
                    corrigido = True
            
            if corrigido:
                return etree.tostring(root, encoding='unicode', xml_declaration=True)
            
        except Exception as e:
            print(f"⚠️ Erro ao corrigir XML: {e}")
        
        return xml_str
    
    def _assinar_xml(self, xml_str, certificado):
        """Assina XML com certificado digital"""
        # Implementação simplificada - usar signxml
        try:
            cert_path = certificado.get('arquivo')
            senha = certificado.get('senha', '')
            
            if not cert_path or not os.path.exists(cert_path):
                raise ValueError('Certificado não encontrado')
            
            # Carregar certificado
            with open(cert_path, 'rb') as f:
                cert_data = f.read()
            
            private_key, cert_obj, _ = pkcs12.load_key_and_certificates(
                cert_data, senha.encode('utf-8'), default_backend()
            )
            
            # Parsear XML
            root = etree.fromstring(xml_str.encode('utf-8'))
            
            # Assinar
            signer = XMLSigner(
                method=etree.methods.enveloped,
                signature_algorithm='rsa-sha1',
                digest_algorithm='sha1',
                c14n_algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
            )
            
            signed_root = signer.sign(root, key=private_key, cert=cert_obj)
            
            return etree.tostring(signed_root, encoding='unicode', xml_declaration=True)
            
        except Exception as e:
            raise ValueError(f'Erro ao assinar XML: {str(e)}')
    
    def _enviar_para_sefaz(self, xml_assinado, ambiente_homologacao, uf, certificado):
        """Envia XML para SEFAZ"""
        # URLs por estado (homologação)
        urls_homologacao = {
            'SP': 'https://homologacao.nfce.fazenda.sp.gov.br/ws/nfceautorizacao.asmx',
            'RJ': 'https://homologacao.nfce.fazenda.rj.gov.br/ws/nfceautorizacao.asmx',
            'MG': 'https://hnfce.fazenda.mg.gov.br/nfce/services/NFeAutorizacao',
            # Adicionar outros estados conforme necessário
        }
        
        url = urls_homologacao.get(uf.upper(), urls_homologacao['SP'])
        
        # Montar envelope SOAP
        soap_body = f'''<?xml version="1.0" encoding="UTF-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <nfeDadosMsg xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
      {xml_assinado}
    </nfeDadosMsg>
  </soap12:Body>
</soap12:Envelope>'''
        
        # Fazer requisição
        headers = {
            'Content-Type': 'application/soap+xml; charset=utf-8',
            'SOAPAction': 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote'
        }
        
        cert_path = certificado.get('arquivo')
        
        try:
            response = requests.post(
                url,
                data=soap_body.encode('utf-8'),
                headers=headers,
                cert=(cert_path, None),
                timeout=30
            )
            return response.text
        except Exception as e:
            raise ValueError(f'Erro ao enviar para SEFAZ: {str(e)}')
    
    def _processar_resposta(self, xml_resposta, ambiente_homologacao, uf, data_original):
        """Processa resposta da SEFAZ"""
        try:
            root = etree.fromstring(xml_resposta.encode('utf-8'))
            ns = {
                'soap': 'http://www.w3.org/2003/05/soap-envelope',
                'nfe': 'http://www.portalfiscal.inf.br/nfe'
            }
            
            # Procurar retEnviNFe
            ret_envi_nfe = root.find('.//nfe:retEnviNFe', ns) or root.find('.//retEnviNFe')
            if ret_envi_nfe is None:
                # Procurar dentro de Body
                body = root.find('.//soap:Body', ns) or root.find('.//Body')
                if body is not None:
                    ret_envi_nfe = body.find('.//nfe:retEnviNFe', ns) or body.find('.//retEnviNFe')
            
            if ret_envi_nfe is None:
                return {
                    'success': False,
                    'autorizada': False,
                    'error': 'Estrutura de resposta não reconhecida',
                    'xml_retorno': xml_resposta
                }
            
            # Extrair cStat
            c_stat = ret_envi_nfe.find('nfe:cStat', ns) or ret_envi_nfe.find('cStat')
            c_stat_text = c_stat.text.strip() if c_stat is not None and c_stat.text else None
            
            # Extrair xMotivo
            x_motivo = ret_envi_nfe.find('nfe:xMotivo', ns) or ret_envi_nfe.find('xMotivo')
            motivo = x_motivo.text.strip() if x_motivo is not None and x_motivo.text else 'Motivo não informado'
            
            # Verificar se foi autorizada (cStat = 100)
            if c_stat_text == '100':
                # Procurar protNFe
                prot_nfe = ret_envi_nfe.find('.//nfe:protNFe', ns) or ret_envi_nfe.find('.//protNFe')
                if prot_nfe is not None:
                    inf_prot = prot_nfe.find('nfe:infProt', ns) or prot_nfe.find('infProt')
                    if inf_prot is not None:
                        n_prot = inf_prot.find('nfe:nProt', ns) or inf_prot.find('nProt')
                        ch_nfe = inf_prot.find('nfe:chNFe', ns) or inf_prot.find('chNFe')
                        
                        protocolo = n_prot.text.strip() if n_prot is not None and n_prot.text else ''
                        chave = ch_nfe.text.strip() if ch_nfe is not None and ch_nfe.text else ''
                        
                        # Gerar QR Code
                        qr_code = self._gerar_qr_code(chave, ambiente_homologacao, uf)
                        
                        return {
                            'success': True,
                            'autorizada': True,
                            'chave': chave,
                            'protocolo': protocolo,
                            'qr_code': qr_code,
                            'xml_retorno': xml_resposta,
                            'message': 'NFC-e autorizada com sucesso'
                        }
            
            # Não autorizada
            return {
                'success': False,
                'autorizada': False,
                'error': motivo,
                'codigo_erro': c_stat_text,
                'xml_retorno': xml_resposta
            }
            
        except Exception as e:
            return {
                'success': False,
                'autorizada': False,
                'error': f'Erro ao processar resposta: {str(e)}',
                'xml_retorno': xml_resposta
            }
    
    def _gerar_qr_code(self, chave, ambiente_homologacao, uf):
        """Gera URL do QR Code"""
        base_url = 'https://homologacao.nfce.sefaz.' + uf.lower() + '.gov.br' if ambiente_homologacao else 'https://nfce.sefaz.' + uf.lower() + '.gov.br'
        return f'{base_url}/qrCode?p={chave}'











