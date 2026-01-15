"""
Serviço MANUAL para emissão de NFC-e
100% LOCAL - gera XML, assina e envia para SEFAZ sem APIs de terceiros
"""

import os
import base64
import tempfile
from datetime import datetime
from decimal import Decimal
from lxml import etree
import random
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.backends import default_backend
from cryptography import x509
import zeep
from zeep.wsse import BinarySignature


class NFCeServiceManual:
    """Serviço manual para emissão de NFC-e - tudo no código, sem APIs"""
    
    def __init__(self):
        pass
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e manualmente (100% local, sem APIs)
        
        Args:
            data: Dicionário com dados da NFC-e
        
        Returns:
            Dicionário com resultado da emissão
        """
        try:
            empresa_data = data.get('empresa', {})
            produtos = data.get('produtos', [])
            pagamentos = data.get('pagamentos', [])
            consumidor = data.get('consumidor', {})
            observacoes = data.get('observacoes', '')
            ambiente_homologacao = empresa_data.get('ambiente_homologacao', True)
            uf = empresa_data.get('uf', 'SP')
            
            print("=" * 60)
            print("EMISSÃO NFC-e MANUAL (100% LOCAL)")
            print("=" * 60)
            print(f"Ambiente: {'HOMOLOGAÇÃO' if ambiente_homologacao else 'PRODUÇÃO'}")
            print(f"CNPJ: {empresa_data.get('cnpj', 'N/A')}")
            print(f"UF: {uf}")
            print(f"Produtos: {len(produtos)}")
            print("=" * 60)
            
            # 1. Carregar certificado
            print("\n[1/5] Carregando certificado...")
            certificado, private_key = self._carregar_certificado(empresa_data)
            if not certificado or not private_key:
                return {
                    'success': False,
                    'error': 'Erro ao carregar certificado digital. Verifique a senha e o formato.',
                    'error_type': 'CertificateError'
                }
            print("✅ Certificado carregado")
            
            # 2. Gerar chave de acesso
            print("\n[2/5] Gerando chave de acesso...")
            chave_acesso = self._gerar_chave_acesso(empresa_data, produtos)
            print(f"✅ Chave: {chave_acesso}")
            
            # 3. Gerar XML da NFC-e
            print("\n[3/5] Gerando XML da NFC-e...")
            xml_nfce = self._gerar_xml_nfce(
                empresa_data, produtos, pagamentos, consumidor, observacoes, chave_acesso
            )
            if not xml_nfce:
                return {
                    'success': False,
                    'error': 'Erro ao gerar XML da NFC-e',
                    'error_type': 'XMLError'
                }
            print("✅ XML gerado")
            
            # 4. Assinar XML
            print("\n[4/5] Assinando XML...")
            xml_assinado = self._assinar_xml_manual(xml_nfce, certificado, private_key, chave_acesso)
            if not xml_assinado:
                return {
                    'success': False,
                    'error': 'Erro ao assinar XML',
                    'error_type': 'SignatureError'
                }
            print("✅ XML assinado")
            
            # 5. Enviar para SEFAZ
            print("\n[5/5] Enviando para SEFAZ...")
            resultado = self._enviar_sefaz_manual(xml_assinado, ambiente_homologacao, uf)
            
            print("\n" + "=" * 60)
            if resultado.get('success'):
                print("✅ NFC-e EMITIDA COM SUCESSO!")
            else:
                print("❌ ERRO NA EMISSÃO")
            print("=" * 60)
            
            return resultado
            
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            print(f"\n❌ ERRO: {str(e)}")
            print(f"\nDetalhes:\n{error_details}")
            
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e: {str(e)}',
                'error_type': 'UnexpectedError',
                'details': error_details
            }
    
    def _carregar_certificado(self, empresa_data):
        """Carrega certificado digital e retorna certificado e chave privada"""
        try:
            if 'certificado_base64' not in empresa_data:
                print("❌ Certificado não fornecido")
                return None, None
            
            cert_bytes = base64.b64decode(empresa_data['certificado_base64'])
            senha = empresa_data.get('senha_certificado', '').encode('utf-8')
            
            # Carregar PKCS12
            from cryptography.hazmat.primitives.serialization import pkcs12
            
            private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
                cert_bytes, senha, backend=default_backend()
            )
            
            if not certificate or not private_key:
                print("❌ Erro ao extrair certificado ou chave privada")
                return None, None
            
            print(f"✅ Certificado válido até: {certificate.not_valid_after}")
            return certificate, private_key
                
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            import traceback
            traceback.print_exc()
            return None, None
    
    def _gerar_chave_acesso(self, empresa_data, produtos):
        """Gera chave de acesso da NFC-e"""
        # Formato: UF (2) + AAMM (4) + CNPJ (14) + Modelo (2) + Série (3) + Número (9) + Tipo Emissão (1) + Código Numérico (8)
        # Para simplificar, vamos gerar uma chave básica
        cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
        uf = empresa_data.get('uf', 'SP')
        uf_codigo = self._get_uf_codigo(uf)
        
        # Data atual
        now = datetime.now()
        aamm = now.strftime('%y%m')
        
        # Número sequencial (simplificado - em produção deve vir de banco de dados)
        numero = str(empresa_data.get('numero_nfce', 1)).zfill(9)
        serie = str(empresa_data.get('serie_nfce', 1)).zfill(3)
        
        # Modelo NFC-e = 65
        modelo = '65'
        
        # Tipo emissão = 1 (Normal)
        tipo_emissao = '1'
        
        # Código numérico aleatório (8 dígitos)
        codigo_numerico = str(random.randint(10000000, 99999999))
        
        # Montar chave (sem dígito verificador ainda)
        chave_sem_dv = f"{uf_codigo}{aamm}{cnpj}{modelo}{serie}{numero}{tipo_emissao}{codigo_numerico}"
        
        # Calcular dígito verificador
        dv = self._calcular_dv_chave(chave_sem_dv)
        
        chave_completa = f"{chave_sem_dv}{dv}"
        
        return chave_completa
    
    def _get_uf_codigo(self, uf):
        """Retorna código da UF"""
        codigos = {
            'AC': '12', 'AL': '27', 'AP': '16', 'AM': '13', 'BA': '29',
            'CE': '23', 'DF': '53', 'ES': '32', 'GO': '52', 'MA': '21',
            'MT': '51', 'MS': '50', 'MG': '31', 'PA': '15', 'PB': '25',
            'PR': '41', 'PE': '26', 'PI': '22', 'RJ': '33', 'RN': '24',
            'RS': '43', 'RO': '11', 'RR': '14', 'SC': '42', 'SP': '35',
            'SE': '28', 'TO': '17'
        }
        return codigos.get(uf.upper(), '35')  # Default SP
    
    def _calcular_dv_chave(self, chave):
        """Calcula dígito verificador da chave de acesso"""
        multiplicadores = [4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        
        soma = 0
        for i, digito in enumerate(chave):
            soma += int(digito) * multiplicadores[i]
        
        resto = soma % 11
        if resto < 2:
            dv = 0
        else:
            dv = 11 - resto
        
        return str(dv)
    
    def _gerar_xml_nfce(self, empresa_data, produtos, pagamentos, consumidor, observacoes, chave_acesso):
        """Gera XML da NFC-e manualmente"""
        try:
            # Namespaces
            ns_nfe = 'http://www.portalfiscal.inf.br/nfe'
            ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
            
            # Criar elemento raiz
            root = etree.Element('{http://www.portalfiscal.inf.br/nfe}enviNFe', 
                                nsmap={'nfe': ns_nfe})
            root.set('versao', '4.00')
            
            # Criar elemento NFe
            nfe = etree.SubElement(root, f'{{{ns_nfe}}}NFe')
            nfe.set('versao', '4.00')
            
            # infNFe
            inf_nfe = etree.SubElement(nfe, f'{{{ns_nfe}}}infNFe')
            inf_nfe.set('Id', f'NFe{chave_acesso}')
            inf_nfe.set('versao', '4.00')
            
            # ide
            ide = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}ide')
            etree.SubElement(ide, f'{{{ns_nfe}}}cUF').text = self._get_uf_codigo(empresa_data.get('uf', 'SP'))
            etree.SubElement(ide, f'{{{ns_nfe}}}cNF').text = chave_acesso[-8:]  # Últimos 8 dígitos
            etree.SubElement(ide, f'{{{ns_nfe}}}natOp').text = 'VENDA'
            etree.SubElement(ide, f'{{{ns_nfe}}}mod').text = '65'  # NFC-e
            etree.SubElement(ide, f'{{{ns_nfe}}}serie').text = str(empresa_data.get('serie_nfce', 1))
            etree.SubElement(ide, f'{{{ns_nfe}}}nNF').text = str(empresa_data.get('numero_nfce', 1))
            
            now = datetime.now()
            etree.SubElement(ide, f'{{{ns_nfe}}}dhEmi').text = now.strftime('%Y-%m-%dT%H:%M:%S-03:00')
            etree.SubElement(ide, f'{{{ns_nfe}}}dhSaiEnt').text = now.strftime('%Y-%m-%dT%H:%M:%S-03:00')
            etree.SubElement(ide, f'{{{ns_nfe}}}tpNF').text = '1'  # 1=Saída
            etree.SubElement(ide, f'{{{ns_nfe}}}idDest').text = '1'  # 1=Operação interna
            etree.SubElement(ide, f'{{{ns_nfe}}}cMunFG').text = empresa_data.get('codigo_municipio_ibge', '3550308')
            etree.SubElement(ide, f'{{{ns_nfe}}}tpImp').text = '4'  # 4=DANFE NFC-e
            etree.SubElement(ide, f'{{{ns_nfe}}}tpEmis').text = '1'  # 1=Emissão normal
            etree.SubElement(ide, f'{{{ns_nfe}}}cDV').text = chave_acesso[-1]
            etree.SubElement(ide, f'{{{ns_nfe}}}tpAmb').text = '2' if empresa_data.get('ambiente_homologacao', True) else '1'
            etree.SubElement(ide, f'{{{ns_nfe}}}finNFe').text = '1'  # 1=Normal
            etree.SubElement(ide, f'{{{ns_nfe}}}indFinal').text = '1'  # 1=Consumidor final
            etree.SubElement(ide, f'{{{ns_nfe}}}indPres').text = '1'  # 1=Presencial
            
            # emit
            emit = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}emit')
            cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
            etree.SubElement(emit, f'{{{ns_nfe}}}CNPJ').text = cnpj
            etree.SubElement(emit, f'{{{ns_nfe}}}xNome').text = empresa_data.get('razao_social', '')
            etree.SubElement(emit, f'{{{ns_nfe}}}xFant').text = empresa_data.get('nome_fantasia', '')
            
            # enderEmit
            ender_emit = etree.SubElement(emit, f'{{{ns_nfe}}}enderEmit')
            endereco = empresa_data.get('endereco', {})
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}xLgr').text = endereco.get('logradouro', '')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}nro').text = endereco.get('numero', '')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}xBairro').text = endereco.get('bairro', '')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}cMun').text = empresa_data.get('codigo_municipio_ibge', '3550308')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}xMun').text = endereco.get('cidade', '')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}UF').text = empresa_data.get('uf', 'SP')
            cep = endereco.get('cep', '').replace('-', '')
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}CEP').text = cep
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}cPais').text = '1058'  # Brasil
            etree.SubElement(ender_emit, f'{{{ns_nfe}}}xPais').text = 'BRASIL'
            telefone = empresa_data.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', '')
            if telefone:
                etree.SubElement(ender_emit, f'{{{ns_nfe}}}fone').text = telefone
            
            etree.SubElement(emit, f'{{{ns_nfe}}}IE').text = empresa_data.get('inscricao_estadual', '')
            
            # CRT (Código de Regime Tributário)
            crt = empresa_data.get('crt', '3')  # 1=Simples, 2=Simples Excesso, 3=Normal
            etree.SubElement(emit, f'{{{ns_nfe}}}CRT').text = crt
            
            # dest (destinatário - consumidor final)
            dest = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}dest')
            if consumidor and consumidor.get('cpf'):
                cpf = consumidor.get('cpf', '').replace('.', '').replace('-', '')
                etree.SubElement(dest, f'{{{ns_nfe}}}CPF').text = cpf
            else:
                # Consumidor não identificado
                etree.SubElement(dest, f'{{{ns_nfe}}}indIEDest').text = '9'  # 9=Não contribuinte
            
            if consumidor and consumidor.get('nome'):
                etree.SubElement(dest, f'{{{ns_nfe}}}xNome').text = consumidor.get('nome', 'CONSUMIDOR FINAL')
            else:
                etree.SubElement(dest, f'{{{ns_nfe}}}xNome').text = 'CONSUMIDOR FINAL'
            
            # det (detalhes dos produtos)
            valor_total = Decimal('0.00')
            for produto in produtos:
                det = etree.SubElement(inf_nfe, f'{{{ns_nfe}}}det')
                det.set('nItem', str(produtos.index(produto) + 1))
                
                prod = etree.SubElement(det, f'{{{ns_nfe}}}prod')
                etree.SubElement(prod, f'{{{ns_nfe}}}cProd').text = str(produto.get('codigo', produto.get('id', '')))
                etree.SubElement(prod, f'{{{ns_nfe}}}cEAN').text = produto.get('codigo_barras', 'SEM GTIN')
                etree.SubElement(prod, f'{{{ns_nfe}}}xProd').text = produto.get('descricao', produto.get('nome', ''))
                etree.SubElement(prod, f'{{{ns_nfe}}}NCM').text = produto.get('ncm', '00000000')
                if produto.get('cest'):
                    etree.SubElement(prod, f'{{{ns_nfe}}}CEST').text = produto.get('cest')
                etree.SubElement(prod, f'{{{ns_nfe}}}CFOP').text = produto.get('cfop', '5102')
                etree.SubElement(prod, f'{{{ns_nfe}}}uCom').text = produto.get('unidade', 'UN')
                etree.SubElement(prod, f'{{{ns_nfe}}}qCom').text = str(produto.get('quantidade', 1.0))
                etree.SubElement(prod, f'{{{ns_nfe}}}vUnCom').text = f"{produto.get('valor_unitario', 0.0):.2f}"
                etree.SubElement(prod, f'{{{ns_nfe}}}vProd').text = f"{produto.get('valor_total', 0.0):.2f}"
                etree.SubElement(prod, f'{{{ns_nfe}}}cEANTrib').text = produto.get('codigo_barras', 'SEM GTIN')
                etree.SubElement(prod, f'{{{ns_nfe}}}uTrib').text = produto.get('unidade', 'UN')
                etree.SubElement(prod, f'{{{ns_nfe}}}qTrib').text = str(produto.get('quantidade', 1.0))
                etree.SubElement(prod, f'{{{ns_nfe}}}vUnTrib').text = f"{produto.get('valor_unitario', 0.0):.2f}"
                etree.SubElement(prod, f'{{{ns_nfe}}}indTot').text = '1'  # 1=Valor total
                
                valor_total += Decimal(str(produto.get('valor_total', 0.0)))
                
                # imposto
                imposto = etree.SubElement(det, f'{{{ns_nfe}}}imposto')
                etree.SubElement(imposto, f'{{{ns_nfe}}}vTotTrib').text = '0.00'
                
                # ICMS
                icms = etree.SubElement(imposto, f'{{{ns_nfe}}}ICMS')
                icms_item = etree.SubElement(icms, f'{{{ns_nfe}}}ICMS00')
                icms_data = produto.get('icms', {})
                etree.SubElement(icms_item, f'{{{ns_nfe}}}orig').text = icms_data.get('origem', '0')
                etree.SubElement(icms_item, f'{{{ns_nfe}}}CST').text = icms_data.get('cst', '102')
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
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vProd').text = f"{valor_total:.2f}"
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vFrete').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vSeg').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vDesc').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vII').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vIPI').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vIPIDevol').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vPIS').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vCOFINS').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vOutro').text = '0.00'
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vNF').text = f"{valor_total:.2f}"
            etree.SubElement(icms_tot, f'{{{ns_nfe}}}vTotTrib').text = '0.00'
            
            # pag (pagamento)
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
            
            # Converter para string
            xml_str = etree.tostring(root, encoding='unicode', xml_declaration=True, pretty_print=True)
            
            return xml_str
            
        except Exception as e:
            print(f"❌ Erro ao gerar XML: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def _assinar_xml_manual(self, xml_str, certificate, private_key, chave_acesso):
        """Assina XML manualmente usando cryptography"""
        try:
            
            # Parse XML
            root = etree.fromstring(xml_str.encode('utf-8'))
            
            # Encontrar elemento NFe
            nfe_elem = None
            for elem in root.iter():
                if 'NFe' in elem.tag:
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
            
            # 1. Canonicalizar infNFe (C14N)
            c14n_xml = etree.tostring(inf_nfe, method='c14n', exclusive=True, with_comments=False)
            
            # 2. Calcular hash SHA1
            hash_obj = hashes.Hash(hashes.SHA1(), backend=default_backend())
            hash_obj.update(c14n_xml)
            hash_value = hash_obj.finalize()
            hash_base64 = base64.b64encode(hash_value).decode('utf-8')
            
            # 3. Montar SignedInfo
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
            
            # 4. Canonicalizar SignedInfo e assinar
            c14n_signed_info = etree.tostring(signed_info, method='c14n', exclusive=True, with_comments=False)
            
            # Assinar com RSA-SHA1
            signature_bytes = private_key.sign(
                c14n_signed_info,
                padding.PKCS1v15(),
                hashes.SHA1()
            )
            signature_base64 = base64.b64encode(signature_bytes).decode('utf-8')
            
            # 5. Adicionar SignatureValue
            signature_value = etree.SubElement(signature_elem, f'{{{ns_ds}}}SignatureValue')
            signature_value.text = signature_base64
            
            # 6. Adicionar KeyInfo
            key_info = etree.SubElement(signature_elem, f'{{{ns_ds}}}KeyInfo')
            x509_data = etree.SubElement(key_info, f'{{{ns_ds}}}X509Data')
            
            # Obter certificado em base64
            cert_pem = certificate.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')
            cert_clean = cert_pem.replace('-----BEGIN CERTIFICATE-----', '').replace('-----END CERTIFICATE-----', '').replace('\n', '').replace('\r', '').strip()
            
            x509_cert = etree.SubElement(x509_data, f'{{{ns_ds}}}X509Certificate')
            x509_cert.text = cert_clean
            
            # 7. Adicionar Signature ao NFe
            nfe_elem.append(signature_elem)
            
            # 8. Retornar XML assinado
            xml_assinado = etree.tostring(root, encoding='unicode', xml_declaration=True)
            
            return xml_assinado
            
        except Exception as e:
            print(f"❌ Erro ao assinar XML: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def _enviar_sefaz_manual(self, xml_assinado, ambiente_homologacao, uf):
        """Envia XML para SEFAZ usando zeep (SOAP)"""
        try:
            # Determinar URL da SEFAZ
            if uf == 'SP':
                if ambiente_homologacao:
                    url = "https://homologacao.nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx"
            else:
                # Para outros estados, usar SVRS
                if ambiente_homologacao:
                    url = "https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
            
            print(f"URL SEFAZ: {url}")
            
            # Criar cliente SOAP
            client = zeep.Client(wsdl=url)
            
            # Preparar XML para envio (escapar caracteres especiais)
            xml_escaped = xml_assinado.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            
            # Montar envelope SOAP
            # O método nfeAutorizacaoLote recebe o XML como string
            try:
                resultado = client.service.nfeAutorizacaoLote(xml_escaped)
                
                # Processar resposta
                if hasattr(resultado, 'nfeResultMsg'):
                    # Parse da resposta
                    resposta_xml = str(resultado.nfeResultMsg)
                    
                    # Parse XML de resposta
                    resposta_root = etree.fromstring(resposta_xml.encode('utf-8'))
                    
                    # Verificar status
                    prot_nfe = resposta_root.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                    
                    if prot_nfe is not None:
                        inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt')
                        if inf_prot is not None:
                            status = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                            motivo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                            
                            if status is not None and status.text == '100':  # 100 = Autorizada
                                chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe')
                                protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                                
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'status': 'autorizada',
                                    'chave_acesso': chave.text if chave is not None else '',
                                    'protocolo': protocolo.text if protocolo is not None else '',
                                    'mensagem': motivo.text if motivo is not None else 'Autorizada',
                                    'xml': xml_assinado
                                }
                            else:
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'status': 'rejeitada',
                                    'error': motivo.text if motivo is not None else 'Erro desconhecido',
                                    'codigo_erro': status.text if status is not None else '',
                                    'error_type': 'SEFAZRejection'
                                }
                
                return {
                    'success': False,
                    'error': 'Resposta da SEFAZ não reconhecida',
                    'error_type': 'UnknownResponse'
                }
                
            except Exception as e:
                print(f"❌ Erro ao chamar serviço SOAP: {e}")
                return {
                    'success': False,
                    'error': f'Erro ao comunicar com SEFAZ: {str(e)}',
                    'error_type': 'SEFAZError'
                }
                
        except Exception as e:
            print(f"❌ Erro ao enviar para SEFAZ: {e}")
            import traceback
            traceback.print_exc()
            return {
                'success': False,
                'error': f'Erro ao enviar para SEFAZ: {str(e)}',
                'error_type': 'SEFAZError'
            }
    
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
        return conversao.get(tipo, '99')

