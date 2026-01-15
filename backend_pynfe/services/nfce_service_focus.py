"""
Serviço ULTRA SIMPLES para emissão de NFC-e usando Focus NFe API
Esta é a forma MAIS FÁCIL de emitir NFC-e - apenas chamadas HTTP
"""

import requests
from datetime import datetime


class NFCeServiceFocus:
    """
    Serviço usando Focus NFe API - MUITO MAIS SIMPLES!
    Não precisa lidar com certificados, assinatura XML, etc.
    A API faz tudo para você!
    """
    
    def __init__(self, api_token=None, ambiente_homologacao=True):
        """
        Args:
            api_token: Token da API Focus NFe (obter em https://focusnfe.com.br)
            ambiente_homologacao: True para homologação, False para produção
        """
        self.api_token = api_token or os.getenv('FOCUSNFE_TOKEN', '')
        self.ambiente_homologacao = ambiente_homologacao
        
        if ambiente_homologacao:
            self.base_url = 'https://homologacao.focusnfe.com.br/v2'
        else:
            self.base_url = 'https://api.focusnfe.com.br/v2'
    
    def emitir_nfce(self, data):
        """
        Emite NFC-e de forma ULTRA SIMPLES via Focus NFe API
        
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
        if not self.api_token:
            return {
                'success': False,
                'error': 'Token da API Focus NFe não configurado.\n\n'
                        '1. Acesse https://focusnfe.com.br\n'
                        '2. Crie uma conta (tem plano gratuito para testes)\n'
                        '3. Obtenha seu token\n'
                        '4. Configure: export FOCUSNFE_TOKEN=seu_token',
                'error_type': 'TokenNotConfigured'
            }
        
        try:
            empresa_data = data.get('empresa', {})
            produtos = data.get('produtos', [])
            pagamentos = data.get('pagamentos', [])
            consumidor = data.get('consumidor', {})
            observacoes = data.get('observacoes', '')
            
            print("=" * 60)
            print("EMISSÃO NFC-e - Focus NFe API (ULTRA SIMPLES)")
            print("=" * 60)
            print(f"Ambiente: {'HOMOLOGAÇÃO' if self.ambiente_homologacao else 'PRODUÇÃO'}")
            print(f"CNPJ: {empresa_data.get('cnpj', 'N/A')}")
            print(f"Produtos: {len(produtos)}")
            print("=" * 60)
            
            # Preparar dados no formato Focus NFe
            nfce_data = self._preparar_dados_focus(empresa_data, produtos, pagamentos, consumidor, observacoes)
            
            # Gerar referência única
            ref = f"NFCE_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            
            # URL da API
            url = f'{self.base_url}/nfce'
            
            # Headers
            headers = {
                'Authorization': f'Token {self.api_token}',
                'Content-Type': 'application/json'
            }
            
            print(f"\n[1/2] Enviando para Focus NFe API...")
            print(f"URL: {url}")
            print(f"Referência: {ref}")
            
            # Enviar requisição
            response = requests.post(
                url,
                json=nfce_data,
                headers=headers,
                timeout=120
            )
            
            print(f"\n[2/2] Resposta recebida (Status: {response.status_code})")
            
            # Processar resposta
            if response.status_code == 201:
                # NFC-e autorizada!
                resultado_data = response.json()
                
                print("\n" + "=" * 60)
                print("✅ NFC-e AUTORIZADA COM SUCESSO!")
                print("=" * 60)
                print(f"Chave de acesso: {resultado_data.get('chave_nfe', 'N/A')}")
                print(f"Número: {resultado_data.get('numero', 'N/A')}")
                print(f"Protocolo: {resultado_data.get('protocolo', 'N/A')}")
                print(f"QR Code: {resultado_data.get('url_qrcode', 'N/A')[:50]}...")
                
                return {
                    'success': True,
                    'autorizada': True,
                    'status': 'autorizada',
                    'chave_acesso': resultado_data.get('chave_nfe', ''),
                    'numero': str(resultado_data.get('numero', '')),
                    'serie': str(resultado_data.get('serie', '1')),
                    'protocolo': resultado_data.get('protocolo', ''),
                    'qr_code': resultado_data.get('url_qrcode', ''),
                    'xml': resultado_data.get('xml', ''),
                    'data': resultado_data
                }
            else:
                # Erro
                error_data = response.json()
                error_msg = error_data.get('mensagem', 'Erro desconhecido')
                
                print("\n" + "=" * 60)
                print("❌ ERRO NA EMISSÃO")
                print("=" * 60)
                print(f"Erro: {error_msg}")
                
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'rejeitada',
                    'error': error_msg,
                    'error_type': 'APIError',
                    'details': error_data
                }
                
        except requests.exceptions.Timeout:
            return {
                'success': False,
                'error': 'Timeout ao comunicar com Focus NFe API',
                'error_type': 'TimeoutError'
            }
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e: {str(e)}',
                'error_type': 'UnexpectedError',
                'details': error_details
            }
    
    def _preparar_dados_focus(self, empresa_data, produtos, pagamentos, consumidor, observacoes):
        """Prepara dados no formato esperado pela Focus NFe API"""
        
        # Limpar CNPJ
        cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
        
        # Preparar itens
        itens = []
        for produto in produtos:
            item = {
                'codigo_produto': produto.get('codigo', produto.get('id', '')),
                'descricao': produto.get('descricao', produto.get('nome', '')),
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
        
        # Montar dados completos
        nfce_data = {
            'ref': f"NFCE_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
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
                nfce_data['cpf_consumidor'] = cpf
            nome = consumidor.get('nome', '')
            if nome:
                nfce_data['nome_consumidor'] = nome
        
        # Adicionar observações
        if observacoes:
            nfce_data['informacoes_adicionais'] = observacoes
        
        return nfce_data
    
    def _converter_forma_pagamento(self, tipo):
        """Converte tipo de pagamento para formato Focus NFe"""
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




















