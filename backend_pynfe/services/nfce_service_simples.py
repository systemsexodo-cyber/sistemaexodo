"""
Serviço SIMPLIFICADO para emissão de NFC-e usando PyTrustNFe
Esta biblioteca é mais simples e confiável que nfelib+signxml
"""

import os
import base64
import tempfile
from datetime import datetime
from decimal import Decimal

# Tentar importar PyTrustNFe
PYTRUST_DISPONIVEL = False
try:
    from pytrustnfe.nfce import recepcao
    from pytrustnfe.certificado import Certificado
    from pytrustnfe.xml import render_xml, sanitize_response
    PYTRUST_DISPONIVEL = True
    print("[OK] PyTrustNFe disponível!")
except ImportError as e:
    PYTRUST_DISPONIVEL = False
    print(f"[AVISO] PyTrustNFe não está instalado: {e}")
    print("[INFO] Instale com: pip install PyTrustNFe")


class NFCeServiceSimples:
    """Serviço simplificado para emissão de NFC-e usando PyTrustNFe"""
    
    def __init__(self):
        self.pytrust_disponivel = PYTRUST_DISPONIVEL
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e de forma SIMPLES usando PyTrustNFe
        
        Args:
            data: Dicionário com:
                - empresa: dados da empresa
                - produtos: lista de produtos
                - pagamentos: lista de pagamentos
                - consumidor: dados do consumidor (opcional)
                - observacoes: observações (opcional)
        
        Returns:
            Dicionário com resultado da emissão
        """
        if not self.pytrust_disponivel:
            return {
                'success': False,
                'error': 'PyTrustNFe não está instalado.\n\nExecute: pip install PyTrustNFe\n\nDepois REINICIE o servidor!',
                'error_type': 'LibraryNotAvailable'
            }
        
        try:
            empresa_data = data.get('empresa', {})
            produtos = data.get('produtos', [])
            pagamentos = data.get('pagamentos', [])
            consumidor = data.get('consumidor', {})
            observacoes = data.get('observacoes', '')
            ambiente_homologacao = empresa_data.get('ambiente_homologacao', True)
            
            print("=" * 60)
            print("EMISSÃO NFC-e SIMPLIFICADA - PyTrustNFe")
            print("=" * 60)
            print(f"Ambiente: {'HOMOLOGAÇÃO' if ambiente_homologacao else 'PRODUÇÃO'}")
            print(f"CNPJ: {empresa_data.get('cnpj', 'N/A')}")
            print(f"Produtos: {len(produtos)}")
            print("=" * 60)
            
            # 1. Carregar certificado
            print("\n[1/5] Carregando certificado...")
            certificado = self._carregar_certificado(empresa_data)
            if not certificado:
                return {
                    'success': False,
                    'error': 'Erro ao carregar certificado digital',
                    'error_type': 'CertificateError'
                }
            print("✅ Certificado carregado")
            
            # 2. Preparar dados da NFC-e
            print("\n[2/5] Preparando dados da NFC-e...")
            nfce_data = self._preparar_dados_nfce(
                empresa_data, produtos, pagamentos, consumidor, observacoes
            )
            print("✅ Dados preparados")
            
            # 3. Gerar XML
            print("\n[3/5] Gerando XML...")
            xml_nfce = self._gerar_xml_nfce(nfce_data, certificado, ambiente_homologacao)
            if not xml_nfce:
                return {
                    'success': False,
                    'error': 'Erro ao gerar XML da NFC-e',
                    'error_type': 'XMLError'
                }
            print("✅ XML gerado")
            
            # 4. Assinar XML
            print("\n[4/5] Assinando XML...")
            xml_assinado = self._assinar_xml(xml_nfce, certificado)
            if not xml_assinado:
                return {
                    'success': False,
                    'error': 'Erro ao assinar XML',
                    'error_type': 'SignatureError'
                }
            print("✅ XML assinado")
            
            # 5. Enviar para SEFAZ
            print("\n[5/5] Enviando para SEFAZ...")
            resultado = self._enviar_sefaz(xml_assinado, ambiente_homologacao, empresa_data.get('uf', 'SP'))
            
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
        """Carrega certificado digital"""
        try:
            # Verificar se tem certificado em base64
            if 'certificado_base64' in empresa_data:
                cert_bytes = base64.b64decode(empresa_data['certificado_base64'])
                senha = empresa_data.get('senha_certificado', '')
                
                # Criar arquivo temporário
                with tempfile.NamedTemporaryFile(delete=False, suffix='.pfx') as f:
                    f.write(cert_bytes)
                    cert_path = f.name
                
                # Carregar certificado PyTrustNFe
                certificado = Certificado(cert_path, senha)
                os.unlink(cert_path)  # Remover arquivo temporário
                
                return certificado
            else:
                print("❌ Certificado não fornecido")
                return None
                
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            return None
    
    def _preparar_dados_nfce(self, empresa_data, produtos, pagamentos, consumidor, observacoes):
        """Prepara dados no formato esperado pelo PyTrustNFe"""
        # Calcular totais
        valor_total = sum(p.get('valor_total', 0) for p in produtos)
        
        # Preparar itens
        itens = []
        for produto in produtos:
            item = {
                'produto': produto.get('descricao', ''),
                'cfop': produto.get('cfop', '5102'),
                'ncm': produto.get('ncm', '00000000'),
                'cest': produto.get('cest'),
                'unidade_comercial': produto.get('unidade', 'UN'),
                'quantidade_comercial': str(produto.get('quantidade', 1.0)),
                'valor_unitario_comercial': str(produto.get('valor_unitario', 0.0)),
                'valor_total': str(produto.get('valor_total', 0.0)),
                'icms_origem': produto.get('icms', {}).get('origem', '0'),
                'icms_situacao_tributaria': produto.get('icms', {}).get('cst', '102'),
                'icms_aliquota': str(produto.get('icms', {}).get('aliquota', 0.0)),
            }
            itens.append(item)
        
        # Preparar dados da NFC-e
        nfce_data = {
            'cnpj_emitente': empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', ''),
            'nome_emitente': empresa_data.get('razao_social', ''),
            'nome_fantasia': empresa_data.get('nome_fantasia', ''),
            'inscricao_estadual': empresa_data.get('inscricao_estadual', ''),
            'codigo_municipio': empresa_data.get('codigo_municipio_ibge', ''),
            'uf': empresa_data.get('uf', 'SP'),
            'logradouro': empresa_data.get('endereco', {}).get('logradouro', ''),
            'numero': empresa_data.get('endereco', {}).get('numero', ''),
            'bairro': empresa_data.get('endereco', {}).get('bairro', ''),
            'municipio': empresa_data.get('endereco', {}).get('cidade', ''),
            'cep': empresa_data.get('endereco', {}).get('cep', '').replace('-', ''),
            'telefone': empresa_data.get('telefone', ''),
            'itens': itens,
            'valor_total': str(valor_total),
            'pagamentos': pagamentos,
            'consumidor_final': '1',  # Sempre consumidor final para NFC-e
            'presenca_comprador': '1',  # Presencial
        }
        
        if consumidor:
            nfce_data['cpf_consumidor'] = consumidor.get('cpf', '').replace('.', '').replace('-', '')
            nfce_data['nome_consumidor'] = consumidor.get('nome', '')
        
        if observacoes:
            nfce_data['informacoes_adicionais'] = observacoes
        
        return nfce_data
    
    def _gerar_xml_nfce(self, nfce_data, certificado, ambiente_homologacao):
        """Gera XML da NFC-e usando PyTrustNFe"""
        try:
            # PyTrustNFe tem função para gerar XML automaticamente
            # Por enquanto, retornar None para indicar que precisa implementar
            # ou usar a função render_xml do PyTrustNFe
            print("⚠️  Geração de XML precisa ser implementada com PyTrustNFe")
            return None
        except Exception as e:
            print(f"❌ Erro ao gerar XML: {e}")
            return None
    
    def _assinar_xml(self, xml_nfce, certificado):
        """Assina XML usando PyTrustNFe"""
        try:
            # PyTrustNFe assina automaticamente
            print("⚠️  Assinatura precisa ser implementada com PyTrustNFe")
            return None
        except Exception as e:
            print(f"❌ Erro ao assinar: {e}")
            return None
    
    def _enviar_sefaz(self, xml_assinado, ambiente_homologacao, uf):
        """Envia para SEFAZ usando PyTrustNFe"""
        try:
            # PyTrustNFe tem função recepcao que faz tudo automaticamente
            print("⚠️  Envio para SEFAZ precisa ser implementado com PyTrustNFe")
            return {
                'success': False,
                'error': 'Implementação em andamento',
                'error_type': 'NotImplemented'
            }
        except Exception as e:
            print(f"❌ Erro ao enviar: {e}")
            return {
                'success': False,
                'error': str(e),
                'error_type': 'SEFAZError'
            }




















