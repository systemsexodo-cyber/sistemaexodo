"""
Serviço GRATUITO para emissão de NFC-e usando PyTrustNFe
Biblioteca Python open source - funciona localmente, sem APIs pagas
"""

import os
import base64
import tempfile
from datetime import datetime
from decimal import Decimal

# Tentar importar PyTrustNFe
PYTRUST_DISPONIVEL = False
try:
    # PyTrustNFe pode ter diferentes estruturas, vamos tentar importar de forma flexível
    try:
        from pytrustnfe.nfce import recepcao
        from pytrustnfe.certificado import Certificado
        from pytrustnfe.xml import render_xml, sanitize_response
    except ImportError:
        # Tentar importação alternativa
        from pytrustnfe import nfce
        from pytrustnfe import certificado
        recepcao = nfce.recepcao
        Certificado = certificado.Certificado
        render_xml = nfce.render_xml
        sanitize_response = nfce.sanitize_response
    
    PYTRUST_DISPONIVEL = True
    print("[OK] PyTrustNFe disponível!")
except ImportError as e:
    PYTRUST_DISPONIVEL = False
    print(f"[AVISO] PyTrustNFe não está instalado: {e}")
    print("[INFO] Instale com: pip install PyTrustNFe")


class NFCeServicePyTrust:
    """Serviço gratuito para emissão de NFC-e usando PyTrustNFe"""
    
    def __init__(self):
        self.pytrust_disponivel = PYTRUST_DISPONIVEL
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e usando PyTrustNFe (GRATUITO e LOCAL)
        
        Args:
            data: Dicionário com dados da NFC-e
        
        Returns:
            Dicionário com resultado da emissão
        """
        if not self.pytrust_disponivel:
            return {
                'success': False,
                'error': 'PyTrustNFe não está instalado.\n\n'
                        'Execute: pip install PyTrustNFe\n\n'
                        'Depois REINICIE o servidor!',
                'error_type': 'LibraryNotAvailable'
            }
        
        try:
            empresa_data = data.get('empresa', {})
            produtos = data.get('produtos', [])
            pagamentos = data.get('pagamentos', [])
            consumidor = data.get('consumidor', {})
            observacoes = data.get('observacoes', '')
            ambiente_homologacao = empresa_data.get('ambiente_homologacao', True)
            uf = empresa_data.get('uf', 'SP')
            
            print("=" * 60)
            print("EMISSÃO NFC-e - PyTrustNFe (GRATUITO)")
            print("=" * 60)
            print(f"Ambiente: {'HOMOLOGAÇÃO' if ambiente_homologacao else 'PRODUÇÃO'}")
            print(f"CNPJ: {empresa_data.get('cnpj', 'N/A')}")
            print(f"UF: {uf}")
            print(f"Produtos: {len(produtos)}")
            print("=" * 60)
            
            # 1. Carregar certificado
            print("\n[1/4] Carregando certificado...")
            certificado = self._carregar_certificado(empresa_data)
            if not certificado:
                return {
                    'success': False,
                    'error': 'Erro ao carregar certificado digital. Verifique a senha e o formato.',
                    'error_type': 'CertificateError'
                }
            print("✅ Certificado carregado")
            
            # 2. Preparar dados da NFC-e no formato PyTrustNFe
            print("\n[2/4] Preparando dados da NFC-e...")
            nfce_dict = self._preparar_dados_pytrust(
                empresa_data, produtos, pagamentos, consumidor, observacoes
            )
            print("✅ Dados preparados")
            
            # 3. Gerar e assinar XML (PyTrustNFe faz tudo automaticamente)
            print("\n[3/4] Gerando e assinando XML...")
            try:
                # PyTrustNFe gera e assina o XML automaticamente
                xml_nfce = render_xml('nfce', nfce_dict, certificado, ambiente_homologacao)
                print("✅ XML gerado e assinado")
            except Exception as e:
                print(f"❌ Erro ao gerar XML: {e}")
                import traceback
                traceback.print_exc()
                return {
                    'success': False,
                    'error': f'Erro ao gerar XML: {str(e)}',
                    'error_type': 'XMLError'
                }
            
            # 4. Enviar para SEFAZ
            print("\n[4/4] Enviando para SEFAZ...")
            try:
                # PyTrustNFe envia para SEFAZ automaticamente
                resultado = recepcao(certificado, xml_nfce, ambiente_homologacao, uf)
                
                # Processar resposta
                resposta = sanitize_response(resultado)
                
                print("\n" + "=" * 60)
                
                if resposta.get('status') == 'autorizada':
                    print("✅ NFC-e AUTORIZADA COM SUCESSO!")
                    print("=" * 60)
                    print(f"Chave de acesso: {resposta.get('chave_nfe', 'N/A')}")
                    print(f"Número: {resposta.get('numero', 'N/A')}")
                    print(f"Protocolo: {resposta.get('protocolo', 'N/A')}")
                    
                    return {
                        'success': True,
                        'autorizada': True,
                        'status': 'autorizada',
                        'chave_acesso': resposta.get('chave_nfe', ''),
                        'numero': str(resposta.get('numero', '')),
                        'serie': str(resposta.get('serie', '1')),
                        'protocolo': resposta.get('protocolo', ''),
                        'qr_code': resposta.get('url_qrcode', ''),
                        'xml': resposta.get('xml', ''),
                        'data': resposta
                    }
                else:
                    print("❌ NFC-e REJEITADA")
                    print("=" * 60)
                    print(f"Erro: {resposta.get('mensagem', 'N/A')}")
                    
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'rejeitada',
                        'error': resposta.get('mensagem', 'Erro desconhecido'),
                        'error_type': 'SEFAZRejection',
                        'data': resposta
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
                
                try:
                    # Carregar certificado PyTrustNFe
                    certificado = Certificado(cert_path, senha)
                    return certificado
                finally:
                    # Remover arquivo temporário
                    try:
                        os.unlink(cert_path)
                    except:
                        pass
            else:
                print("❌ Certificado não fornecido")
                return None
                
        except Exception as e:
            print(f"❌ Erro ao carregar certificado: {e}")
            return None
    
    def _preparar_dados_pytrust(self, empresa_data, produtos, pagamentos, consumidor, observacoes):
        """Prepara dados no formato esperado pelo PyTrustNFe"""
        
        # Limpar CNPJ
        cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
        
        # Preparar itens
        itens = []
        for produto in produtos:
            item = {
                'produto': produto.get('descricao', produto.get('nome', '')),
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
        
        # Preparar pagamentos
        formas_pagamento = []
        for pagamento in pagamentos:
            forma = {
                'forma_pagamento': self._converter_forma_pagamento(pagamento.get('tipo', '01')),
                'valor_pagamento': str(pagamento.get('valor', 0.0))
            }
            formas_pagamento.append(forma)
        
        # Montar dados completos no formato PyTrustNFe
        nfce_dict = {
            'cnpj_emitente': cnpj,
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
            'natureza_operacao': 'VENDA',
            'data_emissao': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'),
            'tipo_documento': '1',  # 1=Entrada, 0=Saída
            'local_destino': '1',  # 1=Interna
            'finalidade': '1',  # 1=Normal
            'consumidor_final': '1',  # 1=Sim (sempre para NFC-e)
            'presenca_comprador': '1',  # 1=Presencial
            'itens': itens,
            'valor_total': str(sum(p.get('valor_total', 0) for p in produtos)),
            'formas_pagamento': formas_pagamento,
        }
        
        # Adicionar consumidor se fornecido
        if consumidor:
            cpf = consumidor.get('cpf', '').replace('.', '').replace('-', '')
            if cpf:
                nfce_dict['cpf_consumidor'] = cpf
            nome = consumidor.get('nome', '')
            if nome:
                nfce_dict['nome_consumidor'] = nome
        
        # Adicionar observações
        if observacoes:
            nfce_dict['informacoes_adicionais'] = observacoes
        
        return nfce_dict
    
    def _converter_forma_pagamento(self, tipo):
        """Converte tipo de pagamento para formato PyTrustNFe"""
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

