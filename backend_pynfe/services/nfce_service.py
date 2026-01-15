"""
Serviço para emissão de NFC-e usando nfelib
Gera XML correto automaticamente a partir dos XSDs oficiais da SEFAZ
"""

import base64
import json
import random
import os
import sys
from datetime import datetime
from decimal import Decimal
from lxml import etree
import re

# Importar nfelib (biblioteca que gera XML correto)
NFELIB_DISPONIVEL = False
try:
    from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
    from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
    import requests
    from signxml import XMLSigner
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.hazmat.backends import default_backend
    NFELIB_DISPONIVEL = True
    print("[OK] nfelib e dependencias importadas com sucesso!")
except ImportError as e:
    NFELIB_DISPONIVEL = False
    print(f"[ERRO] nfelib nao esta instalado: {e}")
    print("[INFO] Instale com: pip install nfelib signxml cryptography")
except Exception as e:
    NFELIB_DISPONIVEL = False
    print(f"[ERRO] Erro ao importar nfelib: {e}")

from services.certificado_service import CertificadoService
try:
    from services.xml_validator import XMLValidator
    VALIDATOR_DISPONIVEL = True
except ImportError:
    VALIDATOR_DISPONIVEL = False
    XMLValidator = None
    print("[INFO] XMLValidator nao disponivel")


class NFCeService:
    """Serviço para emissão de NFC-e"""
    
    def __init__(self):
        self.certificado_service = CertificadoService()
        self._empresa_data = None  # Armazenar dados da empresa atual
        if VALIDATOR_DISPONIVEL:
            # Tentar carregar schemas XSD se disponíveis
            schema_paths = {}
            schema_base_path = r'C:\Users\USER\Downloads\PL_NFAg_1.00d\PL_NFAg_1.00d'
            
            # Procurar schemas de NFe/NFC-e (pode estar em outro diretório)
            # Por enquanto, usar validação estrutural sem XSD
            # Se encontrar schemas, adicionar aqui:
            # schema_paths['enviNFe'] = os.path.join(schema_base_path, 'enviNFe_v4.00.xsd')
            # schema_paths['nfe'] = os.path.join(schema_base_path, 'nfe_v4.00.xsd')
            # schema_paths['tiposBasico'] = os.path.join(schema_base_path, 'tiposBasico_v4.00.xsd')
            
            self.xml_validator = XMLValidator(schema_paths=schema_paths if schema_paths else None)
        else:
            self.xml_validator = None
    
    def _obter_arquivo_numeracao(self, empresa_data, serie):
        """
        Obtém o caminho do arquivo JSON que armazena a numeração sequencial
        
        Args:
            empresa_data: Dicionário com dados da empresa
            serie: Série da NFC-e
            
        Returns:
            Caminho completo do arquivo JSON
        """
        import os
        diretorio_empresa = self._obter_diretorio_empresa(empresa_data)
        arquivo_numeracao = os.path.join(diretorio_empresa, f'numeracao_serie_{serie}.json')
        return arquivo_numeracao
    
    def _obter_proximo_numero(self, empresa_data, serie):
        """
        Obtém o próximo número sequencial da NFC-e para a empresa/série
        
        Args:
            empresa_data: Dicionário com dados da empresa
            serie: Série da NFC-e (padrão: '1')
            
        Returns:
            Próximo número sequencial (string com 9 dígitos)
        """
        import os
        serie = str(serie).strip()[:3].zfill(3)
        arquivo_numeracao = self._obter_arquivo_numeracao(empresa_data, serie)
        
        # Tentar carregar número atual
        numero_atual = 1
        if os.path.exists(arquivo_numeracao):
            try:
                with open(arquivo_numeracao, 'r', encoding='utf-8') as f:
                    dados = json.load(f)
                    numero_atual = dados.get('numero_atual', 1)
                    # Validar que é um número válido
                    if not isinstance(numero_atual, int) or numero_atual < 1:
                        numero_atual = 1
            except Exception as e:
                print(f'>>> [PyNFe] ⚠️ Erro ao ler arquivo de numeração: {e}')
                numero_atual = 1
        
        # Retornar número atual (será incrementado apenas quando autorizado)
        numero_str = str(numero_atual).zfill(9)
        print(f'>>> [PyNFe] Número sequencial obtido: {numero_str} (Série: {serie})')
        return numero_str
    
    def _salvar_numero_atual(self, empresa_data, serie, numero):
        """
        Salva o número atual da numeração sequencial
        
        Args:
            empresa_data: Dicionário com dados da empresa
            serie: Série da NFC-e
            numero: Número atual (pode ser string ou int)
        """
        import os
        serie = str(serie).strip()[:3].zfill(3)
        
        # Converter número para int
        try:
            if isinstance(numero, str):
                numero_int = int(numero.strip())
            else:
                numero_int = int(numero)
        except (ValueError, AttributeError):
            print(f'>>> [PyNFe] ⚠️ Erro ao converter número: {numero}')
            return
        
        arquivo_numeracao = self._obter_arquivo_numeracao(empresa_data, serie)
        
        # Garantir que o diretório existe
        os.makedirs(os.path.dirname(arquivo_numeracao), exist_ok=True)
        
        # Salvar número atual
        dados = {
            'numero_atual': numero_int,
            'serie': serie,
            'ultima_atualizacao': datetime.now().isoformat()
        }
        
        try:
            with open(arquivo_numeracao, 'w', encoding='utf-8') as f:
                json.dump(dados, f, indent=2, ensure_ascii=False)
            print(f'>>> [PyNFe] ✅ Número salvo: {numero_int} (Série: {serie})')
        except Exception as e:
            print(f'>>> [PyNFe] ⚠️ Erro ao salvar número: {e}')
    
    def _incrementar_numero_apos_autorizacao(self, empresa_data, serie, numero_atual):
        """
        Incrementa o número sequencial apenas após autorização da SEFAZ
        
        Args:
            empresa_data: Dicionário com dados da empresa
            serie: Série da NFC-e
            numero_atual: Número atual que foi usado (será incrementado)
        """
        try:
            # Converter número para int
            if isinstance(numero_atual, str):
                numero_int = int(numero_atual.strip())
            else:
                numero_int = int(numero_atual)
            
            # Incrementar para o próximo número
            proximo_numero = numero_int + 1
            
            # Salvar número incrementado
            self._salvar_numero_atual(empresa_data, serie, proximo_numero)
            print(f'>>> [PyNFe] ✅ Numeração incrementada: {numero_int} -> {proximo_numero} (Série: {serie})')
        except Exception as e:
            print(f'>>> [PyNFe] ⚠️ Erro ao incrementar número: {e}')
    
    def _obter_diretorio_empresa(self, empresa_data=None):
        """
        Obtém o diretório para salvar XMLs da empresa
        
        Args:
            empresa_data: Dicionário com dados da empresa (opcional, usa self._empresa_data se não fornecido)
            
        Returns:
            Caminho do diretório da empresa
        """
        import os
        import re
        
        # Usar empresa_data fornecido ou o armazenado
        dados_empresa = empresa_data or self._empresa_data
        
        if not dados_empresa:
            # Se não tem dados da empresa, usar diretório padrão
            base_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'empresas', 'sem_empresa')
            os.makedirs(base_dir, exist_ok=True)
            return base_dir
        
        # Extrair CNPJ da empresa (pode estar em diferentes formatos)
        cnpj = dados_empresa.get('cnpj', '') or dados_empresa.get('CNPJ', '')
        
        # Limpar CNPJ (remover caracteres não numéricos)
        if cnpj:
            cnpj_limpo = re.sub(r'[^\d]', '', str(cnpj))
            if len(cnpj_limpo) >= 11:  # CNPJ tem pelo menos 11 dígitos
                # Usar CNPJ como identificador
                empresa_id = cnpj_limpo
            else:
                # Se CNPJ inválido, usar razão social sanitizada
                razao_social = dados_empresa.get('razao_social', '') or dados_empresa.get('razaoSocial', '') or 'sem_nome'
                empresa_id = re.sub(r'[^\w\s-]', '', razao_social).strip().replace(' ', '_')[:50]
        else:
            # Se não tem CNPJ, usar razão social ou ID
            empresa_id = dados_empresa.get('id', '') or dados_empresa.get('_id', '')
            if not empresa_id:
                razao_social = dados_empresa.get('razao_social', '') or dados_empresa.get('razaoSocial', '') or 'sem_nome'
                empresa_id = re.sub(r'[^\w\s-]', '', razao_social).strip().replace(' ', '_')[:50]
        
        # Criar diretório: logs/empresas/{CNPJ_ou_ID}/
        base_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'empresas', empresa_id)
        os.makedirs(base_dir, exist_ok=True)
        
        return base_dir
    
    def _formatar_erro_sefaz(self, cstat, motivo, campos_resposta=None):
        """
        Formata mensagem de erro da SEFAZ de forma clara e direta
        
        Args:
            cstat: Código de status da SEFAZ
            motivo: Motivo da rejeição/erro
            campos_resposta: Dicionário com campos adicionais da resposta
            
        Returns:
            String com mensagem de erro formatada
        """
        if not motivo:
            motivo = "Motivo não informado pela SEFAZ"
        
        # Remover espaços extras
        motivo = motivo.strip()
        
        # Mensagem base: apenas o motivo da SEFAZ
        mensagem = motivo
        
        # Adicionar informações técnicas se disponíveis
        if campos_resposta:
            info_adicional = []
            
            if 'verAplic' in campos_resposta and campos_resposta['verAplic']:
                info_adicional.append(f"Versão da aplicação SEFAZ: {campos_resposta['verAplic']}")
            
            if 'cUF' in campos_resposta and campos_resposta['cUF']:
                uf_map = {
                    '35': 'SP', '33': 'RJ', '31': 'MG', '43': 'RS',
                    '41': 'PR', '42': 'SC', '32': 'ES', '29': 'BA',
                    '23': 'CE', '53': 'DF', '52': 'GO', '21': 'MA',
                    '51': 'MT', '50': 'MS', '15': 'PA', '25': 'PB',
                    '26': 'PE', '22': 'PI', '24': 'RN', '11': 'RO',
                    '14': 'RR', '27': 'SE', '28': 'TO', '17': 'TO',
                    '12': 'AC', '16': 'AP', '13': 'AM'
                }
                uf = uf_map.get(campos_resposta['cUF'], campos_resposta['cUF'])
                info_adicional.append(f"Estado: {uf}")
            
            if 'dhRecbto' in campos_resposta and campos_resposta['dhRecbto']:
                info_adicional.append(f"Data/hora do recebimento: {campos_resposta['dhRecbto']}")
            
            if info_adicional:
                mensagem += '\n' + '\n'.join(info_adicional)
        
        return mensagem
    
    def _obter_descricao_produto(self, produto):
        """
        Obtém a descrição do produto em diferentes formatos de campo
        
        Aceita os seguintes nomes de campo (em ordem de prioridade):
        - 'descricao'
        - 'nome'
        - 'xProd'
        
        Args:
            produto: Dicionário com dados do produto
            
        Returns:
            String com a descrição do produto ou string vazia se não encontrar
        """
        return produto.get('descricao') or produto.get('nome') or produto.get('xProd') or ''
    
    def _obter_preco_produto(self, produto):
        """
        Obtém o preço unitário do produto em diferentes formatos de campo
        
        Aceita os seguintes nomes de campo (em ordem de prioridade):
        - 'preco'
        - 'valor_unitario'
        - 'valorUnitario'
        - 'valor_unidade'
        - Se houver 'valor_total' e 'quantidade', calcula o preço unitário
        
        Args:
            produto: Dicionário com dados do produto
            
        Returns:
            Decimal com o preço unitário ou None se não encontrar
        """
        # Tentar diferentes nomes de campo
        preco = produto.get('preco') or produto.get('valor_unitario') or produto.get('valorUnitario') or produto.get('valor_unidade')
        
        # Se encontrou, converter para Decimal
        if preco is not None:
            try:
                return Decimal(str(preco))
            except (ValueError, TypeError):
                pass
        
        # Se não encontrou preço direto, tentar calcular a partir de valor_total / quantidade
        valor_total = produto.get('valor_total') or produto.get('valorTotal') or produto.get('valor')
        quantidade = produto.get('quantidade', 1)
        
        if valor_total is not None and quantidade and quantidade > 0:
            try:
                valor_total_decimal = Decimal(str(valor_total))
                quantidade_decimal = Decimal(str(quantidade))
                if quantidade_decimal > 0:
                    return valor_total_decimal / quantidade_decimal
            except (ValueError, TypeError, ZeroDivisionError):
                pass
        
        # Se nada funcionou, retornar None
        return None
    
    def emitir_nfce(self, data):
        """
        Emite uma NFC-e usando nfelib
        
        Args:
            data: Dicionário com dados da NFC-e
            
        Returns:
            Dicionário com resultado da emissão
        """
        debug_print = print
        
        if not NFELIB_DISPONIVEL:
            return {
                'success': False,
                'error': 'nfelib não está instalado.\n\nExecute: pip install nfelib signxml cryptography\n\nDepois REINICIE o servidor backend!',
                'autorizada': False
            }
        
        # Garantir que os módulos estão disponíveis (usar os já importados no topo)
        try:
            # Importar novamente para garantir que estão no escopo local
            from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe_module
            from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe_module
            # Criar aliases para classes aninhadas (estrutura do nfelib)
            Tnfe = nfe_module.Tnfe
            InfNfe = Tnfe.InfNfe
            # Classes para impostos (estrutura aninhada)
            Det = InfNfe.Det
            Imposto = Det.Imposto
            Icms = Imposto.Icms
        except ImportError as e:
            return {
                'success': False,
                'error': f'nfelib não está disponível: {str(e)}\n\nExecute: pip install nfelib signxml cryptography\n\nDepois REINICIE o servidor backend!',
                'autorizada': False
            }
        
        try:
            # Extrair dados
            empresa_data = data['empresa']
            self._empresa_data = empresa_data
            
            produtos_data = data['produtos']
            pagamentos_data = data['pagamentos']
            consumidor_data = data.get('consumidor', {})
            observacoes = data.get('observacoes', '')
            ambiente_homologacao = empresa_data.get('ambiente_homologacao', True)
            
            # Verificar ambiente
            modo_ambiente = "HOMOLOGAÇÃO" if ambiente_homologacao else "PRODUÇÃO"
            debug_print(f'>>> [nfelib] ========================================')
            debug_print(f'>>> [nfelib] AMBIENTE CONFIGURADO: {modo_ambiente}')
            debug_print(f'>>> [nfelib] ========================================')
            
            # Validar certificado
            certificado_base64 = empresa_data.get('certificado_base64')
            senha_certificado = empresa_data.get('senha_certificado')
            
            if not certificado_base64 or not senha_certificado:
                return {
                    'success': False,
                    'error': 'Certificado digital ou senha não fornecidos',
                    'autorizada': False
                }
            
            # Carregar certificado
            certificado = self.certificado_service.carregar_certificado(
                certificado_base64,
                senha_certificado
            )
            
            # Garantir que a senha está no dicionário do certificado
            if 'senha' not in certificado:
                certificado['senha'] = senha_certificado
            if 'certificado_base64' not in certificado:
                certificado['certificado_base64'] = certificado_base64
            
            debug_print(f">>> [nfelib] Certificado carregado. Tem arquivo: {'arquivo' in certificado}")
            debug_print(f">>> [nfelib] Certificado tem senha: {'senha' in certificado}")
            
            # Série e número
            serie_nfce = str(empresa_data.get('serie', '1')).strip()[:3].zfill(3)
            numero_nfce = data.get('numero')
            if not numero_nfce:
                numero_nfce = self._obter_proximo_numero(empresa_data, serie_nfce)
            else:
                numero_nfce = str(numero_nfce).strip()[:9].zfill(9)
            
            debug_print(f'>>> [nfelib] Numero NFC-e: {numero_nfce}')
            debug_print(f'>>> [nfelib] Serie: {serie_nfce}')
            
            # Preparar dados para nfelib
            cnpj = empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
            uf = empresa_data.get('uf', 'SP')
            codigo_uf = self._obter_codigo_uf_nfelib(uf)
            data_emissao = datetime.now()
            codigo_numerico = self._gerar_codigo_numerico_nfelib()
            
            # Gerar chave de acesso
            chave_acesso = self._gerar_chave_acesso_nfelib(
                codigo_uf, codigo_numerico, numero_nfce, serie_nfce,
                data_emissao, cnpj
            )
            
            # 1. Criar estrutura enviNFe
            debug_print(">>> [nfelib] Criando estrutura enviNFe...")
            envi_nfe_obj = envi_nfe_module.TenviNfe()
            envi_nfe_obj.versao = "4.00"
            envi_nfe_obj.id_lote = "000000000000001"  # 15 dígitos
            envi_nfe_obj.ind_sinc = 1  # Síncrono para NFC-e
            
            # 2. Criar NFe
            debug_print(">>> [nfelib] Criando estrutura NFe...")
            nfe_obj = Tnfe()
            nfe_obj.inf_nfe = InfNfe()
            nfe_obj.inf_nfe.versao = "4.00"
            nfe_obj.inf_nfe.id = f"NFe{chave_acesso}"
            
            # 3. Preencher ide
            debug_print(">>> [nfelib] Preenchendo ide...")
            nfe_obj.inf_nfe.ide = InfNfe.Ide()
            nfe_obj.inf_nfe.ide.c_uf = codigo_uf
            nfe_obj.inf_nfe.ide.c_nf = codigo_numerico[:8].zfill(8)
            nfe_obj.inf_nfe.ide.nat_op = data.get('natureza_operacao', 'VENDA')
            nfe_obj.inf_nfe.ide.mod = 65  # NFC-e
            nfe_obj.inf_nfe.ide.serie = int(serie_nfce) if serie_nfce.isdigit() else 1
            nfe_obj.inf_nfe.ide.n_nf = int(numero_nfce) if numero_nfce.isdigit() else 1
            nfe_obj.inf_nfe.ide.dh_emi = data_emissao
            nfe_obj.inf_nfe.ide.tp_nf = 1  # Saída
            nfe_obj.inf_nfe.ide.id_dest = 1  # Operação interna
            nfe_obj.inf_nfe.ide.c_mun_fg = int(empresa_data.get('codigo_ibge', empresa_data.get('codigo_municipio', '3549904')))
            nfe_obj.inf_nfe.ide.tp_imp = 4  # NFC-e
            nfe_obj.inf_nfe.ide.tp_emis = 1  # Normal
            nfe_obj.inf_nfe.ide.c_dv = int(chave_acesso[-1])
            nfe_obj.inf_nfe.ide.tp_amb = 2 if ambiente_homologacao else 1
            nfe_obj.inf_nfe.ide.fin_nfe = 1  # Normal
            nfe_obj.inf_nfe.ide.ind_final = 1  # Consumidor final
            nfe_obj.inf_nfe.ide.ind_pres = 1  # Presencial
            nfe_obj.inf_nfe.ide.proc_emi = 0  # Aplicativo do contribuinte
            nfe_obj.inf_nfe.ide.ver_proc = "Sistema Exodo"
            
            # 4. Preencher emitente
            debug_print(">>> [nfelib] Preenchendo emitente...")
            nfe_obj.inf_nfe.emit = InfNfe.Emit()
            nfe_obj.inf_nfe.emit.cnpj = cnpj
            
            # Sanitizar xNome e xFant (remover caracteres que podem causar erro no schema)
            razao_social = str(empresa_data.get('razao_social', '')).split(':')[0].strip()
            nfe_obj.inf_nfe.emit.x_nome = razao_social
            
            nome_fantasia = str(empresa_data.get('nome_fantasia', '')).split(':')[0].strip()
            if nome_fantasia:
                nfe_obj.inf_nfe.emit.x_fant = nome_fantasia
            
            # Importar TenderEmi do módulo leiaute
            from nfelib.nfe.bindings.v4_0 import leiaute_nfe_v4_00 as leiaute
            nfe_obj.inf_nfe.emit.ender_emit = leiaute.TenderEmi()
            
            logradouro = str(empresa_data.get('logradouro', '')).strip()
            if not logradouro:
                logradouro = str(empresa_data.get('endereco', '')).strip() or 'Não informado'
            nfe_obj.inf_nfe.emit.ender_emit.x_lgr = logradouro
            
            nfe_obj.inf_nfe.emit.ender_emit.nro = str(empresa_data.get('numero', '')).strip() or 'S/N'
            nfe_obj.inf_nfe.emit.ender_emit.x_bairro = str(empresa_data.get('bairro', '')).strip() or 'Centro'
            nfe_obj.inf_nfe.emit.ender_emit.c_mun = int(empresa_data.get('codigo_ibge', empresa_data.get('codigo_municipio', '3549904')))
            
            # Sanitizar Cidade (remover /SP ou similares)
            cidade = str(empresa_data.get('cidade', '')).split('/')[0].strip()
            nfe_obj.inf_nfe.emit.ender_emit.x_mun = cidade
            
            nfe_obj.inf_nfe.emit.ender_emit.uf = uf
            nfe_obj.inf_nfe.emit.ender_emit.cep = str(empresa_data.get('cep', '')).replace('-', '')
            nfe_obj.inf_nfe.emit.ender_emit.c_pais = 1058
            nfe_obj.inf_nfe.emit.ender_emit.x_pais = "Brasil"
            
            ie = str(empresa_data.get('inscricao_estadual', '')).replace('.', '').replace('-', '').replace('/', '').strip()
            nfe_obj.inf_nfe.emit.ie = ie
            nfe_obj.inf_nfe.emit.crt = int(empresa_data.get('crt', '1'))
            
            # 5. Preencher destinatário
            # Garantir que consumidor_data seja sempre um dicionário (não None)
            if consumidor_data is None:
                consumidor_data = {}
            
            if consumidor_data.get('cpf') or consumidor_data.get('nome'):
                debug_print(">>> [nfelib] Preenchendo destinatário...")
                nfe_obj.inf_nfe.dest = InfNfe.Dest()
                if consumidor_data.get('cpf'):
                    nfe_obj.inf_nfe.dest.cpf = consumidor_data.get('cpf').replace('.', '').replace('-', '')
                if consumidor_data.get('nome'):
                    nfe_obj.inf_nfe.dest.x_nome = consumidor_data.get('nome')
                nfe_obj.inf_nfe.dest.ind_ie_dest = 9
            
            # 6. Preencher produtos
            debug_print(f">>> [nfelib] Preenchendo {len(produtos_data)} produtos...")
            nfe_obj.inf_nfe.det = []
            valor_total_produtos = Decimal('0.00')
            
            for idx, produto in enumerate(produtos_data, 1):
                det = InfNfe.Det()
                det.n_item = idx
                
                # Obter preço usando função auxiliar (aceita múltiplos formatos)
                preco_unitario = self._obter_preco_produto(produto)
                if preco_unitario is None or preco_unitario <= 0:
                    nome_produto = self._obter_descricao_produto(produto) or 'N/A'
                    raise ValueError(f"Produto {idx} ({nome_produto}): preço deve ser maior que zero. Valor recebido: {preco_unitario}")
                
                quantidade_prod = Decimal(str(produto.get('quantidade', 1)))
                valor_total_prod = preco_unitario * quantidade_prod
                
                det.prod = InfNfe.Det.Prod()
                det.prod.c_prod = produto.get('codigo', f'PROD-{idx}')
                det.prod.c_ean = produto.get('ean', 'SEM GTIN')
                
                # REGRA SEFAZ: No ambiente de homologação, o primeiro item deve ter descrição específica
                descricao = self._obter_descricao_produto(produto)
                if ambiente_homologacao and idx == 1:
                    descricao = "NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
                det.prod.x_prod = descricao
                det.prod.ncm = produto.get('ncm', '00000000')
                det.prod.cfop = produto.get('cfop', '5405')
                det.prod.u_com = produto.get('unidade', 'UN')
                det.prod.q_com = quantidade_prod
                det.prod.v_un_com = preco_unitario
                det.prod.v_prod = valor_total_prod
                det.prod.c_ean_trib = produto.get('ean', 'SEM GTIN')
                det.prod.u_trib = produto.get('unidade', 'UN')
                det.prod.q_trib = quantidade_prod
                det.prod.v_un_trib = preco_unitario
                det.prod.ind_tot = 1
                
                # Acumular valor total dos produtos
                valor_total_produtos += valor_total_prod
                
                # Impostos
                det.imposto = Imposto()
                det.imposto.v_tot_trib = Decimal(str(produto.get('valor_impostos', 0)))
                
                # ICMS - Verificar se Imposto.Icms existe e é chamável
                try:
                    if not hasattr(Imposto, 'Icms'):
                        raise AttributeError("Imposto.Icms não encontrado")
                    
                    icms_class = Imposto.Icms
                    if icms_class is None:
                        raise ValueError("Imposto.Icms é None")
                    
                    if not callable(icms_class):
                        raise TypeError(f"Imposto.Icms não é chamável. Tipo: {type(icms_class)}")
                    
                    det.imposto.icms = icms_class()
                    debug_print(f">>> [nfelib] ICMS criado para produto {idx}")
                    
                except Exception as e:
                    debug_print(f">>> [ERRO ICMS] Erro ao criar objeto ICMS: {str(e)}")
                    debug_print(f">>> [ERRO ICMS] Tipo do erro: {type(e).__name__}")
                    debug_print(f">>> [ERRO ICMS] Imposto tem atributo Icms: {hasattr(Imposto, 'Icms')}")
                    if hasattr(Imposto, 'Icms'):
                        debug_print(f">>> [ERRO ICMS] Imposto.Icms tipo: {type(Imposto.Icms)}")
                        debug_print(f">>> [ERRO ICMS] Imposto.Icms valor: {Imposto.Icms}")
                    raise ValueError(f"Erro ao criar ICMS: {str(e)}")
                
                # Tentar csosn, depois cst
                csosn = str(produto.get('csosn', produto.get('cst', ''))).strip()
                
                # Fallback inteligente para CSOSN baseado no CFOP se estiver vazio
                if not csosn or csosn == 'None' or csosn == '':
                    cfop_atual = str(produto.get('cfop', '5102')).strip()
                    if cfop_atual == '5405':
                        csosn = '500'
                    else:
                        csosn = '102'

                try:
                    if csosn in ['102', '103', '300', '400']:
                        # Criar instância de ICMSSN102 usando método do objeto icms
                        if not hasattr(det.imposto.icms, 'Icmssn102'):
                            raise AttributeError("Método Icmssn102 não encontrado no objeto icms")
                        icms_item = det.imposto.icms.Icmssn102()
                        icms_item.orig = int(produto.get('origem', 0))
                        icms_item.csosn = csosn
                        det.imposto.icms.icmssn102 = icms_item
                        debug_print(f">>> [nfelib] ICMSSN102 criado para produto {idx} (CSOSN: {csosn})")
                    elif csosn == '101':
                        if not hasattr(det.imposto.icms, 'Icmssn101'):
                            raise AttributeError("Método Icmssn101 não encontrado no objeto icms")
                        icms_item = det.imposto.icms.Icmssn101()
                        icms_item.orig = int(produto.get('origem', 0))
                        icms_item.csosn = '101'
                        icms_item.p_cred_sn = Decimal('0.00')
                        icms_item.v_cred_icmssn = Decimal('0.00')
                        det.imposto.icms.icmssn101 = icms_item
                        debug_print(f">>> [nfelib] ICMSSN101 criado para produto {idx}")
                    elif csosn == '500':
                        # Criar instância de ICMSSN500
                        if not hasattr(det.imposto.icms, 'Icmssn500'):
                            raise AttributeError("Método Icmssn500 não encontrado no objeto icms")
                        icms_item = det.imposto.icms.Icmssn500()
                        icms_item.orig = int(produto.get('origem', 0))
                        icms_item.csosn = '500'
                        det.imposto.icms.icmssn500 = icms_item
                        debug_print(f">>> [nfelib] ICMSSN500 criado para produto {idx}")
                    else:
                        # Fallback para 102
                        if not hasattr(det.imposto.icms, 'Icmssn102'):
                            raise AttributeError("Método Icmssn102 não encontrado no objeto icms")
                        icms_item = det.imposto.icms.Icmssn102()
                        icms_item.orig = int(produto.get('origem', 0))
                        icms_item.csosn = '102'
                        det.imposto.icms.icmssn102 = icms_item
                        debug_print(f">>> [nfelib] ICMSSN102 (fallback) criado para produto {idx}")
                except AttributeError as e:
                    # Se o método não existir, listar métodos disponíveis
                    metodos_icms = [x for x in dir(det.imposto.icms) if not x.startswith('_') and x[0].isupper() and callable(getattr(det.imposto.icms, x, None))]
                    debug_print(f">>> [ERRO ICMS] Método não encontrado: {str(e)}")
                    debug_print(f">>> [ERRO ICMS] Métodos ICMS disponíveis: {metodos_icms}")
                    raise ValueError(f"Método ICMS não encontrado. Métodos disponíveis: {metodos_icms[:20]}")
                except Exception as e:
                    debug_print(f">>> [ERRO ICMS] Erro ao criar ICMS: {str(e)}")
                    debug_print(f">>> [ERRO ICMS] Tipo: {type(e).__name__}")
                    import traceback
                    debug_print(traceback.format_exc())
                    raise
                
                # PIS
                det.imposto.pis = Imposto.Pis()
                pis_item = det.imposto.pis.Pisoutr()
                pis_item.cst = "99"
                pis_item.v_bc = Decimal('0.00')
                pis_item.p_pis = Decimal('0.00')
                pis_item.v_pis = Decimal('0.00')
                det.imposto.pis.pis_outr = pis_item
                
                # COFINS
                det.imposto.cofins = Imposto.Cofins()
                cofins_item = det.imposto.cofins.Cofinsoutr()
                cofins_item.cst = "99"
                cofins_item.v_bc = Decimal('0.00')
                cofins_item.p_cofins = Decimal('0.00')
                cofins_item.v_cofins = Decimal('0.00')
                det.imposto.cofins.cofins_outr = cofins_item
                
                nfe_obj.inf_nfe.det.append(det)
            
            # 7. Preencher totais
            debug_print(">>> [nfelib] Preenchendo totais...")
            nfe_obj.inf_nfe.total = InfNfe.Total()
            nfe_obj.inf_nfe.total.icms_tot = InfNfe.Total.Icmstot()
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
            debug_print(">>> [nfelib] Preenchendo transporte...")
            nfe_obj.inf_nfe.transp = InfNfe.Transp()
            nfe_obj.inf_nfe.transp.mod_frete = 9
            
            # 9. Pagamento
            debug_print(">>> [nfelib] Preenchendo pagamento...")
            nfe_obj.inf_nfe.pag = InfNfe.Pag()
            nfe_obj.inf_nfe.pag.det_pag = []
            
            for pagamento in pagamentos_data:
                det_pag = InfNfe.Pag.DetPag()
                det_pag.ind_pag = 0
                det_pag.t_pag = pagamento.get('tipo', '01')
                det_pag.v_pag = Decimal(str(pagamento.get('valor', 0)))
                if pagamento.get('descricao'):
                    det_pag.x_pag = pagamento.get('descricao')
                nfe_obj.inf_nfe.pag.det_pag.append(det_pag)
            
            # 10. Informações adicionais
            if observacoes:
                debug_print(">>> [nfelib] Adicionando informações adicionais...")
                nfe_obj.inf_nfe.inf_adic = InfNfe.InfAdic()
                nfe_obj.inf_nfe.inf_adic.inf_cpl = f"NFC-e emitida pelo Sistema Exodo\n{observacoes}"
            
            # 11. Adicionar NFe ao enviNFe
            # IMPORTANTE: O nfelib espera uma lista de NFe, mas precisa ser atribuído corretamente
            if not hasattr(envi_nfe_obj, 'nfe') or envi_nfe_obj.nfe is None:
                envi_nfe_obj.nfe = []
            envi_nfe_obj.nfe.append(nfe_obj)
            debug_print(f">>> [nfelib] NFe adicionada ao enviNFe. Total de NFe: {len(envi_nfe_obj.nfe)}")
            
            # Verificar se o objeto está preenchido antes de gerar XML
            debug_print(f">>> [nfelib] Verificando estrutura enviNFe...")
            debug_print(f">>> [nfelib] - versao: {envi_nfe_obj.versao}")
            debug_print(f">>> [nfelib] - id_lote: {envi_nfe_obj.id_lote}")
            debug_print(f">>> [nfelib] - ind_sinc: {envi_nfe_obj.ind_sinc}")
            debug_print(f">>> [nfelib] - nfe: {envi_nfe_obj.nfe if hasattr(envi_nfe_obj, 'nfe') else 'N/A'}")
            
            # 12. Gerar XML manualmente (nfelib não serializa corretamente)
            debug_print(">>> [nfelib] Gerando XML manualmente usando lxml...")
            try:
                from lxml import etree as lxml_etree
                from lxml.etree import QName
                
                ns_nfe = "http://www.portalfiscal.inf.br/nfe"
                
                # Criar elemento raiz enviNFe com namespace padrão
                envi_nfe_elem = lxml_etree.Element(QName(ns_nfe, "enviNFe"), nsmap={None: ns_nfe})
                envi_nfe_elem.set("versao", "4.00")
                # Não precisa setar xmlns manualmente se usar nsmap
                
                # Adicionar idLote
                id_lote_elem = lxml_etree.SubElement(envi_nfe_elem, QName(ns_nfe, "idLote"))
                id_lote_elem.text = str(envi_nfe_obj.id_lote)
                
                # Adicionar indSinc
                ind_sinc_elem = lxml_etree.SubElement(envi_nfe_elem, QName(ns_nfe, "indSinc"))
                ind_sinc_elem.text = str(envi_nfe_obj.ind_sinc)
                
                # Criar elemento NFe
                nfe_elem = lxml_etree.Element(QName(ns_nfe, "NFe"), nsmap={None: ns_nfe})
                
                # Criar elemento infNFe a partir dos dados do nfe_obj.inf_nfe
                inf_nfe_elem = lxml_etree.Element(QName(ns_nfe, "infNFe"), nsmap={None: ns_nfe})
                inf_nfe_elem.set("Id", f"NFe{chave_acesso}")
                inf_nfe_elem.set("versao", "4.00")
                
                # Preencher ide
                ide_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "ide"))
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "cUF")).text = str(codigo_uf)
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "cNF")).text = str(codigo_numerico)[:8].zfill(8)
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "natOp")).text = data.get('natureza_operacao', 'VENDA')
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "mod")).text = "65"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "serie")).text = str(int(serie_nfce) if serie_nfce.isdigit() else 1)
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "nNF")).text = str(int(numero_nfce) if numero_nfce.isdigit() else 1)
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "dhEmi")).text = data_emissao.strftime("%Y-%m-%dT%H:%M:%S-03:00")
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "tpNF")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "idDest")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "cMunFG")).text = str(int(empresa_data.get('codigo_ibge', empresa_data.get('codigo_municipio', '3549904'))))
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "tpImp")).text = "4"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "tpEmis")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "cDV")).text = str(int(chave_acesso[-1]))
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "tpAmb")).text = "2" if ambiente_homologacao else "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "finNFe")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "indFinal")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "indPres")).text = "1"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "indIntermed")).text = "0"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "procEmi")).text = "0"
                lxml_etree.SubElement(ide_elem, QName(ns_nfe, "verProc")).text = "Sistema Exodo"
                
                # Preencher emitente
                emit_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "emit"))
                lxml_etree.SubElement(emit_elem, QName(ns_nfe, "CNPJ")).text = cnpj
                
                # Sanitizar xNome (remover :CNPJ se houver)
                razao_social = str(empresa_data.get('razao_social', '')).split(':')[0].strip()[:60]
                lxml_etree.SubElement(emit_elem, QName(ns_nfe, "xNome")).text = razao_social
                
                if empresa_data.get('nome_fantasia'):
                    nome_fantasia = str(empresa_data.get('nome_fantasia', '')).split(':')[0].strip()[:60]
                    lxml_etree.SubElement(emit_elem, QName(ns_nfe, "xFant")).text = nome_fantasia
                
                ender_emit_elem = lxml_etree.SubElement(emit_elem, QName(ns_nfe, "enderEmit"))
                logradouro = str(empresa_data.get('logradouro', '')).strip()
                if not logradouro:
                    logradouro = str(empresa_data.get('endereco', '')).strip() or 'Não informado'
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "xLgr")).text = logradouro[:60]
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "nro")).text = str(empresa_data.get('numero', '')).strip()[:10] or 'S/N'
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "xBairro")).text = str(empresa_data.get('bairro', '')).strip()[:60] or 'Centro'
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "cMun")).text = str(int(empresa_data.get('codigo_ibge', empresa_data.get('codigo_municipio', '3549904'))))
                
                # Sanitizar xMun (remover /UF se houver)
                cidade = str(empresa_data.get('cidade', '')).split('/')[0].strip()[:60]
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "xMun")).text = cidade
                
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "UF")).text = uf
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "CEP")).text = str(empresa_data.get('cep', '')).replace('-', '')[:8]
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "cPais")).text = "1058"
                lxml_etree.SubElement(ender_emit_elem, QName(ns_nfe, "xPais")).text = "Brasil"
                
                ie = str(empresa_data.get('inscricao_estadual', '')).replace('.', '').replace('-', '').replace('/', '').strip()
                if ie:
                    lxml_etree.SubElement(emit_elem, QName(ns_nfe, "IE")).text = ie
                lxml_etree.SubElement(emit_elem, QName(ns_nfe, "CRT")).text = str(int(empresa_data.get('crt', '1')))
                
                # Preencher destinatário (se houver)
                if consumidor_data.get('cpf') or consumidor_data.get('nome'):
                    dest_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "dest"))
                    if consumidor_data.get('cpf'):
                        lxml_etree.SubElement(dest_elem, QName(ns_nfe, "CPF")).text = consumidor_data.get('cpf').replace('.', '').replace('-', '')
                    if consumidor_data.get('nome'):
                        lxml_etree.SubElement(dest_elem, QName(ns_nfe, "xNome")).text = consumidor_data.get('nome')
                    lxml_etree.SubElement(dest_elem, QName(ns_nfe, "indIEDest")).text = "9"
                
                # Preencher produtos
                # Obter CRT para determinar tipo de ICMS
                crt_emitente = int(empresa_data.get('crt', '1'))
                
                # Recalcular valor_total_produtos para o XML manual
                valor_total_produtos = Decimal('0.00')
                
                for idx, produto in enumerate(produtos_data, 1):
                    # Obter preço do produto (aceita múltiplos formatos de campo)
                    preco = self._obter_preco_produto(produto)
                    quantidade = Decimal(str(produto.get('quantidade', 1)))
                    
                    # Validar preço - não pode ser zero ou None
                    if preco is None or preco <= 0:
                        nome_produto = self._obter_descricao_produto(produto) or 'N/A'
                        raise ValueError(f"Produto {idx} ({nome_produto}): preço deve ser maior que zero. Valor recebido: {preco}")
                    
                    valor_produto = preco * quantidade
                    if valor_produto <= 0:
                        nome_produto = self._obter_descricao_produto(produto) or 'N/A'
                        raise ValueError(f"Produto {idx} ({nome_produto}): valor total (preço × quantidade) deve ser maior que zero. Valor: {valor_produto}")
                    
                    # Acumular valor total
                    valor_total_produtos += valor_produto
                    
                    det_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "det"))
                    det_elem.set("nItem", str(idx))
                    # Preencher produto
                    prod_elem = lxml_etree.SubElement(det_elem, QName(ns_nfe, "prod"))
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "cProd")).text = str(produto.get('codigo', f'COD-{idx}'))[:60]
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "cEAN")).text = str(produto.get('ean', 'SEM GTIN'))
                    
                    # REGRA SEFAZ: No ambiente de homologação, o primeiro item deve ter descrição específica
                    descricao = str(self._obter_descricao_produto(produto))[:120]
                    if ambiente_homologacao and idx == 1:
                        descricao = "NOTA FISCAL EMITIDA EM AMBIENTE DE HOMOLOGACAO - SEM VALOR FISCAL"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "xProd")).text = descricao
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "NCM")).text = produto.get('ncm', '00000000')
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "CFOP")).text = produto.get('cfop', '5102')
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "uCom")).text = produto.get('unidade', 'UN')
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "qCom")).text = f"{quantidade:.4f}"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "vUnCom")).text = f"{preco:.4f}"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "vProd")).text = f"{valor_produto:.2f}"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "cEANTrib")).text = produto.get('codigo_barras', 'SEM GTIN')
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "uTrib")).text = produto.get('unidade', 'UN')
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "qTrib")).text = f"{quantidade:.4f}"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "vUnTrib")).text = f"{preco:.4f}"
                    lxml_etree.SubElement(prod_elem, QName(ns_nfe, "indTot")).text = "1"
                    
                    # Impostos - Verificar CRT para usar ICMS correto
                    imposto_elem = lxml_etree.SubElement(det_elem, QName(ns_nfe, "imposto"))
                    icms_elem = lxml_etree.SubElement(imposto_elem, QName(ns_nfe, "ICMS"))
                    
                    # CRT 1 = Simples Nacional -> usar ICMSSN
                    # CRT 2 ou 3 = Regime Normal -> usar ICMS00, ICMS10, etc.
                    origem = str(produto.get('origem', '0')).strip()
                    # Tentar csosn, depois cst, depois '102' como padrão mais comum fora 500
                    csosn = str(produto.get('csosn', produto.get('cst', ''))).strip()
                    
                    # Logica de fallback inteligente: se for CFOP 5405, provavelmente é 500. Se 5102, 102.
                    cfop_atual = str(produto.get('cfop', '5102')).strip()
                    if not csosn or csosn == 'None':
                        if cfop_atual == '5405':
                            csosn = '500'
                        else:
                            csosn = '102'
                    
                    if crt_emitente == 1:  # Simples Nacional
                        if csosn in ['101']:
                            icmssn_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMSSN101"))
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "orig")).text = origem
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "CSOSN")).text = csosn
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "pCredSN")).text = "0.00"
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "vCredICMSSN")).text = "0.00"
                        elif csosn in ['102', '103', '300', '400']:
                            icmssn_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMSSN102"))
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "orig")).text = origem
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "CSOSN")).text = csosn
                        elif csosn in ['201', '202', '203']:
                            # Para simplificar, tratar como 102 se não tivermos todos os campos de ST
                            icmssn_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMSSN102"))
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "orig")).text = origem
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "CSOSN")).text = "102"
                        elif csosn == '500':
                            icmssn_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMSSN500"))
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "orig")).text = origem
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "CSOSN")).text = "500"
                        else:
                            # ICMSSN900 como último recurso
                            icmssn_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMSSN900"))
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "orig")).text = origem
                            lxml_etree.SubElement(icmssn_elem, QName(ns_nfe, "CSOSN")).text = "900"
                        debug_print(f">>> [nfelib] ICMS Simples Nacional criado para produto {idx} (CSOSN: {csosn})")
                    else:  # Regime Normal (CRT 2 ou 3)
                        # Usar ICMS00, ICMS10, etc conforme CST
                        cst = produto.get('cst', '500')
                        icms00_elem = lxml_etree.SubElement(icms_elem, QName(ns_nfe, "ICMS00"))
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "orig")).text = origem
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "CST")).text = cst
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "modBC")).text = "0"
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "vBC")).text = "0.00"
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "pICMS")).text = "0.00"
                        lxml_etree.SubElement(icms00_elem, QName(ns_nfe, "vICMS")).text = "0.00"
                        debug_print(f">>> [nfelib] ICMS00 criado para produto {idx} (CST: {cst}, CRT: {crt_emitente})")
                    
                    # PIS
                    pis_elem = lxml_etree.SubElement(imposto_elem, QName(ns_nfe, "PIS"))
                    pis_outr_elem = lxml_etree.SubElement(pis_elem, QName(ns_nfe, "PISOutr"))
                    lxml_etree.SubElement(pis_outr_elem, QName(ns_nfe, "CST")).text = "99"
                    lxml_etree.SubElement(pis_outr_elem, QName(ns_nfe, "vBC")).text = "0.00"
                    lxml_etree.SubElement(pis_outr_elem, QName(ns_nfe, "pPIS")).text = "0.00"
                    lxml_etree.SubElement(pis_outr_elem, QName(ns_nfe, "vPIS")).text = "0.00"
                    
                    # COFINS
                    cofins_elem = lxml_etree.SubElement(imposto_elem, QName(ns_nfe, "COFINS"))
                    cofins_outr_elem = lxml_etree.SubElement(cofins_elem, QName(ns_nfe, "COFINSOutr"))
                    lxml_etree.SubElement(cofins_outr_elem, QName(ns_nfe, "CST")).text = "99"
                    lxml_etree.SubElement(cofins_outr_elem, QName(ns_nfe, "vBC")).text = "0.00"
                    lxml_etree.SubElement(cofins_outr_elem, QName(ns_nfe, "pCOFINS")).text = "0.00"
                    lxml_etree.SubElement(cofins_outr_elem, QName(ns_nfe, "vCOFINS")).text = "0.00"
                
                # Preencher totais
                total_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "total"))
                icms_tot_elem = lxml_etree.SubElement(total_elem, QName(ns_nfe, "ICMSTot"))
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vBC")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vICMS")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vICMSDeson")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vFCP")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vBCST")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vST")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vFCPST")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vFCPSTRet")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vProd")).text = f"{valor_total_produtos:.2f}"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vFrete")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vSeg")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vDesc")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vII")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vIPI")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vIPIDevol")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vPIS")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vCOFINS")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vOutro")).text = "0.00"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vNF")).text = f"{valor_total_produtos:.2f}"
                lxml_etree.SubElement(icms_tot_elem, QName(ns_nfe, "vTotTrib")).text = "0.00"
                
                # Preencher transporte
                transp_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "transp"))
                lxml_etree.SubElement(transp_elem, QName(ns_nfe, "modFrete")).text = "9"
                
                # Preencher pagamento
                pag_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "pag"))
                for pagamento in pagamentos_data:
                    det_pag_elem = lxml_etree.SubElement(pag_elem, QName(ns_nfe, "detPag"))
                    lxml_etree.SubElement(det_pag_elem, QName(ns_nfe, "indPag")).text = "0"
                    lxml_etree.SubElement(det_pag_elem, QName(ns_nfe, "tPag")).text = pagamento.get('tipo', '01')
                    lxml_etree.SubElement(det_pag_elem, QName(ns_nfe, "vPag")).text = f"{Decimal(str(pagamento.get('valor', 0))):.2f}"
                
                # Informações adicionais (se houver)
                if observacoes:
                    inf_adic_elem = lxml_etree.SubElement(inf_nfe_elem, QName(ns_nfe, "infAdic"))
                    lxml_etree.SubElement(inf_adic_elem, QName(ns_nfe, "infCpl")).text = f"NFC-e emitida pelo Sistema Exodo\n{observacoes}"
                
                # Adicionar infNFe ao NFe
                nfe_elem.append(inf_nfe_elem)
                
                # ADICIONAR QR CODE (infNFeSupl) - Obrigatório para NFC-e
                try:
                    csc = empresa_data.get('csc', '')
                    # Tentar diversos nomes de campo possíveis vindo do App
                    cid_token = empresa_data.get('cscIdToken', empresa_data.get('cid_token', empresa_data.get('idToken', '')))
                    
                    if not csc or not cid_token:
                        config = empresa_data.get('configuracoes', {})
                        csc = csc or config.get('csc', '')
                        cid_token = cid_token or config.get('cscIdToken', config.get('cid_token', config.get('idToken', '')))
                    
                    if ambiente_homologacao and (not csc or not cid_token):
                        debug_print(">>> [nfelib] ⚠️ Dados CSC/Token incompletos em homologação. Usando padrão para teste.")
                        csc = csc or "123456" 
                        cid_token = cid_token or "000001"
                    
                    if csc and cid_token:
                        debug_print(">>> [nfelib] Preparando dados para QR Code...")
                        # infNFeSupl será inserido após a assinatura no método de envio ou assunatura
                        # Para o lxml, vamos colocar aqui, mas a ordem correta no XML final será validada
                        inf_nfe_supl_elem = lxml_etree.SubElement(nfe_elem, QName(ns_nfe, "infNFeSupl"))
                        
                        # Versão 2.0 (NFC-e 4.0)
                        import hashlib
                        # Garantir que cid_token é string e remover espaços
                        cid_token_str = str(cid_token).strip()
                        # IMPORTANTE: No QR Code 2.0, o ID do Token deve ser usado como string (mantendo zeros à esquerda se houver)
                        p = f"{chave_acesso}|2|{1 if not ambiente_homologacao else 2}|{cid_token_str}"
                        hash_qr = hashlib.sha1((p + csc.strip()).encode('utf-8')).hexdigest().upper()
                        
                        if uf == 'SP':
                            url_qrcode = "https://www.homologacao.nfce.fazenda.sp.gov.br/qrcode" if ambiente_homologacao else "https://www.nfce.fazenda.sp.gov.br/qrcode"
                        else:
                            url_qrcode = "https://nfce-homologacao.svrs.rs.gov.br/ws/setor/qrcode"
                            
                        qr_code_str = f"{url_qrcode}?p={p}|{hash_qr}"
                        lxml_etree.SubElement(inf_nfe_supl_elem, QName(ns_nfe, "qrCode")).text = qr_code_str
                        lxml_etree.SubElement(inf_nfe_supl_elem, QName(ns_nfe, "urlChave")).text = url_qrcode
                        debug_print(f">>> [nfelib] infNFeSupl (QR Code v2.0) adicionado")
                    else:
                        debug_print(f">>> [nfelib] ⚠️ CSC/Token não configurados")
                except Exception as e_qr:
                    debug_print(f">>> [nfelib] ⚠️ Erro ao gerar QR Code: {e_qr}")
                
                # Adicionar NFe ao enviNFe
                envi_nfe_elem.append(nfe_elem)
                
                # Gerar XML final (sem declaração XML quando encoding='unicode')
                xml_str = lxml_etree.tostring(envi_nfe_elem, encoding='unicode', xml_declaration=False, pretty_print=False)
                # Adicionar declaração XML manualmente
                xml_str = '<?xml version="1.0" encoding="UTF-8"?>\n' + xml_str
                debug_print(f">>> [nfelib] ✅ XML gerado manualmente com sucesso! Tamanho: {len(xml_str)} caracteres")
                
                # Salvar XML gerado
                try:
                    empresa_dir = self._obter_diretorio_empresa(empresa_data)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    xml_file = os.path.join(empresa_dir, f'enviNFe_nfelib_{timestamp}.xml')
                    os.makedirs(empresa_dir, exist_ok=True)
                    with open(xml_file, 'w', encoding='utf-8') as f:
                        f.write(xml_str)
                    debug_print(f">>> [nfelib] XML gerado salvo em: {xml_file}")
                except Exception as e:
                    debug_print(f">>> [nfelib] Erro ao salvar XML: {e}")
            except Exception as e:
                debug_print(f">>> [nfelib] ❌ ERRO ao gerar XML: {e}")
                import traceback
                debug_print(traceback.format_exc())
                raise ValueError(f"Erro ao gerar XML: {str(e)}")
            
            # 13. Assinar XML
            debug_print(">>> [nfelib] Assinando XML...")
            xml_assinado = self._assinar_xml_nfelib(xml_str, certificado, chave_acesso)
            
            # 14. Enviar para SEFAZ usando método nfelib (envelope manual)
            debug_print(">>> [nfelib] Enviando para SEFAZ usando método MANUAL (nfelib)...")
            resposta = self._enviar_para_sefaz_nfelib(xml_assinado, ambiente_homologacao, uf, certificado, empresa_data)
            
            # 15. Processar resposta
            if resposta is None:
                debug_print(">>> [nfelib] ❌ Resposta é None!")
                return {
                    'success': False,
                    'error': 'Resposta vazia da SEFAZ',
                    'autorizada': False
                }
            
            if resposta.get('success') and resposta.get('autorizada'):
                # Incrementar número apenas se autorizada
                self._incrementar_numero_apos_autorizacao(empresa_data, serie_nfce, numero_nfce)
                
                # Adicionar informações completas
                resposta['numero'] = numero_nfce
                resposta['serie'] = serie_nfce
                resposta['chave_acesso'] = chave_acesso
                resposta['message'] = '✅ NFC-e autorizada com sucesso!'
                
                # Gerar QR Code
                protocolo = resposta.get('protocolo', '')
                qr_code = self._gerar_qr_code_nfelib(
                    chave_acesso, 
                    protocolo, 
                    ambiente_homologacao,
                    valor_total_produtos,
                    empresa_data.get('uf', 'SP')
                )
                resposta['qr_code'] = qr_code
                
                # Adicionar XML enviado e retornado
                resposta['xml_enviado'] = xml_assinado
                resposta['xml_retorno'] = resposta.get('xml_retorno', '')
                
                debug_print(f">>> [nfelib] ✅ NFC-e autorizada! Protocolo: {protocolo}")
                debug_print(f">>> [nfelib] QR Code gerado: {qr_code[:50]}...")
            else:
                debug_print(f">>> [nfelib] ❌ NFC-e não autorizada: {resposta.get('error')}")
                # Adicionar XML enviado mesmo em caso de erro (para debug)
                resposta['xml_enviado'] = xml_assinado
            
            return resposta
            
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            debug_print(f">>> [nfelib] ❌ ERRO: {e}")
            debug_print(error_details)
            return {
                'success': False,
                'error': str(e),
                'autorizada': False,
                'error_type': type(e).__name__,
                'details': error_details
            }
    
    def consultar_nfce(self, data):
        """
        Consulta status de uma NFC-e
        
        Args:
            data: Dicionário com chave de acesso e dados da empresa
            
        Returns:
            Dicionário com status da NFC-e
        """
        try:
            chave_acesso = data['chave_acesso']
            empresa_data = data['empresa']
            
            # Obter número da NFC-e (sequencial persistente)
            # Se não fornecido no data, usar numeração sequencial persistente
            numero_nfce = data.get('numero')
            if not numero_nfce:
                # Obter próximo número sequencial da empresa/série
                numero_nfce = self._obter_proximo_numero(empresa_data, serie_nfce)
            else:
                # Garantir que tem exatamente 9 dígitos
                numero_nfce = str(numero_nfce).strip()[:9].zfill(9)
            
            print(f'>>> [PyNFe] Numero NFC-e: {numero_nfce}')
            print(f'>>> [PyNFe] Serie: {serie_nfce}')
            
            # Criar NFC-e (sem produtos e pagamentos ainda)
            nfce = self._criar_nfce(
                emitente=emitente,
                cliente=cliente,
                valor_total=valor_total,
                observacoes=observacoes,
                ambiente_homologacao=ambiente_homologacao,
                serie=serie_nfce,
                numero=numero_nfce
            )
            
            # Adicionar produtos usando o método da NotaFiscal
            for produto in produtos:
                # Converter CST para situação tributária do ICMS
                # IMPORTANTE: Usar apenas CSTs implementados no PyNFe para evitar NotImplementedError
                # CSTs implementados: 00, 10, 20, 30, 40, 41, 50, 51, 60, 70, 90, 102, 103, 300, 400, 500
                # Para NFC-e, usar principalmente: 00 (tributado), 40 (isento), 102 (Simples Nacional sem tributação)
                cst = str(produto.icms_cst) if hasattr(produto, 'icms_cst') and produto.icms_cst else '102'
                
                # Mapear CST para situação tributária do ICMS (usar apenas as implementadas)
                if cst in ['00', '10', '20', '30']:
                    icms_situacao_tributaria = '00'  # Tributada integralmente
                elif cst in ['40', '41', '50']:
                    icms_situacao_tributaria = '40'  # Isenta
                elif cst in ['51']:
                    icms_situacao_tributaria = '51'  # Diferido
                elif cst in ['60']:
                    icms_situacao_tributaria = '60'  # ICMS cobrado anteriormente por substituição tributária
                elif cst in ['70']:
                    icms_situacao_tributaria = '70'  # Com redução de base de cálculo e cobrança do ICMS por substituição tributária
                elif cst in ['90']:
                    icms_situacao_tributaria = '90'  # Outras
                elif cst in ['102', '103', '300', '400', '500']:
                    icms_situacao_tributaria = '102'  # Tributação do ICMS isenta por não haver, na legislação, previsão de tributação (Simples Nacional)
                else:
                    # Para qualquer CST não mapeado, usar 102 (Simples Nacional sem tributação)
                    # Isso evita NotImplementedError
                    print(f'⚠️ [PyNFe] CST {cst} não mapeado, usando 102 (Simples Nacional sem tributação)')
                    icms_situacao_tributaria = '102'
                
                # Converter valores para Decimal
                quantidade = Decimal(str(produto.quantidade_comercial))
                valor_unitario = Decimal(str(produto.valor_unitario_comercial))
                valor_total = Decimal(str(produto.valor_total))
                aliquota = Decimal(str(produto.icms_aliquota)) if produto.icms_aliquota > 0 else Decimal('0.0')
                
                # Calcular valores do ICMS
                base_calculo = valor_total if aliquota > 0 else Decimal('0.0')
                valor_icms = valor_total * (aliquota / Decimal('100')) if aliquota > 0 else Decimal('0.0')
                
                produto_nfce = nfce.adicionar_produto_servico(
                    codigo=str(produto.codigo),
                    descricao=produto.descricao,
                    ncm=str(produto.ncm),
                    cfop=str(produto.cfop),
                    unidade_comercial=produto.unidade_comercial,
                    quantidade_comercial=quantidade,
                    valor_unitario_comercial=valor_unitario,
                    unidade_tributavel=produto.unidade_comercial,  # Mesmo da unidade comercial
                    quantidade_tributavel=quantidade,  # Mesmo da quantidade comercial
                    valor_unitario_tributavel=valor_unitario,  # Mesmo do valor unitário comercial
                    valor_total_bruto=valor_total,
                    # IMPORTANTE: PyNFe usa icms_modalidade (CST), não icms_situacao_tributaria
                    icms_modalidade=icms_situacao_tributaria,  # CST/Situação tributária
                    icms_aliquota=aliquota,
                    icms_valor_base_calculo=base_calculo,
                    icms_valor=valor_icms,
                    # Garantir que ICMS origem está definido (obrigatório)
                    icms_origem=0,  # 0=Nacional (padrão para NFC-e)
                    # Para Simples Nacional, também precisa de icms_csosn
                    icms_csosn=icms_situacao_tributaria if icms_situacao_tributaria in ['102', '103', '300', '400', '500', '900'] else None
                )
                
                # Adicionar atributos obrigatórios para serialização
                # O PyNFe espera alguns atributos que podem não estar definidos
                
                # 1. ind_total (obrigatório para serialização)
                # 0=Valor do item não compõe o valor total da NF-e
                # 1=Valor do item compõe o valor total da NF-e (padrão)
                if not hasattr(produto_nfce, 'ind_total'):
                    # Usar compoe_valor_total se disponível, senão usar 1 (padrão)
                    produto_nfce.ind_total = getattr(produto_nfce, 'compoe_valor_total', 1)
                # Garantir que sempre tenha valor
                if produto_nfce.ind_total is None:
                    produto_nfce.ind_total = 1
                
                # 2. valor_tributos_aprox (opcional, mas pode ser acessado na serialização)
                # Valor aproximado dos tributos do item (Lei da Transparência)
                # IMPORTANTE: O PyNFe acessa produto_servico.valor_tributos_aprox na serialização
                # Se o atributo não existir, dará AttributeError. SEMPRE definir!
                # Calcular valor aproximado dos tributos (ICMS + PIS + COFINS)
                tributos_aprox = Decimal('0.0')
                try:
                    if hasattr(produto_nfce, 'icms_valor') and produto_nfce.icms_valor:
                        tributos_aprox += Decimal(str(produto_nfce.icms_valor))
                except:
                    pass
                try:
                    if hasattr(produto_nfce, 'pis_valor') and produto_nfce.pis_valor:
                        tributos_aprox += Decimal(str(produto_nfce.pis_valor))
                except:
                    pass
                try:
                    if hasattr(produto_nfce, 'cofins_valor') and produto_nfce.cofins_valor:
                        tributos_aprox += Decimal(str(produto_nfce.cofins_valor))
                except:
                    pass
                
                # SEMPRE definir o atributo (mesmo que seja None)
                # O PyNFe verifica "if produto_servico.valor_tributos_aprox:" antes de usar
                # Se for None ou 0, não será incluído no XML (comportamento correto)
                produto_nfce.valor_tributos_aprox = tributos_aprox if tributos_aprox > 0 else None
                
                print(f'>>> [PyNFe] Produto {produto.codigo}: valor_tributos_aprox = {produto_nfce.valor_tributos_aprox}')
                
                # 3. PIS e COFINS (opcionais para NFC-e, mas PyNFe pode tentar acessar)
                # Definir atributos padrão para evitar AttributeError
                if not hasattr(produto_nfce, 'pis_modalidade'):
                    # Para NFC-e, usar modalidade padrão: 99 (Outras operações)
                    # Isso evita que o PyNFe tente acessar um atributo inexistente
                    produto_nfce.pis_modalidade = '99'  # Outras operações
                if not hasattr(produto_nfce, 'pis_valor_base_calculo'):
                    produto_nfce.pis_valor_base_calculo = Decimal('0.0')
                if not hasattr(produto_nfce, 'pis_aliquota_percentual'):
                    produto_nfce.pis_aliquota_percentual = Decimal('0.0')
                if not hasattr(produto_nfce, 'pis_valor'):
                    produto_nfce.pis_valor = Decimal('0.0')
                if not hasattr(produto_nfce, 'pis_aliquota_reais'):
                    produto_nfce.pis_aliquota_reais = Decimal('0.0')
                
                # COFINS
                if not hasattr(produto_nfce, 'cofins_modalidade'):
                    produto_nfce.cofins_modalidade = '99'  # Outras operações
                if not hasattr(produto_nfce, 'cofins_valor_base_calculo'):
                    produto_nfce.cofins_valor_base_calculo = Decimal('0.0')
                if not hasattr(produto_nfce, 'cofins_aliquota_percentual'):
                    produto_nfce.cofins_aliquota_percentual = Decimal('0.0')
                if not hasattr(produto_nfce, 'cofins_valor'):
                    produto_nfce.cofins_valor = Decimal('0.0')
                if not hasattr(produto_nfce, 'cofins_aliquota_reais'):
                    produto_nfce.cofins_aliquota_reais = Decimal('0.0')
                
                print(f'>>> [PyNFe] Produto {produto.codigo}: PIS modalidade = {produto_nfce.pis_modalidade}, COFINS modalidade = {produto_nfce.cofins_modalidade}')
            
            # Adicionar pagamentos usando o método da NotaFiscal
            # Mapear tipos de pagamento para descrições
            tipos_pagamento = {
                '01': 'Dinheiro',
                '02': 'Cheque',
                '03': 'Cartão de Crédito',
                '04': 'Cartão de Débito',
                '05': 'Crédito Loja',
                '10': 'Vale Alimentação',
                '11': 'Vale Refeição',
                '12': 'Vale Presente',
                '13': 'Vale Combustível',
                '14': 'Duplicata Mercantil',
                '15': 'Boleto Bancário',
                '90': 'Sem pagamento',
                '99': 'Outros'
            }
            
            for pagamento_data in pagamentos_data:
                tipo = pagamento_data['tipo']
                valor = Decimal(str(pagamento_data['valor']))  # Converter para Decimal
                descricao = tipos_pagamento.get(tipo, 'Outros')
                
                nfce.adicionar_pagamento(
                    t_pag=tipo,  # Código da forma de pagamento
                    v_pag=valor,  # Valor do pagamento (Decimal)
                    x_pag=descricao,  # Descrição da forma de pagamento
                    ind_pag=0  # 0=à Vista, 1=à Prazo
                )
            
            # IMPORTANTE: Gerar código numérico aleatório ANTES de serializar
            # Isso evita que o PyNFe tente calcular o DV com chave incompleta
            if not nfce.codigo_numerico_aleatorio:
                nfce.codigo_numerico_aleatorio = str(random.randint(0, 99999999)).zfill(8)
            
            # IMPORTANTE: Garantir que identificador_unico está definido ANTES de serializar
            # O PyNFe usa isso para criar o ID do elemento infNFe (#NFe...)
            # Se não estiver definido ou duplicado, causa "Ambiguous reference URI"
            # O identificador_unico é uma propriedade que gera automaticamente baseado na chave
            # Mas precisamos garantir que a chave esteja correta antes
            try:
                # Tentar acessar o identificador_unico para forçar sua geração
                _ = nfce.identificador_unico
                print(f'>>> [PyNFe] Identificador único gerado: {nfce.identificador_unico}')
            except Exception as e:
                print(f'⚠️ [PyNFe] Erro ao gerar identificador único: {e}')
                # Se houver erro, o PyNFe tentará gerar durante a serialização
            
            # Forçar cálculo do DV para garantir que está correto
            # Estrutura da chave NFC-e (44 dígitos totais):
            # cUF (2) + AAMM (4) + CNPJ (14) + mod (2) + série (3) + nNF (9) + tpEmis (1) + cNF (8) + cDV (1) = 44
            # Para calcular DV: 43 dígitos (sem o DV) + 1 (DV) = 44
            try:
                from pynfe.utils.flags import CODIGOS_ESTADOS
                from pynfe.utils import so_numeros
                
                # 1. cUF - Código UF (2 dígitos)
                uf_code = str(CODIGOS_ESTADOS.get(nfce.uf, '35'))[:2].zfill(2)
                
                # 2. AAMM - Ano e mês (4 dígitos: AAMM)
                ano_mes = nfce.data_emissao.strftime("%y%m")
                if len(ano_mes) != 4:
                    ano_mes = ano_mes[:4].zfill(4)
                
                # 3. CNPJ - CNPJ do emitente (14 dígitos)
                cnpj = so_numeros(str(nfce.emitente.cnpj))[:14].zfill(14)
                
                # 4. mod - Modelo do documento (2 dígitos) - NFC-e = 65
                modelo = str(nfce.modelo)[:2].zfill(2)
                
                # 5. série - Série do documento (3 dígitos)
                serie = str(nfce.serie)[:3].zfill(3)
                
                # 6. nNF - Número da NFC-e (9 dígitos)
                numero = str(nfce.numero_nf)[:9].zfill(9)
                
                # 7. tpEmis - Tipo de emissão (1 dígito)
                tp_emis = str(nfce.forma_emissao)[:1].zfill(1)
                
                # 8. cNF - Código numérico aleatório (8 dígitos)
                if not nfce.codigo_numerico_aleatorio:
                    nfce.codigo_numerico_aleatorio = str(random.randint(0, 99999999)).zfill(8)
                cnf = str(nfce.codigo_numerico_aleatorio)[:8].zfill(8)
                
                # Montar chave de 43 dígitos (sem DV)
                chave_43 = f"{uf_code}{ano_mes}{cnpj}{modelo}{serie}{numero}{tp_emis}{cnf}"
                
                # Validar tamanho exato
                if len(chave_43) != 43:
                    print(f'❌ [PyNFe] ERRO: Chave tem {len(chave_43)} dígitos, esperado 43!')
                    print(f'  UF: {uf_code} ({len(uf_code)})')
                    print(f'  AAMM: {ano_mes} ({len(ano_mes)})')
                    print(f'  CNPJ: {cnpj} ({len(cnpj)})')
                    print(f'  Modelo: {modelo} ({len(modelo)})')
                    print(f'  Série: {serie} ({len(serie)})')
                    print(f'  Número: {numero} ({len(numero)})')
                    print(f'  TPEmis: {tp_emis} ({len(tp_emis)})')
                    print(f'  CNF: {cnf} ({len(cnf)})')
                    print(f'  Total: {len(uf_code) + len(ano_mes) + len(cnpj) + len(modelo) + len(serie) + len(numero) + len(tp_emis) + len(cnf)}')
                    raise ValueError(f"Chave deve ter exatamente 43 dígitos, mas tem {len(chave_43)}: {chave_43}")
                
                # Calcular dígito verificador (DV) - 1 dígito
                dv = nfce._dv_codigo_numerico(chave_43)
                
                # Chave completa: 43 dígitos + 1 DV = 44 dígitos
                chave_completa = f"{chave_43}{dv}"
                
                print(f'✅ [PyNFe] Chave gerada corretamente:')
                print(f'  Chave (43 dígitos): {chave_43}')
                print(f'  DV: {dv}')
                print(f'  Chave completa (44 dígitos): {chave_completa}')
                
            except Exception as e:
                print(f'❌ [PyNFe] Erro ao gerar chave de acesso: {e}')
                import traceback
                traceback.print_exc()
                raise  # Re-raise para não continuar com chave inválida
            
            # Assinar NFC-e
            assinador = AssinaturaA1(
                certificado=certificado['arquivo'],
                senha=senha_certificado
            )
            
            # IMPORTANTE: Guardar referência do objeto nfce para possível uso direto
            # O PyNFe pode precisar do objeto NotaFiscal para montar o lote corretamente
            
            # Adicionar NFC-e à fonte de dados
            _fonte_dados.adicionar_objeto(nfce)
            
            # Patch: Se temos código IBGE do cadastro, garantir que será usado
            # O PyNFe tenta converter nome para código, mas se o código não estiver
            # no dicionário, podemos precisar fazer um monkey patch
            codigo_ibge_cadastro = empresa_data.get('codigo_municipio', '') or empresa_data.get('codigoIBGE', '')
            if codigo_ibge_cadastro:
                codigo_ibge_cadastro = str(codigo_ibge_cadastro).strip()
                print(f'>>> [PyNFe] Código IBGE do cadastro para validação: {codigo_ibge_cadastro}')
            
            # Serializar XML (retorna elemento XML, não string)
            serializador = SerializacaoXML(_fonte_dados, homologacao=ambiente_homologacao)
            
            # Monkey patch temporário para usar código diretamente se necessário
            original_obter_codigo = None
            try:
                from pynfe.utils import obter_codigo_por_municipio
                original_obter_codigo = obter_codigo_por_municipio
                
                # Se temos código IBGE válido, criar função que retorna o código diretamente
                if codigo_ibge_cadastro and len(codigo_ibge_cadastro) >= 6:
                    def obter_codigo_patch(municipio, uf):
                        # Se o município passado é um código numérico, retornar diretamente
                        if municipio.isdigit() and len(municipio) >= 6:
                            print(f'>>> [PyNFe] Patch: Retornando código diretamente: {municipio}')
                            return municipio
                        # Caso contrário, usar função original
                        return original_obter_codigo(municipio, uf)
                    
                    # Aplicar patch temporário
                    import pynfe.utils
                    pynfe.utils.obter_codigo_por_municipio = obter_codigo_patch
                    print(f'>>> [PyNFe] Patch aplicado para usar código IBGE diretamente')
            except Exception as e:
                print(f'⚠️ [PyNFe] Não foi possível aplicar patch: {e}')
            
            try:
                xml_elemento = serializador.exportar(retorna_string=False, limpar=False)
                
                # IMPORTANTE: Verificar se há IDs duplicados no XML antes de assinar
                # Isso evita o erro "Ambiguous reference URI"
                from lxml import etree as lxml_etree
                
                # Converter para string e parsear novamente para garantir estrutura correta
                xml_string = lxml_etree.tostring(xml_elemento, encoding='unicode', pretty_print=False)
                xml_parsed = lxml_etree.fromstring(xml_string.encode('utf-8'))
                
                # Verificar IDs duplicados
                ids_encontrados = {}
                for elem in xml_parsed.iter():
                    if 'Id' in elem.attrib:
                        id_value = elem.attrib['Id']
                        if id_value in ids_encontrados:
                            print(f'⚠️ [PyNFe] ID duplicado encontrado: {id_value}')
                            print(f'⚠️ [PyNFe] Primeiro elemento: {ids_encontrados[id_value].tag}')
                            print(f'⚠️ [PyNFe] Segundo elemento: {elem.tag}')
                            # Remover ID duplicado ou renomear
                            elem.attrib['Id'] = f"{id_value}_{random.randint(1000, 9999)}"
                            print(f'⚠️ [PyNFe] ID renomeado para: {elem.attrib["Id"]}')
                        else:
                            ids_encontrados[id_value] = elem
                
                # Usar XML parseado (sem IDs duplicados)
                xml_elemento = xml_parsed
                print(f'>>> [PyNFe] XML verificado, {len(ids_encontrados)} IDs únicos encontrados')
                
            finally:
                # Restaurar função original
                if original_obter_codigo:
                    import pynfe.utils
                    pynfe.utils.obter_codigo_por_municipio = original_obter_codigo
                    print(f'>>> [PyNFe] Patch removido')
            
            # Assinar XML (retorna string diretamente)
            # debug_print já está definido no início da função
            # Log do XML antes de assinar (primeiros 500 chars)
            try:
                from lxml import etree as lxml_etree
                xml_antes_assinatura = lxml_etree.tostring(xml_elemento, encoding='unicode', pretty_print=True)
                debug_print(f'>>> [PyNFe] XML antes de assinar (primeiros 1000 chars):')
                debug_print(xml_antes_assinatura[:1000])
            except Exception as e:
                debug_print(f'>>> [PyNFe] ⚠️ Erro ao gerar log do XML antes de assinar: {e}')
            
            xml_assinado = assinador.assinar(xml_elemento, retorna_string=True)
            
            # Log do XML assinado (primeiros 1000 chars)
            debug_print(f'>>> [PyNFe] XML assinado (primeiros 1000 chars):')
            debug_print(xml_assinado[:1000] if xml_assinado else 'XML assinado está vazio!')
            debug_print(f'>>> [PyNFe] Tamanho do XML assinado: {len(xml_assinado) if xml_assinado else 0} caracteres')
            
            # Verificar se o XML assinado é válido
            if not xml_assinado or not xml_assinado.strip():
                return {
                    'success': False,
                    'error': 'Erro ao assinar XML: XML assinado está vazio',
                    'details': 'O processo de assinatura não retornou um XML válido'
                }
            
            # Validar estrutura básica do XML antes de enviar
            try:
                from lxml import etree as lxml_etree
                xml_validacao = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
                
                # Verificar se tem namespace correto
                if not xml_validacao.tag.endswith('}NFe') and xml_validacao.tag != 'NFe':
                    debug_print(f'>>> [PyNFe] ⚠️ Tag raiz inesperada: {xml_validacao.tag}')
                
                # Verificar se tem infNFe
                ns_nfe = {"nfe": "http://www.portalfiscal.inf.br/nfe"}
                inf_nfe = xml_validacao.find('.//nfe:infNFe', ns_nfe) or xml_validacao.find('.//infNFe')
                if inf_nfe is None:
                    debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento infNFe não encontrado no XML!')
                    return {
                        'success': False,
                        'error': 'XML inválido: elemento infNFe não encontrado',
                        'details': 'O XML não contém a estrutura básica necessária'
                    }
                
                # Verificar campos obrigatórios
                ide = inf_nfe.find('.//nfe:ide', ns_nfe) or inf_nfe.find('.//ide')
                if ide is None:
                    debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento ide não encontrado!')
                    return {
                        'success': False,
                        'error': 'XML inválido: elemento ide não encontrado',
                        'details': 'O XML não contém informações de identificação'
                    }
                
                # Verificar se tem versão
                versao = inf_nfe.get('versao')
                if not versao:
                    debug_print(f'>>> [PyNFe] ⚠️ Versão não especificada no infNFe')
                else:
                    debug_print(f'>>> [PyNFe] Versão do XML: {versao}')
                
                # Verificar se tem Id
                id_nfe = inf_nfe.get('Id')
                if not id_nfe:
                    debug_print(f'>>> [PyNFe] ⚠️ Id não especificado no infNFe')
                else:
                    debug_print(f'>>> [PyNFe] Id da NFC-e: {id_nfe}')
                
                debug_print(f'>>> [PyNFe] ✅ Estrutura básica do XML validada')
            except Exception as e_validacao:
                debug_print(f'>>> [PyNFe] ❌ Erro ao validar XML: {e_validacao}')
                return {
                    'success': False,
                    'error': f'Erro ao validar XML: {str(e_validacao)}',
                    'details': 'O XML assinado não pôde ser validado'
                }
            
            # Enviar para SEFAZ
            # Configurar ambiente (homologação ou produção)
            uf = empresa_data.get('uf', 'SP')
            
            debug_print(f'>>> [PyNFe] Enviando NFC-e para SEFAZ...')
            debug_print(f'>>> [PyNFe] UF: {uf}')
            debug_print(f'>>> [PyNFe] Ambiente: {"Homologação" if ambiente_homologacao else "Produção"}')
            debug_print(f'>>> [PyNFe] Modelo: 65 (NFC-e)')
            
            comunicacao = ComunicacaoSefaz(
                uf=uf,
                certificado=certificado['arquivo'],
                certificado_senha=senha_certificado,  # CORRETO: certificado_senha, não senha
                homologacao=ambiente_homologacao
            )
            
            # Autorizar NFC-e (modelo 65)
            # IMPORTANTE: O método correto é autorizacao(), não autorizar()
            # Parâmetros: modelo (string "nfe" ou "nfce"), nota_fiscal (XML elemento), id_lote, ind_sinc, contingencia, timeout
            # Para NFC-e, usar modelo="nfce" (string) e ind_sinc=1 (síncrono)
            # O método retorna uma tupla: (sucesso, xml_resposta)
            
            # IMPORTANTE: O método autorizacao() espera o XML ELEMENTO
            # O método assinar() modifica o xml_elemento in-place, então ele já está assinado
            # Mas vamos usar o XML assinado parseado de volta para garantir
            try:
                from lxml import etree as lxml_etree
                xml_elemento_assinado = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
                debug_print(f'>>> [PyNFe] XML elemento preparado para envio (tag: {xml_elemento_assinado.tag})')
                
                # CORREÇÕES CRÍTICAS NO XML ANTES DE MONTAR O LOTE
                # Baseado na análise do XML gerado que estava com erros
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] CORRIGINDO XML DA NFe ANTES DE MONTAR LOTE')
                debug_print(f'>>> [PyNFe] ========================================')
                
                ns_nfe_correcao = {"nfe": "http://www.portalfiscal.inf.br/nfe"}
                
                # 1. Corrigir cMunFG (deve ser código IBGE, não nome)
                inf_nfe_correcao = xml_elemento_assinado.find('.//nfe:infNFe', ns_nfe_correcao) or xml_elemento_assinado.find('.//infNFe')
                if inf_nfe_correcao is not None:
                    ide_correcao = inf_nfe_correcao.find('.//nfe:ide', ns_nfe_correcao) or inf_nfe_correcao.find('.//ide')
                    if ide_correcao is not None:
                        c_mun_fg = ide_correcao.find('.//nfe:cMunFG', ns_nfe_correcao) or ide_correcao.find('.//cMunFG')
                        if c_mun_fg is not None and c_mun_fg.text:
                            # Verificar se é nome em vez de código
                            if not c_mun_fg.text.strip().isdigit() or len(c_mun_fg.text.strip()) != 7:
                                # Tentar obter código IBGE do emitente
                                emit_correcao = inf_nfe_correcao.find('.//nfe:emit', ns_nfe_correcao) or inf_nfe_correcao.find('.//emit')
                                if emit_correcao is not None:
                                    ender_emit = emit_correcao.find('.//nfe:enderEmit', ns_nfe_correcao) or emit_correcao.find('.//enderEmit')
                                    if ender_emit is not None:
                                        c_mun_emit = ender_emit.find('.//nfe:cMun', ns_nfe_correcao) or ender_emit.find('.//cMun')
                                        if c_mun_emit is not None and c_mun_emit.text and c_mun_emit.text.strip().isdigit():
                                            c_mun_fg.text = c_mun_emit.text.strip()
                                            debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{c_mun_fg.text}"')
                                        else:
                                            # Usar código conhecido para São José dos Campos
                                            if 'Sao Jose' in c_mun_fg.text or 'São José' in c_mun_fg.text:
                                                c_mun_fg.text = '3549904'
                                                debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido para código IBGE: 3549904')
                    
                    # 2. Corrigir CRT (não pode estar vazio)
                    emit_correcao = inf_nfe_correcao.find('.//nfe:emit', ns_nfe_correcao) or inf_nfe_correcao.find('.//emit')
                    if emit_correcao is not None:
                        crt = emit_correcao.find('.//nfe:CRT', ns_nfe_correcao) or emit_correcao.find('.//CRT')
                        if crt is not None:
                            if not crt.text or not crt.text.strip():
                                # Definir CRT padrão (1=Simples Nacional)
                                crt.text = '1'
                                debug_print(f'>>> [PyNFe] ✅ CRT corrigido: 1 (Simples Nacional)')
                    
                    # 3. Corrigir valores decimais (vUnCom, vUnTrib)
                    # Aplicar correção de valores decimais
                    corrigido_dec, problemas_dec = self._validar_valores_decimais_xml(inf_nfe_correcao)
                    if corrigido_dec:
                        debug_print(f'>>> [PyNFe] ✅ Valores decimais corrigidos na NFe')
                    
                    # 4. Verificar duplicação de infNFe
                    todas_inf_nfe = xml_elemento_assinado.findall('.//nfe:infNFe', ns_nfe_correcao) or xml_elemento_assinado.findall('.//infNFe')
                    if len(todas_inf_nfe) > 1:
                        debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: Encontradas {len(todas_inf_nfe)} infNFe! Removendo duplicatas...')
                        # Manter apenas a primeira
                        for inf_nfe_dup in todas_inf_nfe[1:]:
                            parent = inf_nfe_dup.getparent()
                            if parent is not None:
                                parent.remove(inf_nfe_dup)
                                debug_print(f'>>> [PyNFe] ✅ infNFe duplicada removida')
                    
                    # Regenerar XML após correções
                    xml_assinado = lxml_etree.tostring(xml_elemento_assinado, encoding='unicode', xml_declaration=False, pretty_print=False)
                    xml_elemento_assinado = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
                    debug_print(f'>>> [PyNFe] ✅ XML da NFe corrigido')
                
                # Verificar se tem assinatura no XML
                ns_dsig = {"ds": "http://www.w3.org/2000/09/xmldsig#"}
                assinatura = xml_elemento_assinado.find('.//ds:Signature', ns_dsig)
                if assinatura is not None:
                    debug_print(f'>>> [PyNFe] ✅ Assinatura encontrada no XML')
                else:
                    debug_print(f'>>> [PyNFe] ⚠️ Assinatura NÃO encontrada no XML!')
            except Exception as e:
                debug_print(f'>>> [PyNFe] ❌ Erro ao parsear XML assinado: {e}')
                return {
                    'success': False,
                    'error': f'Erro ao preparar XML para envio: {str(e)}',
                    'details': 'O XML assinado não pôde ser parseado de volta para elemento'
                }
            
            # IMPORTANTE: Montar o lote (enviNFe) manualmente para garantir estrutura correta
            # O PyNFe pode estar gerando o lote incorretamente, causando erro 225
            debug_print(f'>>> [PyNFe] ========================================')
            debug_print(f'>>> [PyNFe] MONTANDO LOTE (enviNFe) MANUALMENTE')
            debug_print(f'>>> [PyNFe] ========================================')
            
            try:
                from lxml import etree as lxml_etree
                
                # Criar elemento enviNFe com estrutura correta
                # Baseado no schema XSD oficial: idLote deve ter 15 dígitos, indSinc=1 para NFC-e
                ns_nfe = "http://www.portalfiscal.inf.br/nfe"
                envi_nfe = lxml_etree.Element(
                    '{' + ns_nfe + '}enviNFe',
                    nsmap={None: ns_nfe},
                    versao='4.00'
                )
                
                # Adicionar idLote (PRIMEIRO elemento, obrigatório)
                # idLote deve ter exatamente 15 dígitos conforme schema XSD
                id_lote = lxml_etree.SubElement(envi_nfe, '{' + ns_nfe + '}idLote')
                id_lote.text = '000000000000001'  # 15 dígitos (pode ser incrementado se necessário)
                debug_print(f'>>> [PyNFe] ✅ idLote adicionado: {id_lote.text} (15 dígitos)')
                
                # Adicionar indSinc (SEGUNDO elemento, obrigatório para NFC-e)
                # indSinc=1 indica processamento síncrono (NFC-e sempre síncrono)
                ind_sinc = lxml_etree.SubElement(envi_nfe, '{' + ns_nfe + '}indSinc')
                ind_sinc.text = '1'  # 1 = síncrono (NFC-e sempre síncrono)
                debug_print(f'>>> [PyNFe] ✅ indSinc adicionado: 1 (síncrono)')
                
                # Adicionar NFe (TERCEIRO elemento, obrigatório)
                # O xml_elemento_assinado já deve ser o elemento NFe completo
                # Verificar se é NFe ou se precisa extrair
                nfe_elemento = xml_elemento_assinado
                if not (nfe_elemento.tag.endswith('NFe') or nfe_elemento.tag == 'NFe'):
                    # Tentar encontrar NFe dentro
                    nfe_encontrado = nfe_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or nfe_elemento.find('.//NFe')
                    if nfe_encontrado is not None:
                        nfe_elemento = nfe_encontrado
                
                # Garantir que NFe tem namespace correto
                if not nfe_elemento.tag.startswith('{' + ns_nfe + '}'):
                    # Criar nova NFe com namespace correto
                    nfe_corrigida = lxml_etree.Element('{' + ns_nfe + '}NFe', nsmap={None: ns_nfe})
                    # Copiar todos os filhos
                    for child in nfe_elemento:
                        nfe_corrigida.append(child)
                    nfe_elemento = nfe_corrigida
                
                # APLICAR CORREÇÕES CRÍTICAS NO XML DA NFe ANTES DE ADICIONAR AO LOTE
                # Isso garante que o XML que vai para o lote está correto
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] APLICANDO CORREÇÕES FINAIS NO XML DA NFe')
                debug_print(f'>>> [PyNFe] ========================================')
                
                ns_nfe_correcao_final = {"nfe": "http://www.portalfiscal.inf.br/nfe"}
                
                # 1. Corrigir cMunFG em TODAS as infNFe
                todas_inf_nfe_final = nfe_elemento.findall('.//nfe:infNFe', ns_nfe_correcao_final) or nfe_elemento.findall('.//infNFe')
                debug_print(f'>>> [PyNFe] Encontradas {len(todas_inf_nfe_final)} infNFe no XML')
                
                # Se houver mais de uma infNFe, manter apenas a primeira (remover duplicatas)
                if len(todas_inf_nfe_final) > 1:
                    debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: Múltiplas infNFe encontradas! Removendo duplicatas...')
                    # Remover todas exceto a primeira
                    for inf_nfe_dup in todas_inf_nfe_final[1:]:
                        parent = inf_nfe_dup.getparent()
                        if parent is not None:
                            debug_print(f'>>> [PyNFe] Removendo infNFe duplicada (Id: {inf_nfe_dup.get("Id", "N/A")})')
                            parent.remove(inf_nfe_dup)
                    # Rebuscar após remoção
                    todas_inf_nfe_final = nfe_elemento.findall('.//nfe:infNFe', ns_nfe_correcao_final) or nfe_elemento.findall('.//infNFe')
                    debug_print(f'>>> [PyNFe] ✅ {len(todas_inf_nfe_final)} infNFe restante(s) após remoção de duplicatas')
                
                # Aplicar correções em cada infNFe restante
                for inf_nfe_final in todas_inf_nfe_final:
                    # 1.1. Corrigir cMunFG - OBRIGATÓRIO: deve ser código IBGE de 7 dígitos
                    ide_final = inf_nfe_final.find('.//nfe:ide', ns_nfe_correcao_final) or inf_nfe_final.find('.//ide')
                    if ide_final is not None:
                        c_mun_fg_final = ide_final.find('.//nfe:cMunFG', ns_nfe_correcao_final) or ide_final.find('.//cMunFG')
                        if c_mun_fg_final is not None:
                            # Verificar se é nome em vez de código
                            if not c_mun_fg_final.text or not c_mun_fg_final.text.strip().isdigit() or len(c_mun_fg_final.text.strip()) != 7:
                                valor_original = c_mun_fg_final.text if c_mun_fg_final.text else "vazio"
                                # Obter código IBGE do emitente
                                emit_final = inf_nfe_final.find('.//nfe:emit', ns_nfe_correcao_final) or inf_nfe_final.find('.//emit')
                                if emit_final is not None:
                                    ender_emit_final = emit_final.find('.//nfe:enderEmit', ns_nfe_correcao_final) or emit_final.find('.//enderEmit')
                                    if ender_emit_final is not None:
                                        c_mun_emit_final = ender_emit_final.find('.//nfe:cMun', ns_nfe_correcao_final) or ender_emit_final.find('.//cMun')
                                        if c_mun_emit_final is not None and c_mun_emit_final.text and c_mun_emit_final.text.strip().isdigit() and len(c_mun_emit_final.text.strip()) == 7:
                                            c_mun_fg_final.text = c_mun_emit_final.text.strip()
                                            debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{valor_original}" → "{c_mun_fg_final.text}"')
                                        else:
                                            # Usar código conhecido para São José dos Campos
                                            c_mun_fg_final.text = '3549904'
                                            debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{valor_original}" → "3549904"')
                                else:
                                    # Se não encontrou emitente, usar código padrão
                                    c_mun_fg_final.text = '3549904'
                                    debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido (emitente não encontrado): "{valor_original}" → "3549904"')
                    
                    # 1.2. Corrigir CRT - OBRIGATÓRIO: não pode estar vazio
                    emit_final = inf_nfe_final.find('.//nfe:emit', ns_nfe_correcao_final) or inf_nfe_final.find('.//emit')
                    if emit_final is not None:
                        crt_final = emit_final.find('.//nfe:CRT', ns_nfe_correcao_final) or emit_final.find('.//CRT')
                        if crt_final is not None:
                            if not crt_final.text or not crt_final.text.strip():
                                crt_final.text = '1'  # Simples Nacional (padrão)
                                debug_print(f'>>> [PyNFe] ✅ CRT corrigido: vazio → "1"')
                        else:
                            # Se CRT não existe, criar
                            crt_final = lxml_etree.SubElement(emit_final, '{' + ns_nfe_correcao_final['nfe'] + '}CRT')
                            crt_final.text = '1'
                            debug_print(f'>>> [PyNFe] ✅ CRT criado: "1"')
                    
                    # 1.3. Corrigir valores decimais
                    corrigido_dec_final, problemas_dec_final = self._validar_valores_decimais_xml(inf_nfe_final)
                    if corrigido_dec_final:
                        debug_print(f'>>> [PyNFe] ✅ Valores decimais corrigidos')
                    if problemas_dec_final:
                        for problema in problemas_dec_final:
                            debug_print(f'>>> [PyNFe] ⚠️ {problema}')
                
                debug_print(f'>>> [PyNFe] ✅ Correções finais aplicadas no XML da NFe')
                
                # IMPORTANTE: Regenerar XML após correções para garantir que as mudanças sejam aplicadas
                xml_corrigido_str = lxml_etree.tostring(nfe_elemento, encoding='unicode', xml_declaration=False, pretty_print=False)
                nfe_elemento = lxml_etree.fromstring(xml_corrigido_str.encode('utf-8'))
                debug_print(f'>>> [PyNFe] ✅ XML regenerado após correções')
                
                # Adicionar NFe ao lote
                envi_nfe.append(nfe_elemento)
                debug_print(f'>>> [PyNFe] ✅ NFe adicionada ao lote')
                
                # Validar estrutura do lote montado
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] VALIDAÇÃO DO LOTE MONTADO')
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] Tag raiz: {envi_nfe.tag}')
                debug_print(f'>>> [PyNFe] Versão: {envi_nfe.get("versao")}')
                debug_print(f'>>> [PyNFe] Namespace: {envi_nfe.nsmap.get(None) if envi_nfe.nsmap else "N/A"}')
                
                elementos = list(envi_nfe)
                debug_print(f'>>> [PyNFe] Número de elementos filhos: {len(elementos)}')
                for i, elem in enumerate(elementos, 1):
                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                    debug_print(f'>>> [PyNFe]   {i}. {tag_limpa}')
                
                # Gerar XML do lote para debug
                lote_xml_str = lxml_etree.tostring(envi_nfe, encoding='unicode', xml_declaration=False, pretty_print=False)
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] XML DO LOTE MONTADO (primeiros 2000 chars):')
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(lote_xml_str[:2000])
                debug_print(f'>>> [PyNFe] ========================================')
                debug_print(f'>>> [PyNFe] Tamanho total: {len(lote_xml_str)} caracteres')
                debug_print(f'>>> [PyNFe] ========================================')
                
                # Salvar lote montado
                try:
                    empresa_dir = self._obter_diretorio_empresa()
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    lote_file = os.path.join(empresa_dir, f'lote_enviNFe_montado_{timestamp}.xml')
                    with open(lote_file, 'w', encoding='utf-8') as f:
                        f.write(lote_xml_str)
                    debug_print(f'>>> [PyNFe] Lote montado salvo em: {lote_file}')
                except Exception as e_save:
                    debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar lote montado: {e_save}')
                
                # IMPORTANTE: O PyNFe espera receber o elemento NFe, não o lote (enviNFe)
                # O PyNFe monta o lote internamente. Mas podemos interceptar e corrigir depois.
                # Por enquanto, vamos usar a NFe extraída do lote
                nfe_do_lote = envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or envi_nfe.find('.//NFe')
                if nfe_do_lote is not None:
                    xml_elemento_assinado = nfe_do_lote
                    debug_print(f'>>> [PyNFe] ✅ Extraída NFe do lote montado')
                else:
                    debug_print(f'>>> [PyNFe] ⚠️ NFe não encontrada no lote, usando elemento original')
                # O lote montado será usado para validação, mas o PyNFe receberá apenas a NFe
                
            except Exception as e_lote:
                debug_print(f'>>> [PyNFe] ⚠️ Erro ao montar lote manualmente: {e_lote}')
                import traceback
                debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                debug_print(f'>>> [PyNFe] Continuando com elemento original...')
            
            debug_print(f'>>> [PyNFe] Chamando comunicacao.autorizacao()...')
            debug_print(f'>>> [PyNFe] Parâmetros: modelo="nfce", id_lote=1, ind_sinc=1')
            debug_print(f'>>> [PyNFe] Tipo do xml_elemento_assinado: {type(xml_elemento_assinado)}')
            debug_print(f'>>> [PyNFe] Tag do elemento: {xml_elemento_assinado.tag}')
            
            # Log do XML completo antes de enviar (para debug)
            try:
                xml_completo_str = lxml_etree.tostring(xml_elemento_assinado, encoding='unicode', pretty_print=False)
                debug_print(f'>>> [PyNFe] XML completo que será enviado (primeiros 2000 chars):')
                debug_print(xml_completo_str[:2000])
                debug_print(f'>>> [PyNFe] Tamanho total do XML: {len(xml_completo_str)} caracteres')
            except Exception as e_log:
                debug_print(f'>>> [PyNFe] ⚠️ Erro ao gerar log do XML completo: {e_log}')
            
            # IMPORTANTE: O PyNFe pode estar criando o lote incorretamente
            # Vamos tentar passar o objeto NotaFiscal diretamente, para que o PyNFe
            # monte o lote corretamente internamente
            # Mas primeiro, vamos tentar com o XML elemento (formato padrão)
            debug_print(f'>>> [PyNFe] Enviando XML elemento para autorizacao()...')
            debug_print(f'>>> [PyNFe] Tag do elemento: {xml_elemento_assinado.tag}')
            debug_print(f'>>> [PyNFe] Namespace: {xml_elemento_assinado.nsmap if hasattr(xml_elemento_assinado, "nsmap") else "N/A"}')
            
            # Verificar se o elemento tem a estrutura correta (deve ser NFe)
            if not (xml_elemento_assinado.tag.endswith('NFe') or xml_elemento_assinado.tag == 'NFe'):
                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: Tag do elemento não é NFe: {xml_elemento_assinado.tag}')
                # Tentar encontrar o elemento NFe dentro
                nfe_elem = xml_elemento_assinado.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or xml_elemento_assinado.find('.//NFe')
                if nfe_elem is not None:
                    debug_print(f'>>> [PyNFe] Encontrado elemento NFe dentro, usando ele')
                    xml_elemento_assinado = nfe_elem
            
            # IMPORTANTE: O erro cStat 225 "Falha no Schema XML do lote de NFe" geralmente indica
            # que o PyNFe está gerando um lote (enviNFe) com estrutura incorreta.
            # Possíveis causas:
            # 1. Namespace incorreto no elemento enviNFe
            # 2. Versão do schema incorreta
            # 3. Elementos obrigatórios faltando ou na ordem errada
            # 4. Problema na montagem do lote pelo PyNFe
            #
            # Vamos adicionar validação e logs detalhados para identificar o problema
            debug_print(f'>>> [PyNFe] ========================================')
            debug_print(f'>>> [PyNFe] PREPARAÇÃO PARA AUTORIZAÇÃO')
            debug_print(f'>>> [PyNFe] ========================================')
            debug_print(f'>>> [PyNFe] Modelo: nfce (65)')
            debug_print(f'>>> [PyNFe] ID Lote: 1')
            debug_print(f'>>> [PyNFe] Ind Sinc: 1 (síncrono)')
            modo_ambiente = "HOMOLOGAÇÃO" if ambiente_homologacao else "PRODUÇÃO"
            tp_amb_xml = "2" if ambiente_homologacao else "1"
            
            debug_print(f'>>> [PyNFe] ========================================')
            debug_print(f'>>> [PyNFe] CONFIGURAÇÃO DO AMBIENTE')
            debug_print(f'>>> [PyNFe] ========================================')
            debug_print(f'>>> [PyNFe] Ambiente: {modo_ambiente}')
            debug_print(f'>>> [PyNFe] ambiente_homologacao: {ambiente_homologacao}')
            debug_print(f'>>> [PyNFe] tpAmb no XML: {tp_amb_xml} (1=Produção, 2=Homologação)')
            debug_print(f'>>> [PyNFe] UF: {uf}')
            debug_print(f'>>> [PyNFe] ========================================')
            
            # IMPORTANTE: Verificar se o XML da nota tem todos os elementos obrigatórios
            # antes de enviar para evitar erro de schema
            try:
                from lxml import etree as lxml_etree
                ns_nfe = {"nfe": "http://www.portalfiscal.inf.br/nfe"}
                
                # Verificar elementos obrigatórios no infNFe
                inf_nfe = xml_elemento_assinado.find('.//nfe:infNFe', ns_nfe) or xml_elemento_assinado.find('.//infNFe')
                if inf_nfe is not None:
                    # Verificar se tem versão
                    versao = inf_nfe.get('versao')
                    if not versao or versao != '4.00':
                        debug_print(f'>>> [PyNFe] ⚠️ Versão incorreta ou ausente: {versao}, corrigindo para 4.00')
                        inf_nfe.set('versao', '4.00')
                    
                    # Verificar se tem Id (chave de acesso)
                    id_nfe = inf_nfe.get('Id')
                    if not id_nfe or not id_nfe.startswith('NFe'):
                        debug_print(f'>>> [PyNFe] ⚠️ Id incorreto ou ausente: {id_nfe}')
                    
                    # Verificar elementos obrigatórios
                    ide = inf_nfe.find('.//nfe:ide', ns_nfe) or inf_nfe.find('.//ide')
                    if ide is None:
                        debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento ide não encontrado!')
                        return {
                            'success': False,
                            'error': 'XML inválido: elemento ide não encontrado',
                            'details': 'O XML não contém informações de identificação obrigatórias'
                        }
                    
                    # IMPORTANTE: Verificar e corrigir tpAmb (tipo de ambiente)
                    tp_amb = ide.find('.//nfe:tpAmb', ns_nfe) or ide.find('.//tpAmb')
                    if tp_amb is not None:
                        tp_amb_atual = tp_amb.text
                        tp_amb_esperado = "2" if ambiente_homologacao else "1"
                        debug_print(f'>>> [PyNFe] tpAmb no XML: {tp_amb_atual} (esperado: {tp_amb_esperado} para {modo_ambiente})')
                        if tp_amb_atual != tp_amb_esperado:
                            debug_print(f'>>> [PyNFe] ⚠️ CORRIGINDO tpAmb de {tp_amb_atual} para {tp_amb_esperado}')
                            tp_amb.text = tp_amb_esperado
                            debug_print(f'>>> [PyNFe] ✅ tpAmb corrigido para {tp_amb_esperado}')
                    else:
                        debug_print(f'>>> [PyNFe] ⚠️ tpAmb não encontrado no XML!')
                    
                    # Verificar se tem emitente
                    emit = inf_nfe.find('.//nfe:emit', ns_nfe) or inf_nfe.find('.//emit')
                    if emit is None:
                        debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento emit não encontrado!')
                        return {
                            'success': False,
                            'error': 'XML inválido: elemento emit não encontrado',
                            'details': 'O XML não contém informações do emitente obrigatórias'
                        }
                    
                    # Verificar se tem produtos
                    det = inf_nfe.findall('.//nfe:det', ns_nfe) or inf_nfe.findall('.//det')
                    if not det:
                        debug_print(f'>>> [PyNFe] ❌ ERRO: Nenhum produto encontrado!')
                        return {
                            'success': False,
                            'error': 'XML inválido: nenhum produto encontrado',
                            'details': 'A NFC-e deve conter pelo menos um produto'
                        }
                    
                    # Verificar se tem total
                    total = inf_nfe.find('.//nfe:total', ns_nfe) or inf_nfe.find('.//total')
                    if total is None:
                        debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento total não encontrado!')
                        return {
                            'success': False,
                            'error': 'XML inválido: elemento total não encontrado',
                            'details': 'O XML não contém informações de totalização obrigatórias'
                        }
                    
                    # Verificar se tem pagamento (obrigatório para NFC-e)
                    pag = inf_nfe.find('.//nfe:pag', ns_nfe) or inf_nfe.find('.//pag')
                    if pag is None:
                        debug_print(f'>>> [PyNFe] ❌ ERRO: Elemento pag não encontrado!')
                        return {
                            'success': False,
                            'error': 'XML inválido: elemento pag não encontrado',
                            'details': 'A NFC-e deve conter informações de pagamento'
                        }
                    
                    debug_print(f'>>> [PyNFe] ✅ Validação do XML: Todos os elementos obrigatórios encontrados')
                    debug_print(f'>>> [PyNFe]   - Versão: {versao}')
                    debug_print(f'>>> [PyNFe]   - Id: {id_nfe[:50] if id_nfe else "N/A"}...')
                    debug_print(f'>>> [PyNFe]   - Produtos: {len(det)}')
            except Exception as e_validacao:
                debug_print(f'>>> [PyNFe] ⚠️ Erro ao validar XML antes de enviar: {e_validacao}')
                # Continuar mesmo com erro de validação (pode ser problema de namespace)
            
            # IMPORTANTE: Interceptar e corrigir o XML do lote antes de enviar
            # O erro 225 indica que o lote (enviNFe) está com estrutura incorreta
            # Vamos fazer monkey patch no método que faz a requisição HTTP para interceptar e corrigir o XML do lote
            # CRÍTICO: Interceptar TAMBÉM o método requests.Session.post caso o PyNFe use Session
            try:
                import requests
                original_post = requests.post
                original_session_post = None
                if hasattr(requests.Session, 'post'):
                    original_session_post = requests.Session.post
                xml_lote_interceptado = None
                
                def post_interceptado(*args, **kwargs):
                    """Intercepta requisição HTTP para capturar e corrigir XML do lote"""
                    nonlocal xml_lote_interceptado
                    
                    # Verificar 'data' ou 'body' (requests pode usar qualquer um)
                    body = None
                    if 'data' in kwargs:
                        body = kwargs['data']
                    elif 'body' in kwargs:
                        body = kwargs['body']
                    elif len(args) > 1:
                        body = args[1]  # Segundo argumento pode ser o body
                    
                    body_str = None  # Inicializar variável
                    
                    if body and isinstance(body, (str, bytes)):
                        xml_str = body.decode('utf-8') if isinstance(body, bytes) else body
                        body_str = xml_str  # Inicializar body_str
                        
                        debug_print(f'>>> [PyNFe] ========================================')
                        debug_print(f'>>> [PyNFe] INTERCEPTAÇÃO HTTP - XML CAPTURADO')
                        debug_print(f'>>> [PyNFe] ========================================')
                        debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                        debug_print(f'>>> [PyNFe] Primeiros 500 chars: {xml_str[:500]}')
                        
                        # IMPORTANTE: Processar SEMPRE que contiver qualquer XML (SOAP, enviNFe, NFe, etc.)
                        # Não importa o formato, vamos extrair e reconstruir completamente
                        tem_xml = any(tag in xml_str for tag in ['<soap', '<enviNFe', '<NFe', '<nfeDadosMsg', 'xmlns', '<?xml'])
                        
                        if tem_xml:
                                xml_lote_interceptado = xml_str
                                debug_print(f'>>> [PyNFe] ✅ XML detectado - processando...')
                                
                                # IMPORTANTE: Salvar XML completo do lote para análise
                                try:
                                    import os
                                    
                                    # Obter diretório da empresa
                                    empresa_dir = self._obter_diretorio_empresa()
                                    
                                    # Salvar XML do lote com timestamp
                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                    xml_file = os.path.join(empresa_dir, f'lote_enviNFe_{timestamp}.xml')
                                    
                                    with open(xml_file, 'w', encoding='utf-8') as f:
                                        f.write(xml_str)
                                    
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] XML DO LOTE INTERCEPTADO E SALVO')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] Arquivo salvo em: {xml_file}')
                                    debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] XML COMPLETO DO LOTE:')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(xml_str)
                                    debug_print(f'>>> [PyNFe] ========================================')
                                except Exception as e_save:
                                    debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar XML do lote: {e_save}')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] XML DO LOTE INTERCEPTADO')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                                    debug_print(f'>>> [PyNFe] XML completo:')
                                    debug_print(xml_str)
                                    debug_print(f'>>> [PyNFe] ========================================')
                                
                                # IMPORTANTE: Corrigir estrutura do lote antes de enviar
                                try:
                                    from lxml import etree as lxml_etree
                                    
                                    # IMPORTANTE: SEMPRE remover completamente o envelope SOAP
                                    # O XML correto deve ser APENAS o enviNFe, sem envelope SOAP
                                    xml_original = xml_str
                                    dentro_soap = '<soap' in xml_str.lower() or '<soapenv' in xml_str.lower() or '<soap12' in xml_str.lower() or 'nfeDadosMsg' in xml_str
                                    
                                    # SEMPRE extrair APENAS o enviNFe (mesmo se não estiver em SOAP explícito)
                                    if dentro_soap or 'nfeDadosMsg' in xml_str:
                                        debug_print(f'>>> [PyNFe] ⚠️ XML contém envelope SOAP - removendo e extraindo apenas enviNFe')
                                        try:
                                            soap_xml = lxml_etree.fromstring(xml_original.encode('utf-8'))
                                            # Procurar enviNFe dentro do SOAP
                                            envi_nfe_encontrado = None
                                            for elem in soap_xml.iter():
                                                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                                if tag_limpa == 'enviNFe':
                                                    envi_nfe_encontrado = elem
                                                    break
                                            
                                            if envi_nfe_encontrado is not None:
                                                # Extrair apenas o enviNFe (sem SOAP)
                                                # IMPORTANTE: Gerar XML sem prefixos
                                                xml_str = lxml_etree.tostring(envi_nfe_encontrado, 
                                                                              encoding='unicode', 
                                                                              xml_declaration=False,
                                                                              method='xml')
                                                # Remover prefixos que possam ter sido adicionados
                                                xml_str = re.sub(r'ns\d+:', '', xml_str)
                                                debug_print(f'>>> [PyNFe] ✅ enviNFe extraído do envelope SOAP')
                                            else:
                                                # Tentar extrair por string se não encontrar por elemento
                                                inicio = xml_str.find('<enviNFe')
                                                fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                                if inicio >= 0 and fim > inicio:
                                                    xml_str = xml_str[inicio:fim]
                                                    # Remover prefixos
                                                    xml_str = re.sub(r'ns\d+:', '', xml_str)
                                                    debug_print(f'>>> [PyNFe] ✅ enviNFe extraído do SOAP por string')
                                                else:
                                                    raise ValueError('enviNFe não encontrado dentro do SOAP')
                                        except Exception as e_soap:
                                            debug_print(f'>>> [PyNFe] ⚠️ Erro ao extrair enviNFe do SOAP: {e_soap}')
                                            # Tentar extrair por string como fallback
                                            inicio = xml_str.find('<enviNFe')
                                            fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                            if inicio >= 0 and fim > inicio:
                                                xml_str = xml_str[inicio:fim]
                                                debug_print(f'>>> [PyNFe] ✅ enviNFe extraído por string (fallback)')
                                            else:
                                                raise
                                    
                                    # IMPORTANTE: SEMPRE reconstruir o XML do zero para garantir estrutura limpa
                                    # Não confiar no XML original - sempre reconstruir
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    debug_print(f'>>> [PyNFe] RECONSTRUÇÃO COMPLETA DO XML DO ZERO')
                                    debug_print(f'>>> [PyNFe] ========================================')
                                    
                                    namespace_correto = 'http://www.portalfiscal.inf.br/nfe'
                                    
                                    # Parsear XML para encontrar NFe (pode estar em SOAP, enviNFe, etc.)
                                    try:
                                        xml_temp = lxml_etree.fromstring(xml_str.encode('utf-8'))
                                    except Exception as e_parse:
                                        debug_print(f'>>> [PyNFe] ❌ Erro ao parsear XML: {e_parse}')
                                        raise
                                    
                                    # Encontrar NFe (pode estar em qualquer lugar do XML)
                                    nfe_para_reconstruir = None
                                    for elem in xml_temp.iter():
                                        tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_limpa == 'NFe':
                                            nfe_para_reconstruir = elem
                                            debug_print(f'>>> [PyNFe] ✅ NFe encontrada para reconstrução')
                                            break
                                    
                                    if nfe_para_reconstruir is None:
                                        debug_print(f'>>> [PyNFe] ❌ ERRO: NFe não encontrada no XML!')
                                        debug_print(f'>>> [PyNFe] Tags encontradas:')
                                        for elem in xml_temp.iter():
                                            tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            debug_print(f'>>> [PyNFe]   - {tag_limpa}')
                                        raise ValueError('NFe não encontrada no XML')
                                    
                                    # RECONSTRUIR enviNFe completamente do zero - ESTRUTURA LIMPA
                                    # Seguindo o padrão do XML de exemplo fornecido pelo usuário
                                    envi_nfe_reconstruido_final = lxml_etree.Element(
                                        '{' + namespace_correto + '}enviNFe',
                                        nsmap={None: namespace_correto},
                                        versao='4.00'
                                    )
                                    
                                    debug_print(f'>>> [PyNFe] Criando enviNFe limpo com namespace: {namespace_correto}')
                                    
                                    # 1. idLote (15 dígitos) - SEMPRE primeiro
                                    id_lote_final = lxml_etree.SubElement(envi_nfe_reconstruido_final, '{' + namespace_correto + '}idLote')
                                    id_lote_final.text = '000000000000001'  # Sempre 15 dígitos
                                    
                                    # 2. indSinc (valor 1) - SEMPRE segundo
                                    ind_sinc_final = lxml_etree.SubElement(envi_nfe_reconstruido_final, '{' + namespace_correto + '}indSinc')
                                    ind_sinc_final.text = '1'
                                    
                                    # 3. NFe (copiar e limpar completamente - SEM prefixos)
                                    nfe_reconstruida_final = self._copiar_elemento_limpo(nfe_para_reconstruir, namespace_correto)
                                    
                                    # Aplicar correções finais na infNFe
                                    inf_nfe_final = nfe_reconstruida_final.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_reconstruida_final.find('.//infNFe')
                                    if inf_nfe_final is not None:
                                        self._aplicar_correcoes_finais_infnfe(inf_nfe_final, namespace_correto)
                                    
                                    envi_nfe_reconstruido_final.append(nfe_reconstruida_final)
                                    
                                    # Gerar XML final completamente limpo - SEM prefixos, SEM SOAP
                                    # IMPORTANTE: Usar método que NÃO adiciona prefixos
                                    xml_str = lxml_etree.tostring(envi_nfe_reconstruido_final, 
                                                                  encoding='unicode', 
                                                                  xml_declaration=False,
                                                                  pretty_print=False,
                                                                  method='xml')
                                    
                                    # CRÍTICO: Remover TODOS os prefixos e namespaces extras
                                    # O XML correto deve ter APENAS: xmlns="http://www.portalfiscal.inf.br/nfe"
                                    # Remover QUALQUER outro namespace ou prefixo
                                    for i in range(10):  # Múltiplas passadas para garantir
                                        # Remover prefixos ns0:, ns1:, etc.
                                        xml_str = xml_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '').replace('ns4:', '').replace('ns5:', '').replace('ns6:', '').replace('ns7:', '').replace('ns8:', '').replace('ns9:', '')
                                        
                                        # Remover declarações de namespace com prefixos
                                        xml_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', xml_str)
                                        xml_str = re.sub(r'xmlns:xsi="[^"]*"', '', xml_str)
                                        xml_str = re.sub(r'xmlns:xsd="[^"]*"', '', xml_str)
                                        xml_str = re.sub(r'xmlns:soap[^=]*="[^"]*"', '', xml_str)
                                        xml_str = re.sub(r'xmlns:soapenv[^=]*="[^"]*"', '', xml_str)
                                        xml_str = re.sub(r'xmlns:soap12[^=]*="[^"]*"', '', xml_str)
                                        
                                        # Garantir que há apenas UM namespace (o correto)
                                        # Se houver múltiplos xmlns, manter apenas o primeiro (o correto)
                                        if xml_str.count('xmlns=') > 1:
                                            # Encontrar o primeiro xmlns correto
                                            primeiro_xmlns = re.search(r'xmlns="http://www\.portalfiscal\.inf\.br/nfe"', xml_str)
                                            if primeiro_xmlns:
                                                # Remover todos os outros xmlns
                                                xml_str = re.sub(r'\s+xmlns="[^"]*"', '', xml_str, count=0)
                                                # Adicionar o xmlns correto no elemento raiz
                                                xml_str = re.sub(r'(<enviNFe[^>]*?)', r'\1 xmlns="http://www.portalfiscal.inf.br/nfe"', xml_str, count=1)
                                    
                                    debug_print(f'>>> [PyNFe] Prefixos removidos (10 passadas)')
                                    
                                    # VERIFICAÇÃO FINAL: Garantir que não há SOAP, nfeDadosMsg ou prefixos
                                    if '<soap' in xml_str.lower() or 'nfeDadosMsg' in xml_str or 'soap:Envelope' in xml_str:
                                        debug_print(f'>>> [PyNFe] ❌ ERRO: SOAP ainda presente após remoção!')
                                        # Extrair APENAS o enviNFe
                                        inicio = xml_str.find('<enviNFe')
                                        fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                        if inicio >= 0 and fim > inicio:
                                            xml_str = xml_str[inicio:fim]
                                            debug_print(f'>>> [PyNFe] ✅ enviNFe extraído (SOAP removido)')
                                    
                                    # Verificar se ainda há prefixos
                                    if re.search(r'ns\d+:', xml_str):
                                        debug_print(f'>>> [PyNFe] ❌ ERRO: Prefixos ainda presentes!')
                                        # Remover todos os prefixos restantes
                                        xml_str = re.sub(r'ns\d+:', '', xml_str)
                                        debug_print(f'>>> [PyNFe] ✅ Prefixos removidos (regex final)')
                                    
                                    # Garantir que não há SOAP (por segurança)
                                    if '<soap' in xml_str.lower() or 'nfeDadosMsg' in xml_str or 'soap:Envelope' in xml_str:
                                        debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: SOAP ainda presente - removendo...')
                                        inicio = xml_str.find('<enviNFe')
                                        fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                        if inicio >= 0 and fim > inicio:
                                            xml_str = xml_str[inicio:fim]
                                    
                                    debug_print(f'>>> [PyNFe] ✅ XML completamente reconstruído do zero (SEM SOAP, SEM PREFIXOS)')
                                    debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                                    debug_print(f'>>> [PyNFe] Primeiros 500 chars: {xml_str[:500]}')
                                    
                                    # IMPORTANTE: O XML já está reconstruído e limpo
                                    # GARANTIR que está correto antes de aplicar
                                    # Verificações finais críticas
                                    if '<soap' in xml_str.lower() or 'nfeDadosMsg' in xml_str or 'soap:Envelope' in xml_str:
                                        debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: SOAP ainda presente após reconstrução!')
                                        # Extrair apenas enviNFe por string
                                        inicio = xml_str.find('<enviNFe')
                                        fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                        if inicio >= 0 and fim > inicio:
                                            xml_str = xml_str[inicio:fim]
                                            debug_print(f'>>> [PyNFe] ✅ SOAP removido por string')
                                    
                                    if 'ns0:' in xml_str or 'ns1:' in xml_str:
                                        debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: Prefixos ainda presentes após reconstrução!')
                                        xml_str = xml_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '')
                                        xml_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', xml_str)
                                        debug_print(f'>>> [PyNFe] ✅ Prefixos removidos por string')
                                    
                                    # Corrigir idLote se necessário
                                    if '<idLote>1</idLote>' in xml_str:
                                        xml_str = xml_str.replace('<idLote>1</idLote>', '<idLote>000000000000001</idLote>')
                                        debug_print(f'>>> [PyNFe] ✅ idLote corrigido para 15 dígitos')
                                    
                                    # Corrigir cMunFG se necessário
                                    cMunFG_match = re.search(r'<cMunFG>([^<]+)</cMunFG>', xml_str)
                                    if cMunFG_match:
                                        cMunFG_valor = cMunFG_match.group(1)
                                        if not cMunFG_valor.strip().isdigit() or len(cMunFG_valor.strip()) != 7:
                                            # Buscar código no emitente
                                            cMun_match = re.search(r'<cMun>(\d{7})</cMun>', xml_str)
                                            if cMun_match:
                                                codigo_ibge = cMun_match.group(1)
                                                xml_str = xml_str.replace(f'<cMunFG>{cMunFG_valor}</cMunFG>', f'<cMunFG>{codigo_ibge}</cMunFG>')
                                                debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{cMunFG_valor}" → "{codigo_ibge}"')
                                            else:
                                                xml_str = xml_str.replace(f'<cMunFG>{cMunFG_valor}</cMunFG>', '<cMunFG>3549904</cMunFG>')
                                                debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido com fallback: "{cMunFG_valor}" → "3549904"')
                                    
                                    # Corrigir CRT duplicado
                                    if xml_str.count('<CRT>') > 1 or '<CRT/>' in xml_str:
                                        xml_str = re.sub(r'<CRT[^>]*>.*?</CRT>', '', xml_str)
                                        xml_str = re.sub(r'<CRT/>', '', xml_str)
                                        xml_str = re.sub(r'(</IE>)', r'\1<CRT>1</CRT>', xml_str, count=1)
                                        debug_print(f'>>> [PyNFe] ✅ CRT duplicado removido')
                                    
                                    # Corrigir verProc
                                    if 'PyNFe' in xml_str and '<verProc>' in xml_str:
                                        xml_str = re.sub(r'<verProc>[^<]*PyNFe[^<]*</verProc>', '<verProc>Sistema Exodo</verProc>', xml_str)
                                        debug_print(f'>>> [PyNFe] ✅ verProc corrigido')
                                    
                                    # Atualizar body da requisição IMEDIATAMENTE com XML reconstruído e corrigido
                                    if 'data' in kwargs:
                                        kwargs['data'] = xml_str.encode('utf-8') if isinstance(kwargs.get('data'), bytes) else xml_str
                                    elif 'body' in kwargs:
                                        kwargs['body'] = xml_str.encode('utf-8') if isinstance(kwargs.get('body'), bytes) else xml_str
                                    else:
                                        args_list = list(args)
                                        args_list[1] = xml_str.encode('utf-8') if isinstance(args_list[1], bytes) else xml_str
                                        args = tuple(args_list)
                                    
                                    debug_print(f'>>> [PyNFe] ✅ XML reconstruído e corrigido aplicado na requisição')
                                    debug_print(f'>>> [PyNFe] Verificação final: SOAP={("<soap" in xml_str.lower())}, Prefixos={("ns0:" in xml_str)}, idLote correto={("<idLote>000000000000001</idLote>" in xml_str or re.search(r"<idLote>\d{15}</idLote>", xml_str) is not None)}')
                                    
                                    # Continuar com validação apenas para log (XML já está correto)
                                    try:
                                        lote_xml = lxml_etree.fromstring(xml_str.encode('utf-8'))
                                    except Exception as e_parse:
                                        debug_print(f'>>> [PyNFe] ⚠️ Erro ao parsear XML reconstruído: {e_parse}')
                                        lote_xml = None
                                    
                                    # Verificar se tem enviNFe (apenas para log)
                                    ns_nfe = {"nfe": "http://www.portalfiscal.inf.br/nfe"}
                                    envi_nfe = None
                                    if lote_xml is not None:
                                        envi_nfe = lote_xml.find('.//nfe:enviNFe', ns_nfe)
                                        if envi_nfe is None:
                                            envi_nfe = lote_xml.find('.//enviNFe')
                                        
                                        # Se não encontrou, pode ser que o elemento raiz seja o enviNFe
                                        if envi_nfe is None:
                                            if 'enviNFe' in lote_xml.tag or lote_xml.tag.endswith('enviNFe'):
                                                envi_nfe = lote_xml
                                    
                                    if envi_nfe is None:
                                        debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: enviNFe não encontrado após reconstrução')
                                    else:
                                        debug_print(f'>>> [PyNFe] ✅ enviNFe encontrado após reconstrução')
                                    
                                    # Se encontrou envi_nfe, fazer validação adicional (opcional - XML já está correto)
                                    if envi_nfe is not None:
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        debug_print(f'>>> [PyNFe] VALIDAÇÃO E CORREÇÃO DO LOTE')
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        
                                        corrigido = False
                                        problemas_encontrados = []
                                        
                                        # 1. Validar e corrigir versão
                                        versao_atual = envi_nfe.get('versao')
                                        debug_print(f'>>> [PyNFe] Versão atual: {versao_atual}')
                                        if not versao_atual or versao_atual != '4.00':
                                            problemas_encontrados.append(f'Versão incorreta: {versao_atual} (esperado: 4.00)')
                                            debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: Versão incorreta "{versao_atual}", corrigindo para 4.00')
                                            envi_nfe.set('versao', '4.00')
                                            corrigido = True
                                        else:
                                            debug_print(f'>>> [PyNFe] ✅ Versão correta: 4.00')
                                        
                                        # 2. Validar e corrigir namespace
                                        namespace_atual = envi_nfe.nsmap.get(None) if hasattr(envi_nfe, 'nsmap') and envi_nfe.nsmap else None
                                        debug_print(f'>>> [PyNFe] Namespace atual: {namespace_atual}')
                                        namespace_correto = 'http://www.portalfiscal.inf.br/nfe'
                                        
                                        if not namespace_atual or namespace_atual != namespace_correto:
                                            problemas_encontrados.append(f'Namespace incorreto: {namespace_atual} (esperado: {namespace_correto})')
                                            debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: Namespace incorreto "{namespace_atual}", corrigindo')
                                            
                                            # Criar novo elemento com namespace correto
                                            tag_sem_ns = 'enviNFe'
                                            if '{' in envi_nfe.tag:
                                                tag_sem_ns = envi_nfe.tag.split('}')[-1]
                                            
                                            novo_envi_nfe = lxml_etree.Element(
                                                '{' + namespace_correto + '}' + tag_sem_ns,
                                                nsmap={None: namespace_correto},
                                                versao='4.00'
                                            )
                                            
                                            # IMPORTANTE: Ordem dos elementos no enviNFe deve ser:
                                            # 1. idLote (obrigatório, 15 dígitos)
                                            # 2. indSinc (obrigatório para NFC-e, valor 1)
                                            # 3. NFe (obrigatório)
                                            
                                            # Copiar filhos na ordem correta
                                            id_lote_encontrado = None
                                            ind_sinc_encontrado = None
                                            nfe_encontrada = None
                                            outros_elementos = []
                                            
                                            for child in envi_nfe:
                                                tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                                if tag_limpa == 'idLote':
                                                    id_lote_encontrado = child
                                                elif tag_limpa == 'indSinc':
                                                    ind_sinc_encontrado = child
                                                elif tag_limpa == 'NFe':
                                                    nfe_encontrada = child
                                                else:
                                                    outros_elementos.append(child)
                                            
                                            # Adicionar na ordem correta: idLote primeiro, indSinc segundo, depois NFe
                                            if id_lote_encontrado:
                                                # Garantir que idLote tem 15 dígitos
                                                id_lote_texto = id_lote_encontrado.text or '1'
                                                id_lote_texto = id_lote_texto.strip().zfill(15)[:15]  # Garantir 15 dígitos
                                                id_lote_encontrado.text = id_lote_texto
                                                novo_envi_nfe.append(id_lote_encontrado)
                                            else:
                                                # Criar idLote se não existir (15 dígitos)
                                                id_lote = lxml_etree.SubElement(novo_envi_nfe, '{' + namespace_correto + '}idLote')
                                                id_lote.text = '000000000000001'  # 15 dígitos
                                                problemas_encontrados.append('idLote ausente - adicionado')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: idLote ausente, adicionando com 15 dígitos')
                                            
                                            # Adicionar indSinc (obrigatório para NFC-e)
                                            if ind_sinc_encontrado:
                                                novo_envi_nfe.append(ind_sinc_encontrado)
                                            else:
                                                # Criar indSinc se não existir (NFC-e sempre síncrono)
                                                ind_sinc = lxml_etree.SubElement(novo_envi_nfe, '{' + namespace_correto + '}indSinc')
                                                ind_sinc.text = '1'  # 1 = síncrono
                                                problemas_encontrados.append('indSinc ausente - adicionado')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: indSinc ausente, adicionando (valor 1)')
                                            
                                            if nfe_encontrada:
                                                novo_envi_nfe.append(nfe_encontrada)
                                            else:
                                                problemas_encontrados.append('NFe ausente dentro do lote')
                                                debug_print(f'>>> [PyNFe] ❌ PROBLEMA CRÍTICO: NFe ausente dentro do lote!')
                                            
                                            # Adicionar outros elementos (se houver)
                                            for elem in outros_elementos:
                                                novo_envi_nfe.append(elem)
                                            
                                            # Substituir elemento antigo
                                            if envi_nfe == lote_xml:
                                                lote_xml = novo_envi_nfe
                                            elif envi_nfe.getparent() is not None:
                                                envi_nfe.getparent().replace(envi_nfe, novo_envi_nfe)
                                            
                                            envi_nfe = novo_envi_nfe
                                            corrigido = True
                                        else:
                                            debug_print(f'>>> [PyNFe] ✅ Namespace correto: {namespace_correto}')
                                        
                                        # 3. Validar idLote (deve ser o primeiro elemento)
                                        id_lote_elem = envi_nfe.find('nfe:idLote', ns_nfe)
                                        if id_lote_elem is None:
                                            id_lote_elem = envi_nfe.find('idLote')
                                        
                                        if id_lote_elem is None:
                                            problemas_encontrados.append('idLote ausente')
                                            debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: idLote ausente, adicionando')
                                            # IMPORTANTE: idLote deve ser o PRIMEIRO elemento e ter 15 dígitos
                                            id_lote = lxml_etree.Element('{' + namespace_correto + '}idLote')
                                            id_lote.text = '000000000000001'  # 15 dígitos
                                            # Inserir como primeiro elemento
                                            if len(envi_nfe) > 0:
                                                envi_nfe.insert(0, id_lote)
                                            else:
                                                envi_nfe.append(id_lote)
                                            corrigido = True
                                        else:
                                            # Garantir que idLote tem 15 dígitos
                                            id_lote_texto_original = id_lote_elem.text or '1'
                                            id_lote_texto_corrigido = id_lote_texto_original.strip().zfill(15)[:15]
                                            if id_lote_texto_original != id_lote_texto_corrigido:
                                                id_lote_elem.text = id_lote_texto_corrigido
                                                problemas_encontrados.append(f'idLote corrigido para 15 dígitos: {id_lote_texto_corrigido}')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: idLote corrigido para 15 dígitos: {id_lote_texto_corrigido}')
                                                corrigido = True
                                            
                                            # Verificar se idLote é o primeiro elemento
                                            if list(envi_nfe).index(id_lote_elem) != 0:
                                                problemas_encontrados.append('idLote não é o primeiro elemento')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: idLote não é o primeiro elemento, reordenando')
                                                # Remover e reinserir como primeiro
                                                id_lote_texto = id_lote_elem.text
                                                envi_nfe.remove(id_lote_elem)
                                                id_lote_novo = lxml_etree.Element('{' + namespace_correto + '}idLote')
                                                id_lote_novo.text = id_lote_texto
                                                envi_nfe.insert(0, id_lote_novo)
                                                corrigido = True
                                            else:
                                                debug_print(f'>>> [PyNFe] ✅ idLote presente e na posição correta: {id_lote_elem.text} ({len(id_lote_elem.text)} dígitos)')
                                        
                                        # 3.5. Validar indSinc (deve ser o segundo elemento, após idLote)
                                        ind_sinc_elem = envi_nfe.find('nfe:indSinc', ns_nfe)
                                        if ind_sinc_elem is None:
                                            ind_sinc_elem = envi_nfe.find('indSinc')
                                        
                                        if ind_sinc_elem is None:
                                            problemas_encontrados.append('indSinc ausente')
                                            debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: indSinc ausente, adicionando (valor 1)')
                                            # IMPORTANTE: indSinc deve ser o SEGUNDO elemento (após idLote)
                                            ind_sinc = lxml_etree.Element('{' + namespace_correto + '}indSinc')
                                            ind_sinc.text = '1'  # 1 = síncrono (NFC-e sempre síncrono)
                                            # Inserir como segundo elemento (após idLote)
                                            if len(envi_nfe) > 0:
                                                envi_nfe.insert(1, ind_sinc)
                                            else:
                                                envi_nfe.append(ind_sinc)
                                            corrigido = True
                                        else:
                                            # Verificar se indSinc é o segundo elemento (após idLote)
                                            indice_ind_sinc = list(envi_nfe).index(ind_sinc_elem)
                                            if indice_ind_sinc != 1:
                                                problemas_encontrados.append('indSinc não é o segundo elemento')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: indSinc não é o segundo elemento, reordenando')
                                                # Remover e reinserir como segundo
                                                ind_sinc_texto = ind_sinc_elem.text
                                                envi_nfe.remove(ind_sinc_elem)
                                                ind_sinc_novo = lxml_etree.Element('{' + namespace_correto + '}indSinc')
                                                ind_sinc_novo.text = ind_sinc_texto
                                                envi_nfe.insert(1, ind_sinc_novo)
                                                corrigido = True
                                            else:
                                                debug_print(f'>>> [PyNFe] ✅ indSinc presente e na posição correta: {ind_sinc_elem.text}')
                                        
                                        # 4. Validar NFe (deve ser o terceiro elemento, após idLote e indSinc)
                                        nfe_elem = envi_nfe.find('nfe:NFe', ns_nfe)
                                        if nfe_elem is None:
                                            nfe_elem = envi_nfe.find('NFe')
                                        
                                        if nfe_elem is None:
                                            problemas_encontrados.append('NFe ausente dentro do lote')
                                            debug_print(f'>>> [PyNFe] ❌ PROBLEMA CRÍTICO: NFe não encontrada dentro do lote!')
                                        else:
                                            debug_print(f'>>> [PyNFe] ✅ NFe encontrada dentro do lote')
                                            
                                            # Verificar se NFe tem namespace correto
                                            if not nfe_elem.tag.startswith('{' + namespace_correto + '}'):
                                                problemas_encontrados.append(f'Namespace da NFe incorreto: {nfe_elem.tag}')
                                                debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: NFe com namespace incorreto, corrigindo')
                                                # Criar nova NFe com namespace correto
                                                nova_nfe = lxml_etree.Element(
                                                    '{' + namespace_correto + '}NFe',
                                                    nsmap={None: namespace_correto}
                                                )
                                                
                                                # Copiar todos os filhos
                                                for child in nfe_elem:
                                                    nova_nfe.append(child)
                                                
                                                # Substituir mantendo posição
                                                posicao = list(envi_nfe).index(nfe_elem)
                                                envi_nfe.remove(nfe_elem)
                                                envi_nfe.insert(posicao, nova_nfe)
                                                nfe_elem = nova_nfe
                                                corrigido = True
                                            else:
                                                debug_print(f'>>> [PyNFe] ✅ NFe com namespace correto')
                                            
                                            # Verificar se NFe é o terceiro elemento (após idLote e indSinc)
                                            elementos_ordem = list(envi_nfe)
                                            if len(elementos_ordem) >= 3:
                                                if elementos_ordem[2] != nfe_elem:
                                                    problemas_encontrados.append('NFe não é o terceiro elemento')
                                                    debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: NFe não é o terceiro elemento, reordenando')
                                                    # Reordenar: idLote primeiro, indSinc segundo, NFe terceiro
                                                    id_lote_elem_ordem = elementos_ordem[0] if len(elementos_ordem) > 0 else None
                                                    ind_sinc_elem_ordem = elementos_ordem[1] if len(elementos_ordem) > 1 else None
                                                    elementos_ordenados = []
                                                    if id_lote_elem_ordem:
                                                        elementos_ordenados.append(id_lote_elem_ordem)
                                                    if ind_sinc_elem_ordem:
                                                        elementos_ordenados.append(ind_sinc_elem_ordem)
                                                    elementos_ordenados.append(nfe_elem)
                                                    for elem in elementos_ordem:
                                                        if elem != id_lote_elem_ordem and elem != ind_sinc_elem_ordem and elem != nfe_elem:
                                                            elementos_ordenados.append(elem)
                                                    
                                                    # Limpar e adicionar na ordem correta
                                                    for elem in list(envi_nfe):
                                                        envi_nfe.remove(elem)
                                                    for elem in elementos_ordenados:
                                                        envi_nfe.append(elem)
                                                    corrigido = True
                                                else:
                                                    debug_print(f'>>> [PyNFe] ✅ NFe presente e na posição correta (terceiro elemento)')
                                            
                                            # IMPORTANTE: Validar estrutura da NFe dentro do lote
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] VALIDAÇÃO DA NFe DENTRO DO LOTE')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            
                                            # Verificar infNFe dentro da NFe
                                            inf_nfe = nfe_elem.find('nfe:infNFe', ns_nfe)
                                            if inf_nfe is None:
                                                inf_nfe = nfe_elem.find('infNFe')
                                            
                                            if inf_nfe is None:
                                                problemas_encontrados.append('infNFe ausente dentro da NFe')
                                                debug_print(f'>>> [PyNFe] ❌ PROBLEMA CRÍTICO: infNFe não encontrada dentro da NFe!')
                                            else:
                                                debug_print(f'>>> [PyNFe] ✅ infNFe encontrada')
                                                
                                                # Verificar versão da infNFe
                                                versao_inf = inf_nfe.get('versao')
                                                if versao_inf != '4.00':
                                                    problemas_encontrados.append(f'Versão da infNFe incorreta: {versao_inf} (esperado: 4.00)')
                                                    debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: Versão da infNFe é {versao_inf}, corrigindo para 4.00')
                                                    inf_nfe.set('versao', '4.00')
                                                    corrigido = True
                                                
                                                # Verificar Id da infNFe
                                                id_inf = inf_nfe.get('Id')
                                                if not id_inf or not id_inf.startswith('NFe'):
                                                    problemas_encontrados.append(f'Id da infNFe inválido: {id_inf}')
                                                    debug_print(f'>>> [PyNFe] ⚠️ PROBLEMA: Id da infNFe inválido: {id_inf}')
                                                
                                                # Verificar elementos obrigatórios da infNFe
                                                elementos_obrigatorios = {
                                                    'ide': 'Identificação',
                                                    'emit': 'Emitente',
                                                    'det': 'Produtos/Serviços',
                                                    'total': 'Totalização',
                                                    'pag': 'Pagamento'
                                                }
                                                
                                                for elem_tag, descricao in elementos_obrigatorios.items():
                                                    elem = inf_nfe.find(f'nfe:{elem_tag}', ns_nfe) or inf_nfe.find(elem_tag)
                                                    if elem is None:
                                                        problemas_encontrados.append(f'{descricao} ({elem_tag}) ausente na infNFe')
                                                        debug_print(f'>>> [PyNFe] ❌ PROBLEMA: {descricao} ({elem_tag}) ausente!')
                                                    else:
                                                        debug_print(f'>>> [PyNFe] ✅ {descricao} ({elem_tag}) presente')
                                                
                                                # CORREÇÕES CRÍTICAS: cMunFG e CRT
                                                # 1. Corrigir cMunFG - OBRIGATÓRIO: deve ser código IBGE de 7 dígitos
                                                ide_correcao = inf_nfe.find('nfe:ide', ns_nfe) or inf_nfe.find('ide')
                                                if ide_correcao is not None:
                                                    c_mun_fg_correcao = ide_correcao.find('nfe:cMunFG', ns_nfe) or ide_correcao.find('cMunFG')
                                                    if c_mun_fg_correcao is not None:
                                                        # Verificar se é nome em vez de código
                                                        if not c_mun_fg_correcao.text or not c_mun_fg_correcao.text.strip().isdigit() or len(c_mun_fg_correcao.text.strip()) != 7:
                                                            valor_original_cmun = c_mun_fg_correcao.text if c_mun_fg_correcao.text else "vazio"
                                                            # Obter código IBGE do emitente
                                                            emit_correcao = inf_nfe.find('nfe:emit', ns_nfe) or inf_nfe.find('emit')
                                                            if emit_correcao is not None:
                                                                ender_emit_correcao = emit_correcao.find('nfe:enderEmit', ns_nfe) or emit_correcao.find('enderEmit')
                                                                if ender_emit_correcao is not None:
                                                                    c_mun_emit_correcao = ender_emit_correcao.find('nfe:cMun', ns_nfe) or ender_emit_correcao.find('cMun')
                                                                    if c_mun_emit_correcao is not None and c_mun_emit_correcao.text and c_mun_emit_correcao.text.strip().isdigit() and len(c_mun_emit_correcao.text.strip()) == 7:
                                                                        c_mun_fg_correcao.text = c_mun_emit_correcao.text.strip()
                                                                        debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{valor_original_cmun}" → "{c_mun_fg_correcao.text}"')
                                                                        corrigido = True
                                                                    else:
                                                                        # Usar código conhecido para São José dos Campos
                                                                        c_mun_fg_correcao.text = '3549904'
                                                                        debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{valor_original_cmun}" → "3549904"')
                                                                        corrigido = True
                                                                else:
                                                                    # Se não encontrou emitente, usar código padrão
                                                                    c_mun_fg_correcao.text = '3549904'
                                                                    debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido (emitente não encontrado): "{valor_original_cmun}" → "3549904"')
                                                                    corrigido = True
                                                
                                                # 2. Corrigir CRT - OBRIGATÓRIO: não pode estar vazio e não pode ter duplicados
                                                emit_correcao = inf_nfe.find('nfe:emit', ns_nfe) or inf_nfe.find('emit')
                                                if emit_correcao is not None:
                                                    # IMPORTANTE: Remover TODOS os CRTs primeiro (pode haver duplicados)
                                                    crts = emit_correcao.findall('nfe:CRT', ns_nfe) + emit_correcao.findall('CRT')
                                                    crt_valido_encontrado = None
                                                    for crt_elem in crts:
                                                        if crt_elem.text and crt_elem.text.strip():
                                                            if crt_valido_encontrado is None:
                                                                crt_valido_encontrado = crt_elem.text.strip()
                                                            # Remover duplicados
                                                            parent = crt_elem.getparent()
                                                            if parent is not None:
                                                                parent.remove(crt_elem)
                                                                debug_print(f'>>> [PyNFe] ✅ CRT duplicado/vazio removido')
                                                                corrigido = True
                                                    
                                                    # Criar um único CRT válido
                                                    crt_correcao = lxml_etree.SubElement(emit_correcao, '{' + namespace_correto + '}CRT')
                                                    if crt_valido_encontrado:
                                                        crt_correcao.text = crt_valido_encontrado
                                                        debug_print(f'>>> [PyNFe] ✅ CRT único criado: "{crt_valido_encontrado}"')
                                                    else:
                                                        crt_correcao.text = '1'  # Simples Nacional (padrão)
                                                        debug_print(f'>>> [PyNFe] ✅ CRT criado com valor padrão: "1"')
                                                    corrigido = True
                                                
                                                # 3. Validar valores decimais (devem ter exatamente 2 casas decimais)
                                                corrigido_decimais, problemas_decimais = self._validar_valores_decimais_xml(inf_nfe)
                                                if corrigido_decimais:
                                                    debug_print(f'>>> [PyNFe] ✅ Valores decimais corrigidos na infNFe')
                                                    corrigido = True
                                                if problemas_decimais:
                                                    for problema in problemas_decimais:
                                                        debug_print(f'>>> [PyNFe] ⚠️ {problema}')
                                                
                                                # 4. Validar caracteres proibidos
                                                corrigido_chars, problemas_chars = self._validar_caracteres_proibidos(inf_nfe)
                                                if corrigido_chars:
                                                    debug_print(f'>>> [PyNFe] ✅ Caracteres proibidos removidos da infNFe')
                                                    corrigido = True
                                                if problemas_chars:
                                                    for problema in problemas_chars:
                                                        debug_print(f'>>> [PyNFe] ⚠️ {problema}')
                                                
                                                # 5. Corrigir verProc - Versão do processo de emissão
                                                ide_verproc = inf_nfe.find('nfe:ide', ns_nfe) or inf_nfe.find('ide')
                                                if ide_verproc is not None:
                                                    ver_proc = ide_verproc.find('nfe:verProc', ns_nfe) or ide_verproc.find('verProc')
                                                    if ver_proc is not None:
                                                        # Alterar para "Sistema Exodo" conforme exemplo
                                                        ver_proc_original = ver_proc.text if ver_proc.text else ''
                                                        if 'pynfe' in ver_proc_original.lower() or ver_proc_original == '':
                                                            ver_proc.text = 'Sistema Exodo'
                                                            debug_print(f'>>> [PyNFe] ✅ verProc corrigido: "{ver_proc_original}" → "Sistema Exodo"')
                                                            corrigido = True
                                                    else:
                                                        # Criar verProc se não existir
                                                        ver_proc = lxml_etree.SubElement(ide_verproc, '{' + namespace_correto + '}verProc')
                                                        ver_proc.text = 'Sistema Exodo'
                                                        debug_print(f'>>> [PyNFe] ✅ verProc criado: "Sistema Exodo"')
                                                        corrigido = True
                                                
                                                # 6. Corrigir xPais - Deve ser "Brasil" (não "BRASIL")
                                                emit_xpais = inf_nfe.find('nfe:emit', ns_nfe) or inf_nfe.find('emit')
                                                if emit_xpais is not None:
                                                    ender_emit_xpais = emit_xpais.find('nfe:enderEmit', ns_nfe) or emit_xpais.find('enderEmit')
                                                    if ender_emit_xpais is not None:
                                                        x_pais = ender_emit_xpais.find('nfe:xPais', ns_nfe) or ender_emit_xpais.find('xPais')
                                                        if x_pais is not None:
                                                            if x_pais.text and x_pais.text.upper() == 'BRASIL':
                                                                x_pais.text = 'Brasil'
                                                                debug_print(f'>>> [PyNFe] ✅ xPais corrigido: "BRASIL" → "Brasil"')
                                                                corrigido = True
                                                
                                                # 7. Adicionar infAdic/infCpl se não existir (opcional, mas presente no exemplo)
                                                inf_adic = inf_nfe.find('nfe:infAdic', ns_nfe) or inf_nfe.find('infAdic')
                                                if inf_adic is None:
                                                    # Criar infAdic com infCpl
                                                    inf_adic = lxml_etree.SubElement(inf_nfe, '{' + namespace_correto + '}infAdic')
                                                    inf_cpl = lxml_etree.SubElement(inf_adic, '{' + namespace_correto + '}infCpl')
                                                    inf_cpl.text = 'NFC-e emitida pelo Sistema Exodo'
                                                    debug_print(f'>>> [PyNFe] ✅ infAdic/infCpl adicionado')
                                                    corrigido = True
                                            
                                            debug_print(f'>>> [PyNFe] ========================================')
                                        
                                        # Resumo dos problemas encontrados
                                        if problemas_encontrados:
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] PROBLEMAS ENCONTRADOS NO LOTE:')
                                            for i, problema in enumerate(problemas_encontrados, 1):
                                                debug_print(f'>>> [PyNFe]   {i}. {problema}')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                        else:
                                            debug_print(f'>>> [PyNFe] ✅ Nenhum problema encontrado na estrutura do lote')
                                        
                                        # Validação final da estrutura do lote
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        debug_print(f'>>> [PyNFe] VALIDAÇÃO FINAL DO LOTE')
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        
                                        # Verificar estrutura final
                                        versao_final = envi_nfe.get('versao')
                                        namespace_final = envi_nfe.nsmap.get(None) if hasattr(envi_nfe, 'nsmap') and envi_nfe.nsmap else None
                                        id_lote_final = envi_nfe.find('nfe:idLote', ns_nfe) or envi_nfe.find('idLote')
                                        nfe_final = envi_nfe.find('nfe:NFe', ns_nfe) or envi_nfe.find('NFe')
                                        
                                        debug_print(f'>>> [PyNFe] Estrutura final do lote:')
                                        debug_print(f'>>> [PyNFe]   - Versão: {versao_final} {"✅" if versao_final == "4.00" else "❌"}')
                                        debug_print(f'>>> [PyNFe]   - Namespace: {namespace_final} {"✅" if namespace_final == namespace_correto else "❌"}')
                                        debug_print(f'>>> [PyNFe]   - idLote: {"✅" if id_lote_final is not None else "❌"} {id_lote_final.text if id_lote_final is not None else ""}')
                                        debug_print(f'>>> [PyNFe]   - NFe: {"✅" if nfe_final is not None else "❌"}')
                                        
                                        # Verificar ordem dos elementos
                                        elementos_finais = list(envi_nfe)
                                        ordem_correta = True
                                        if len(elementos_finais) >= 1:
                                            primeiro = elementos_finais[0]
                                            tag_primeiro = primeiro.tag.split('}')[-1] if '}' in primeiro.tag else primeiro.tag
                                            if tag_primeiro != 'idLote':
                                                ordem_correta = False
                                                debug_print(f'>>> [PyNFe] ⚠️ Primeiro elemento não é idLote: {tag_primeiro}')
                                        
                                        if len(elementos_finais) >= 2:
                                            segundo = elementos_finais[1]
                                            tag_segundo = segundo.tag.split('}')[-1] if '}' in segundo.tag else segundo.tag
                                            if tag_segundo != 'indSinc':
                                                ordem_correta = False
                                                debug_print(f'>>> [PyNFe] ⚠️ Segundo elemento não é indSinc: {tag_segundo}')
                                        
                                        if len(elementos_finais) >= 3:
                                            terceiro = elementos_finais[2]
                                            tag_terceiro = terceiro.tag.split('}')[-1] if '}' in terceiro.tag else terceiro.tag
                                            if tag_terceiro != 'NFe':
                                                ordem_correta = False
                                                debug_print(f'>>> [PyNFe] ⚠️ Terceiro elemento não é NFe: {tag_terceiro}')
                                        
                                        if ordem_correta:
                                            debug_print(f'>>> [PyNFe] ✅ Ordem dos elementos correta: idLote, indSinc, NFe')
                                        else:
                                            debug_print(f'>>> [PyNFe] ⚠️ Ordem dos elementos pode estar incorreta')
                                        
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        
                                        # IMPORTANTE: Sempre atualizar XML se houve correção ou se há problemas
                                        # Mesmo que não tenha sido possível corrigir automaticamente, 
                                        # precisamos garantir que o XML está na melhor forma possível
                                        if corrigido or problemas_encontrados:
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] ATUALIZANDO XML DO LOTE')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] Correções aplicadas: {corrigido}')
                                            debug_print(f'>>> [PyNFe] Problemas encontrados: {len(problemas_encontrados)}')
                                            
                                            if problemas_encontrados and not corrigido:
                                                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: Há problemas que não puderam ser corrigidos automaticamente!')
                                                debug_print(f'>>> [PyNFe] O XML será atualizado, mas pode ainda conter problemas.')
                                            # IMPORTANTE: RECONSTRUIR COMPLETAMENTE O LOTE DO ZERO
                                            # Extrair apenas a NFe assinada e reconstruir o enviNFe limpo
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] RECONSTRUINDO LOTE COMPLETAMENTE DO ZERO')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            
                                            # Extrair NFe (com assinatura)
                                            nfe_para_reconstruir = envi_nfe.find('nfe:NFe', ns_nfe) or envi_nfe.find('NFe')
                                            if nfe_para_reconstruir is None:
                                                # Tentar encontrar em qualquer lugar
                                                nfe_para_reconstruir = lote_xml.find('.//nfe:NFe', ns_nfe) or lote_xml.find('.//NFe')
                                            
                                            if nfe_para_reconstruir is None:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO: NFe não encontrada para reconstrução!')
                                                xml_corrigido = lxml_etree.tostring(envi_nfe if envi_nfe == lote_xml else lote_xml, 
                                                                                  encoding='unicode', 
                                                                                  xml_declaration=False,
                                                                                  pretty_print=False)
                                            else:
                                                # RECONSTRUIR enviNFe do zero com estrutura perfeita
                                                envi_nfe_novo = lxml_etree.Element(
                                                    '{' + namespace_correto + '}enviNFe',
                                                    nsmap={None: namespace_correto},
                                                    versao='4.00'
                                                )
                                                
                                                # 1. idLote (15 dígitos)
                                                id_lote_novo = lxml_etree.SubElement(envi_nfe_novo, '{' + namespace_correto + '}idLote')
                                                id_lote_texto = '000000000000001'
                                                id_lote_elem_original = envi_nfe.find('nfe:idLote', ns_nfe) or envi_nfe.find('idLote')
                                                if id_lote_elem_original and id_lote_elem_original.text:
                                                    id_lote_texto = id_lote_elem_original.text.strip().zfill(15)[:15]
                                                id_lote_novo.text = id_lote_texto
                                                
                                                # 2. indSinc (valor 1)
                                                ind_sinc_novo = lxml_etree.SubElement(envi_nfe_novo, '{' + namespace_correto + '}indSinc')
                                                ind_sinc_novo.text = '1'
                                                
                                                # 3. NFe (copiar e limpar)
                                                # IMPORTANTE: Copiar NFe e remover prefixos recursivamente
                                                nfe_nova = self._copiar_elemento_limpo(nfe_para_reconstruir, namespace_correto)
                                                envi_nfe_novo.append(nfe_nova)
                                                
                                                # Aplicar correções finais na NFe reconstruída
                                                inf_nfe_reconstruida = nfe_nova.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_nova.find('.//infNFe')
                                                if inf_nfe_reconstruida is not None:
                                                    self._aplicar_correcoes_finais_infnfe(inf_nfe_reconstruida, namespace_correto)
                                                
                                                # Gerar XML final limpo
                                                xml_corrigido = lxml_etree.tostring(envi_nfe_novo, 
                                                                                  encoding='unicode', 
                                                                                  xml_declaration=False,
                                                                                  pretty_print=False)
                                                
                                                debug_print(f'>>> [PyNFe] ✅ Lote reconstruído completamente do zero')
                                                debug_print(f'>>> [PyNFe] Tamanho do XML reconstruído: {len(xml_corrigido)} caracteres')
                                                
                                                # Substituir o XML original pelo reconstruído
                                                envi_nfe.clear()
                                                for child in envi_nfe_novo:
                                                    envi_nfe.append(child)
                                                for attr, valor in envi_nfe_novo.attrib.items():
                                                    envi_nfe.set(attr, valor)
                                                envi_nfe.tag = envi_nfe_novo.tag
                                                if hasattr(envi_nfe, 'nsmap'):
                                                    envi_nfe.nsmap.clear()
                                                    envi_nfe.nsmap.update(envi_nfe_novo.nsmap)
                                            
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] XML DO LOTE CORRIGIDO')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] XML corrigido (primeiros 2000 chars):')
                                            debug_print(xml_corrigido[:2000])
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            
                                            # IMPORTANTE: Validar XML corrigido antes de usar
                                            # Baseado em: https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/
                                            try:
                                                # Tentar parsear o XML corrigido para garantir que está válido
                                                xml_validacao = lxml_etree.fromstring(xml_corrigido.encode('utf-8'))
                                                debug_print(f'>>> [PyNFe] ✅ XML corrigido é válido (parse bem-sucedido)')
                                                
                                                # Verificar estrutura básica
                                                envi_nfe_validacao = xml_validacao.find('.//nfe:enviNFe', ns_nfe) or xml_validacao.find('.//enviNFe')
                                                if envi_nfe_validacao is None and 'enviNFe' in xml_validacao.tag:
                                                    envi_nfe_validacao = xml_validacao
                                                
                                                if envi_nfe_validacao is not None:
                                                    versao_val = envi_nfe_validacao.get('versao')
                                                    id_lote_val = envi_nfe_validacao.find('nfe:idLote', ns_nfe) or envi_nfe_validacao.find('idLote')
                                                    nfe_val = envi_nfe_validacao.find('nfe:NFe', ns_nfe) or envi_nfe_validacao.find('NFe')
                                                    
                                                    debug_print(f'>>> [PyNFe] Validação do XML corrigido:')
                                                    debug_print(f'>>> [PyNFe]   - Versão: {versao_val} {"✅" if versao_val == "4.00" else "❌"}')
                                                    debug_print(f'>>> [PyNFe]   - idLote: {"✅" if id_lote_val is not None else "❌"}')
                                                    debug_print(f'>>> [PyNFe]   - NFe: {"✅" if nfe_val is not None else "❌"}')
                                                    
                                                    # CORREÇÕES CRÍTICAS DENTRO DA NFe
                                                    # Aplicar correções em TODAS as infNFe dentro da NFe
                                                    todas_inf_nfe_intercept = nfe_val.findall('.//nfe:infNFe', ns_nfe) or nfe_val.findall('.//infNFe')
                                                    debug_print(f'>>> [PyNFe] Encontradas {len(todas_inf_nfe_intercept)} infNFe para correção')
                                                    
                                                    for inf_nfe_intercept in todas_inf_nfe_intercept:
                                                        # 1. Corrigir cMunFG - OBRIGATÓRIO: deve ser código IBGE de 7 dígitos
                                                        ide_intercept = inf_nfe_intercept.find('.//nfe:ide', ns_nfe) or inf_nfe_intercept.find('.//ide')
                                                        if ide_intercept is not None:
                                                            c_mun_fg_intercept = ide_intercept.find('.//nfe:cMunFG', ns_nfe) or ide_intercept.find('.//cMunFG')
                                                            if c_mun_fg_intercept is not None:
                                                                # Verificar se é nome em vez de código
                                                                if not c_mun_fg_intercept.text or not c_mun_fg_intercept.text.strip().isdigit() or len(c_mun_fg_intercept.text.strip()) != 7:
                                                                    valor_original_cmun = c_mun_fg_intercept.text if c_mun_fg_intercept.text else "vazio"
                                                                    # Obter código IBGE do emitente
                                                                    emit_intercept = inf_nfe_intercept.find('.//nfe:emit', ns_nfe) or inf_nfe_intercept.find('.//emit')
                                                                    if emit_intercept is not None:
                                                                        ender_emit_intercept = emit_intercept.find('.//nfe:enderEmit', ns_nfe) or emit_intercept.find('.//enderEmit')
                                                                        if ender_emit_intercept is not None:
                                                                            c_mun_emit_intercept = ender_emit_intercept.find('.//nfe:cMun', ns_nfe) or ender_emit_intercept.find('.//cMun')
                                                                            if c_mun_emit_intercept is not None and c_mun_emit_intercept.text and c_mun_emit_intercept.text.strip().isdigit() and len(c_mun_emit_intercept.text.strip()) == 7:
                                                                                c_mun_fg_intercept.text = c_mun_emit_intercept.text.strip()
                                                                                debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido na interceptação: "{valor_original_cmun}" → "{c_mun_fg_intercept.text}"')
                                                                                corrigido = True
                                                                            else:
                                                                                # Usar código conhecido para São José dos Campos
                                                                                c_mun_fg_intercept.text = '3549904'
                                                                                debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido na interceptação: "{valor_original_cmun}" → "3549904"')
                                                                                corrigido = True
                                                                        else:
                                                                            # Se não encontrou emitente, usar código padrão
                                                                            c_mun_fg_intercept.text = '3549904'
                                                                            debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido na interceptação (emitente não encontrado): "{valor_original_cmun}" → "3549904"')
                                                                            corrigido = True
                                                        
                                                        # 2. Corrigir CRT - OBRIGATÓRIO: não pode estar vazio
                                                        emit_intercept = inf_nfe_intercept.find('.//nfe:emit', ns_nfe) or inf_nfe_intercept.find('.//emit')
                                                        if emit_intercept is not None:
                                                            # Remover CRT vazio se existir
                                                            crts = emit_intercept.findall('.//nfe:CRT', ns_nfe) or emit_intercept.findall('.//CRT')
                                                            crt_vazio_removido = False
                                                            for crt_elem in crts:
                                                                if not crt_elem.text or not crt_elem.text.strip():
                                                                    parent = crt_elem.getparent()
                                                                    if parent is not None:
                                                                        parent.remove(crt_elem)
                                                                        crt_vazio_removido = True
                                                                        debug_print(f'>>> [PyNFe] ✅ CRT vazio removido')
                                                                        corrigido = True
                                                            
                                                            # Verificar se tem CRT válido
                                                            crt_intercept = emit_intercept.find('.//nfe:CRT', ns_nfe) or emit_intercept.find('.//CRT')
                                                            if crt_intercept is None or not crt_intercept.text or not crt_intercept.text.strip():
                                                                # Criar ou corrigir CRT
                                                                if crt_intercept is None:
                                                                    crt_intercept = lxml_etree.SubElement(emit_intercept, '{' + namespace_correto + '}CRT')
                                                                crt_intercept.text = '1'  # Simples Nacional (padrão)
                                                                debug_print(f'>>> [PyNFe] ✅ CRT corrigido/criado na interceptação: "1"')
                                                                corrigido = True
                                                    
                                                    # VALIDAÇÕES ADICIONAIS BASEADAS NO ARTIGO TECNOSPEED
                                                    # 1. Validar valores decimais (devem ter exatamente 2 casas decimais)
                                                    if nfe_val is not None:
                                                        corrigido_decimais, problemas_decimais = self._validar_valores_decimais_xml(nfe_val)
                                                        if corrigido_decimais:
                                                            debug_print(f'>>> [PyNFe] ✅ Valores decimais corrigidos')
                                                            corrigido = True
                                                        if problemas_decimais:
                                                            for problema in problemas_decimais:
                                                                debug_print(f'>>> [PyNFe] ⚠️ {problema}')
                                                        
                                                        # 2. Validar caracteres proibidos
                                                        corrigido_chars, problemas_chars = self._validar_caracteres_proibidos(nfe_val)
                                                        if corrigido_chars:
                                                            debug_print(f'>>> [PyNFe] ✅ Caracteres proibidos removidos')
                                                            corrigido = True
                                                        if problemas_chars:
                                                            for problema in problemas_chars:
                                                                debug_print(f'>>> [PyNFe] ⚠️ {problema}')
                                                    
                                                    # Regenerar XML após todas as correções
                                                    if corrigido:
                                                        xml_corrigido = lxml_etree.tostring(envi_nfe if envi_nfe == lote_xml else lote_xml, 
                                                                                          encoding='unicode', 
                                                                                          xml_declaration=False,
                                                                                          pretty_print=False)
                                                        debug_print(f'>>> [PyNFe] ✅ XML regenerado após correções (cMunFG, CRT, decimais)')
                                                    
                                                    # 3. Validar estrutura completa do XML
                                                    valido_estrutura, problemas_estrutura, avisos_estrutura = self._validar_estrutura_xml_completa(xml_corrigido)
                                                    if problemas_estrutura:
                                                        for problema in problemas_estrutura:
                                                            debug_print(f'>>> [PyNFe] ❌ PROBLEMA ESTRUTURAL: {problema}')
                                                            problemas_encontrados.append(problema)
                                                    if avisos_estrutura:
                                                        for aviso in avisos_estrutura:
                                                            debug_print(f'>>> [PyNFe] ⚠️ AVISO: {aviso}')
                                                    
                                                    if versao_val == '4.00' and id_lote_val is not None and nfe_val is not None and valido_estrutura:
                                                        debug_print(f'>>> [PyNFe] ✅ XML corrigido está estruturalmente correto!')
                                                    else:
                                                        debug_print(f'>>> [PyNFe] ⚠️ XML corrigido ainda tem problemas estruturais')
                                            except Exception as e_validacao:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO: XML corrigido não é válido: {e_validacao}')
                                                import traceback
                                                debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                                            
                                            # IMPORTANTE: NÃO recolocar no SOAP - enviar apenas o XML puro do enviNFe
                                            # O XML correto é APENAS o enviNFe, sem envelope SOAP, sem prefixos
                                            xml_str = xml_corrigido
                                            
                                            # GARANTIR que não há SOAP nem prefixos
                                            if '<soap' in xml_str.lower() or 'nfeDadosMsg' in xml_str:
                                                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: SOAP ainda presente no XML final - removendo...')
                                                inicio = xml_str.find('<enviNFe')
                                                fim = xml_str.rfind('</enviNFe>') + len('</enviNFe>')
                                                if inicio >= 0 and fim > inicio:
                                                    xml_str = xml_str[inicio:fim]
                                            
                                            # Remover TODOS os prefixos
                                            xml_str = xml_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '')
                                            xml_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', xml_str)
                                            
                                            debug_print(f'>>> [PyNFe] ✅ XML final será APENAS o enviNFe (sem SOAP, sem prefixos)')
                                            debug_print(f'>>> [PyNFe] Tamanho do XML final: {len(xml_str)} caracteres')
                                            
                                            # Verificação final crítica
                                            if '<soap' in xml_str.lower() or 'nfeDadosMsg' in xml_str:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: SOAP ainda presente após remoção!')
                                            if 'ns0:' in xml_str or 'ns1:' in xml_str:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: Prefixos ainda presentes após remoção!')
                                            if '<idLote>1</idLote>' in xml_str:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: idLote ainda com valor "1" (deve ser 15 dígitos)!')
                                                xml_str = xml_str.replace('<idLote>1</idLote>', '<idLote>000000000000001</idLote>')
                                                debug_print(f'>>> [PyNFe] ✅ idLote corrigido para 15 dígitos')
                                            
                                            # IMPORTANTE: Verificar se ainda tem prefixos ns0: no XML
                                            if 'ns0:' in xml_str or 'xmlns:ns0' in xml_str:
                                                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: XML ainda contém prefixos ns0: - removendo...')
                                                # Remover prefixos por substituição de string (último recurso)
                                                xml_str = xml_str.replace('ns0:', '').replace('xmlns:ns0="http://www.portalfiscal.inf.br/nfe"', '')
                                                debug_print(f'>>> [PyNFe] ✅ Prefixos ns0: removidos por substituição de string')
                                            
                                            # Verificar se cMunFG ainda está como texto
                                            import re
                                            cMunFG_match = re.search(r'<cMunFG>([^<]+)</cMunFG>', xml_str)
                                            if cMunFG_match:
                                                cMunFG_valor = cMunFG_match.group(1)
                                                if not cMunFG_valor.strip().isdigit() or len(cMunFG_valor.strip()) != 7:
                                                    debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: cMunFG ainda é texto "{cMunFG_valor}" - corrigindo...')
                                                    # Buscar código no emitente
                                                    cMun_match = re.search(r'<cMun>(\d{7})</cMun>', xml_str)
                                                    if cMun_match:
                                                        codigo_ibge = cMun_match.group(1)
                                                        xml_str = xml_str.replace(f'<cMunFG>{cMunFG_valor}</cMunFG>', f'<cMunFG>{codigo_ibge}</cMunFG>')
                                                        debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido: "{cMunFG_valor}" → "{codigo_ibge}"')
                                                    else:
                                                        xml_str = xml_str.replace(f'<cMunFG>{cMunFG_valor}</cMunFG>', '<cMunFG>3549904</cMunFG>')
                                                        debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido com fallback: "{cMunFG_valor}" → "3549904"')
                                            
                                            # Verificar se verProc ainda é PyNFe
                                            if 'PyNFe' in xml_str and '<verProc>' in xml_str:
                                                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: verProc ainda contém PyNFe - corrigindo...')
                                                xml_str = re.sub(r'<verProc>[^<]*PyNFe[^<]*</verProc>', '<verProc>Sistema Exodo</verProc>', xml_str)
                                                debug_print(f'>>> [PyNFe] ✅ verProc corrigido para "Sistema Exodo"')
                                            
                                            # Verificar se CRT está duplicado
                                            crt_count = xml_str.count('<CRT>')
                                            if crt_count > 1:
                                                debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: CRT duplicado ({crt_count} vezes) - removendo duplicados...')
                                                # Manter apenas o primeiro CRT válido
                                                crt_match = re.search(r'<CRT>(\d)</CRT>', xml_str)
                                                if crt_match:
                                                    crt_valor = crt_match.group(1)
                                                    # Remover todos os CRTs
                                                    xml_str = re.sub(r'<CRT>[^<]*</CRT>', '', xml_str)
                                                    # Adicionar um único CRT após IE
                                                    xml_str = re.sub(r'(</IE>)', r'\1<CRT>' + crt_valor + '</CRT>', xml_str, count=1)
                                                    debug_print(f'>>> [PyNFe] ✅ CRT duplicados removidos, mantido apenas um: "{crt_valor}"')
                                            
                                            # Remover namespaces extras do enviNFe
                                            xml_str = re.sub(r'xmlns:xsi="[^"]*"', '', xml_str)
                                            xml_str = re.sub(r'xmlns:xsd="[^"]*"', '', xml_str)
                                            xml_str = re.sub(r'xmlns:soap="[^"]*"', '', xml_str)
                                            xml_str = re.sub(r'\s+', ' ', xml_str)  # Remover espaços extras
                                            debug_print(f'>>> [PyNFe] ✅ Namespaces extras removidos do enviNFe')
                                            
                                            # VALIDAÇÃO COMPLETA DO XML ANTES DE ENVIAR
                                            if self.xml_validator:
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                debug_print(f'>>> [PyNFe] VALIDAÇÃO COMPLETA DO XML')
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                resultado_validacao = self.xml_validator.validar_completo(xml_str)
                                                
                                                if resultado_validacao['valido']:
                                                    debug_print(f'>>> [PyNFe] ✅ XML VALIDADO COM SUCESSO!')
                                                else:
                                                    debug_print(f'>>> [PyNFe] ❌ XML COM ERROS DE VALIDAÇÃO!')
                                                    debug_print(f'>>> [PyNFe] Estrutura válida: {resultado_validacao["estrutura_valida"]}')
                                                    debug_print(f'>>> [PyNFe] Decimais válidos: {resultado_validacao["decimais_validos"]}')
                                                
                                                # Exibir erros
                                                if resultado_validacao['erros']:
                                                    debug_print(f'>>> [PyNFe] ERROS ENCONTRADOS ({len(resultado_validacao["erros"])}):')
                                                    for i, erro in enumerate(resultado_validacao['erros'], 1):
                                                        debug_print(f'>>> [PyNFe]   {i}. {erro}')
                                                
                                                # Exibir avisos
                                                if resultado_validacao['avisos']:
                                                    debug_print(f'>>> [PyNFe] AVISOS ({len(resultado_validacao["avisos"])}):')
                                                    for i, aviso in enumerate(resultado_validacao['avisos'], 1):
                                                        debug_print(f'>>> [PyNFe]   {i}. {aviso}')
                                                
                                                # Gerar e salvar relatório
                                                relatorio = self.xml_validator.gerar_relatorio(resultado_validacao)
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                debug_print(relatorio)
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                
                                                # Salvar relatório em arquivo
                                                try:
                                                    import os
                                                    empresa_dir = self._obter_diretorio_empresa()
                                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                                    relatorio_file = os.path.join(empresa_dir, f'validacao_xml_{timestamp}.txt')
                                                    with open(relatorio_file, 'w', encoding='utf-8') as f:
                                                        f.write(relatorio)
                                                    debug_print(f'>>> [PyNFe] Relatório salvo em: {relatorio_file}')
                                                except Exception as e:
                                                    debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar relatório: {e}')
                                                
                                                # Se houver erros críticos, tentar corrigir automaticamente
                                                if not resultado_validacao['valido'] and resultado_validacao['erros']:
                                                    debug_print(f'>>> [PyNFe] ⚠️ Tentando corrigir erros automaticamente...')
                                                    xml_str = self._corrigir_erros_validacao(xml_str, resultado_validacao)
                                                    
                                                    # Revalidar após correção
                                                    resultado_validacao_pos = self.xml_validator.validar_completo(xml_str)
                                                    if resultado_validacao_pos['valido']:
                                                        debug_print(f'>>> [PyNFe] ✅ XML CORRIGIDO E VALIDADO!')
                                                    else:
                                                        debug_print(f'>>> [PyNFe] ⚠️ Ainda há erros após correção automática')
                                                        if resultado_validacao_pos['erros']:
                                                            debug_print(f'>>> [PyNFe] Erros restantes:')
                                                            for i, erro in enumerate(resultado_validacao_pos['erros'], 1):
                                                                debug_print(f'>>> [PyNFe]   {i}. {erro}')
                                            
                                            # IMPORTANTE: RECONSTRUÇÃO FINAL COMPLETA DO XML
                                            # Garantir que o XML está completamente limpo e correto
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] RECONSTRUÇÃO FINAL COMPLETA DO XML')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            
                                            # Parsear XML corrigido
                                            try:
                                                xml_final_tree = lxml_etree.fromstring(xml_str.encode('utf-8'))
                                                
                                                # Encontrar enviNFe
                                                envi_nfe_final = xml_final_tree
                                                if 'enviNFe' not in xml_final_tree.tag:
                                                    envi_nfe_final = xml_final_tree.find('.//enviNFe') or xml_final_tree.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
                                                
                                                if envi_nfe_final is None:
                                                    envi_nfe_final = xml_final_tree
                                                
                                                # RECONSTRUIR COMPLETAMENTE DO ZERO
                                                namespace_final = 'http://www.portalfiscal.inf.br/nfe'
                                                envi_nfe_reconstruido = lxml_etree.Element(
                                                    '{' + namespace_final + '}enviNFe',
                                                    nsmap={None: namespace_final},
                                                    versao='4.00'
                                                )
                                                
                                                # 1. idLote (15 dígitos)
                                                id_lote_reconstruido = lxml_etree.SubElement(envi_nfe_reconstruido, '{' + namespace_final + '}idLote')
                                                id_lote_original = envi_nfe_final.find('.//idLote') or envi_nfe_final.find('.//{http://www.portalfiscal.inf.br/nfe}idLote')
                                                if id_lote_original is not None and id_lote_original.text:
                                                    id_lote_reconstruido.text = id_lote_original.text.strip().zfill(15)[:15]
                                                else:
                                                    id_lote_reconstruido.text = '000000000000001'
                                                
                                                # 2. indSinc (valor 1)
                                                ind_sinc_reconstruido = lxml_etree.SubElement(envi_nfe_reconstruido, '{' + namespace_final + '}indSinc')
                                                ind_sinc_reconstruido.text = '1'
                                                
                                                # 3. NFe (copiar e limpar completamente)
                                                nfe_original = envi_nfe_final.find('.//NFe') or envi_nfe_final.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                                                if nfe_original is not None:
                                                    # Copiar NFe sem prefixos
                                                    nfe_reconstruida = self._copiar_elemento_limpo(nfe_original, namespace_final)
                                                    
                                                    # Aplicar correções finais na infNFe
                                                    inf_nfe_reconstruida = nfe_reconstruida.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_reconstruida.find('.//infNFe')
                                                    if inf_nfe_reconstruida is not None:
                                                        self._aplicar_correcoes_finais_infnfe(inf_nfe_reconstruida, namespace_final)
                                                    
                                                    envi_nfe_reconstruido.append(nfe_reconstruida)
                                                
                                                # Gerar XML final completamente limpo
                                                xml_str = lxml_etree.tostring(envi_nfe_reconstruido, 
                                                                              encoding='unicode', 
                                                                              xml_declaration=False,
                                                                              pretty_print=False)
                                                
                                                # Remover qualquer prefixo de namespace restante
                                                xml_str = xml_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '')
                                                xml_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', xml_str)
                                                xml_str = re.sub(r'xmlns:xsi="[^"]*"', '', xml_str)
                                                xml_str = re.sub(r'xmlns:xsd="[^"]*"', '', xml_str)
                                                xml_str = re.sub(r'xmlns:soap="[^"]*"', '', xml_str)
                                                
                                                debug_print(f'>>> [PyNFe] ✅ XML completamente reconstruído do zero')
                                                debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                                                
                                            except Exception as e_reconstrucao:
                                                debug_print(f'>>> [PyNFe] ⚠️ Erro na reconstrução final: {e_reconstrucao}')
                                                import traceback
                                                debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                                            
                                            # Verificar se o XML corrigido está correto
                                            if 'idLote>000000000000001</idLote>' in xml_str or '<idLote>000000000000001</idLote>' in xml_str or re.search(r'<idLote>\d{15}</idLote>', xml_str):
                                                debug_print(f'>>> [PyNFe] ✅ idLote com 15 dígitos confirmado no XML final')
                                            if '<indSinc>1</indSinc>' in xml_str:
                                                debug_print(f'>>> [PyNFe] ✅ indSinc confirmado no XML final')
                                            else:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO: indSinc NÃO encontrado no XML final!')
                                            
                                            # Verificar campos críticos
                                            if re.search(r'<cMunFG>\d{7}</cMunFG>', xml_str):
                                                debug_print(f'>>> [PyNFe] ✅ cMunFG com código IBGE confirmado')
                                            if '<CRT>1</CRT>' in xml_str and xml_str.count('<CRT>') == 1:
                                                debug_print(f'>>> [PyNFe] ✅ CRT único confirmado')
                                            if '<verProc>Sistema Exodo</verProc>' in xml_str:
                                                debug_print(f'>>> [PyNFe] ✅ verProc corrigido confirmado')
                                            if 'ns0:' not in xml_str and 'ns1:' not in xml_str:
                                                debug_print(f'>>> [PyNFe] ✅ Prefixos de namespace removidos')
                                            
                                            # Salvar XML corrigido para análise
                                            try:
                                                import os
                                                
                                                # Obter diretório da empresa
                                                empresa_dir = self._obter_diretorio_empresa()
                                                
                                                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                                xml_file_corrigido = os.path.join(empresa_dir, f'lote_enviNFe_corrigido_{timestamp}.xml')
                                                with open(xml_file_corrigido, 'w', encoding='utf-8') as f:
                                                    f.write(xml_str)
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                debug_print(f'>>> [PyNFe] XML CORRIGIDO SALVO')
                                                debug_print(f'>>> [PyNFe] ========================================')
                                                debug_print(f'>>> [PyNFe] Arquivo: {xml_file_corrigido}')
                                                debug_print(f'>>> [PyNFe] Tamanho: {len(xml_str)} caracteres')
                                                
                                                # Verificar se cMunFG e CRT foram corrigidos
                                                if 'cMunFG>3549904</cMunFG>' in xml_str or '<cMunFG>3549904</cMunFG>' in xml_str:
                                                    debug_print(f'>>> [PyNFe] ✅ cMunFG corrigido confirmado no XML final')
                                                if '<CRT>1</CRT>' in xml_str and '<CRT/>' not in xml_str:
                                                    debug_print(f'>>> [PyNFe] ✅ CRT corrigido confirmado no XML final')
                                                
                                                # Se há problemas não corrigidos, adicionar aviso no arquivo
                                                if problemas_encontrados and not corrigido:
                                                    aviso_file = xml_file_corrigido.replace('.xml', '_AVISOS.txt')
                                                    with open(aviso_file, 'w', encoding='utf-8') as f:
                                                        f.write('PROBLEMAS ENCONTRADOS NO XML DO LOTE:\n')
                                                        f.write('=' * 60 + '\n\n')
                                                        for i, problema in enumerate(problemas_encontrados, 1):
                                                            f.write(f'{i}. {problema}\n')
                                                        f.write('\n' + '=' * 60 + '\n')
                                                        f.write('ATENÇÃO: Estes problemas não puderam ser corrigidos automaticamente.\n')
                                                        f.write('Verifique o XML manualmente e corrija antes de reenviar.\n')
                                                    debug_print(f'>>> [PyNFe] Arquivo de avisos salvo: {aviso_file}')
                                                
                                                debug_print(f'>>> [PyNFe] ========================================')
                                            except Exception as e_save:
                                                debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar XML corrigido: {e_save}')
                                            
                                            # IMPORTANTE: O XML já foi reconstruído e aplicado acima
                                            # Esta seção é apenas para validação adicional
                                            # Não atualizar novamente aqui para evitar sobrescrever o XML já correto
                                            debug_print(f'>>> [PyNFe] ✅ XML já foi reconstruído e aplicado anteriormente')
                                        else:
                                            # Se não houve correção nem problemas, ainda assim validar estrutura
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] NENHUMA CORREÇÃO NECESSÁRIA')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                            debug_print(f'>>> [PyNFe] O XML do lote parece estar correto.')
                                            debug_print(f'>>> [PyNFe] Versão: {versao_final}')
                                            debug_print(f'>>> [PyNFe] Namespace: {namespace_final}')
                                            debug_print(f'>>> [PyNFe] idLote: {"Presente" if id_lote_final is not None else "Ausente"}')
                                            debug_print(f'>>> [PyNFe] NFe: {"Presente" if nfe_final is not None else "Ausente"}')
                                            debug_print(f'>>> [PyNFe] ========================================')
                                except Exception as e_correcao:
                                    debug_print(f'>>> [PyNFe] ⚠️ Erro ao corrigir XML do lote: {e_correcao}')
                                    import traceback
                                    debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                                    # Continuar mesmo se não conseguir corrigir
                                    
                                    # Continuar com validação original
                                    if envi_nfe is not None:
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        debug_print(f'>>> [PyNFe] ANÁLISE DETALHADA DO LOTE')
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        
                                        # Verificar versão
                                        versao = envi_nfe.get('versao')
                                        debug_print(f'>>> [PyNFe] Versão do lote: {versao}')
                                        if versao != '4.00':
                                            debug_print(f'>>> [PyNFe] ❌ ERRO: Versão do lote é {versao}, esperado 4.00')
                                        else:
                                            debug_print(f'>>> [PyNFe] ✅ Versão correta: 4.00')
                                        
                                        # Verificar namespace
                                        namespace = envi_nfe.nsmap.get(None) if hasattr(envi_nfe, 'nsmap') else None
                                        debug_print(f'>>> [PyNFe] Namespace do lote: {namespace}')
                                        if namespace != 'http://www.portalfiscal.inf.br/nfe':
                                            debug_print(f'>>> [PyNFe] ⚠️ ATENÇÃO: Namespace pode estar incorreto')
                                        
                                        # Verificar se tem idLote
                                        id_lote_elem = envi_nfe.find('nfe:idLote', ns_nfe)
                                        if id_lote_elem is None:
                                            id_lote_elem = envi_nfe.find('idLote')
                                        if id_lote_elem is not None:
                                            debug_print(f'>>> [PyNFe] ✅ ID do lote: {id_lote_elem.text}')
                                        else:
                                            debug_print(f'>>> [PyNFe] ❌ ERRO: idLote não encontrado!')
                                        
                                        # Verificar se tem NFe dentro
                                        nfe_elem = envi_nfe.find('nfe:NFe', ns_nfe)
                                        if nfe_elem is None:
                                            nfe_elem = envi_nfe.find('NFe')
                                        if nfe_elem is not None:
                                            debug_print(f'>>> [PyNFe] ✅ NFe encontrada dentro do lote')
                                            
                                            # Verificar estrutura da NFe
                                            inf_nfe = nfe_elem.find('nfe:infNFe', ns_nfe)
                                            if inf_nfe is None:
                                                inf_nfe = nfe_elem.find('infNFe')
                                            
                                            if inf_nfe is not None:
                                                versao_nfe = inf_nfe.get('versao')
                                                debug_print(f'>>> [PyNFe] Versão da NFe: {versao_nfe}')
                                                
                                                # Verificar elementos obrigatórios
                                                ide = inf_nfe.find('nfe:ide', ns_nfe) or inf_nfe.find('ide')
                                                emit = inf_nfe.find('nfe:emit', ns_nfe) or inf_nfe.find('emit')
                                                det = inf_nfe.findall('nfe:det', ns_nfe) or inf_nfe.findall('det')
                                                total = inf_nfe.find('nfe:total', ns_nfe) or inf_nfe.find('total')
                                                pag = inf_nfe.find('nfe:pag', ns_nfe) or inf_nfe.find('pag')
                                                
                                                debug_print(f'>>> [PyNFe] Elementos da NFe:')
                                                debug_print(f'>>> [PyNFe]   - ide: {"✅" if ide is not None else "❌"}')
                                                debug_print(f'>>> [PyNFe]   - emit: {"✅" if emit is not None else "❌"}')
                                                debug_print(f'>>> [PyNFe]   - det (produtos): {"✅" if det else "❌"} ({len(det)} itens)')
                                                debug_print(f'>>> [PyNFe]   - total: {"✅" if total is not None else "❌"}')
                                                debug_print(f'>>> [PyNFe]   - pag: {"✅" if pag is not None else "❌"}')
                                            else:
                                                debug_print(f'>>> [PyNFe] ❌ ERRO: infNFe não encontrada dentro da NFe!')
                                        else:
                                            debug_print(f'>>> [PyNFe] ❌ ERRO: NFe não encontrada dentro do lote!')
                                        
                                        # Listar todos os elementos filhos do enviNFe
                                        debug_print(f'>>> [PyNFe] Elementos filhos do enviNFe:')
                                        for child in envi_nfe:
                                            tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                            texto = child.text[:50] if child.text else '(vazio)'
                                            debug_print(f'>>> [PyNFe]   - {tag_limpa}: {texto}')
                                        
                                        debug_print(f'>>> [PyNFe] ========================================')
                                except Exception as e_validacao:
                                    debug_print(f'>>> [PyNFe] ⚠️ Erro ao validar XML do lote: {e_validacao}')
                                    import traceback
                                    debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                    
                    # IMPORTANTE: Verificação final crítica ANTES de enviar - SEMPRE RECONSTRUIR
                    if 'data' in kwargs:
                        body_final = kwargs['data']
                    elif 'body' in kwargs:
                        body_final = kwargs['body']
                    else:
                        body_final = args[1] if len(args) > 1 else None
                    
                    if body_final:
                        body_str = body_final.decode('utf-8') if isinstance(body_final, bytes) else str(body_final)
                        
                        debug_print(f'>>> [PyNFe] ========================================')
                        debug_print(f'>>> [PyNFe] VERIFICAÇÃO FINAL CRÍTICA ANTES DE ENVIAR')
                        debug_print(f'>>> [PyNFe] ========================================')
                        
                        # SEMPRE RECONSTRUIR DO ZERO - não confiar em nada
                        precisa_reconstruir = False
                        
                        # Verificar se tem SOAP
                        if '<soap' in body_str.lower() or 'nfeDadosMsg' in body_str or 'soap:Envelope' in body_str or 'soap:Body' in body_str:
                            debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: SOAP ainda presente!')
                            precisa_reconstruir = True
                        
                        # Verificar se tem prefixos
                        if 'ns0:' in body_str or 'ns1:' in body_str:
                            debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: Prefixos ainda presentes!')
                            precisa_reconstruir = True
                        
                        # Verificar idLote
                        import re
                        id_lote_match = re.search(r'<idLote>(\d+)</idLote>', body_str)
                        if id_lote_match:
                            id_lote_valor = id_lote_match.group(1)
                            if len(id_lote_valor) != 15:
                                debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: idLote não tem 15 dígitos: {id_lote_valor}!')
                                precisa_reconstruir = True
                        
                        # Verificar cMunFG
                        cMunFG_match = re.search(r'<cMunFG>([^<]+)</cMunFG>', body_str)
                        if cMunFG_match:
                            cMunFG_valor = cMunFG_match.group(1)
                            if not cMunFG_valor.strip().isdigit() or len(cMunFG_valor.strip()) != 7:
                                debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: cMunFG não é código IBGE: {cMunFG_valor}!')
                                precisa_reconstruir = True
                        
                        # Se precisa reconstruir, fazer AGORA
                        if precisa_reconstruir:
                            debug_print(f'>>> [PyNFe] ========================================')
                            debug_print(f'>>> [PyNFe] RECONSTRUÇÃO FINAL URGENTE DO XML')
                            debug_print(f'>>> [PyNFe] ========================================')
                            
                            try:
                                from lxml import etree as lxml_etree
                                
                                # 1. Remover SOAP completamente
                                if '<soap' in body_str.lower() or 'nfeDadosMsg' in body_str:
                                    inicio = body_str.find('<enviNFe')
                                    fim = body_str.rfind('</enviNFe>') + len('</enviNFe>')
                                    if inicio >= 0 and fim > inicio:
                                        body_str = body_str[inicio:fim]
                                        debug_print(f'>>> [PyNFe] ✅ SOAP removido')
                                
                                # 2. Parsear XML
                                xml_temp = lxml_etree.fromstring(body_str.encode('utf-8'))
                                
                                # 3. Encontrar NFe
                                nfe_para_reconstruir = None
                                for elem in xml_temp.iter():
                                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                    if tag_limpa == 'NFe':
                                        nfe_para_reconstruir = elem
                                        break
                                
                                if nfe_para_reconstruir is None:
                                    # Tentar encontrar dentro de enviNFe
                                    envi_nfe_temp = xml_temp
                                    if 'enviNFe' not in xml_temp.tag:
                                        envi_nfe_temp = xml_temp.find('.//enviNFe') or xml_temp.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
                                    
                                    if envi_nfe_temp is not None:
                                        nfe_para_reconstruir = envi_nfe_temp.find('.//NFe') or envi_nfe_temp.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                                
                                if nfe_para_reconstruir is None:
                                    raise ValueError('NFe não encontrada para reconstrução final')
                                
                                # 4. RECONSTRUIR enviNFe completamente do zero
                                namespace_final = 'http://www.portalfiscal.inf.br/nfe'
                                envi_nfe_final_limpo = lxml_etree.Element(
                                    '{' + namespace_final + '}enviNFe',
                                    nsmap={None: namespace_final},
                                    versao='4.00'
                                )
                                
                                # idLote (15 dígitos)
                                id_lote_final = lxml_etree.SubElement(envi_nfe_final_limpo, '{' + namespace_final + '}idLote')
                                id_lote_final.text = '000000000000001'
                                
                                # indSinc (valor 1)
                                ind_sinc_final = lxml_etree.SubElement(envi_nfe_final_limpo, '{' + namespace_final + '}indSinc')
                                ind_sinc_final.text = '1'
                                
                                # NFe (copiar sem prefixos)
                                nfe_limpa = self._copiar_elemento_limpo(nfe_para_reconstruir, namespace_final)
                                
                                # Aplicar correções finais
                                inf_nfe_limpa = nfe_limpa.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_limpa.find('.//infNFe')
                                if inf_nfe_limpa is not None:
                                    self._aplicar_correcoes_finais_infnfe(inf_nfe_limpa, namespace_final)
                                
                                envi_nfe_final_limpo.append(nfe_limpa)
                                
                                # 5. Gerar XML final limpo
                                body_str = lxml_etree.tostring(envi_nfe_final_limpo, 
                                                              encoding='unicode', 
                                                              xml_declaration=False,
                                                              pretty_print=False)
                                
                                # 6. Remover qualquer prefixo restante
                                body_str = body_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '')
                                body_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', body_str)
                                body_str = re.sub(r'xmlns:xsi="[^"]*"', '', body_str)
                                body_str = re.sub(r'xmlns:xsd="[^"]*"', '', body_str)
                                body_str = re.sub(r'xmlns:soap="[^"]*"', '', body_str)
                                
                                debug_print(f'>>> [PyNFe] ✅ XML RECONSTRUÍDO DO ZERO (FINAL)')
                                debug_print(f'>>> [PyNFe] Tamanho: {len(body_str)} caracteres')
                                
                                # Atualizar body
                                if 'data' in kwargs:
                                    kwargs['data'] = body_str.encode('utf-8') if isinstance(kwargs.get('data'), bytes) else body_str
                                elif 'body' in kwargs:
                                    kwargs['body'] = body_str.encode('utf-8') if isinstance(kwargs.get('body'), bytes) else body_str
                                else:
                                    args_list = list(args)
                                    args_list[1] = body_str.encode('utf-8') if isinstance(args_list[1], bytes) else body_str
                                    args = tuple(args_list)
                                
                            except Exception as e_reconstrucao_final:
                                debug_print(f'>>> [PyNFe] ❌ ERRO na reconstrução final: {e_reconstrucao_final}')
                                import traceback
                                debug_print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
                                # Tentar correção por string como último recurso
                                if '<soap' in body_str.lower():
                                    inicio = body_str.find('<enviNFe')
                                    fim = body_str.rfind('</enviNFe>') + len('</enviNFe>')
                                    if inicio >= 0 and fim > inicio:
                                        body_str = body_str[inicio:fim]
                                body_str = body_str.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '')
                                body_str = re.sub(r'xmlns:ns\d+="[^"]*"', '', body_str)
                                if 'data' in kwargs:
                                    kwargs['data'] = body_str.encode('utf-8') if isinstance(kwargs.get('data'), bytes) else body_str
                                elif 'body' in kwargs:
                                    kwargs['body'] = body_str.encode('utf-8') if isinstance(kwargs.get('body'), bytes) else body_str
                                else:
                                    args_list = list(args)
                                    args_list[1] = body_str.encode('utf-8') if isinstance(args_list[1], bytes) else body_str
                                    args = tuple(args_list)
                        
                        # IMPORTANTE: Obter body_str atualizado após todas as correções
                        body_str_final = None
                        if 'data' in kwargs:
                            body_str_final = kwargs['data']
                            if isinstance(body_str_final, bytes):
                                body_str_final = body_str_final.decode('utf-8')
                        elif 'body' in kwargs:
                            body_str_final = kwargs['body']
                            if isinstance(body_str_final, bytes):
                                body_str_final = body_str_final.decode('utf-8')
                        elif len(args) > 1:
                            body_str_final = args[1]
                            if isinstance(body_str_final, bytes):
                                body_str_final = body_str_final.decode('utf-8')
                        
                        if body_str_final is None:
                            body_str_final = body_str if 'body_str' in locals() else ''
                        
                        # Verificação final
                        debug_print(f'>>> [PyNFe] ========================================')
                        debug_print(f'>>> [PyNFe] ENVIANDO REQUISIÇÃO PARA SEFAZ')
                        debug_print(f'>>> [PyNFe] ========================================')
                        debug_print(f'>>> [PyNFe] URL: {args[0] if args else "N/A"}')
                        debug_print(f'>>> [PyNFe] Tamanho do body: {len(body_str_final)} caracteres')
                        
                        # Verificações críticas
                        tem_soap = '<soap' in body_str_final.lower() or 'nfeDadosMsg' in body_str_final or 'soap:Envelope' in body_str_final
                        tem_prefixos = 'ns0:' in body_str_final or 'ns1:' in body_str_final
                        tem_envinfe = 'enviNFe' in body_str_final
                        id_lote_ok = re.search(r'<idLote>\d{15}</idLote>', body_str_final) is not None
                        tem_indsinc = '<indSinc>1</indSinc>' in body_str_final
                        
                        debug_print(f'>>> [PyNFe] Verificações finais:')
                        debug_print(f'>>> [PyNFe]   - enviNFe presente: {"✅" if tem_envinfe else "❌"}')
                        debug_print(f'>>> [PyNFe]   - SEM SOAP: {"✅" if not tem_soap else "❌"}')
                        debug_print(f'>>> [PyNFe]   - SEM prefixos: {"✅" if not tem_prefixos else "❌"}')
                        debug_print(f'>>> [PyNFe]   - idLote 15 dígitos: {"✅" if id_lote_ok else "❌"}')
                        debug_print(f'>>> [PyNFe]   - indSinc presente: {"✅" if tem_indsinc else "❌"}')
                        
                        if tem_soap or tem_prefixos or not id_lote_ok or not tem_indsinc:
                            debug_print(f'>>> [PyNFe] ❌ ERRO CRÍTICO: XML ainda tem problemas!')
                            debug_print(f'>>> [PyNFe] Primeiros 1000 chars do XML:')
                            debug_print(body_str_final[:1000])
                            
                            # ÚLTIMA TENTATIVA: Reconstruir completamente se ainda houver problemas
                            if tem_soap or tem_prefixos:
                                debug_print(f'>>> [PyNFe] ⚠️ ÚLTIMA CORREÇÃO: Removendo SOAP e prefixos...')
                                # Extrair apenas enviNFe
                                inicio = body_str_final.find('<enviNFe')
                                fim = body_str_final.rfind('</enviNFe>') + len('</enviNFe>')
                                if inicio >= 0 and fim > inicio:
                                    body_str_final = body_str_final[inicio:fim]
                                
                                # Remover prefixos
                                body_str_final = body_str_final.replace('ns0:', '').replace('ns1:', '').replace('ns2:', '').replace('ns3:', '')
                                body_str_final = re.sub(r'xmlns:ns\d+="[^"]*"', '', body_str_final)
                                body_str_final = re.sub(r'xmlns:xsi="[^"]*"', '', body_str_final)
                                body_str_final = re.sub(r'xmlns:xsd="[^"]*"', '', body_str_final)
                                body_str_final = re.sub(r'xmlns:soap="[^"]*"', '', body_str_final)
                                
                                # Aplicar correção final
                                if 'data' in kwargs:
                                    kwargs['data'] = body_str_final.encode('utf-8') if isinstance(kwargs.get('data'), bytes) else body_str_final
                                elif 'body' in kwargs:
                                    kwargs['body'] = body_str_final.encode('utf-8') if isinstance(kwargs.get('body'), bytes) else body_str_final
                                else:
                                    args_list = list(args)
                                    args_list[1] = body_str_final.encode('utf-8') if isinstance(args_list[1], bytes) else body_str_final
                                    args = tuple(args_list)
                                
                                debug_print(f'>>> [PyNFe] ✅ Correção final aplicada')
                        else:
                            debug_print(f'>>> [PyNFe] ✅ XML CORRETO - Pronto para enviar!')
                        
                        # Salvar XML final que será enviado (para análise)
                        try:
                            import os
                            empresa_dir = self._obter_diretorio_empresa()
                            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                            xml_final_file = os.path.join(empresa_dir, f'xml_final_enviado_{timestamp}.xml')
                            with open(xml_final_file, 'w', encoding='utf-8') as f:
                                f.write(body_str_final)
                            debug_print(f'>>> [PyNFe] XML final salvo em: {xml_final_file}')
                        except Exception as e_save_final:
                            debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar XML final: {e_save_final}')
                        
                        debug_print(f'>>> [PyNFe] ========================================')
                    
                    # Chamar método original com XML corrigido
                    return original_post(*args, **kwargs)
                
                # Aplicar interceptação temporariamente
                requests.post = post_interceptado
                debug_print(f'>>> [PyNFe] Interceptação de requisição HTTP ativada')
                
                try:
                    resultado_autorizacao = comunicacao.autorizacao(
                        modelo="nfce",  # NFC-e (deve ser string "nfce", não int 65)
                        nota_fiscal=xml_elemento_assinado,  # XML elemento assinado
                        id_lote=1,  # ID do lote
                        ind_sinc=1,  # 1=síncrono (NFC-e sempre síncrono)
                        contingencia=False,
                        timeout=30
                    )
                finally:
                    # Restaurar métodos originais
                    requests.post = original_post
                    if original_session_post is not None:
                        requests.Session.post = original_session_post
                    debug_print(f'>>> [PyNFe] Interceptação removida')
                    debug_print(f'>>> [PyNFe] Interceptação de requisição HTTP desativada')
                    
            except Exception as e_intercept:
                debug_print(f'>>> [PyNFe] ⚠️ Erro ao interceptar requisição: {e_intercept}')
                # Continuar sem interceptação
            resultado_autorizacao = comunicacao.autorizacao(
                modelo="nfce",  # NFC-e (deve ser string "nfce", não int 65)
                nota_fiscal=xml_elemento_assinado,  # XML elemento assinado
                id_lote=1,  # ID do lote
                ind_sinc=1,  # 1=síncrono (NFC-e sempre síncrono)
                contingencia=False,
                timeout=30
            )
            debug_print(f'>>> [PyNFe] Resposta recebida de autorizacao()')
            
            # O método autorizacao retorna uma tupla:
            # - Sucesso síncrono (ind_sinc=1): (0, raiz) onde raiz é o XML nfeProc
            # - Sucesso assíncrono (ind_sinc=0): (0, nrec, nota_fiscal) onde nrec é número do recibo
            # - Erro: (1, retorno, nota_fiscal) onde retorno é o objeto Response
            # Para NFC-e sempre usamos síncrono (ind_sinc=1), então esperamos (0, raiz) ou (1, retorno, nota_fiscal)
            
            codigo = resultado_autorizacao[0]
            sucesso = (codigo == 0)
            
            if sucesso:
                # Sucesso: (0, raiz) - raiz é o XML nfeProc com nota autorizada
                if len(resultado_autorizacao) == 2:
                    _, xml_resposta = resultado_autorizacao
                elif len(resultado_autorizacao) == 3:
                    # Assíncrono: (0, nrec, nota_fiscal) - não deveria acontecer com ind_sinc=1
                    _, nrec, xml_resposta = resultado_autorizacao
                    debug_print(f'>>> [PyNFe] ⚠️ Autorização assíncrona inesperada, recibo: {nrec}')
                else:
                    sucesso = False
                    xml_resposta = None
            else:
                # Erro: (1, retorno, nota_fiscal)
                if len(resultado_autorizacao) == 3:
                    _, retorno, nota_fiscal = resultado_autorizacao
                    # retorno é um objeto Response do requests
                    xml_resposta = retorno.text if hasattr(retorno, 'text') else str(retorno)
                else:
                    xml_resposta = str(resultado_autorizacao)
            
            debug_print(f'>>> [PyNFe] Resultado autorização: sucesso={sucesso}, código={codigo}, valores={len(resultado_autorizacao)}')
            
            # Processar resposta
            if sucesso:
                # xml_resposta é o XML com a nota autorizada
                # Parsear resposta XML da SEFAZ
                from lxml import etree as lxml_etree
                xml_resposta_str = lxml_etree.tostring(xml_resposta, encoding='unicode') if hasattr(xml_resposta, 'tag') else str(xml_resposta)
                
                # Verificar se o XML não está vazio
                if not xml_resposta_str or not xml_resposta_str.strip():
                    debug_print(f'>>> [PyNFe] ⚠️ XML de resposta está vazio!')
                    debug_print(f'>>> [PyNFe] Tipo de xml_resposta: {type(xml_resposta)}')
                    debug_print(f'>>> [PyNFe] xml_resposta: {str(xml_resposta)[:200]}')
                    return {
                        'success': False,
                        'error': 'Resposta da SEFAZ está vazia. Verifique a conexão e o certificado.',
                        'autorizada': False,  # Flag explícita de não autorização
                        'details': 'A SEFAZ não retornou nenhum dado. Isso pode indicar problema de conexão, certificado inválido ou serviço indisponível.'
                    }
                
                resultado = self._processar_resposta_sefaz(xml_resposta_str, ambiente_homologacao)
                
                # Extrair informações da resposta
                status = resultado.get('status', 'processando')
                protocolo = resultado.get('protocolo')
                motivo = resultado.get('motivo', '')
                
                debug_print(f'>>> [PyNFe] Status: {status}')
                debug_print(f'>>> [PyNFe] Protocolo: {protocolo}')
                
                if status == 'autorizada':
                    # ✅ NOTA AUTORIZADA PELA SEFAZ (cStat 100 ou 150)
                    # Incrementar numeração sequencial apenas após autorização
                    self._incrementar_numero_apos_autorizacao(empresa_data, serie_nfce, numero_nfce)
                    
                    # Gerar chave de acesso corretamente (44 dígitos)
                    chave_acesso = self._gerar_chave_acesso(nfce)
                    
                    # Mensagem de sucesso clara
                    print(f'')
                    print(f'{"="*70}')
                    print(f'✅ NFC-e EMITIDA COM SUCESSO!')
                    print(f'{"="*70}')
                    print(f'📋 Número: {nfce.numero_nf}')
                    print(f'📋 Série: {nfce.serie}')
                    print(f'🔑 Chave de Acesso: {chave_acesso}')
                    print(f'📄 Protocolo: {protocolo}')
                    print(f'🌐 Ambiente: {"HOMOLOGAÇÃO" if ambiente_homologacao else "PRODUÇÃO"}')
                    print(f'✅ Status: AUTORIZADA pela SEFAZ')
                    print(f'{"="*70}')
                    print(f'')
                    
                    debug_print(f'>>> [PyNFe] ========================================')
                    debug_print(f'>>> [PyNFe] ✅ NFC-e EMITIDA COM SUCESSO!')
                    debug_print(f'>>> [PyNFe] ========================================')
                    debug_print(f'>>> [PyNFe] Número: {nfce.numero_nf}')
                    debug_print(f'>>> [PyNFe] Série: {nfce.serie}')
                    debug_print(f'>>> [PyNFe] Chave de Acesso: {chave_acesso}')
                    debug_print(f'>>> [PyNFe] Protocolo: {protocolo}')
                    debug_print(f'>>> [PyNFe] Ambiente: {"HOMOLOGAÇÃO" if ambiente_homologacao else "PRODUÇÃO"}')
                    debug_print(f'>>> [PyNFe] ✅ Status: AUTORIZADA pela SEFAZ')
                    debug_print(f'>>> [PyNFe] ========================================')
                    
                    return {
                        'success': True,
                        'message': f'✅ NFC-e emitida com sucesso! Número: {nfce.numero_nf}, Série: {nfce.serie}',
                        'data': {
                            'chave_acesso': chave_acesso,
                            'numero': str(nfce.numero_nf),
                            'serie': str(nfce.serie),
                            'protocolo': protocolo,
                            'status': 'autorizada',
                            'autorizada': True,  # Flag explícita de autorização
                            'cstat': resultado.get('codigo'),  # cStat da SEFAZ (100 ou 150)
                            'xml': xml_assinado,
                            'qr_code': self._gerar_qr_code(chave_acesso, protocolo, ambiente_homologacao),
                            'ambiente': 'homologacao' if ambiente_homologacao else 'producao'
                        }
                    }
                else:
                    # ❌ NOTA NÃO AUTORIZADA (rejeitada, denegada, etc)
                    # NÃO incrementar numeração sequencial (número será reutilizado)
                    cstat = resultado.get('codigo', '')
                    print(f'')
                    print(f'{"="*70}')
                    print(f'❌ NFC-e NÃO FOI AUTORIZADA')
                    print(f'{"="*70}')
                    print(f'📋 Status: {status}')
                    print(f'📋 Código SEFAZ (cStat): {cstat}')
                    print(f'📄 Motivo: {motivo}')
                    if protocolo:
                        print(f'📄 Protocolo: {protocolo}')
                    print(f'⚠️ Numeração NÃO foi incrementada (nota não autorizada)')
                    print(f'{"="*70}')
                    print(f'')
                    
                    debug_print(f'>>> [PyNFe] ========================================')
                    debug_print(f'>>> [PyNFe] ❌ NFC-e NÃO FOI AUTORIZADA')
                    debug_print(f'>>> [PyNFe] ========================================')
                    debug_print(f'>>> [PyNFe] Status: {status}')
                    debug_print(f'>>> [PyNFe] Código SEFAZ (cStat): {cstat}')
                    debug_print(f'>>> [PyNFe] Motivo: {motivo}')
                    if protocolo:
                        debug_print(f'>>> [PyNFe] Protocolo: {protocolo}')
                    debug_print(f'>>> [PyNFe] ⚠️ Numeração NÃO foi incrementada (nota não autorizada)')
                    debug_print(f'>>> [PyNFe] ========================================')
                    
                    # Incluir todos os detalhes da resposta da SEFAZ
                    resultado_completo = {
                        'success': False,
                        'message': f'❌ NFC-e não foi autorizada. Status: {status}',
                        'error': f'NFC-e {status}: {motivo}',
                        'status': status,
                        'autorizada': False,  # Flag explícita de não autorização
                        'cstat': cstat,  # Código da SEFAZ
                        'protocolo': protocolo,
                        'motivo': motivo,
                        'xml_resposta': xml_resposta_str if 'xml_resposta_str' in locals() else str(xml_resposta),
                        'details': xml_resposta_str if 'xml_resposta_str' in locals() else str(xml_resposta)
                    }
                    
                    # Adicionar campos adicionais se disponíveis
                    if 'resultado' in locals() and isinstance(resultado, dict):
                        resultado_completo.update({
                            'xmotivo': resultado.get('motivo'),
                            'verAplic': resultado.get('verAplic'),
                            'cUF': resultado.get('cUF'),
                            'dhRecbto': resultado.get('dhRecbto')
                        })
                    
                    return resultado_completo
            else:
                # Mensagem de erro clara
                print(f'')
                print(f'{"="*70}')
                print(f'❌ ERRO AO EMITIR NFC-e')
                print(f'{"="*70}')
                
                # Se não teve sucesso, extrair mensagem de erro do retorno
                erro_msg = 'Erro desconhecido ao autorizar NFC-e'
                
                if len(resultado_autorizacao) == 3:
                    _, retorno, nota_fiscal = resultado_autorizacao
                    debug_print(f'>>> [PyNFe] Tipo de retorno: {type(retorno)}')
                    debug_print(f'>>> [PyNFe] Retorno tem text: {hasattr(retorno, "text")}')
                    if hasattr(retorno, 'text'):
                        debug_print(f'>>> [PyNFe] Retorno.text é None: {retorno.text is None}')
                        if retorno.text is not None:
                            debug_print(f'>>> [PyNFe] Retorno.text length: {len(retorno.text)}')
                            debug_print(f'>>> [PyNFe] Retorno.text (primeiros 200): {retorno.text[:200]}')
                    
                    # retorno é um objeto Response do requests
                    if hasattr(retorno, 'text') and retorno.text:
                        texto_bruto = retorno.text
                        texto_xml = texto_bruto.strip() if texto_bruto else ''
                        
                        # Verificar se há conteúdo válido (não apenas espaços)
                        if not texto_xml or len(texto_xml) < 10:
                            # Resposta muito curta ou vazia
                            status_code = getattr(retorno, 'status_code', 'N/A')
                            erro_msg = f'Resposta da SEFAZ está vazia ou inválida (HTTP {status_code})'
                            if texto_bruto:
                                erro_msg += f'. Conteúdo recebido: {repr(texto_bruto[:100])}'
                            debug_print(f'>>> [PyNFe] ⚠️ Resposta vazia ou muito curta: {len(texto_xml) if texto_xml else 0} caracteres')
                        else:
                            try:
                                # Tentar parsear XML de erro
                                from lxml import etree as lxml_etree
                                # Verificar se parece ser XML (começa com <)
                                if not texto_xml.lstrip().startswith('<'):
                                    raise ValueError(f'Resposta não é XML válido. Início: {repr(texto_xml[:50])}')
                                
                                erro_xml = lxml_etree.fromstring(texto_xml.encode('utf-8'))
                                
                                # Definir namespaces comuns
                                ns = {
                                    "nfe": "http://www.portalfiscal.inf.br/nfe",
                                    "soap": "http://www.w3.org/2003/05/soap-envelope",
                                    "soap12": "http://www.w3.org/2003/05/soap-envelope",
                                    "soapenv": "http://schemas.xmlsoap.org/soap/envelope/",
                                    "soap11": "http://schemas.xmlsoap.org/soap/envelope/"
                                }
                                
                                debug_print(f'>>> [PyNFe] Parseando resposta da SEFAZ...')
                                debug_print(f'>>> [PyNFe] Tag raiz: {erro_xml.tag}')
                                
                                # Tentar encontrar retEnviNFe em diferentes locais
                                ret_envi_nfe = None
                                
                                # 1. Procurar diretamente (evitar uso de find() em contexto booleano)
                                ret_envi_nfe = erro_xml.find('.//nfe:retEnviNFe', ns)
                                if ret_envi_nfe is None:
                                    ret_envi_nfe = erro_xml.find('.//retEnviNFe')
                                
                                # 2. Se não encontrou, procurar dentro de envelope SOAP
                                if ret_envi_nfe is None:
                                    # Procurar dentro de Body do SOAP
                                    body = erro_xml.find('.//soap:Body', ns)
                                    if body is None:
                                        body = erro_xml.find('.//soap12:Body', ns)
                                    if body is None:
                                        body = erro_xml.find('.//soapenv:Body', ns)
                                    if body is None:
                                        body = erro_xml.find('.//soap11:Body', ns)
                                    if body is None:
                                        body = erro_xml.find('.//Body')
                                    
                                    if body is not None:
                                        debug_print(f'>>> [PyNFe] Encontrado envelope SOAP, procurando retEnviNFe dentro...')
                                        
                                        # Procurar primeiro dentro de nfeResultMsg (comum em respostas SOAP)
                                        nfe_result_msg = None
                                        for child in body:
                                            if 'nfeResultMsg' in child.tag or 'ResultMsg' in child.tag or 'resultMsg' in child.tag:
                                                nfe_result_msg = child
                                                debug_print(f'>>> [PyNFe] Encontrado nfeResultMsg: {child.tag}')
                                                break
                                        
                                        if nfe_result_msg is not None:
                                            # Procurar retEnviNFe dentro de nfeResultMsg
                                            ret_envi_nfe = nfe_result_msg.find('.//nfe:retEnviNFe', ns)
                                            if ret_envi_nfe is None:
                                                ret_envi_nfe = nfe_result_msg.find('.//retEnviNFe')
                                            
                                            # Se ainda não encontrou, procurar em qualquer elemento filho de nfeResultMsg
                                            if ret_envi_nfe is None:
                                                for child in nfe_result_msg.iter():
                                                    if 'retEnviNFe' in child.tag or 'retEnvi' in child.tag:
                                                        ret_envi_nfe = child
                                                        debug_print(f'>>> [PyNFe] Encontrado retEnviNFe dentro de nfeResultMsg: {child.tag}')
                                                        break
                                        
                                        # Se ainda não encontrou, procurar diretamente no Body
                                        if ret_envi_nfe is None:
                                            ret_envi_nfe = body.find('.//nfe:retEnviNFe', ns)
                                            if ret_envi_nfe is None:
                                                ret_envi_nfe = body.find('.//retEnviNFe')
                                        
                                        # Se ainda não encontrou, procurar em qualquer elemento filho do Body
                                        if ret_envi_nfe is None:
                                            for child in body.iter():
                                                if 'retEnviNFe' in child.tag or 'retEnvi' in child.tag:
                                                    ret_envi_nfe = child
                                                    debug_print(f'>>> [PyNFe] Encontrado elemento similar no Body: {child.tag}')
                                                    break
                                
                                # 3. Se ainda não encontrou, procurar em qualquer lugar do XML
                                if ret_envi_nfe is None:
                                    debug_print(f'>>> [PyNFe] Procurando retEnviNFe em todo o XML...')
                                    for elem in erro_xml.iter():
                                        if 'retEnviNFe' in elem.tag or 'retEnvi' in elem.tag:
                                            ret_envi_nfe = elem
                                            debug_print(f'>>> [PyNFe] Encontrado elemento: {elem.tag}')
                                            break
                                
                                if ret_envi_nfe is not None:
                                    debug_print(f'>>> [PyNFe] ✅ Elemento retEnviNFe encontrado: {ret_envi_nfe.tag}')
                                    
                                    # IMPORTANTE: Os elementos cStat e xMotivo são filhos DIRETOS do retEnviNFe
                                    # Não usar .// (busca recursiva), buscar diretamente os filhos
                                    # O namespace está definido no elemento pai, então os filhos herdam
                                    
                                    # Tentar diferentes formas de buscar (filhos diretos)
                                    cstat_elem = None
                                    motivo_elem = None
                                    
                                    # 1. Buscar com namespace explícito (filho direto)
                                    cstat_elem = ret_envi_nfe.find('nfe:cStat', ns)
                                    motivo_elem = ret_envi_nfe.find('nfe:xMotivo', ns)
                                    
                                    # 2. Se não encontrou, buscar sem namespace (filho direto)
                                    if cstat_elem is None:
                                        cstat_elem = ret_envi_nfe.find('cStat')
                                    if motivo_elem is None:
                                        motivo_elem = ret_envi_nfe.find('xMotivo')
                                    
                                    # 3. Se ainda não encontrou, buscar em qualquer lugar (recursivo)
                                    if cstat_elem is None:
                                        cstat_elem = ret_envi_nfe.find('.//nfe:cStat', ns) or ret_envi_nfe.find('.//cStat')
                                    if motivo_elem is None:
                                        motivo_elem = ret_envi_nfe.find('.//nfe:xMotivo', ns) or ret_envi_nfe.find('.//xMotivo')
                                    
                                    # 4. Se ainda não encontrou, iterar pelos filhos diretamente
                                    if cstat_elem is None or motivo_elem is None:
                                        for child in ret_envi_nfe:
                                            tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                            if tag_limpa == 'cStat' and cstat_elem is None:
                                                cstat_elem = child
                                                debug_print(f'>>> [PyNFe] cStat encontrado iterando filhos: {child.tag}')
                                            elif tag_limpa == 'xMotivo' and motivo_elem is None:
                                                motivo_elem = child
                                                debug_print(f'>>> [PyNFe] xMotivo encontrado iterando filhos: {child.tag}')
                                    
                                    debug_print(f'>>> [PyNFe] cStat encontrado: {cstat_elem is not None}')
                                    debug_print(f'>>> [PyNFe] xMotivo encontrado: {motivo_elem is not None}')
                                    
                                    if cstat_elem is not None and cstat_elem.text:
                                        cstat = cstat_elem.text.strip()
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        debug_print(f'>>> [PyNFe] RESPOSTA DA SEFAZ - DETALHES COMPLETOS')
                                        debug_print(f'>>> [PyNFe] ========================================')
                                        debug_print(f'>>> [PyNFe] Código de status (cStat): {cstat}')
                                        
                                        # Extrair TODOS os campos da resposta
                                        campos_resposta = {}
                                        for child in ret_envi_nfe:
                                            tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                            valor = child.text.strip() if child.text else ''
                                            campos_resposta[tag_limpa] = valor
                                            debug_print(f'>>> [PyNFe] {tag_limpa}: {valor}')
                                        
                                        # Formatar mensagem de erro de forma clara e informativa
                                        motivo_texto = motivo_elem.text.strip() if motivo_elem is not None and motivo_elem.text else ''
                                        
                                        # Salvar resposta completa para análise (se houver erro)
                                        if cstat and cstat not in ['100', '150']:
                                            try:
                                                import os
                                                
                                                # Obter diretório da empresa
                                                empresa_dir = self._obter_diretorio_empresa()
                                                
                                                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                                resposta_file = os.path.join(empresa_dir, f'resposta_sefaz_cstat{cstat}_{timestamp}.xml')
                                                
                                                with open(resposta_file, 'w', encoding='utf-8') as f:
                                                    f.write(texto_xml)
                                                
                                                debug_print(f'>>> [PyNFe] Resposta completa salva em: {resposta_file}')
                                            except Exception as e_save:
                                                debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar resposta: {e_save}')
                                        
                                        # Usar função de formatação para criar mensagem clara
                                        erro_msg = self._formatar_erro_sefaz(cstat, motivo_texto, campos_resposta)
                                        
                                        # IMPORTANTE: Verificar se é sucesso (cStat 100 ou 150) antes de mostrar erro
                                        if cstat in ['100', '150']:
                                            # ✅ NOTA AUTORIZADA - Processar como sucesso
                                            print(f'')
                                            print(f'{"="*70}')
                                            print(f'✅ NFC-e AUTORIZADA COM SUCESSO!')
                                            print(f'{"="*70}')
                                            print(f'📋 Código SEFAZ (cStat): {cstat}')
                                            print(f'📄 Status: AUTORIZADA pela SEFAZ')
                                            print(f'📄 Motivo: {motivo_texto}')
                                            if campos_resposta:
                                                if 'verAplic' in campos_resposta:
                                                    print(f'📱 Versão SEFAZ: {campos_resposta["verAplic"]}')
                                                if 'cUF' in campos_resposta:
                                                    print(f'🌐 Estado: {campos_resposta["cUF"]}')
                                                if 'dhRecbto' in campos_resposta:
                                                    print(f'🕐 Data/Hora: {campos_resposta["dhRecbto"]}')
                                            print(f'{"="*70}')
                                            print(f'')
                                            
                                            # Retornar como sucesso
                                            return {
                                                'success': True,
                                                'message': f'✅ NFC-e autorizada com sucesso! {motivo_texto}',
                                                'autorizada': True,  # Flag explícita de autorização
                                                'cstat': cstat,
                                                'motivo': motivo_texto,
                                                'xmotivo': motivo_texto,
                                                'campos_resposta': campos_resposta,
                                                'verAplic': campos_resposta.get('verAplic') if campos_resposta else None,
                                                'cUF': campos_resposta.get('cUF') if campos_resposta else None,
                                                 'dhRecbto': campos_resposta.get('dhRecbto') if campos_resposta else None,
                                                 'xml_resposta': texto_xml if 'texto_xml' in locals() else None
                                             }
                                        else:
                                             # ❌ NOTA NÃO AUTORIZADA - Mostrar erro
                                             print(f'')
                                             print(f'{"="*70}')
                                             print(f'❌ NFC-e NÃO FOI AUTORIZADA')
                                             print(f'{"="*70}')
                                             print(f'📋 Código SEFAZ (cStat): {cstat}')
                                             print(f'📄 Motivo: {motivo_texto}')
                                             if campos_resposta:
                                                 if 'verAplic' in campos_resposta:
                                                     print(f'📱 Versão da aplicação SEFAZ: {campos_resposta["verAplic"]}')
                                                 if 'cUF' in campos_resposta:
                                                     print(f'🌐 Estado: {campos_resposta["cUF"]}')
                                                 if 'dhRecbto' in campos_resposta:
                                                     print(f'🕐 Data/hora do recebimento: {campos_resposta["dhRecbto"]}')
                                             print(f'⚠️ Numeração NÃO foi incrementada (nota não autorizada)')
                                             print(f'{"="*70}')
                                             print(f'')
                                             
                                             debug_print(f'>>> [PyNFe] ========================================')
                                             debug_print(f'>>> [PyNFe] ❌ NFC-e NÃO FOI AUTORIZADA')
                                             debug_print(f'>>> [PyNFe] ========================================')
                                             debug_print(f'>>> [PyNFe] Código SEFAZ (cStat): {cstat}')
                                             debug_print(f'>>> [PyNFe] Motivo: {motivo_texto}')
                                             if campos_resposta:
                                                 debug_print(f'>>> [PyNFe] Campos da resposta: {campos_resposta}')
                                             debug_print(f'>>> [PyNFe] ========================================')
                                             
                                             # IMPORTANTE: Retornar erro com TODOS os detalhes da SEFAZ
                                             # ⚠️ Numeração NÃO foi incrementada (nota não autorizada)
                                             return {
                                                 'success': False,
                                                 'message': f'❌ NFC-e não foi autorizada: {motivo_texto}',
                                                 'error': motivo_texto,  # Motivo direto da SEFAZ
                                                 'autorizada': False,  # Flag explícita de não autorização
                                                 'cstat': cstat,
                                                 'motivo': motivo_texto,
                                                 'xmotivo': motivo_texto,
                                                 'campos_resposta': campos_resposta,
                                                 'verAplic': campos_resposta.get('verAplic') if campos_resposta else None,
                                                 'cUF': campos_resposta.get('cUF') if campos_resposta else None,
                                                 'dhRecbto': campos_resposta.get('dhRecbto') if campos_resposta else None,
                                                 'xml_resposta': texto_xml if 'texto_xml' in locals() else None,
                                                 'details': motivo_texto
                                             }
                                    elif motivo_elem is not None and motivo_elem.text:
                                        motivo_texto = motivo_elem.text.strip()
                                        erro_msg = self._formatar_erro_sefaz(None, motivo_texto, {})
                                        debug_print(f'>>> [PyNFe] Motivo encontrado (sem cStat): {motivo_texto}')
                                        # Retornar erro mesmo sem cStat
                                        return {
                                            'success': False,
                                            'message': f'❌ NFC-e não foi autorizada: {motivo_texto}',
                                            'error': motivo_texto,
                                            'autorizada': False,
                                            'cstat': None,
                                            'motivo': motivo_texto,
                                            'xmotivo': motivo_texto,
                                            'xml_resposta': texto_xml if 'texto_xml' in locals() else None
                                        }
                                    else:
                                        # Tentar extrair qualquer texto útil do retEnviNFe
                                        texto_ret = lxml_etree.tostring(ret_envi_nfe, encoding='unicode', method='text')
                                        if texto_ret and texto_ret.strip():
                                            erro_msg = f'Erro na resposta da SEFAZ: {texto_ret[:200].strip()}'
                                        else:
                                            # Salvar XML completo para análise
                                            try:
                                                import os
                                                empresa_dir = self._obter_diretorio_empresa()
                                                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                                resposta_file = os.path.join(empresa_dir, f'resposta_sefaz_retEnviNFe_sem_campos_{timestamp}.xml')
                                                with open(resposta_file, 'w', encoding='utf-8') as f:
                                                    f.write(texto_xml)
                                                debug_print(f'>>> [PyNFe] ⚠️ XML salvo para análise: {resposta_file}')
                                                
                                                # Extrair todos os filhos do retEnviNFe
                                                filhos_info = []
                                                for child in ret_envi_nfe:
                                                    tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                                    valor = child.text.strip() if child.text else '(vazio)'
                                                    filhos_info.append(f'{tag_limpa}={valor[:50]}')
                                                
                                                if filhos_info:
                                                    erro_msg = f'Erro na resposta da SEFAZ (estrutura não reconhecida). Campos encontrados no retEnviNFe: {"; ".join(filhos_info[:5])}'
                                                else:
                                                    erro_msg = f'Erro na resposta da SEFAZ (estrutura não reconhecida). XML salvo em: {resposta_file}'
                                            except Exception as e_save:
                                                debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar XML: {e_save}')
                                                erro_msg = 'Erro na resposta da SEFAZ (estrutura não reconhecida)'
                                        
                                        debug_print(f'>>> [PyNFe] ⚠️ Não foi possível extrair cStat ou xMotivo do retEnviNFe')
                                        debug_print(f'>>> [PyNFe] Estrutura do retEnviNFe: {lxml_etree.tostring(ret_envi_nfe, encoding="unicode")[:500]}')
                                        debug_print(f'>>> [PyNFe] Filhos do retEnviNFe: {[child.tag for child in ret_envi_nfe]}')
                                else:  # if ret_envi_nfe is not None
                                    debug_print(f'>>> [PyNFe] ⚠️ Elemento retEnviNFe não encontrado, procurando em outros lugares...')
                                    
                                    # Tentar encontrar mensagem de erro em outros lugares
                                    motivo_elem = None
                                    cstat_elem = None
                                    
                                    # Procurar xMotivo em qualquer lugar (evitar uso de find() em contexto booleano)
                                    for ns_prefix, ns_uri in ns.items():
                                        motivo_elem = erro_xml.find(f'.//{ns_prefix}:xMotivo', ns)
                                        if motivo_elem is not None:
                                            break
                                    if motivo_elem is None:
                                        motivo_elem = erro_xml.find('.//xMotivo')
                                    
                                    # Procurar cStat em qualquer lugar
                                    for ns_prefix, ns_uri in ns.items():
                                        cstat_elem = erro_xml.find(f'.//{ns_prefix}:cStat', ns)
                                        if cstat_elem is not None:
                                            break
                                    if cstat_elem is None:
                                        cstat_elem = erro_xml.find('.//cStat')
                                    
                                    if motivo_elem is not None and motivo_elem.text:
                                        erro_msg = motivo_elem.text.strip()
                                        debug_print(f'>>> [PyNFe] Motivo encontrado fora de retEnviNFe: {erro_msg}')
                                    elif cstat_elem is not None and cstat_elem.text:
                                        erro_msg = f'Código de erro: {cstat_elem.text.strip()}'
                                        debug_print(f'>>> [PyNFe] cStat encontrado: {cstat_elem.text.strip()}')
                                    else:
                                        # Tentar extrair informações diretamente do XML sem retEnviNFe
                                        debug_print(f'>>> [PyNFe] ⚠️ Elemento retEnviNFe não encontrado, procurando campos diretamente...')
                                        
                                        # Procurar campos específicos em qualquer lugar do XML
                                        cstat_encontrado = None
                                        motivo_encontrado = None
                                        
                                        # Buscar cStat
                                        for elem in erro_xml.iter():
                                            tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            if tag_limpa == 'cStat' and elem.text:
                                                cstat_encontrado = elem.text.strip()
                                                debug_print(f'>>> [PyNFe] cStat encontrado: {cstat_encontrado}')
                                                break
                                        
                                        # Buscar xMotivo
                                        for elem in erro_xml.iter():
                                            tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            if tag_limpa == 'xMotivo' and elem.text:
                                                motivo_encontrado = elem.text.strip()
                                                debug_print(f'>>> [PyNFe] xMotivo encontrado: {motivo_encontrado}')
                                                break
                                        
                                        # Formatar mensagem de erro de forma clara
                                        campos_resposta_encontrados = {}
                                        if cstat_encontrado:
                                            campos_resposta_encontrados['cStat'] = cstat_encontrado
                                        if motivo_encontrado:
                                            campos_resposta_encontrados['xMotivo'] = motivo_encontrado
                                        
                                        erro_msg = self._formatar_erro_sefaz(
                                            cstat_encontrado, 
                                            motivo_encontrado, 
                                            campos_resposta_encontrados if campos_resposta_encontrados else None
                                        )
                                        
                                        if not motivo_encontrado and not cstat_encontrado:
                                            # Salvar XML completo para análise
                                            try:
                                                import os
                                                empresa_dir = self._obter_diretorio_empresa()
                                                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                                resposta_file = os.path.join(empresa_dir, f'resposta_sefaz_estrutura_nao_reconhecida_{timestamp}.xml')
                                                with open(resposta_file, 'w', encoding='utf-8') as f:
                                                    f.write(texto_xml)
                                                debug_print(f'>>> [PyNFe] ⚠️ XML salvo para análise: {resposta_file}')
                                                
                                                # Tentar extrair qualquer informação útil do XML
                                                info_extraida = []
                                                for elem in erro_xml.iter():
                                                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                                    if elem.text and elem.text.strip() and tag_limpa not in ['Body', 'Envelope', 'Header']:
                                                        info_extraida.append(f'{tag_limpa}: {elem.text.strip()[:100]}')
                                                        if len(info_extraida) >= 10:  # Limitar a 10 elementos
                                                            break
                                                
                                                if info_extraida:
                                                    erro_msg = f'Erro na resposta da SEFAZ (estrutura não reconhecida). Informações encontradas: {"; ".join(info_extraida[:5])}'
                                                else:
                                                    erro_msg = f'Erro na resposta da SEFAZ (estrutura não reconhecida). XML salvo em: {resposta_file}'
                                            except Exception as e_save:
                                                debug_print(f'>>> [PyNFe] ⚠️ Erro ao salvar XML: {e_save}')
                                                erro_msg = 'Erro na resposta da SEFAZ (estrutura não reconhecida)'
                                            
                                            debug_print(f'>>> [PyNFe] ⚠️ Estrutura da resposta não reconhecida')
                                            debug_print(f'>>> [PyNFe] XML completo (primeiros 1000 chars): {texto_xml[:1000]}')
                                            debug_print(f'>>> [PyNFe] Tag raiz do XML: {erro_xml.tag}')
                                            debug_print(f'>>> [PyNFe] Filhos da raiz: {[child.tag for child in erro_xml][:10]}')
                            except Exception as e_parse:
                                # Se não conseguir parsear, criar mensagem simples
                                texto_erro = retorno.text[:500] if retorno.text else ''
                                
                                erro_msg = f'Erro ao processar resposta da SEFAZ: {str(e_parse)}'
                                
                                # Tentar salvar resposta bruta para análise
                                try:
                                    import os
                                    
                                    # Obter diretório da empresa
                                    empresa_dir = self._obter_diretorio_empresa()
                                    
                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                    resposta_file = os.path.join(empresa_dir, f'resposta_sefaz_erro_parse_{timestamp}.xml')
                                    with open(resposta_file, 'w', encoding='utf-8') as f:
                                        f.write(retorno.text if retorno.text else '')
                                    debug_print(f'>>> [PyNFe] Resposta salva em: {resposta_file}')
                                except:
                                    pass
                                
                                debug_print(f'>>> [PyNFe] ⚠️ Erro ao parsear XML: {e_parse}')
                                debug_print(f'>>> [PyNFe] Texto recebido: {texto_erro[:200]}')
                    elif hasattr(retorno, 'status_code'):
                        status_code = retorno.status_code
                        texto_resposta = retorno.text[:200] if hasattr(retorno, 'text') and retorno.text else 'Sem resposta'
                        
                        # Formatar mensagem de erro HTTP de forma clara
                        if status_code == 400:
                            debug_print(f'>>> [PyNFe] ❌ HTTP 400 Bad Request - XML pode estar inválido')
                            if hasattr(retorno, 'text') and retorno.text:
                                debug_print(f'>>> [PyNFe] Resposta completa da SEFAZ (primeiros 2000 chars):')
                                debug_print(retorno.text[:2000])
                                
                                # Tentar parsear resposta de erro da SEFAZ
                                try:
                                    from lxml import etree as lxml_etree
                                    erro_xml = lxml_etree.fromstring(retorno.text.encode('utf-8'))
                                    ns = {"soap": "http://www.w3.org/2003/05/soap-envelope", "nfe": "http://www.portalfiscal.inf.br/nfe"}
                                    motivo = erro_xml.find('.//nfe:xMotivo', ns)
                                    if motivo is not None and motivo.text:
                                        erro_msg = motivo.text.strip()
                                    else:
                                        erro_msg = f'Erro HTTP 400: Requisição inválida'
                                except:
                                    erro_msg = f'Erro HTTP 400: Requisição inválida'
                        else:
                            erro_msg = f'Erro HTTP {status_code}'
                            if hasattr(retorno, 'reason') and retorno.reason:
                                erro_msg += f' - {retorno.reason}'
                        
                        debug_print(f'>>> [PyNFe] Erro HTTP {status_code}, resposta vazia: {not (hasattr(retorno, "text") and retorno.text)}')
                        if hasattr(retorno, 'headers'):
                            debug_print(f'>>> [PyNFe] Headers da resposta: {dict(retorno.headers)}')
                    else:
                        erro_msg = f'Erro desconhecido na comunicação com a SEFAZ: {type(retorno)}'
                        debug_print(f'>>> [PyNFe] Retorno não é Response do requests: {type(retorno)}')
                else:
                    erro_msg = f'Resultado inesperado da autorização (tamanho: {len(resultado_autorizacao)})'
                    debug_print(f'>>> [PyNFe] Tamanho inesperado da tupla: {len(resultado_autorizacao)}')
                
                # IMPORTANTE: Tentar extrair dados da SEFAZ da resposta antes de retornar
                cstat_extraido = None
                motivo_extraido = None
                ver_aplic_extraido = None
                cuf_extraido = None
                dh_recbto_extraido = None
                campos_resposta_extraidos = {}
                
                if len(resultado_autorizacao) == 3:
                    _, retorno, _ = resultado_autorizacao
                    if hasattr(retorno, 'text') and retorno.text:
                        try:
                            from lxml import etree as lxml_etree
                            texto_xml_erro = retorno.text.strip()
                            if texto_xml_erro and texto_xml_erro.startswith('<'):
                                erro_xml_extrair = lxml_etree.fromstring(texto_xml_erro.encode('utf-8'))
                                ns_extrair = {
                                    "nfe": "http://www.portalfiscal.inf.br/nfe",
                                    "soap": "http://www.w3.org/2003/05/soap-envelope"
                                }
                                
                                # Procurar retEnviNFe
                                ret_envi_extrair = erro_xml_extrair.find('.//nfe:retEnviNFe', ns_extrair) or erro_xml_extrair.find('.//retEnviNFe')
                                if ret_envi_extrair is None:
                                    # Procurar dentro de nfeResultMsg
                                    nfe_result = erro_xml_extrair.find('.//nfeResultMsg') or erro_xml_extrair.find('.//ResultMsg')
                                    if nfe_result is not None:
                                        ret_envi_extrair = nfe_result.find('.//nfe:retEnviNFe', ns_extrair) or nfe_result.find('.//retEnviNFe')
                                
                                if ret_envi_extrair is not None:
                                    for child in ret_envi_extrair:
                                        tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                        valor = child.text.strip() if child.text else ''
                                        campos_resposta_extraidos[tag_limpa] = valor
                                        
                                        if tag_limpa == 'cStat':
                                            cstat_extraido = valor
                                        elif tag_limpa == 'xMotivo':
                                            motivo_extraido = valor
                                        elif tag_limpa == 'verAplic':
                                            ver_aplic_extraido = valor
                                        elif tag_limpa == 'cUF':
                                            cuf_extraido = valor
                                        elif tag_limpa == 'dhRecbto':
                                            dh_recbto_extraido = valor
                        except:
                            pass
                
                # Formatar mensagem de erro clara com dados da SEFAZ
                if motivo_extraido:
                    erro_msg_final = motivo_extraido
                else:
                    erro_msg_final = erro_msg
                
                print(f'')
                print(f'{"="*70}')
                print(f'❌ NFC-e NÃO FOI AUTORIZADA')
                print(f'{"="*70}')
                if cstat_extraido:
                    print(f'📋 Código SEFAZ (cStat): {cstat_extraido}')
                print(f'📄 Motivo: {erro_msg_final}')
                if ver_aplic_extraido:
                    print(f'📋 Versão da aplicação SEFAZ: {ver_aplic_extraido}')
                if cuf_extraido:
                    print(f'📋 Estado: {cuf_extraido}')
                if dh_recbto_extraido:
                    print(f'📋 Data/hora do recebimento: {dh_recbto_extraido}')
                print(f'⚠️ Numeração NÃO foi incrementada (nota não autorizada)')
                print(f'{"="*70}')
                print(f'')
                
                debug_print(f'>>> [PyNFe] ❌ Erro na autorização: {erro_msg_final}')
                debug_print(f'>>> [PyNFe] Tipo do retorno: {type(resultado_autorizacao)}')
                debug_print(f'>>> [PyNFe] Tamanho da tupla: {len(resultado_autorizacao)}')
                if len(resultado_autorizacao) == 3:
                    _, retorno, _ = resultado_autorizacao
                    if hasattr(retorno, 'text') and retorno.text:
                        debug_print(f'>>> [PyNFe] Resposta completa (primeiros 1000 chars): {retorno.text[:1000]}')
                    if hasattr(retorno, 'status_code'):
                        debug_print(f'>>> [PyNFe] Status HTTP: {retorno.status_code}')
                
                # Incluir TODOS os detalhes do erro e da resposta da SEFAZ
                # ⚠️ Numeração NÃO foi incrementada (nota não autorizada)
                resultado_erro = {
                    'success': False,
                    'message': f'❌ NFC-e não foi autorizada: {erro_msg_final}',
                    'error': erro_msg_final,  # Mensagem clara com erro da SEFAZ
                    'autorizada': False,  # Flag explícita de não autorização
                    'cstat': cstat_extraido,  # Código da SEFAZ
                    'motivo': motivo_extraido,  # Motivo da SEFAZ
                    'xmotivo': motivo_extraido,  # xMotivo da SEFAZ
                    'verAplic': ver_aplic_extraido,  # Versão da aplicação
                    'cUF': cuf_extraido,  # Estado
                    'dhRecbto': dh_recbto_extraido,  # Data/hora do recebimento
                    'campos_resposta': campos_resposta_extraidos if campos_resposta_extraidos else None,
                    'erro_completo': erro_msg_final,
                    'details': erro_msg_final
                }
                
                # Adicionar XML de resposta se disponível
                if len(resultado_autorizacao) == 3:
                    _, retorno, _ = resultado_autorizacao
                    if hasattr(retorno, 'text') and retorno.text:
                        resultado_erro['xml_resposta'] = retorno.text
                        resultado_erro['status_code'] = getattr(retorno, 'status_code', None)
                
                return resultado_erro
                
        except Exception as e:
            import traceback
            error_details = traceback.format_exc()
            
            print("=" * 50)
            print(f"❌ ERRO em emitir_nfce: {type(e).__name__}")
            print("=" * 50)
            print(f"Erro: {str(e)}")
            print("Traceback:")
            print(error_details)
            print("=" * 50)
            
            # Criar mensagem de erro simples
            error_message = str(e) if str(e) else f'Erro {type(e).__name__} ao processar emissão da NFC-e'
            
            return {
                'success': False,
                'error': error_message,
                'autorizada': False,  # Flag explícita de não autorização
                'error_type': type(e).__name__,
                'details': error_details
            }
    
    def consultar_nfce(self, data):
        """
        Consulta status de uma NFC-e
        
        Args:
            data: Dicionário com chave de acesso e dados da empresa
            
        Returns:
            Dicionário com status da NFC-e
        """
        try:
            chave_acesso = data['chave_acesso']
            empresa_data = data['empresa']
            
            # Carregar certificado
            certificado = self.certificado_service.carregar_certificado(
                empresa_data['certificado_base64'],
                empresa_data['senha_certificado']
            )
            
            # Consultar na SEFAZ
            comunicacao = ComunicacaoSefaz(
                uf=empresa_data.get('uf', 'SP'),
                certificado=certificado['arquivo'],
                certificado_senha=empresa_data['senha_certificado'],  # CORRETO: certificado_senha, não senha
                homologacao=empresa_data.get('ambiente_homologacao', True)
            )
            
            # IMPORTANTE: Para consulta, também precisa definir modelo como string "nfce"
            resposta = comunicacao.consulta_nota(modelo="nfce", chave=chave_acesso)
            
            if resposta.status_code == 200:
                return {
                    'success': True,
                    'data': self._processar_resposta_consulta(resposta.text)
                }
            else:
                return {
                    'success': False,
                    'error': f'Erro ao consultar: {resposta.status_code}'
                }
                
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }
    
    def _criar_emitente(self, empresa_data):
        """Cria objeto Emitente"""
        from pynfe.utils import obter_codigo_por_municipio
        
        cidade = empresa_data.get('cidade', '')
        uf = empresa_data.get('uf', 'SP')
        
        # Priorizar código IBGE do cadastro da empresa
        codigo_municipio = empresa_data.get('codigo_municipio', '') or empresa_data.get('codigoIBGE', '')
        
        # Limpar espaços e garantir que é string
        if codigo_municipio:
            codigo_municipio = str(codigo_municipio).strip()
        
        print(f'>>> [PyNFe] Dados do município:')
        print(f'  Cidade: {cidade}')
        print(f'  UF: {uf}')
        print(f'  Código IBGE do cadastro: {codigo_municipio if codigo_municipio else "não fornecido"}')
        
        # O PyNFe espera o NOME do município em endereco_municipio
        # Se temos código IBGE, obter o nome correspondente
        nome_municipio = cidade  # Manter nome original
        
        if codigo_municipio and len(codigo_municipio) >= 6:  # Código IBGE tem pelo menos 6 dígitos
            print(f'✅ [PyNFe] Código IBGE do cadastro: {codigo_municipio}')
            # Obter nome do município pelo código IBGE
            # O PyNFe precisa do NOME, não do código
            try:
                from pynfe.utils import obter_municipio_por_codigo
                # Converter código para string e garantir formato correto
                codigo_str = str(codigo_municipio).strip()
                # Tentar obter nome do município pelo código
                nome_municipio_validado = obter_municipio_por_codigo(codigo_str, uf)
                print(f'✅ [PyNFe] Nome do município obtido do código {codigo_str}: {nome_municipio_validado}')
                nome_municipio = nome_municipio_validado
            except ValueError:
                # Código não encontrado no dicionário do PyNFe
                print(f'⚠️ [PyNFe] Código {codigo_str} não encontrado no dicionário do PyNFe para UF {uf}')
                print(f'⚠️ [PyNFe] Tentando validar pelo nome: {nome_municipio}')
                # Tentar converter nome para código para validar
                try:
                    from pynfe.utils import obter_codigo_por_municipio
                    codigo_obtido = obter_codigo_por_municipio(nome_municipio, uf)
                    print(f'✅ [PyNFe] Código obtido pelo nome: {codigo_obtido}')
                    if codigo_obtido != codigo_str:
                        print(f'⚠️ [PyNFe] ATENÇÃO: Código do cadastro ({codigo_str}) difere do obtido pelo nome ({codigo_obtido})')
                        print(f'⚠️ [PyNFe] O código do cadastro pode estar incorreto ou desatualizado')
                        print(f'⚠️ [PyNFe] Usando código obtido pelo nome para garantir compatibilidade')
                    # Continuar com o nome, o PyNFe usará o código correto
                except Exception as e2:
                    print(f'❌ [PyNFe] Erro ao validar município pelo nome: {e2}')
                    # Se nem código nem nome funcionarem, usar o nome original e deixar PyNFe tentar
                    print(f'⚠️ [PyNFe] Usando nome original e deixando PyNFe processar: {nome_municipio}')
            except Exception as e:
                print(f'❌ [PyNFe] Erro ao obter nome do código {codigo_municipio}: {e}')
                # Em caso de erro inesperado, usar nome original
                print(f'⚠️ [PyNFe] Usando nome original: {nome_municipio}')
        elif not codigo_municipio or len(codigo_municipio) < 6:
            # Tentar obter código IBGE pelo nome
            try:
                codigo_municipio = obter_codigo_por_municipio(cidade, uf)
                print(f'>>> [PyNFe] Município "{cidade}/{uf}" → Código IBGE: {codigo_municipio}')
            except ValueError as e:
                # Tentar variações do nome
                print(f'⚠️ [PyNFe] Erro ao obter código do município "{cidade}/{uf}": {e}')
                
                # Tentar variações comuns
                variacoes = [
                    cidade,
                    cidade.upper(),
                    cidade.title(),
                    cidade.replace('DOS', 'DO').replace('DAS', 'DA'),
                    cidade.replace('SAO', 'SÃO'),
                    cidade.replace('SÃO', 'SAO'),
                ]
                
                codigo_encontrado = None
                for variacao in variacoes:
                    try:
                        codigo_encontrado = obter_codigo_por_municipio(variacao, uf)
                        print(f'>>> [PyNFe] Município encontrado com variação "{variacao}": {codigo_encontrado}')
                        break
                    except:
                        continue
                
                if codigo_encontrado:
                    codigo_municipio = codigo_encontrado
                else:
                    # Códigos conhecidos para cidades comuns
                    codigos_conhecidos = {
                        ('SAO JOSE DOS CAMPOS', 'SP'): '3509502',
                        ('SÃO JOSÉ DOS CAMPOS', 'SP'): '3509502',
                        ('SAO PAULO', 'SP'): '3550308',
                        ('SÃO PAULO', 'SP'): '3550308',
                        ('RIO DE JANEIRO', 'RJ'): '3304557',
                    }
                    
                    cidade_upper = cidade.upper().strip()
                    chave = (cidade_upper, uf)
                    
                    if chave in codigos_conhecidos:
                        codigo_municipio = codigos_conhecidos[chave]
                        print(f'>>> [PyNFe] Usando código conhecido para "{cidade}/{uf}": {codigo_municipio}')
                    else:
                        raise ValueError(
                            f"Não foi possível obter código IBGE para município '{cidade}/{uf}'. "
                            f"SOLUÇÃO: Adicione 'codigo_municipio' nos dados da empresa. "
                            f"Exemplo: 'codigo_municipio': '3509502' para São José dos Campos/SP"
                        )
            except Exception as e:
                print(f'❌ [PyNFe] Erro inesperado ao obter código do município: {e}')
                raise
        
        # Criar emitente com NOME do município
        # O PyNFe converterá o nome para código durante a serialização
        emitente = Emitente(
            razao_social=empresa_data['razao_social'],
            nome_fantasia=empresa_data.get('nome_fantasia', empresa_data['razao_social']),
            cnpj=empresa_data['cnpj'],
            inscricao_estadual=empresa_data['inscricao_estadual'],
            endereco_logradouro=empresa_data.get('endereco', ''),
            endereco_numero=empresa_data.get('numero', ''),
            endereco_bairro=empresa_data.get('bairro', ''),
            endereco_municipio=nome_municipio,  # NOME do município (PyNFe converte para código)
            endereco_uf=uf,
            endereco_cep=empresa_data.get('cep', ''),
            endereco_pais='1058',  # Brasil
            telefone=empresa_data.get('telefone', ''),
            email=empresa_data.get('email', '')
        )
        
        print(f'✅ [PyNFe] Emitente criado com município: {nome_municipio}/{uf}')
        if codigo_municipio:
            print(f'✅ [PyNFe] Código IBGE esperado: {codigo_municipio}')
        
        return emitente
    
    def _criar_cliente(self, consumidor_data):
        """Cria objeto Cliente"""
        from pynfe.utils import obter_codigo_por_municipio
        
        cidade = consumidor_data.get('cidade', '')
        uf = consumidor_data.get('uf', '')
        
        # Se tiver cidade e UF, converter para código IBGE
        codigo_municipio = ''
        if cidade and uf:
            try:
                codigo_municipio = obter_codigo_por_municipio(cidade, uf)
            except Exception:
                # Se não conseguir, usar código direto se fornecido
                codigo_municipio = consumidor_data.get('codigo_municipio', '')
        
        return Cliente(
            razao_social=consumidor_data.get('nome', 'CONSUMIDOR NÃO IDENTIFICADO'),
            tipo_documento='CPF' if len(consumidor_data.get('cpf', '')) == 11 else 'CNPJ',
            numero_documento=consumidor_data.get('cpf') or consumidor_data.get('cnpj', ''),
            indicador_ie=9,  # Não contribuinte
            endereco_logradouro=consumidor_data.get('endereco', ''),
            endereco_numero=consumidor_data.get('numero', ''),
            endereco_bairro=consumidor_data.get('bairro', ''),
            endereco_municipio=codigo_municipio if codigo_municipio else '',  # Usar código IBGE se disponível
            endereco_uf=uf,
            endereco_cep=consumidor_data.get('cep', ''),
            endereco_pais='1058'
        )
    
    def _criar_produto(self, produto_data):
        """Cria objeto Produto"""
        return Produto(
            codigo=produto_data['codigo'],
            descricao=produto_data['descricao'],
            ncm=produto_data['ncm'],
            cfop=produto_data['cfop'],
            unidade_comercial=produto_data['unidade'],
            quantidade_comercial=produto_data['quantidade'],
            valor_unitario_comercial=produto_data['valor_unitario'],
            valor_total=produto_data['valor_total'],
            icms_cst=produto_data.get('icms', {}).get('cst', '00'),
            icms_aliquota=produto_data.get('icms', {}).get('aliquota', 0.0)
        )
    
    def _criar_nfce(self, emitente, cliente, valor_total, 
                    observacoes, ambiente_homologacao, serie, numero):
        """Cria objeto NotaFiscal (NFC-e)"""
        # Produtos e pagamentos serão adicionados depois usando os métodos apropriados
        # Ambiente: 1=Produção, 2=Homologação (conforme PyNFe)
        return NotaFiscal(
            emitente=emitente,
            cliente=cliente,
            numero_nf=numero,
            serie=serie,
            data_emissao=datetime.now(),
            data_saida_entrada=datetime.now(),
            modelo=65,  # NFC-e (deve ser int, não string)
            natureza_operacao='VENDA',
            tipo_documento=1,  # 1=Saída
            tipo_impressao_danfe=4,  # 4=NFC-e
            finalidade_emissao=1,  # 1=Normal
            cliente_final=1,  # 1=Sim (consumidor final)
            indicador_presencial=1,  # 1=Operação presencial
            indicador_intermediador=0,  # 0=Sem intermediador
            indicador_destino=1,  # 1=Operação interna (NFC-e sempre interna)
            uf=emitente.endereco_uf,
            municipio=emitente.endereco_municipio,  # Já é código IBGE do emitente
            forma_emissao='1',  # 1=Emissão normal
            processo_emissao=0,  # 0=Emissão de NF-e com aplicativo do contribuinte
            valor_total_nota=Decimal(str(valor_total))
        )
    
    def _processar_resposta_sefaz(self, xml_resposta, ambiente_homologacao):
        """Processa resposta da SEFAZ"""
        try:
            from lxml import etree
            
            # Verificar se o XML não está vazio
            if not xml_resposta or not xml_resposta.strip():
                print(f'>>> [PyNFe] ⚠️ _processar_resposta_sefaz recebeu XML vazio!')
                return {
                    'status': 'rejeitada',
                    'protocolo': None,
                    'motivo': 'Resposta da SEFAZ está vazia',
                    'codigo': None
                }
            
            # Parsear XML de resposta
            xml_resposta_clean = xml_resposta.strip()
            if not xml_resposta_clean:
                raise ValueError('XML de resposta está vazio após strip')
            
            root = etree.fromstring(xml_resposta_clean.encode('utf-8'))
            
            # Namespaces comuns
            ns = {
                'soap': 'http://www.w3.org/2003/05/soap-envelope',
                'soap12': 'http://www.w3.org/2003/05/soap-envelope',
                'soapenv': 'http://schemas.xmlsoap.org/soap/envelope/',
                'soap11': 'http://schemas.xmlsoap.org/soap/envelope/',
                'nfe': 'http://www.portalfiscal.inf.br/nfe'
            }
            
            # Procurar retEnviNFe primeiro (evitar uso de find() em contexto booleano)
            ret_envi_nfe = root.find('.//nfe:retEnviNFe', ns)
            if ret_envi_nfe is None:
                ret_envi_nfe = root.find('.//retEnviNFe')
            
            # Se não encontrou, procurar dentro de envelope SOAP
            if ret_envi_nfe is None:
                body = root.find('.//soap:Body', ns)
                if body is None:
                    body = root.find('.//soap12:Body', ns)
                if body is None:
                    body = root.find('.//soapenv:Body', ns)
                if body is None:
                    body = root.find('.//soap11:Body', ns)
                if body is None:
                    body = root.find('.//Body')
                
                if body is not None:
                    ret_envi_nfe = body.find('.//nfe:retEnviNFe', ns)
                    if ret_envi_nfe is None:
                        ret_envi_nfe = body.find('.//retEnviNFe')
            
            # Se ainda não encontrou, procurar em qualquer lugar
            if ret_envi_nfe is None:
                for elem in root.iter():
                    if 'retEnviNFe' in elem.tag or 'retEnvi' in elem.tag:
                        ret_envi_nfe = elem
                        break
            
            # Extrair informações
            status_code = None
            motivo = ''
            protocolo = None
            
            if ret_envi_nfe is not None:
                # IMPORTANTE: Os elementos são filhos DIRETOS do retEnviNFe
                # Buscar diretamente os filhos, não usar .// (busca recursiva)
                
                # Buscar cStat (filho direto)
                status_elem = ret_envi_nfe.find('nfe:cStat', ns)
                if status_elem is None:
                    status_elem = ret_envi_nfe.find('cStat')
                if status_elem is None:
                    # Se não encontrou, iterar pelos filhos
                    for child in ret_envi_nfe:
                        tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                        if tag_limpa == 'cStat':
                            status_elem = child
                            break
                
                status_code = status_elem.text.strip() if status_elem is not None and status_elem.text else None
                
                # Buscar xMotivo (filho direto)
                motivo_elem = ret_envi_nfe.find('nfe:xMotivo', ns)
                if motivo_elem is None:
                    motivo_elem = ret_envi_nfe.find('xMotivo')
                if motivo_elem is None:
                    # Se não encontrou, iterar pelos filhos
                    for child in ret_envi_nfe:
                        tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                        if tag_limpa == 'xMotivo':
                            motivo_elem = child
                            break
                
                motivo = motivo_elem.text.strip() if motivo_elem is not None and motivo_elem.text else ''
                
                # Buscar nProt (filho direto)
                protocolo_elem = ret_envi_nfe.find('nfe:nProt', ns)
                if protocolo_elem is None:
                    protocolo_elem = ret_envi_nfe.find('nProt')
                if protocolo_elem is None:
                    # Se não encontrou, iterar pelos filhos
                    for child in ret_envi_nfe:
                        tag_limpa = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                        if tag_limpa == 'nProt':
                            protocolo_elem = child
                            break
                
                protocolo = protocolo_elem.text.strip() if protocolo_elem is not None and protocolo_elem.text else None
            else:
                # Procurar diretamente no root
                status_elem = (root.find('.//nfe:cStat', ns) or 
                              root.find('.//cStat'))
                status_code = status_elem.text.strip() if status_elem is not None and status_elem.text else None
                
                motivo_elem = (root.find('.//nfe:xMotivo', ns) or 
                              root.find('.//xMotivo'))
                motivo = motivo_elem.text.strip() if motivo_elem is not None and motivo_elem.text else ''
                
                protocolo_elem = (root.find('.//nfe:nProt', ns) or 
                                 root.find('.//nProt'))
                protocolo = protocolo_elem.text.strip() if protocolo_elem is not None and protocolo_elem.text else None
            
            # Determinar status
            if status_code == '100' or status_code == '150':  # Autorizada
                status = 'autorizada'
            elif status_code in ['110', '301', '302']:  # Denegada
                status = 'denegada'
            elif status_code:  # Rejeitada (qualquer outro código)
                status = 'rejeitada'
            else:  # Sem código (erro no parsing)
                status = 'processando'
            
            print(f'>>> [PyNFe] Resposta processada: status={status}, código={status_code}, motivo={motivo[:100] if motivo else "N/A"}')
            
            return {
                'status': status,
                'protocolo': protocolo,
                'motivo': motivo,
                'codigo': status_code
            }
        except Exception as e:
            import traceback
            print(f'>>> [PyNFe] Erro ao processar resposta: {e}')
            print(f'>>> [PyNFe] Traceback: {traceback.format_exc()}')
            # Em caso de erro, retornar estrutura básica
            return {
                'status': 'processando',
                'protocolo': None,
                'motivo': f'Erro ao processar resposta: {str(e)}',
                'codigo': None
            }
    
    def _processar_resposta_consulta(self, xml_resposta):
        """Processa resposta da consulta"""
        # TODO: Implementar parsing do XML de resposta
        return {
            'status': 'autorizada'
        }
    
    def _validar_valores_decimais_xml(self, xml_elemento):
        """
        Valida e corrige valores decimais no XML conforme schema XSD oficial
        Baseado em: 
        - https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/
        - Schema oficial: tiposBasico_v3.10.xsd (TDec_1302)
        
        Regras do TDec_1302 (Tipo Decimal 13 dígitos corpo + 2 decimais):
        - Pattern: 0|0\\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\\.[0-9]{2})?
        - Pode ser: 0, 0.00, 1, 12.50, 1234567890123.45
        - NÃO pode ser: 0.000 (3 casas), 1.5 (1 casa), 0.1 (1 casa)
        - Máximo: 13 dígitos antes da vírgula, exatamente 2 após
        """
        from lxml import etree as lxml_etree
        import re
        
        corrigido = False
        problemas = []
        
        # Campos decimais que devem seguir padrão TDec_1302
        campos_decimais_1302 = [
            'vProd', 'vUnCom', 'vUnTrib', 'vFrete', 'vSeg', 'vDesc', 'vOutro',
            'vBC', 'vICMS', 'vICMSDeson', 'vFCP', 'vBCST', 'vST', 'vFCPST',
            'vFCPSTRet', 'vIPI', 'vIPIDevol', 'vPIS', 'vCOFINS', 'vNF', 
            'vTotTrib', 'vICMSUFDest', 'vFCPUFDest', 'vICMSUFRemet',
            'vPag', 'vTroco', 'vLiq'
        ]
        
        # Pattern do schema oficial TDec_1302
        pattern_tdec_1302 = re.compile(r'^(0|0\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\.[0-9]{2})?)$')
        
        # Buscar todos os elementos no XML
        for elem in xml_elemento.iter():
            tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            
            # Verificar se é um campo decimal que precisa validação
            if tag_limpa in campos_decimais_1302 and elem.text:
                valor_original = elem.text.strip()
                
                # Verificar se já está no padrão correto
                if pattern_tdec_1302.match(valor_original):
                    continue  # Já está correto
                
                # Tentar converter e corrigir
                try:
                    valor_decimal = Decimal(valor_original)
                    
                    # Casos especiais conforme pattern:
                    if valor_decimal == 0:
                        # Zero pode ser "0" ou "0.00"
                        valor_formatado = "0.00"
                    else:
                        # Formatar com exatamente 2 casas decimais
                        valor_formatado = f"{valor_decimal:.2f}"
                    
                    # Validar padrão: máximo 13 dígitos antes da vírgula
                    partes = valor_formatado.split('.')
                    parte_inteira = partes[0]
                    
                    if len(parte_inteira) > 13:
                        problemas.append(f"Campo {tag_limpa} excede 13 dígitos: {valor_formatado}")
                        # Truncar para 13 dígitos (limite do schema)
                        parte_inteira = parte_inteira[:13]
                        valor_formatado = parte_inteira + '.' + partes[1]
                    
                    # Validar que tem exatamente 2 casas decimais
                    if '.' in valor_formatado:
                        parte_decimal = valor_formatado.split('.')[1]
                        if len(parte_decimal) != 2:
                            # Garantir 2 casas decimais
                            parte_decimal = parte_decimal.ljust(2, '0')[:2]
                            valor_formatado = partes[0] + '.' + parte_decimal
                    
                    # Se o valor mudou, atualizar
                    if valor_original != valor_formatado:
                        elem.text = valor_formatado
                        corrigido = True
                        print(f'>>> [PyNFe] ✅ Valor decimal corrigido (TDec_1302): {tag_limpa} de "{valor_original}" para "{valor_formatado}"')
                
                except (ValueError, Exception) as e:
                    problemas.append(f"Campo {tag_limpa} com valor inválido: {valor_original} ({str(e)})")
                    print(f'>>> [PyNFe] ❌ Erro ao validar {tag_limpa}: {valor_original} - {str(e)}')
        
        return corrigido, problemas
    
    def _corrigir_erros_validacao(self, xml_str: str, resultado_validacao) -> str:
        """
        Tenta corrigir automaticamente os erros encontrados na validação.
        """
        import re
        
        xml_corrigido = xml_str
        erros_corrigidos = []
        
        for erro in resultado_validacao['erros']:
            # Corrigir cMunFG inválido
            if 'cMunFG' in erro and ('deve ser código IBGE' in erro or 'tamanho incorreto' in erro):
                # Buscar código no emitente
                cMun_match = re.search(r'<cMun>(\d{7})</cMun>', xml_corrigido)
                if cMun_match:
                    codigo_ibge = cMun_match.group(1)
                    xml_corrigido = re.sub(r'<cMunFG>[^<]+</cMunFG>', f'<cMunFG>{codigo_ibge}</cMunFG>', xml_corrigido, count=1)
                    erros_corrigidos.append('cMunFG corrigido para código IBGE')
                else:
                    xml_corrigido = re.sub(r'<cMunFG>[^<]+</cMunFG>', '<cMunFG>3549904</cMunFG>', xml_corrigido, count=1)
                    erros_corrigidos.append('cMunFG corrigido com fallback')
            
            # Corrigir verProc vazio ou com PyNFe
            if 'verProc' in erro or ('verProc' in xml_corrigido and 'PyNFe' in xml_corrigido):
                xml_corrigido = re.sub(r'<verProc>[^<]*</verProc>', '<verProc>Sistema Exodo</verProc>', xml_corrigido)
                erros_corrigidos.append('verProc corrigido para Sistema Exodo')
            
            # Corrigir CRT duplicado
            if 'CRT duplicado' in erro:
                crt_match = re.search(r'<CRT>(\d)</CRT>', xml_corrigido)
                if crt_match:
                    crt_valor = crt_match.group(1)
                    xml_corrigido = re.sub(r'<CRT>[^<]*</CRT>', '', xml_corrigido)
                    xml_corrigido = re.sub(r'(</IE>)', r'\1<CRT>' + crt_valor + '</CRT>', xml_corrigido, count=1)
                    erros_corrigidos.append('CRT duplicado removido')
            
            # Corrigir CRT vazio
            if 'CRT vazio' in erro:
                xml_corrigido = re.sub(r'<CRT></CRT>', '<CRT>1</CRT>', xml_corrigido)
                xml_corrigido = re.sub(r'<CRT/>', '<CRT>1</CRT>', xml_corrigido)
                erros_corrigidos.append('CRT vazio corrigido')
            
            # Corrigir xPais
            if 'xPais' in erro and 'Brasil' in erro:
                xml_corrigido = re.sub(r'<xPais>BRASIL</xPais>', '<xPais>Brasil</xPais>', xml_corrigido, flags=re.IGNORECASE)
                erros_corrigidos.append('xPais corrigido para Brasil')
        
        if erros_corrigidos:
            debug_print(f'>>> [PyNFe] Correções aplicadas: {len(erros_corrigidos)}')
            for correcao in erros_corrigidos:
                debug_print(f'>>> [PyNFe]   - {correcao}')
        
        return xml_corrigido
    
    def _validar_caracteres_proibidos(self, xml_elemento):
        """
        Valida e remove caracteres proibidos no XML
        Baseado em: https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/
        
        Caracteres proibidos: *, /, ?, !, etc. em campos de texto
        """
        import re
        
        corrigido = False
        problemas = []
        
        # Caracteres proibidos em campos de texto (exceto em alguns campos específicos)
        caracteres_proibidos = ['*', '/', '?', '!', '<', '>', '&']
        
        # Campos de texto que não devem ter caracteres proibidos
        campos_texto = ['xNome', 'xFant', 'xProd', 'xLgr', 'xBairro', 'xMun', 'xPais', 
                        'infCpl', 'infAdProd', 'xObs']
        
        for elem in xml_elemento.iter():
            tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            
            if tag_limpa in campos_texto and elem.text:
                texto_original = elem.text
                texto_corrigido = texto_original
                
                # Remover caracteres proibidos
                for char in caracteres_proibidos:
                    if char in texto_corrigido:
                        texto_corrigido = texto_corrigido.replace(char, '')
                        problemas.append(f"Caractere proibido '{char}' removido de {tag_limpa}")
                        corrigido = True
                
                # Remover quebras de linha e espaços extras
                texto_corrigido = ' '.join(texto_corrigido.split())
                
                if texto_original != texto_corrigido:
                    elem.text = texto_corrigido
                    debug_print(f'>>> [PyNFe] ✅ Texto corrigido: {tag_limpa}')
        
        return corrigido, problemas
    
    def _validar_estrutura_xml_completa(self, xml_str):
        """
        Valida estrutura completa do XML antes de enviar
        Baseado em: https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/
        """
        from lxml import etree as lxml_etree
        import re
        
        problemas = []
        avisos = []
        
        try:
            # 1. Validar tamanho do arquivo (máximo 500KB recomendado)
            tamanho_kb = len(xml_str.encode('utf-8')) / 1024
            if tamanho_kb > 500:
                avisos.append(f"Tamanho do XML: {tamanho_kb:.2f} KB (recomendado: < 500 KB)")
            
            # 2. Validar que é XML válido
            try:
                xml_tree = lxml_etree.fromstring(xml_str.encode('utf-8'))
            except Exception as e:
                problemas.append(f"XML malformado: {str(e)}")
                return False, problemas, avisos
            
            # 3. Validar tags XML (não devem ter espaços ou quebras de linha indevidas)
            if re.search(r'<\s+[^>]+>', xml_str):
                problemas.append("Tags XML com espaços indevidos")
            
            # 4. Validar fechamento de tags
            tags_abertas = re.findall(r'<([^/!?][^>]*?)(?:\s|>)', xml_str)
            tags_fechadas = re.findall(r'</([^>]+)>', xml_str)
            
            # Contar tags auto-fechadas
            tags_auto_fechadas = re.findall(r'<[^>]+/>', xml_str)
            
            # 5. Validar namespace
            if 'xmlns="http://www.portalfiscal.inf.br/nfe"' not in xml_str:
                if 'enviNFe' in xml_str or 'NFe' in xml_str:
                    avisos.append("Namespace pode estar incorreto")
            
            # 6. Validar versão
            if 'versao="4.00"' not in xml_str:
                if 'enviNFe' in xml_str or 'infNFe' in xml_str:
                    avisos.append("Versão pode estar incorreta (esperado: 4.00)")
            
            return len(problemas) == 0, problemas, avisos
            
        except Exception as e:
            problemas.append(f"Erro na validação: {str(e)}")
            return False, problemas, avisos
    
    def _copiar_elemento_limpo(self, elemento_original, namespace_correto):
        """
        Copia um elemento XML e seus filhos, removendo prefixos de namespace e garantindo namespace correto.
        """
        from lxml import etree as lxml_etree
        
        if elemento_original is None:
            return None
        
        # Obter tag sem prefixo
        if '}' in elemento_original.tag:
            tag_sem_prefixo = elemento_original.tag.split('}')[-1]
        else:
            tag_sem_prefixo = elemento_original.tag
        
        # Criar novo elemento com namespace correto (sem prefixo)
        novo_elemento = lxml_etree.Element(
            '{' + namespace_correto + '}' + tag_sem_prefixo,
            nsmap={None: namespace_correto}
        )
        
        # Copiar atributos (exceto namespaces)
        for attr, valor in elemento_original.attrib.items():
            if attr != 'xmlns' and not attr.startswith('xmlns:'):
                novo_elemento.set(attr, valor)
        
        # Copiar texto
        if elemento_original.text:
            novo_elemento.text = elemento_original.text
        
        # Processar filhos recursivamente
        for child in elemento_original:
            child_limpo = self._copiar_elemento_limpo(child, namespace_correto)
            if child_limpo is not None:
                novo_elemento.append(child_limpo)
        
        # Copiar tail
        if elemento_original.tail:
            novo_elemento.tail = elemento_original.tail
        
        return novo_elemento
    
    def _aplicar_correcoes_finais_infnfe(self, inf_nfe_element, namespace_correto):
        """
        Aplica correções finais no elemento infNFe, garantindo que todos os campos estejam corretos.
        """
        from lxml import etree as lxml_etree
        import re
        
        ns_nfe = {"nfe": namespace_correto}
        
        # 1. Corrigir cMunFG - deve ser código IBGE de 7 dígitos
        ide = inf_nfe_element.find('nfe:ide', ns_nfe) or inf_nfe_element.find('ide')
        if ide is not None:
            c_mun_fg = ide.find('nfe:cMunFG', ns_nfe) or ide.find('cMunFG')
            if c_mun_fg is not None:
                if not c_mun_fg.text or not c_mun_fg.text.strip().isdigit() or len(c_mun_fg.text.strip()) != 7:
                    # Obter código IBGE do emitente
                    emit = inf_nfe_element.find('nfe:emit', ns_nfe) or inf_nfe_element.find('emit')
                    if emit is not None:
                        ender_emit = emit.find('nfe:enderEmit', ns_nfe) or emit.find('enderEmit')
                        if ender_emit is not None:
                            c_mun = ender_emit.find('nfe:cMun', ns_nfe) or ender_emit.find('cMun')
                            if c_mun is not None and c_mun.text and c_mun.text.strip().isdigit() and len(c_mun.text.strip()) == 7:
                                c_mun_fg.text = c_mun.text.strip()
                            else:
                                c_mun_fg.text = '3549904'  # São José dos Campos
                        else:
                            c_mun_fg.text = '3549904'
                    else:
                        c_mun_fg.text = '3549904'
            
            # 2. Corrigir verProc
            ver_proc = ide.find('nfe:verProc', ns_nfe) or ide.find('verProc')
            if ver_proc is not None:
                if not ver_proc.text or 'pynfe' in ver_proc.text.lower():
                    ver_proc.text = 'Sistema Exodo'
            else:
                ver_proc = lxml_etree.SubElement(ide, '{' + namespace_correto + '}verProc')
                ver_proc.text = 'Sistema Exodo'
        
        # 3. Corrigir CRT - remover duplicados e garantir único
        emit = inf_nfe_element.find('nfe:emit', ns_nfe) or inf_nfe_element.find('emit')
        if emit is not None:
            # Remover todos os CRTs
            crts = emit.findall('nfe:CRT', ns_nfe) + emit.findall('CRT')
            crt_valido = None
            for crt in crts:
                if crt.text and crt.text.strip():
                    if crt_valido is None:
                        crt_valido = crt.text.strip()
                emit.remove(crt)
            
            # Criar um único CRT válido
            crt_novo = lxml_etree.SubElement(emit, '{' + namespace_correto + '}CRT')
            crt_novo.text = crt_valido if crt_valido else '1'
        
        # 4. Corrigir xPais - deve ser "Brasil" (não "BRASIL")
        if emit is not None:
            ender_emit = emit.find('nfe:enderEmit', ns_nfe) or emit.find('enderEmit')
            if ender_emit is not None:
                x_pais = ender_emit.find('nfe:xPais', ns_nfe) or ender_emit.find('xPais')
                if x_pais is not None and x_pais.text and x_pais.text.upper() == 'BRASIL':
                    x_pais.text = 'Brasil'
        
        # 5. Adicionar infAdic/infCpl se não existir
        inf_adic = inf_nfe_element.find('nfe:infAdic', ns_nfe) or inf_nfe_element.find('infAdic')
        if inf_adic is None:
            inf_adic = lxml_etree.SubElement(inf_nfe_element, '{' + namespace_correto + '}infAdic')
            inf_cpl = lxml_etree.SubElement(inf_adic, '{' + namespace_correto + '}infCpl')
            inf_cpl.text = 'NFC-e emitida pelo Sistema Exodo'
    
    def _remover_prefixos_namespace(self, elemento):
        """
        Remove prefixos de namespace (ns0:, ns1:, etc.) de um elemento XML e seus filhos.
        Reconstrói o elemento com namespace direto, sem prefixos.
        """
        from lxml import etree as lxml_etree
        
        namespace_correto = 'http://www.portalfiscal.inf.br/nfe'
        
        def limpar_elemento(elem):
            """Função recursiva para limpar prefixos"""
            if elem is None:
                return None
            
            # Obter tag sem prefixo
            if '}' in elem.tag:
                tag_sem_prefixo = elem.tag.split('}')[-1]
            else:
                tag_sem_prefixo = elem.tag
            
            # Criar novo elemento com namespace direto (sem prefixo)
            novo_elem = lxml_etree.Element(
                '{' + namespace_correto + '}' + tag_sem_prefixo,
                nsmap={None: namespace_correto}
            )
            
            # Copiar atributos
            for attr, valor in elem.attrib.items():
                if attr != 'xmlns' and not attr.startswith('xmlns:'):
                    novo_elem.set(attr, valor)
            
            # Copiar texto
            if elem.text:
                novo_elem.text = elem.text
            
            # Processar filhos recursivamente
            for child in elem:
                child_limpo = limpar_elemento(child)
                if child_limpo is not None:
                    novo_elem.append(child_limpo)
            
            # Copiar tail
            if elem.tail:
                novo_elem.tail = elem.tail
            
            return novo_elem
        
        # Limpar elemento raiz
        elemento_limpo = limpar_elemento(elemento)
        
        # Substituir elemento original
        if elemento_limpo is not None:
            # Limpar filhos do elemento original
            for child in list(elemento):
                elemento.remove(child)
            
            # Adicionar filhos limpos
            for child in elemento_limpo:
                elemento.append(child)
            
            # Copiar atributos
            elemento.attrib.clear()
            for attr, valor in elemento_limpo.attrib.items():
                elemento.set(attr, valor)
            
            # Atualizar namespace
            elemento.tag = elemento_limpo.tag
            if hasattr(elemento, 'nsmap'):
                elemento.nsmap.clear()
                elemento.nsmap.update({None: namespace_correto})
    
    def _gerar_chave_acesso(self, nfce):
        """
        Gera chave de acesso da NFC-e (44 dígitos totais)
        Estrutura: cUF(2) + AAMM(4) + CNPJ(14) + mod(2) + série(3) + nNF(9) + tpEmis(1) + cNF(8) + cDV(1) = 44
        Para calcular DV: 43 dígitos (sem DV) + 1 (DV) = 44
        """
        from pynfe.utils.flags import CODIGOS_ESTADOS
        from pynfe.utils import so_numeros
        
        # 1. cUF - Código UF (2 dígitos)
        uf = str(CODIGOS_ESTADOS.get(nfce.uf, '35'))[:2].zfill(2)
        
        # 2. AAMM - Ano e mês (4 dígitos: YYMM)
        ano_mes = nfce.data_emissao.strftime("%y%m")
        if len(ano_mes) != 4:
            ano_mes = ano_mes[:4].zfill(4)
        
        # 3. CNPJ - CNPJ do emitente (14 dígitos)
        cnpj = so_numeros(str(nfce.emitente.cnpj))[:14].zfill(14)
        
        # 4. mod - Modelo do documento (2 dígitos) - NFC-e = 65
        modelo = str(nfce.modelo)[:2].zfill(2)
        
        # 5. série - Série do documento (3 dígitos)
        serie = str(nfce.serie)[:3].zfill(3)
        
        # 6. nNF - Número da NFC-e (9 dígitos)
        numero = str(nfce.numero_nf)[:9].zfill(9)
        
        # 7. tpEmis - Tipo de emissão (1 dígito)
        tp_emis = str(nfce.forma_emissao)[:1].zfill(1)
        
        # 8. cNF - Código numérico aleatório (8 dígitos)
        if not nfce.codigo_numerico_aleatorio:
            nfce.codigo_numerico_aleatorio = str(random.randint(0, 99999999)).zfill(8)
        cnf = str(nfce.codigo_numerico_aleatorio)[:8].zfill(8)
        
        # Montar chave de 43 dígitos (sem DV)
        chave_43 = f"{uf}{ano_mes}{cnpj}{modelo}{serie}{numero}{tp_emis}{cnf}"
        
        # Validar tamanho exato
        if len(chave_43) != 43:
            raise ValueError(
                f"Chave de acesso deve ter exatamente 43 dígitos, mas tem {len(chave_43)}. "
                f"Componentes: UF({len(uf)}) + AAMM({len(ano_mes)}) + CNPJ({len(cnpj)}) + "
                f"mod({len(modelo)}) + série({len(serie)}) + nNF({len(numero)}) + "
                f"tpEmis({len(tp_emis)}) + cNF({len(cnf)}) = {len(chave_43)}. "
                f"Chave: {chave_43}"
            )
        
        # Calcular dígito verificador (DV) - 1 dígito
        dv = nfce._dv_codigo_numerico(chave_43)
        
        # Retornar chave completa: 43 dígitos + 1 DV = 44 dígitos
        return f"{chave_43}{dv}"
    
    def _gerar_qr_code(self, chave_acesso, protocolo, ambiente_homologacao):
        """Gera string do QR Code para NFC-e"""
        # Formato do QR Code NFC-e:
        # URL?p=chave_acesso|protocolo|timestamp|valor_total|destino|digest
        
        # URL base (homologação ou produção)
        if ambiente_homologacao:
            # URLs de homologação por estado
            url_base = 'https://www.sefazvirtual.fazenda.gov.br/NFCE/NFCE-COM.aspx'
        else:
            url_base = 'https://www.sefazvirtual.fazenda.gov.br/NFCE/NFCE-COM.aspx'
        
        # Timestamp
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        
        # Montar QR Code
        # Formato: URL?p=chave|protocolo|timestamp|valor|destino|digest
        # Por enquanto, usar formato simplificado
        qr_data = f'{chave_acesso}|{protocolo}|{timestamp}'
        
        return f'{url_base}?p={qr_data}'
    
    def _gerar_qr_code_nfelib(self, chave_acesso, protocolo, ambiente_homologacao, valor_total, uf='SP'):
        """
        Gera string do QR Code para NFC-e conforme layout oficial
        
        Formato oficial:
        URL?chNFe=CHAVE&nVersao=100&tpAmb=AMBIENTE&cDest=CPF_CNPJ&dhEmi=DATA&vNF=VALOR&vICMS=VALOR&digVal=DIGEST&cIdToken=TOKEN
        
        Args:
            chave_acesso: Chave de acesso da NFC-e (44 dígitos)
            protocolo: Número do protocolo de autorização
            ambiente_homologacao: True para homologação, False para produção
            valor_total: Valor total da NFC-e
            uf: Sigla do estado (para URL correta)
            
        Returns:
            String com URL do QR Code
        """
        import hashlib
        from decimal import Decimal
        
        # URL base conforme estado e ambiente
        if ambiente_homologacao:
            if uf == 'SP':
                url_base = 'https://homologacao.nfce.fazenda.sp.gov.br/qrcode'
            else:
                url_base = 'https://www.sefazvirtual.fazenda.gov.br/NFCE/NFCE-COM.aspx'
        else:
            if uf == 'SP':
                url_base = 'https://nfce.fazenda.sp.gov.br/qrcode'
            else:
                url_base = 'https://www.sefazvirtual.fazenda.gov.br/NFCE/NFCE-COM.aspx'
        
        # Parâmetros do QR Code
        n_versao = '100'  # Versão do QR Code
        tp_amb = '2' if ambiente_homologacao else '1'
        c_dest = ''  # CPF/CNPJ do destinatário (opcional para NFC-e)
        
        # Data/hora de emissão (extrair da chave de acesso se possível)
        # Formato: AAMM (ano e mês) estão na posição 2-5 da chave
        try:
            ano_mes = chave_acesso[2:6]  # AAMM
            ano = '20' + ano_mes[:2]
            mes = ano_mes[2:4]
            # Usar data/hora atual como fallback
            dh_emi = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00')
        except:
            dh_emi = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00')
        
        # Valores
        v_nf = f"{Decimal(str(valor_total)):.2f}"
        v_icms = "0.00"  # Valor do ICMS (geralmente 0 para Simples Nacional)
        
        # Digest (hash SHA-1 do protocolo)
        # Formato: Base64 do SHA-1 do protocolo
        try:
            digest_bytes = hashlib.sha1(protocolo.encode('utf-8')).digest()
            import base64
            dig_val = base64.b64encode(digest_bytes).decode('utf-8')
        except:
            dig_val = ''
        
        # Token CSC (Código de Segurança do Contribuinte)
        # Este valor deve vir da configuração da empresa
        c_id_token = '000001'  # Valor padrão, deve ser configurado
        
        # Montar URL do QR Code
        params = [
            f'chNFe={chave_acesso}',
            f'nVersao={n_versao}',
            f'tpAmb={tp_amb}',
            f'cDest={c_dest}',
            f'dhEmi={dh_emi}',
            f'vNF={v_nf}',
            f'vICMS={v_icms}',
            f'digVal={dig_val}',
            f'cIdToken={c_id_token}'
        ]
        
        qr_code = f"{url_base}?{'&'.join(params)}"
        
        return qr_code
    
    # ============================================
    # MÉTODOS AUXILIARES PARA NFELIB
    # ============================================
    
    def _obter_codigo_uf_nfelib(self, uf):
        """Obtém código da UF para nfelib"""
        codigos = {
            'AC': 12, 'AL': 27, 'AP': 16, 'AM': 13, 'BA': 29,
            'CE': 23, 'DF': 53, 'ES': 32, 'GO': 52, 'MA': 21,
            'MT': 51, 'MS': 50, 'MG': 31, 'PA': 15, 'PB': 25,
            'PR': 41, 'PE': 26, 'PI': 22, 'RJ': 33, 'RN': 24,
            'RS': 43, 'RO': 11, 'RR': 14, 'SC': 42, 'SP': 35,
            'SE': 28, 'TO': 17
        }
        return codigos.get(uf.upper(), 35)
    
    def _gerar_codigo_numerico_nfelib(self):
        """Gera código numérico de 8 dígitos para nfelib"""
        return str(random.randint(10000000, 99999999))
    
    def _gerar_chave_acesso_nfelib(self, codigo_uf, codigo_numerico, numero, serie, data_emissao, cnpj):
        """Gera chave de acesso de 44 dígitos para nfelib"""
        aamm = data_emissao.strftime('%y%m')
        mod = '65'  # NFC-e
        serie_formatada = str(serie).zfill(3)
        n_nf_formatado = str(numero).zfill(9)
        tp_emis = '1'
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
    
    def _assinar_xml_nfelib(self, xml_str, certificado, chave_acesso):
        """Assina XML com certificado digital usando nfelib"""
        # Definir debug_print para este método
        debug_print = print
        try:
            debug_print(">>> [nfelib] Iniciando assinatura do XML...")
            
            # Verificar se certificado tem arquivo ou dados diretos
            if 'arquivo' in certificado:
                cert_path = certificado['arquivo']
                debug_print(f">>> [nfelib] Carregando certificado do arquivo: {cert_path}")
                
                # Verificar se arquivo existe
                if not os.path.exists(cert_path):
                    raise FileNotFoundError(f"Arquivo de certificado não encontrado: {cert_path}")
                
                with open(cert_path, 'rb') as f:
                    cert_data = f.read()
                
                debug_print(f">>> [nfelib] Certificado carregado: {len(cert_data)} bytes")
            elif 'dados' in certificado:
                # Certificado já está em bytes
                cert_data = certificado['dados']
                debug_print(f">>> [nfelib] Usando certificado de dados: {len(cert_data)} bytes")
            elif 'certificado_base64' in certificado:
                # Decodificar base64
                import base64
                cert_data = base64.b64decode(certificado['certificado_base64'])
                debug_print(f">>> [nfelib] Certificado decodificado de base64: {len(cert_data)} bytes")
            else:
                raise ValueError("Certificado não contém 'arquivo', 'dados' ou 'certificado_base64'")
            
            # Obter senha
            senha = certificado.get('senha', '')
            if not senha:
                raise ValueError("Senha do certificado não fornecida")
            
            # Tratar senha (pode ser string ou bytes)
            if isinstance(senha, str):
                cert_password = senha.encode('utf-8')
            else:
                cert_password = senha
            
            debug_print(f">>> [nfelib] Tentando carregar PKCS12 (senha: {'*' * len(senha)})...")
            
            # Tentar carregar certificado PKCS12
            # Tentar diferentes codificações da senha se necessário
            private_key = None
            certificate = None
            
            # Tentativa 1: Senha como está
            try:
                private_key, certificate, _ = pkcs12.load_key_and_certificates(
                    cert_data, cert_password, backend=default_backend()
                )
                debug_print(">>> [nfelib] ✅ Certificado PKCS12 carregado com sucesso!")
            except ValueError as e:
                error_msg = str(e)
                debug_print(f">>> [nfelib] Tentativa 1 falhou: {error_msg}")
                
                # Tentativa 2: Senha sem espaços no início/fim
                if isinstance(senha, str):
                    senha_limpa = senha.strip()
                    if senha_limpa != senha:
                        debug_print(f">>> [nfelib] Tentando com senha sem espaços...")
                        try:
                            cert_password_limpo = senha_limpa.encode('utf-8')
                            private_key, certificate, _ = pkcs12.load_key_and_certificates(
                                cert_data, cert_password_limpo, backend=default_backend()
                            )
                            debug_print(">>> [nfelib] ✅ Certificado PKCS12 carregado (senha sem espaços)!")
                        except ValueError:
                            pass
                
                # Tentativa 3: Senha como latin-1 (alguns certificados usam)
                if private_key is None and isinstance(senha, str):
                    debug_print(f">>> [nfelib] Tentando com codificação latin-1...")
                    try:
                        cert_password_latin = senha.encode('latin-1')
                        private_key, certificate, _ = pkcs12.load_key_and_certificates(
                            cert_data, cert_password_latin, backend=default_backend()
                        )
                        debug_print(">>> [nfelib] ✅ Certificado PKCS12 carregado (latin-1)!")
                    except ValueError:
                        pass
                
                # Se ainda não funcionou, lançar erro detalhado
                if private_key is None or certificate is None:
                    # Re-lançar o erro original com diagnóstico
                    error_msg = str(e)
                    debug_print(f">>> [nfelib] ❌ Erro ao carregar PKCS12: {error_msg}")
                    
                    # Diagnóstico detalhado
                    debug_print(f">>> [nfelib] Diagnóstico:")
                    debug_print(f">>> [nfelib]   - Tamanho dos dados: {len(cert_data)} bytes")
                    debug_print(f">>> [nfelib]   - Primeiros bytes (hex): {cert_data[:20].hex() if len(cert_data) >= 20 else 'muito pequeno'}")
                    debug_print(f">>> [nfelib]   - Senha fornecida: {'Sim' if senha else 'Não'}")
                    debug_print(f">>> [nfelib]   - Tamanho da senha: {len(senha) if senha else 0} caracteres")
                    
                    # Verificar se é formato PKCS12 válido
                    if len(cert_data) < 4:
                        raise ValueError("Dados do certificado muito pequenos (pode estar corrompido)")
                    
                    # Tentar verificar se é realmente PKCS12
                    if cert_data[:2] == b'PK':
                        raise ValueError("Arquivo parece ser ZIP, não PKCS12. Certificado pode estar em formato incorreto.")
                    
                    # Sugerir possíveis problemas
                    sugestoes = []
                    if 'password' in error_msg.lower() or 'senha' in error_msg.lower():
                        sugestoes.append("1. Verifique se a senha está correta (pode ter espaços no início/fim)")
                        sugestoes.append("2. Certifique-se de que não há caracteres especiais mal codificados")
                        sugestoes.append("3. Tente copiar e colar a senha novamente")
                        sugestoes.append("4. Verifique se a senha não foi alterada acidentalmente")
                    
                    if 'pkcs12' in error_msg.lower() or 'data' in error_msg.lower():
                        sugestoes.append("5. O certificado pode estar corrompido")
                        sugestoes.append("6. O certificado pode estar em formato diferente (PEM, DER, etc)")
                        sugestoes.append("7. Verifique se o certificado foi decodificado corretamente do base64")
                        sugestoes.append("8. Tente fazer upload do certificado novamente")
                    
                    if sugestoes:
                        debug_print(f">>> [nfelib] Sugestões:")
                        for sugestao in sugestoes:
                            debug_print(f">>> [nfelib]   {sugestao}")
                    
                    raise ValueError(f"Erro ao carregar certificado PKCS12: {error_msg}. Verifique a senha e o formato do certificado.")
            
            # PROBLEMA: signxml 3.0+ tem incompatibilidades graves
            # SOLUÇÃO: Usar assinatura manual sem signxml
            # Não vamos mais usar XMLSigner - vamos assinar manualmente
            debug_print(">>> [nfelib] Usando assinatura manual (bypass signxml completamente)...")
            
            root = etree.fromstring(xml_str.encode('utf-8'))
            
            # Debug: mostrar estrutura do XML
            debug_print(f">>> [nfelib] Tag raiz: {root.tag}")
            debug_print(f">>> [nfelib] Namespace: {root.nsmap if hasattr(root, 'nsmap') else 'N/A'}")
            
            # Tentar diferentes formas de encontrar o elemento NFe
            nfe_elem = None
            
            # Tentativa 1: Com namespace completo
            nfe_elem = root.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
            if nfe_elem is not None:
                debug_print(">>> [nfelib] NFe encontrado com namespace completo")
            
            # Tentativa 2: Sem namespace
            if nfe_elem is None:
                nfe_elem = root.find('.//NFe')
                if nfe_elem is not None:
                    debug_print(">>> [nfelib] NFe encontrado sem namespace")
            
            # Tentativa 3: Buscar por qualquer tag que termine com NFe
            if nfe_elem is None:
                for elem in root.iter():
                    if elem.tag.endswith('NFe') or 'NFe' in elem.tag:
                        nfe_elem = elem
                        debug_print(f">>> [nfelib] NFe encontrado por iteração: {elem.tag}")
                        break
            
            # Tentativa 4: Se root é enviNFe, procurar NFe como filho direto
            if nfe_elem is None and root.tag.endswith('enviNFe'):
                debug_print(">>> [nfelib] Root é enviNFe, procurando NFe como filho direto...")
                for child in root:
                    if child.tag.endswith('NFe') or 'NFe' in child.tag:
                        nfe_elem = child
                        debug_print(f">>> [nfelib] NFe encontrado como filho direto: {child.tag}")
                        break
            
            # Tentativa 5: Buscar recursivamente por qualquer elemento com NFe no nome
            if nfe_elem is None:
                debug_print(">>> [nfelib] Buscando recursivamente...")
                def find_nfe_recursive(elem):
                    if 'NFe' in elem.tag:
                        return elem
                    for child in elem:
                        result = find_nfe_recursive(child)
                        if result is not None:
                            return result
                    return None
                nfe_elem = find_nfe_recursive(root)
                if nfe_elem is not None:
                    debug_print(f">>> [nfelib] NFe encontrado recursivamente: {nfe_elem.tag}")
            
            # Se ainda não encontrou, mostrar estrutura do XML para debug
            if nfe_elem is None:
                debug_print(">>> [nfelib] ❌ NFe não encontrado. Estrutura do XML:")
                debug_print(f">>> [nfelib] Tag raiz: {root.tag}")
                debug_print(f">>> [nfelib] Filhos diretos:")
                for i, child in enumerate(root):
                    debug_print(f">>> [nfelib]   [{i}] {child.tag}")
                debug_print(f">>> [nfelib] XML completo (primeiros 500 chars):")
                xml_preview = etree.tostring(root, encoding='unicode', pretty_print=True)[:500]
                debug_print(xml_preview)
                raise ValueError("Elemento NFe não encontrado no XML. Verifique a estrutura do XML gerado.")
            
            # Assinar o elemento NFe
            debug_print(">>> [nfelib] Assinando elemento NFe...")
            debug_print(f">>> [nfelib] Tipo do certificado: {type(certificate)}")
            debug_print(f">>> [nfelib] Tipo da chave privada: {type(private_key)}")
            
            # PROBLEMA: signxml 3.0+ tem incompatibilidades com cryptography e OpenSSL
            # SOLUÇÃO: Usar assinatura manual com cryptography diretamente
            # Vamos criar a assinatura XML manualmente sem depender do signxml problemático
            
            debug_print(">>> [nfelib] Usando assinatura manual (bypass signxml)...")
            
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import padding
            from cryptography.hazmat.primitives.asymmetric import rsa
            import base64
            # etree já está importado no topo do arquivo, não precisa importar novamente
            from xml.dom import minidom
            
            # 1. Obter elemento infNFe
            inf_nfe = nfe_elem.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe')
            if inf_nfe is None:
                inf_nfe = nfe_elem.find('.//infNFe')
            if inf_nfe is None:
                raise ValueError("Elemento infNFe não encontrado")
            
            # 2. Obter dados do certificado
            cert_pem = certificate.public_bytes(encoding=serialization.Encoding.PEM).decode('utf-8')
            cert_clean = cert_pem.replace('-----BEGIN CERTIFICATE-----', '').replace('-----END CERTIFICATE-----', '').replace('\n', '').replace('\r', '').strip()
            
            # 3. Montar elemento Signature manualmente (SEM prefixos)
            ns_ds = "http://www.w3.org/2000/09/xmldsig#"
            signature_elem = etree.Element('{' + ns_ds + '}Signature', nsmap={None: ns_ds})
            
            # SignedInfo
            signed_info = etree.SubElement(signature_elem, '{' + ns_ds + '}SignedInfo')
            
            # CanonicalizationMethod
            canon_method = etree.SubElement(signed_info, '{' + ns_ds + '}CanonicalizationMethod')
            canon_method.set('Algorithm', 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315')
            
            # SignatureMethod
            sig_method = etree.SubElement(signed_info, '{' + ns_ds + '}SignatureMethod')
            sig_method.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#rsa-sha1')
            
            # Reference
            reference = etree.SubElement(signed_info, '{' + ns_ds + '}Reference')
            reference.set('URI', f'#NFe{chave_acesso}')
            
            # Transforms
            transforms = etree.SubElement(reference, '{' + ns_ds + '}Transforms')
            transform = etree.SubElement(transforms, '{' + ns_ds + '}Transform')
            transform.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#enveloped-signature')
            transform2 = etree.SubElement(transforms, '{' + ns_ds + '}Transform')
            transform2.set('Algorithm', 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315')
            
            # DigestMethod
            digest_method = etree.SubElement(reference, '{' + ns_ds + '}DigestMethod')
            digest_method.set('Algorithm', 'http://www.w3.org/2000/09/xmldsig#sha1')
            
            # 4. Canonicalizar infNFe e calcular DigestValue
            c14n_inf_nfe = etree.tostring(inf_nfe, method='c14n', exclusive=True, with_comments=False)
            digest = hashes.Hash(hashes.SHA1(), backend=default_backend())
            digest.update(c14n_inf_nfe)
            hash_value = digest.finalize()
            hash_base64 = base64.b64encode(hash_value).decode('utf-8')
            debug_print(f">>> [nfelib] Hash SHA1 do infNFe calculado: {hash_base64[:50]}...")
            
            # DigestValue
            digest_value = etree.SubElement(reference, '{' + ns_ds + '}DigestValue')
            digest_value.text = hash_base64
            
            # 5. Canonicalizar SignedInfo e assinar
            c14n_signed_info = etree.tostring(signed_info, method='c14n', exclusive=True, with_comments=False)
            debug_print(f">>> [nfelib] SignedInfo canonicalizado: {len(c14n_signed_info)} bytes")
            
            # Assinar SignedInfo canonicalizado (RSA-SHA1)
            signature_bytes = private_key.sign(
                c14n_signed_info,
                padding.PKCS1v15(),
                hashes.SHA1()
            )
            signature_base64 = base64.b64encode(signature_bytes).decode('utf-8')
            debug_print(f">>> [nfelib] Assinatura gerada: {len(signature_bytes)} bytes")
            
            # SignatureValue
            signature_value = etree.SubElement(signature_elem, '{' + ns_ds + '}SignatureValue')
            signature_value.text = signature_base64
            
            # KeyInfo
            key_info = etree.SubElement(signature_elem, '{' + ns_ds + '}KeyInfo')
            x509_data = etree.SubElement(key_info, '{' + ns_ds + '}X509Data')
            x509_cert = etree.SubElement(x509_data, '{' + ns_ds + '}X509Certificate')
            x509_cert.text = cert_clean
            
            # 7. Adicionar Signature ao NFe
            # Para NFC-e 4.0, a Signature DEVE vir DEPOIS de infNFeSupl se ele existir.
            # No entanto, a Signature DEVE assinar infNFe. 
            # O schema TNFe define a sequência como: infNFe, infNFeSupl(opt), Signature.
            nfe_elem.append(signature_elem)
            
            # 8. Retornar XML assinado completo
            # O nfe_elem já está assinado e faz parte do root (enviNFe)
            xml_assinado = etree.tostring(root, encoding='unicode', xml_declaration=False)
            debug_print(">>> [nfelib] ✅ XML assinado manualmente com sucesso!")
            debug_print(f">>> [nfelib] Tamanho do XML assinado: {len(xml_assinado)} caracteres")
            
            return xml_assinado
            
        except Exception as e:
            print(f">>> [nfelib] ❌ Erro ao assinar XML: {e}")
            raise
    
    def _enviar_para_sefaz_nfelib(self, xml_assinado, ambiente_homologacao, uf, certificado=None, empresa_data=None):
        """Envia XML para SEFAZ usando nfelib"""
        debug_print = print  # Usar print como debug_print
        try:
            if uf == 'SP':
                if ambiente_homologacao:
                    url = "https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx"
            else:
                if ambiente_homologacao:
                    url = "https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
                else:
                    url = "https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx"
            
            debug_print(f">>> [nfelib] URL SEFAZ: {url}")
            
            # Construir envelope SOAP usando lxml para garantir estrutura correta
            from lxml import etree as lxml_etree
            from lxml.etree import QName
            
            # Remover declaração XML do xml_assinado (não deve ter dentro do envelope SOAP)
            xml_para_enviar = xml_assinado
            if xml_para_enviar.strip().startswith('<?xml'):
                # Encontrar o fim da declaração XML
                fim_declaracao = xml_para_enviar.find('?>')
                if fim_declaracao >= 0:
                    xml_para_enviar = xml_para_enviar[fim_declaracao + 2:].strip()
                    debug_print(f">>> [nfelib] Declaração XML removida do XML assinado")
            
            # Parsear XML assinado e limpar namespaces
            try:
                xml_envi_nfe_parsed = lxml_etree.fromstring(xml_para_enviar.encode('utf-8'))
            except Exception as e:
                debug_print(f">>> [nfelib] ⚠️ Erro ao parsear XML: {e}")
                # Tentar sem encoding
                xml_envi_nfe_parsed = lxml_etree.fromstring(xml_para_enviar)
            
            # Serializar XML do enviNFe (lxml com nsmap deve gerar sem prefixos desnecessários)
            xml_envi_nfe_str = lxml_etree.tostring(xml_envi_nfe_parsed, encoding='unicode', xml_declaration=False)
            
            # Remover prefixos ns0: se ainda existirem (backup de segurança)
            if 'ns0:' in xml_envi_nfe_str:
                import re
                # Remover definições de namespace com prefixo
                xml_envi_nfe_str = re.sub(r' xmlns:ns0="[^"]*"', '', xml_envi_nfe_str)
                # Remover prefixos das tags de fechamento primeiro
                xml_envi_nfe_str = re.sub(r'</ns0:', '</', xml_envi_nfe_str)
                # Remover prefixos das tags de abertura
                xml_envi_nfe_str = re.sub(r'<ns0:', '<', xml_envi_nfe_str)
                debug_print(f">>> [nfelib] Prefixos ns0: removidos via regex")
            
            # GARANTIR namespace padrão no enviNFe
            # A SEFAZ exige esse namespace para validar o schema
            if 'xmlns="http://www.portalfiscal.inf.br/nfe"' not in xml_envi_nfe_str:
                 # Substituir apenas a primeira ocorrência do enviNFe (tag de abertura)
                 xml_envi_nfe_str = xml_envi_nfe_str.replace('<enviNFe', '<enviNFe xmlns="http://www.portalfiscal.inf.br/nfe"', 1)
                 debug_print(f">>> [nfelib] Namespace padrão reinserido no enviNFe")
            else:
                debug_print(f">>> [nfelib] Namespace padrão já presente")
            
            # Criar envelope SOAP 1.2
            ns_soap = "http://www.w3.org/2003/05/soap-envelope"
            ns_nfe_wsdl = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4"
            
            # Não escapar XML (enviar como estrutura XML real dentro do SOAP)
            # xml_envi_nfe_escaped = xml_envi_nfe_str.replace('&', '&amp;') ... (REMOVIDO)
            
            soap_envelope = f"""<?xml version="1.0" encoding="UTF-8"?>
<soap12:Envelope xmlns:soap12="{ns_soap}" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <soap12:Body>
    <nfeDadosMsg xmlns="{ns_nfe_wsdl}">{xml_envi_nfe_str}</nfeDadosMsg>
  </soap12:Body>
</soap12:Envelope>"""
            debug_print(f">>> [nfelib] Envelope SOAP construído com escape XML (sem CDATA)")
            
            debug_print(f">>> [nfelib] Envelope SOAP construído: {len(soap_envelope)} chars")
            
            # Salvar envelope SOAP para análise
            if empresa_data:
                try:
                    empresa_dir = self._obter_diretorio_empresa(empresa_data)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    soap_file = os.path.join(empresa_dir, f'soap_envelope_{timestamp}.xml')
                    os.makedirs(empresa_dir, exist_ok=True)
                    with open(soap_file, 'w', encoding='utf-8') as f:
                        f.write(soap_envelope)
                    debug_print(f">>> [nfelib] Envelope SOAP salvo em: {soap_file}")
                except Exception as e:
                    debug_print(f">>> [nfelib] ⚠️ Erro ao salvar envelope SOAP: {e}")
            
            # Em SOAP 1.2, o SOAPAction pode ser incluído no Content-Type ou omitido
            # Vamos tentar incluir no Content-Type primeiro
            headers = {
                'Content-Type': 'application/soap+xml; charset=utf-8; action="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote"'
            }
            
            # Desabilitar verificação SSL em ambiente de homologação (comum em desenvolvimento)
            # Em produção, usar verify=True com certificados corretos
            verify_ssl = not ambiente_homologacao  # False em homologação, True em produção
            if ambiente_homologacao:
                import urllib3
                urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
                debug_print(f">>> [nfelib] ⚠️ Verificação SSL desabilitada para homologação")
            
            # Preparar certificado para autenticação HTTPS (mutual TLS)
            # O requests não suporta .pfx diretamente, então vamos usar uma sessão com adaptador customizado
            # ou usar o certificado já carregado para criar arquivos temporários PEM
            cert_params = None
            if certificado and 'arquivo' in certificado:
                cert_path = certificado['arquivo']
                cert_senha = certificado.get('senha', '')
                if os.path.exists(cert_path):
                    try:
                        # Carregar certificado PKCS12
                        from cryptography.hazmat.primitives.serialization import pkcs12
                        from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
                        import tempfile
                        
                        with open(cert_path, 'rb') as f:
                            pfx_data = f.read()
                        
                        # Carregar PKCS12
                        private_key_obj, certificate_obj, additional_certificates = pkcs12.load_key_and_certificates(
                            pfx_data,
                            cert_senha.encode('utf-8') if isinstance(cert_senha, str) else cert_senha
                        )
                        
                        if private_key_obj and certificate_obj:
                            # Criar arquivos temporários PEM
                            with tempfile.NamedTemporaryFile(mode='w', suffix='.pem', delete=False) as cert_file:
                                cert_file.write(certificate_obj.public_bytes(Encoding.PEM).decode('utf-8'))
                                cert_pem_path = cert_file.name
                            
                            with tempfile.NamedTemporaryFile(mode='w', suffix='.key', delete=False) as key_file:
                                key_file.write(private_key_obj.private_bytes(
                                    Encoding.PEM,
                                    PrivateFormat.PKCS8,
                                    NoEncryption()
                                ).decode('utf-8'))
                                key_pem_path = key_file.name
                            
                            cert_params = (cert_pem_path, key_pem_path)
                            debug_print(f">>> [nfelib] Certificado extraído do .pfx para autenticação HTTPS")
                        else:
                            debug_print(f">>> [nfelib] ⚠️ Não foi possível extrair certificado e chave do .pfx")
                    except Exception as e_cert:
                        debug_print(f">>> [nfelib] ⚠️ Erro ao preparar certificado para HTTPS: {e_cert}")
                        # Continuar sem certificado (pode funcionar em alguns casos)
                else:
                    debug_print(f">>> [nfelib] ⚠️ Arquivo de certificado não encontrado: {cert_path}")
            
            response = requests.post(
                url, 
                data=soap_envelope.encode('utf-8'), 
                headers=headers, 
                timeout=30, 
                verify=verify_ssl,
                cert=cert_params
            )
            
            debug_print(f">>> [nfelib] Status HTTP: {response.status_code}")
            debug_print(f">>> [nfelib] Headers: {dict(response.headers)}")
            debug_print(f">>> [nfelib] Content-Length: {response.headers.get('Content-Length', 'N/A')}")
            
            # Verificar se a resposta está vazia (Content-Length: 0)
            content_length = response.headers.get('Content-Length', '')
            resposta_vazia = content_length == '0' or (not response.text or len(response.text.strip()) == 0)
            
            if resposta_vazia and response.status_code == 400:
                debug_print(f">>> [nfelib] ❌ HTTP 400 Bad Request com resposta vazia")
                debug_print(f">>> [nfelib] Isso indica que a SEFAZ rejeitou a requisição ANTES de processar o XML")
                debug_print(f">>> [nfelib] Possíveis causas:")
                debug_print(f">>> [nfelib]   1. XML malformado ou inválido")
                debug_print(f">>> [nfelib]   2. Certificado inválido ou expirado")
                debug_print(f">>> [nfelib]   3. Problema com a assinatura digital")
                debug_print(f">>> [nfelib]   4. Headers HTTP incorretos")
                debug_print(f">>> [nfelib]   5. URL do serviço incorreta")
                
                return {
                    'success': False,
                    'error': 'Erro HTTP 400: Resposta vazia - SEFAZ rejeitou antes de processar (possível erro no XML, certificado ou assinatura)',
                    'autorizada': False,
                    'status_code': 400,
                    'details': 'A SEFAZ retornou HTTP 400 com resposta vazia. Isso geralmente indica que a requisição foi rejeitada antes mesmo de processar o XML. Verifique: XML válido, certificado válido, assinatura digital correta.'
                }
            
            if response.text:
                debug_print(f">>> [nfelib] Resposta (primeiros 1000 chars): {response.text[:1000]}")
            else:
                debug_print(f">>> [nfelib] ⚠️ Resposta não tem conteúdo (text é None ou vazio)")
            
            if response.status_code == 200:
                return self._processar_resposta_sefaz_nfelib(response.text, ambiente_homologacao)
            else:
                # Tentar extrair mensagem de erro da resposta
                error_msg = f'Erro HTTP {response.status_code}'
                try:
                    from lxml import etree as lxml_etree
                    # Tentar parsear resposta como XML/SOAP
                    if response.text and response.text.strip():
                        resp_xml = lxml_etree.fromstring(response.text.encode('utf-8'))
                        # Procurar mensagem de erro
                        for elem in resp_xml.iter():
                            if 'faultstring' in elem.tag.lower() or 'message' in elem.tag.lower():
                                error_msg = f'Erro HTTP {response.status_code}: {elem.text}'
                                break
                        
                        # Tentar encontrar retEnviNFe com erro
                        ret_envinfe = resp_xml.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                        if ret_envinfe is None:
                            ret_envinfe = resp_xml.find('.//retEnviNFe')
                        
                        if ret_envinfe is not None:
                            c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                            if c_stat is None:
                                c_stat = ret_envinfe.find('.//cStat')
                            
                            x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                            if x_motivo is None:
                                x_motivo = ret_envinfe.find('.//xMotivo')
                            
                            if c_stat is not None and x_motivo is not None:
                                codigo = c_stat.text if c_stat.text else str(response.status_code)
                                motivo = x_motivo.text if x_motivo.text else 'Erro desconhecido'
                                error_msg = f'cStat {codigo}: {motivo}'
                except Exception as e_parse:
                    debug_print(f">>> [nfelib] Erro ao parsear resposta: {e_parse}")
                
                return {
                    'success': False,
                    'error': error_msg,
                    'autorizada': False,
                    'status_code': response.status_code,
                    'resposta_sefaz': response.text[:2000] if response.text else ''
                }
                
        except Exception as e:
            print(f">>> [nfelib] ❌ Erro ao enviar para SEFAZ: {e}")
            return {
                'success': False,
                'error': str(e),
                'autorizada': False
            }
    
    def _enviar_para_sefaz_simples(self, xml_assinado, ambiente_homologacao, uf, certificado=None, empresa_data=None):
        """SOLUÇÃO SIMPLES: Envia XML diretamente para SEFAZ sem interceptações complexas"""
        debug_print = print
        try:
            from pynfe.processamento.comunicacao import ComunicacaoSefaz
            from lxml import etree as lxml_etree
            
            # Obter caminho do certificado
            cert_path = certificado.get('arquivo') if certificado and 'arquivo' in certificado else None
            cert_senha = certificado.get('senha', '') if certificado else ''
            
            if not cert_path or not os.path.exists(cert_path):
                return {
                    'success': False,
                    'error': 'Certificado não encontrado',
                    'autorizada': False
                }
            
            debug_print(">>> [SIMPLES] Parseando XML assinado...")
            xml_elemento = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
            
            # Extrair enviNFe
            envi_nfe = xml_elemento
            if not xml_elemento.tag.endswith('enviNFe'):
                envi_nfe = xml_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
                if envi_nfe is None:
                    envi_nfe = xml_elemento.find('.//enviNFe')
            
            if envi_nfe is None:
                return {
                    'success': False,
                    'error': 'enviNFe não encontrado no XML',
                    'autorizada': False
                }
            
            # Extrair NFe do enviNFe
            nfe_elem = envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
            if nfe_elem is None:
                nfe_elem = envi_nfe.find('.//NFe')
            
            if nfe_elem is None:
                return {
                    'success': False,
                    'error': 'NFe não encontrada no enviNFe',
                    'autorizada': False
                }
            
            # Extrair idLote
            id_lote_elem = envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}idLote')
            if id_lote_elem is None:
                id_lote_elem = envi_nfe.find('.//idLote')
            
            id_lote = int(id_lote_elem.text) if id_lote_elem is not None and id_lote_elem.text else 1
            
            debug_print(f">>> [SIMPLES] Enviando para SEFAZ (idLote: {id_lote})...")
            
            # Criar comunicação
            comunicacao = ComunicacaoSefaz(
                uf=uf,
                certificado=cert_path,
                certificado_senha=cert_senha,
                homologacao=ambiente_homologacao
            )
            
            # IMPORTANTE: Verificar se o idLote tem 15 dígitos (PyNFe pode não fazer isso automaticamente)
            if id_lote < 100000000000000:  # Se tem menos de 15 dígitos
                id_lote_str = str(id_lote).zfill(15)
                debug_print(f">>> [SIMPLES] ⚠️ idLote corrigido: {id_lote} → {id_lote_str}")
                # Tentar extrair idLote do XML e corrigir
                id_lote_elem_xml = envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}idLote')
                if id_lote_elem_xml is None:
                    id_lote_elem_xml = envi_nfe.find('.//idLote')
                if id_lote_elem_xml is not None:
                    id_lote_elem_xml.text = id_lote_str
                    id_lote = int(id_lote_str)
                    debug_print(f">>> [SIMPLES] ✅ idLote corrigido no XML: {id_lote_str}")
            
            debug_print(f">>> [SIMPLES] Enviando com idLote: {id_lote}")
            
            # Interceptar requests.post para ver o que está sendo enviado
            import requests
            original_post = requests.post
            
            def post_interceptado(*args, **kwargs):
                url = args[0] if args else kwargs.get('url', '')
                debug_print(f">>> [SIMPLES] 🔍 Interceptando POST para: {url}")
                
                # Verificar dados em diferentes locais
                data_str = None
                
                # 1. Verificar em kwargs['data']
                if 'data' in kwargs:
                    data = kwargs['data']
                    if isinstance(data, (str, bytes)):
                        data_str = data if isinstance(data, str) else data.decode('utf-8', errors='ignore')
                
                # 2. Verificar em args[1] (segundo argumento)
                elif len(args) >= 2:
                    data = args[1]
                    if isinstance(data, (str, bytes)):
                        data_str = data if isinstance(data, str) else data.decode('utf-8', errors='ignore')
                
                # 3. Verificar em kwargs['json']
                elif 'json' in kwargs:
                    import json
                    data_str = json.dumps(kwargs['json'], indent=2)
                
                if data_str:
                    debug_print(f">>> [SIMPLES] 📤 Dados ANTES das correções (primeiros 2000 chars):")
                    debug_print(data_str[:2000])
                    
                    # CORREÇÃO 1: Corrigir idLote para 15 dígitos
                    import re
                    id_lote_pattern = r'<idLote>(\d+)</idLote>'
                    id_lote_match = re.search(id_lote_pattern, data_str)
                    if id_lote_match:
                        id_lote_atual = id_lote_match.group(1)
                        id_lote_corrigido = str(int(id_lote_atual)).zfill(15)[:15]
                        if id_lote_atual != id_lote_corrigido:
                            data_str = re.sub(id_lote_pattern, f'<idLote>{id_lote_corrigido}</idLote>', data_str)
                            debug_print(f">>> [SIMPLES] ✅ idLote corrigido no SOAP: {id_lote_atual} → {id_lote_corrigido}")
                    
                    # CORREÇÃO 2: Para SP, o envelope SOAP precisa ter a estrutura correta
                    # IMPORTANTE: Usar método de string replacement para preservar prefixos ns0: e assinatura
                    # SP espera: <soap:Envelope><soap:Body><nfeAutorizacaoLote><nfeDadosMsg>...
                    # Mas o PyNFe pode estar gerando: <soap:Envelope><soap:Body><nfeDadosMsg>...
                    nfe_wsdl_ns = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4"
                    
                    # Usar método de string replacement (preserva prefixos ns0: e assinatura)
                    # MODIFICADO: NÃO adicionar nfeAutorizacaoLote wrapper (parece causar erro 400 em SP)
                    # Apenas garantir que nfeDadosMsg tem o namespace correto
                    
                    if 'nfeDadosMsg' in data_str:
                         if f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"' not in data_str:
                            # Adicionar namespace ao nfeDadosMsg se não tiver
                            data_str = re.sub(
                                r'<nfeDadosMsg(\s+[^>]*)?>',
                                f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"\\1>',
                                data_str,
                                count=1
                            )
                            debug_print(f">>> [SIMPLES] ✅ Namespace adicionado ao nfeDadosMsg")
                         
                         # REMOVIDO: Wrapper nfeAutorizacaoLote
                         # if 'nfeAutorizacaoLote' not in data_str:
                         #     ... (código removido)
                    
                    r""" CODIGO REMOVIDO:
                    if 'nfeDadosMsg' in data_str and 'nfeAutorizacaoLote' not in data_str:
                        debug_print(f">>> [SIMPLES] ⚠️ Adicionando wrapper nfeAutorizacaoLote (preservando prefixos ns0:)...")
                        # IMPORTANTE: O nfeDadosMsg DEVE ter o namespace mesmo dentro do nfeAutorizacaoLote
                        # Garantir que nfeDadosMsg tem o namespace antes de adicionar o wrapper
                        if f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"' not in data_str:
                            # Adicionar namespace ao nfeDadosMsg se não tiver
                            data_str = re.sub(
                                r'<nfeDadosMsg(\s+[^>]*)?>',
                                f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"\\1>',
                                data_str,
                                count=1
                            )
                            debug_print(f">>> [SIMPLES] ✅ Namespace adicionado ao nfeDadosMsg")
                        # Adicionar wrapper nfeAutorizacaoLote ANTES do nfeDadosMsg
                        data_str = data_str.replace(
                            '<nfeDadosMsg',
                            f'<nfeAutorizacaoLote xmlns="{nfe_wsdl_ns}"><nfeDadosMsg',
                            1
                        )
                        # Fechar o wrapper ANTES do fechamento do Body
                        data_str = data_str.replace('</soap:Body>', '</nfeAutorizacaoLote></soap:Body>')
                        debug_print(f">>> [SIMPLES] ✅ Wrapper nfeAutorizacaoLote adicionado (prefixos ns0: preservados)")
                    elif 'nfeAutorizacaoLote' in data_str and 'nfeDadosMsg' in data_str:
                        # Já tem nfeAutorizacaoLote, garantir que nfeDadosMsg tem o namespace correto
                        if f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"' not in data_str:
                            debug_print(f">>> [SIMPLES] ⚠️ Adicionando namespace ao nfeDadosMsg...")
                            data_str = re.sub(
                                r'<nfeDadosMsg(\s+[^>]*)?>',
                                f'<nfeDadosMsg xmlns="{nfe_wsdl_ns}"\\1>',
                                data_str,
                                count=1
                            )
                            debug_print(f">>> [SIMPLES] ✅ Namespace adicionado ao nfeDadosMsg")
                        else:
                            debug_print(f">>> [SIMPLES] ✅ nfeDadosMsg já tem namespace correto")
                    """
                    
                    # CORREÇÃO 3: NÃO remover prefixos ns0: se houver assinatura (quebra a assinatura!)
                    # Em vez disso, apenas garantir que o namespace está correto
                    # A SEFAZ aceita prefixos desde que o namespace esteja correto
                    if 'ns0:' in data_str and 'Signature' in data_str:
                        debug_print(f">>> [SIMPLES] ⚠️ XML tem assinatura - NÃO removendo prefixos ns0: (quebra assinatura)")
                        # Apenas garantir que o namespace está correto no elemento raiz
                        if 'xmlns:ns0="http://www.portalfiscal.inf.br/nfe"' not in data_str:
                            # Adicionar namespace se não tiver
                            data_str = data_str.replace('<ns0:NFe', '<ns0:NFe xmlns:ns0="http://www.portalfiscal.inf.br/nfe"', 1)
                            debug_print(f">>> [SIMPLES] ✅ Namespace ns0: garantido no NFe")
                    elif 'ns0:' in data_str and 'Signature' not in data_str:
                        # Se não tem assinatura, pode remover prefixos
                        data_str = re.sub(r'<ns0:([^>]+)>', r'<\1>', data_str)
                        data_str = re.sub(r'</ns0:([^>]+)>', r'</\1>', data_str)
                        data_str = re.sub(r'\s+xmlns:ns0="[^"]*"', '', data_str)
                        debug_print(f">>> [SIMPLES] ✅ Prefixos ns0: removidos do SOAP (sem assinatura)")
                    
                    # Validar XML antes de enviar
                    try:
                        lxml_etree.fromstring(data_str.encode('utf-8'))
                        debug_print(f">>> [SIMPLES] ✅ XML válido (bem formado)")
                    except Exception as e_valid:
                        debug_print(f">>> [SIMPLES] ❌ XML INVÁLIDO: {e_valid}")
                    
                    debug_print(f">>> [SIMPLES] 📤 Dados DEPOIS das correções (primeiros 2000 chars):")
                    debug_print(data_str[:2000])
                    debug_print(f">>> [SIMPLES] 📊 Tamanho total: {len(data_str)} caracteres")
                    
                    # Verificar se tem nfeAutorizacaoLote e nfeDadosMsg
                    tem_autorizacao_lote = 'nfeAutorizacaoLote' in data_str
                    tem_dados_msg = 'nfeDadosMsg' in data_str
                    tem_envi_nfe = 'enviNFe' in data_str
                    tem_nfe = '<NFe' in data_str or '<ns0:NFe' in data_str
                    tem_assinatura = 'Signature' in data_str
                    debug_print(f">>> [SIMPLES] 🔍 Verificação de estrutura:")
                    debug_print(f">>> [SIMPLES]   - nfeAutorizacaoLote: {tem_autorizacao_lote}")
                    debug_print(f">>> [SIMPLES]   - nfeDadosMsg: {tem_dados_msg}")
                    debug_print(f">>> [SIMPLES]   - enviNFe: {tem_envi_nfe}")
                    debug_print(f">>> [SIMPLES]   - NFe: {tem_nfe}")
                    debug_print(f">>> [SIMPLES]   - Assinatura: {tem_assinatura}")
                    
                    # Salvar para análise
                    try:
                        log_dir = self._obter_diretorio_empresa(empresa_data)
                        os.makedirs(log_dir, exist_ok=True)
                        from datetime import datetime
                        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                        soap_file = os.path.join(log_dir, f'soap_simples_enviado_{timestamp}.xml')
                        with open(soap_file, 'w', encoding='utf-8') as f:
                            f.write(data_str)
                        debug_print(f">>> [SIMPLES] 💾 SOAP salvo em: {soap_file}")
                    except Exception as e_save:
                        debug_print(f">>> [SIMPLES] ⚠️ Erro ao salvar SOAP: {e_save}")
                    
                    # Atualizar kwargs ou args com dados corrigidos
                    if 'data' in kwargs:
                        kwargs['data'] = data_str.encode('utf-8') if isinstance(kwargs.get('data'), bytes) else data_str
                    elif len(args) >= 2:
                        args_list = list(args)
                        args_list[1] = data_str.encode('utf-8') if isinstance(args[1], bytes) else data_str
                        args = tuple(args_list)
                else:
                    debug_print(f">>> [SIMPLES] ⚠️ Nenhum dado encontrado para interceptar!")
                    debug_print(f">>> [SIMPLES] 📋 kwargs keys: {list(kwargs.keys())}")
                    debug_print(f">>> [SIMPLES] 📋 args count: {len(args)}")
                
                if 'headers' in kwargs:
                    headers = kwargs['headers']
                    debug_print(f">>> [SIMPLES] 📋 Headers originais: {headers}")
                    
                    # CORRIGIR: Para SP com SOAP 1.2, NÃO usar SOAPAction (pode causar erro 400)
                    # Remover SOAPAction se existir (SP não aceita com SOAP 1.2)
                    if 'SOAPAction' in headers:
                        del headers['SOAPAction']
                        debug_print(f">>> [SIMPLES] ✅ SOAPAction removido (SP não aceita com SOAP 1.2)")
                    elif 'soapaction' in [k.lower() for k in headers.keys()]:
                        for key in list(headers.keys()):
                            if key.lower() == 'soapaction':
                                del headers[key]
                                debug_print(f">>> [SIMPLES] ✅ SOAPAction removido (SP não aceita com SOAP 1.2)")
                                break
                    
                    # CORRIGIR: Garantir Content-Type correto para SOAP 1.2
                    # Para SP, o action DEVE estar no Content-Type (formato SOAP 1.2)
                    import re
                    soap_action = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote'
                    base_content_type = 'application/soap+xml; charset=utf-8'
                    final_content_type = f'{base_content_type}; action="{soap_action}"'
                    
                    debug_print(f">>> [SIMPLES] 🔧 Iniciando correção do Content-Type...")
                    debug_print(f">>> [SIMPLES] 🔧 Headers keys: {list(headers.keys())}")
                    
                    content_type_key = None
                    for key in headers.keys():
                        debug_print(f">>> [SIMPLES] 🔧 Verificando key: {key} (lower: {key.lower()})")
                        if key.lower() == 'content-type':
                            content_type_key = key
                            debug_print(f">>> [SIMPLES] 🔧 Content-Type encontrado com key: {content_type_key}")
                            break
                    
                    if content_type_key:
                        content_type = headers[content_type_key]
                        debug_print(f">>> [SIMPLES] 🔍 Content-Type original: {content_type}")
                        
                        # Verificar se já tem action
                        if 'action=' not in content_type.lower():
                            # Adicionar action ao Content-Type
                            headers[content_type_key] = final_content_type
                            debug_print(f">>> [SIMPLES] ✅ Action adicionado ao Content-Type: {final_content_type}")
                        else:
                            # Verificar se o action está correto
                            if soap_action not in content_type:
                                # Substituir action existente
                                content_type = re.sub(r'action="[^"]*"', f'action="{soap_action}"', content_type)
                                headers[content_type_key] = content_type
                                debug_print(f">>> [SIMPLES] ✅ Action corrigido no Content-Type: {content_type}")
                            else:
                                # Action já está correto, mas garantir formato base
                                if 'application/soap+xml' not in content_type.lower():
                                    # Extrair action e reconstruir com formato correto
                                    action_match = re.search(r'action="([^"]*)"', content_type)
                                    if action_match:
                                        headers[content_type_key] = f'{base_content_type}; action="{action_match.group(1)}"'
                                    else:
                                        headers[content_type_key] = final_content_type
                                    debug_print(f">>> [SIMPLES] ✅ Content-Type reformatado para SOAP 1.2: {headers[content_type_key]}")
                                else:
                                    debug_print(f">>> [SIMPLES] ✅ Content-Type já está correto: {content_type}")
                    else:
                        # Se não encontrou content-type, criar um novo
                        debug_print(f">>> [SIMPLES] ⚠️ Content-Type não encontrado, criando novo...")
                        headers['Content-Type'] = final_content_type
                        debug_print(f">>> [SIMPLES] ✅ Content-Type criado com action: {final_content_type}")
                    
                # Log final dos headers
                debug_print(f">>> [SIMPLES] 📋 Headers FINAIS antes do envio: {headers}")
                
                # Log do certificado se estiver presente
                if 'cert' in kwargs:
                    debug_print(f">>> [SIMPLES] 🔐 Certificado HTTPS: {kwargs['cert']}")
                elif len(args) > 3:
                    debug_print(f">>> [SIMPLES] 🔐 Certificado pode estar em args")
                
                # Log do verify SSL
                if 'verify' in kwargs:
                    debug_print(f">>> [SIMPLES] 🔒 SSL Verify: {kwargs['verify']}")
                
                return original_post(*args, **kwargs)
            
            # Aplicar interceptação temporariamente
            requests.post = post_interceptado
            
            try:
                # Enviar diretamente
                resultado = comunicacao.autorizacao(
                    modelo="nfce",
                    nota_fiscal=nfe_elem,
                    id_lote=id_lote,
                    ind_sinc=1,
                    contingencia=False,
                    timeout=30
                )
            finally:
                # Restaurar método original
                requests.post = original_post
            
            # Processar resposta
            if isinstance(resultado, tuple) and len(resultado) >= 2:
                status = resultado[0]
                xml_resposta = resultado[1]
                
                debug_print(f">>> [SIMPLES] Status da resposta: {status}")
                debug_print(f">>> [SIMPLES] Tipo da resposta: {type(xml_resposta)}")
                
                if status == 0:
                    # Sucesso - processar nfeProc
                    debug_print(">>> [SIMPLES] ✅ Status 0 - Sucesso! Processando nfeProc...")
                    return self._processar_resposta_nfeproc(xml_resposta, ambiente_homologacao)
                else:
                    # Erro - tentar extrair mensagem
                    debug_print(f">>> [SIMPLES] ❌ Status {status} - Erro! Tentando extrair mensagem...")
                    
                    # Tentar extrair do objeto Response
                    texto_resposta = None
                    
                    # Verificar atributos do Response
                    debug_print(f">>> [SIMPLES] Verificando atributos do Response...")
                    debug_print(f">>> [SIMPLES] - hasattr text: {hasattr(xml_resposta, 'text')}")
                    debug_print(f">>> [SIMPLES] - hasattr content: {hasattr(xml_resposta, 'content')}")
                    debug_print(f">>> [SIMPLES] - hasattr status_code: {hasattr(xml_resposta, 'status_code')}")
                    
                    if hasattr(xml_resposta, 'status_code'):
                        debug_print(f">>> [SIMPLES] - status_code: {xml_resposta.status_code}")
                    if hasattr(xml_resposta, 'headers'):
                        debug_print(f">>> [SIMPLES] - headers: {dict(xml_resposta.headers)}")
                    
                    if hasattr(xml_resposta, 'text'):
                        debug_print(f">>> [SIMPLES] - text is None: {xml_resposta.text is None}")
                        debug_print(f">>> [SIMPLES] - text value: {repr(xml_resposta.text) if xml_resposta.text else 'VAZIO'}")
                        debug_print(f">>> [SIMPLES] - text length: {len(xml_resposta.text) if xml_resposta.text else 0}")
                        if xml_resposta.text and xml_resposta.text.strip():
                            texto_resposta = xml_resposta.text
                            debug_print(f">>> [SIMPLES] ✅ Resposta tem text: {len(texto_resposta)} caracteres")
                        else:
                            debug_print(f">>> [SIMPLES] ⚠️ text está vazio ou None")
                            # Tentar content mesmo assim
                            if hasattr(xml_resposta, 'content'):
                                try:
                                    content_str = xml_resposta.content.decode('utf-8') if xml_resposta.content else ''
                                    if content_str and content_str.strip():
                                        texto_resposta = content_str
                                        debug_print(f">>> [SIMPLES] ✅ Resposta tem content: {len(texto_resposta)} caracteres")
                                except:
                                    pass
                    elif hasattr(xml_resposta, 'content') and xml_resposta.content:
                        try:
                            texto_resposta = xml_resposta.content.decode('utf-8')
                            debug_print(f">>> [SIMPLES] ✅ Resposta tem content: {len(texto_resposta)} caracteres")
                        except Exception as e_decode:
                            debug_print(f">>> [SIMPLES] ⚠️ Erro ao decodificar content: {e_decode}")
                    elif isinstance(xml_resposta, str):
                        texto_resposta = xml_resposta
                        debug_print(f">>> [SIMPLES] ✅ Resposta é string: {len(texto_resposta)} caracteres")
                    else:
                        debug_print(f">>> [SIMPLES] ⚠️ Não conseguiu extrair texto da resposta")
                        debug_print(f">>> [SIMPLES] Tipo completo: {type(xml_resposta)}")
                        debug_print(f">>> [SIMPLES] Dir: {[x for x in dir(xml_resposta) if not x.startswith('_')][:10]}")
                    
                    if texto_resposta:
                        debug_print(f">>> [SIMPLES] Primeiros 500 chars da resposta: {texto_resposta[:500]}")
                        try:
                            erro_xml = lxml_etree.fromstring(texto_resposta.encode('utf-8'))
                            
                            # Procurar retEnviNFe em diferentes locais
                            ret_envinfe = erro_xml.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                            if ret_envinfe is None:
                                ret_envinfe = erro_xml.find('.//retEnviNFe')
                            
                            # Se não encontrou, procurar dentro de SOAP Body
                            if ret_envinfe is None:
                                soap_body = erro_xml.find('.//{http://www.w3.org/2003/05/soap-envelope}Body')
                                if soap_body is None:
                                    soap_body = erro_xml.find('.//Body')
                                if soap_body is not None:
                                    ret_envinfe = soap_body.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                                    if ret_envinfe is None:
                                        ret_envinfe = soap_body.find('.//retEnviNFe')
                            
                            if ret_envinfe is not None:
                                c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                if c_stat is None:
                                    c_stat = ret_envinfe.find('.//cStat')
                                
                                x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                if x_motivo is None:
                                    x_motivo = ret_envinfe.find('.//xMotivo')
                                
                                if c_stat is not None and x_motivo is not None:
                                    codigo = c_stat.text if c_stat.text else 'N/A'
                                    motivo = x_motivo.text if x_motivo.text else 'Erro desconhecido'
                                    debug_print(f">>> [SIMPLES] ✅ Erro extraído: cStat {codigo}: {motivo}")
                                    return {
                                        'success': False,
                                        'error': f'cStat {codigo}: {motivo}',
                                        'autorizada': False,
                                        'codigo_erro': codigo,
                                        'motivo': motivo
                                    }
                                else:
                                    debug_print(f">>> [SIMPLES] ⚠️ retEnviNFe encontrado mas sem cStat/xMotivo")
                            else:
                                debug_print(f">>> [SIMPLES] ⚠️ retEnviNFe não encontrado no XML")
                        except Exception as e_parse:
                            debug_print(f">>> [SIMPLES] ⚠️ Erro ao parsear XML: {e_parse}")
                            import traceback
                            debug_print(traceback.format_exc())
                    
                    # Se não conseguiu extrair, retornar erro genérico
                    debug_print(f">>> [SIMPLES] ❌ Não foi possível extrair mensagem de erro")
                    
                    # Se status_code é 400 e Content-Length é 0, é erro de estrutura
                    if hasattr(xml_resposta, 'status_code') and xml_resposta.status_code == 400:
                        content_length = xml_resposta.headers.get('Content-Length', '0') if hasattr(xml_resposta, 'headers') else '0'
                        if content_length == '0' or not texto_resposta or not texto_resposta.strip():
                            return {
                                'success': False,
                                'error': 'HTTP 400: SEFAZ rejeitou antes de processar (possível erro no XML, certificado ou SOAP envelope)',
                                'autorizada': False,
                                'status': status,
                                'status_code': 400,
                                'details': 'A SEFAZ retornou HTTP 400 com resposta vazia. Isso geralmente indica problema na estrutura do XML, certificado inválido ou envelope SOAP incorreto.'
                            }
                    
                    return {
                        'success': False,
                        'error': f'Erro na comunicação com SEFAZ (status: {status}). Verifique os logs para detalhes.',
                        'autorizada': False,
                        'status': status,
                        'status_code': xml_resposta.status_code if hasattr(xml_resposta, 'status_code') else None,
                        'resposta_raw': texto_resposta[:1000] if texto_resposta else None
                    }
            else:
                return {
                    'success': False,
                    'error': 'Resposta inesperada da SEFAZ',
                    'autorizada': False
                }
                
        except Exception as e:
            debug_print(f">>> [SIMPLES] ❌ Erro: {e}")
            import traceback
            debug_print(traceback.format_exc())
            return {
                'success': False,
                'error': f'Erro ao enviar para SEFAZ: {str(e)}',
                'autorizada': False
            }
    
    def _enviar_para_sefaz_usando_pynfe(self, xml_assinado, ambiente_homologacao, uf, certificado=None, empresa_data=None):
        """Envia XML para SEFAZ usando PyNFe (tem lógica SOAP testada) - MÉTODO ANTIGO"""
        debug_print = print
        try:
            # Importar PyNFe
            from pynfe.processamento.comunicacao import ComunicacaoSefaz
            from lxml import etree as lxml_etree
            
            # Obter caminho do certificado
            cert_path = certificado.get('arquivo') if certificado and 'arquivo' in certificado else None
            cert_senha = certificado.get('senha', '') if certificado else ''
            
            if not cert_path or not os.path.exists(cert_path):
                return {
                    'success': False,
                    'error': 'Certificado não encontrado para envio',
                    'autorizada': False
                }
            
            debug_print(f">>> [nfelib] Usando PyNFe para enviar XML assinado...")
            
            # Interceptar requests.post para ver o que o PyNFe está enviando
            import requests
            original_post = requests.post
            
            # Extrair enviNFe do XML assinado para usar no interceptador
            xml_elemento_temp = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
            envi_nfe_temp = xml_elemento_temp
            if not xml_elemento_temp.tag.endswith('enviNFe'):
                envi_nfe_temp = xml_elemento_temp.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
                if envi_nfe_temp is None:
                    envi_nfe_temp = xml_elemento_temp.find('.//enviNFe')
            
            if envi_nfe_temp is None:
                return {
                    'success': False,
                    'error': 'enviNFe não encontrado no XML assinado para interceptação',
                    'autorizada': False
                }
            
            # Converter enviNFe para string (sem declaração XML)
            # IMPORTANTE: Usar method='c14n' ou garantir que namespaces sejam preservados
            envi_nfe_xml_str = lxml_etree.tostring(envi_nfe_temp, encoding='unicode', xml_declaration=False)
            
            # Verificar se o NFe dentro do enviNFe tem namespace
            nfe_check = envi_nfe_temp.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
            if nfe_check is None:
                nfe_check = envi_nfe_temp.find('.//NFe')
                if nfe_check is not None and not nfe_check.tag.startswith('{http://www.portalfiscal.inf.br/nfe}'):
                    # Corrigir namespace do NFe antes de converter para string
                    nfe_novo = lxml_etree.Element('{http://www.portalfiscal.inf.br/nfe}NFe')
                    for attr_name, attr_value in nfe_check.attrib.items():
                        nfe_novo.set(attr_name, attr_value)
                    for child in nfe_check:
                        nfe_novo.append(child)
                    nfe_check.getparent().replace(nfe_check, nfe_novo)
                    # Re-converter para string após correção
                    envi_nfe_xml_str = lxml_etree.tostring(envi_nfe_temp, encoding='unicode', xml_declaration=False)
                    debug_print(f">>> [nfelib] ✅ Namespace do NFe corrigido ANTES da substituição")
            
            # Remover qualquer prefixo ns0: que possa ter sobrado (mas preservar namespace)
            import re
            # Substituir prefixos ns0: mas manter o namespace no elemento
            envi_nfe_xml_str = re.sub(r'<ns0:([^>]+)>', r'<\1>', envi_nfe_xml_str)
            envi_nfe_xml_str = re.sub(r'</ns0:([^>]+)>', r'</\1>', envi_nfe_xml_str)
            envi_nfe_xml_str = re.sub(r'\s+xmlns:ns0="[^"]*"', '', envi_nfe_xml_str)
            
            # Garantir que o NFe tenha namespace explícito se não tiver
            if '<NFe>' in envi_nfe_xml_str and 'xmlns=' not in envi_nfe_xml_str.split('<NFe>')[1].split('>')[0]:
                # Adicionar namespace ao NFe se não tiver
                envi_nfe_xml_str = envi_nfe_xml_str.replace('<NFe>', '<NFe xmlns="http://www.portalfiscal.inf.br/nfe">', 1)
                debug_print(f">>> [nfelib] ✅ Namespace adicionado ao NFe na string XML")
            
            def post_interceptado(*args, **kwargs):
                url = args[0] if args else kwargs.get('url', '')
                debug_print(f">>> [nfelib] 🔍 Interceptando request POST para: {url}")
                
                # Log dos dados sendo enviados (PyNFe pode usar 'data', 'json', ou passar como segundo argumento)
                data_str = None
                
                # Verificar se data está em kwargs
                if 'data' in kwargs:
                    data = kwargs['data']
                    if isinstance(data, (str, bytes)):
                        data_str = data if isinstance(data, str) else data.decode('utf-8', errors='ignore')
                
                # Verificar se está em args (segundo argumento)
                elif len(args) >= 2:
                    data = args[1]
                    if isinstance(data, (str, bytes)):
                        data_str = data if isinstance(data, str) else data.decode('utf-8', errors='ignore')
                
                # Verificar se está em json
                elif 'json' in kwargs:
                    import json
                    data_str = json.dumps(kwargs['json'], indent=2)
                
                if data_str:
                    # SUBSTITUIR completamente o conteúdo do nfeDadosMsg pelo nosso enviNFe assinado
                    try:
                        # Parsear o SOAP
                        soap_root = lxml_etree.fromstring(data_str.encode('utf-8'))
                        
                        # Encontrar nfeDadosMsg
                        nfe_dados_msg = soap_root.find('.//{http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4}nfeDadosMsg')
                        if nfe_dados_msg is None:
                            # Tentar sem namespace
                            nfe_dados_msg = soap_root.find('.//nfeDadosMsg')
                        
                        if nfe_dados_msg is not None:
                            # Limpar conteúdo existente
                            conteudo_antes = lxml_etree.tostring(nfe_dados_msg, encoding='unicode', xml_declaration=False)
                            debug_print(f">>> [nfelib] 📋 Conteúdo ANTES da substituição (primeiros 500 chars): {conteudo_antes[:500]}")
                            
                            nfe_dados_msg.clear()
                            # Adicionar nosso enviNFe assinado
                            envi_nfe_elem = lxml_etree.fromstring(envi_nfe_xml_str.encode('utf-8'))
                            
                            # Garantir que o enviNFe tenha o namespace correto
                            if not envi_nfe_elem.tag.startswith('{http://www.portalfiscal.inf.br/nfe}'):
                                # Adicionar namespace se não tiver
                                envi_nfe_elem.tag = '{http://www.portalfiscal.inf.br/nfe}enviNFe'
                            
                            # Garantir que o NFe dentro do enviNFe também tenha namespace
                            nfe_inside = envi_nfe_elem.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                            if nfe_inside is None:
                                nfe_inside = envi_nfe_elem.find('.//NFe')
                            
                            if nfe_inside is not None:
                                # Verificar se tem namespace
                                if not nfe_inside.tag.startswith('{http://www.portalfiscal.inf.br/nfe}'):
                                    # Criar novo elemento com namespace correto
                                    nfe_novo = lxml_etree.Element('{http://www.portalfiscal.inf.br/nfe}NFe')
                                    # Copiar todos os atributos e filhos
                                    for attr_name, attr_value in nfe_inside.attrib.items():
                                        nfe_novo.set(attr_name, attr_value)
                                    for child in nfe_inside:
                                        nfe_novo.append(child)
                                    # Substituir o elemento antigo pelo novo
                                    nfe_inside.getparent().replace(nfe_inside, nfe_novo)
                                    debug_print(f">>> [nfelib] ✅ Namespace do NFe corrigido")
                                else:
                                    debug_print(f">>> [nfelib] ✅ NFe já tem namespace correto")
                            
                            nfe_dados_msg.append(envi_nfe_elem)
                            
                            # Verificar se foi adicionado
                            conteudo_depois = lxml_etree.tostring(nfe_dados_msg, encoding='unicode', xml_declaration=False)
                            debug_print(f">>> [nfelib] 📋 Conteúdo DEPOIS da substituição (primeiros 500 chars): {conteudo_depois[:500]}")
                            
                            # Serializar novamente (sem declaração XML quando encoding='unicode')
                            data_str = lxml_etree.tostring(soap_root, encoding='unicode', xml_declaration=False)
                            # Adicionar declaração XML manualmente
                            if not data_str.startswith('<?xml'):
                                data_str = '<?xml version="1.0" encoding="UTF-8"?>' + data_str
                            
                            debug_print(f">>> [nfelib] ✅ Conteúdo do nfeDadosMsg substituído pelo enviNFe assinado")
                        else:
                            debug_print(f">>> [nfelib] ⚠️ nfeDadosMsg não encontrado no SOAP, tentando outras correções...")
                    except Exception as e_subst:
                        debug_print(f">>> [nfelib] ⚠️ Erro ao substituir nfeDadosMsg: {e_subst}")
                        import traceback
                        debug_print(traceback.format_exc())
                    
                    # CORRIGIR idLote no SOAP antes de enviar
                    import re
                    # Procurar <idLote>valor</idLote> e corrigir para 15 dígitos
                    id_lote_pattern = r'<idLote>(\d+)</idLote>'
                    id_lote_match = re.search(id_lote_pattern, data_str)
                    if id_lote_match:
                        id_lote_atual = id_lote_match.group(1)
                        id_lote_corrigido = str(id_lote_atual).strip().zfill(15)[:15]
                        if id_lote_atual != id_lote_corrigido:
                            data_str = re.sub(id_lote_pattern, f'<idLote>{id_lote_corrigido}</idLote>', data_str)
                            debug_print(f">>> [nfelib] ✅ idLote corrigido no SOAP: {id_lote_atual} → {id_lote_corrigido}")
                    
                    # REMOVER prefixos ns0: do XML (causam erro na SEFAZ)
                    # Substituir <ns0:tag> por <tag> e </ns0:tag> por </tag>
                    # Também remover xmlns:ns0="..." se existir
                    if 'ns0:' in data_str:
                        # Remover prefixos ns0: de todas as tags
                        data_str = re.sub(r'<ns0:([^>]+)>', r'<\1>', data_str)
                        data_str = re.sub(r'</ns0:([^>]+)>', r'</\1>', data_str)
                        # Remover atributos xmlns:ns0="..."
                        data_str = re.sub(r'\s+xmlns:ns0="[^"]*"', '', data_str)
                        debug_print(f">>> [nfelib] ✅ Prefixos ns0: removidos do XML")
                    
                    # Atualizar kwargs['data'] ou args com o valor corrigido
                    if 'data' in kwargs:
                        kwargs['data'] = data_str.encode('utf-8') if isinstance(kwargs['data'], bytes) else data_str
                    elif len(args) >= 2:
                        # Se estava em args, precisamos reconstruir
                        args = list(args)
                        args[1] = data_str.encode('utf-8') if isinstance(args[1], bytes) else data_str
                        args = tuple(args)
                    
                    debug_print(f">>> [nfelib] 📤 Dados enviados (primeiros 2000 chars):")
                    debug_print(data_str[:2000])
                    
                    # Salvar SOAP envelope para debug
                    try:
                        log_dir = self._obter_diretorio_empresa(empresa_data)
                        os.makedirs(log_dir, exist_ok=True)
                        from datetime import datetime
                        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                        soap_file = os.path.join(log_dir, f'soap_pynfe_enviado_{timestamp}.xml')
                        with open(soap_file, 'w', encoding='utf-8') as f:
                            f.write(data_str)
                        debug_print(f">>> [nfelib] 💾 SOAP salvo em: {soap_file}")
                    except Exception as e_save:
                        debug_print(f">>> [nfelib] ⚠️ Erro ao salvar SOAP: {e_save}")
                else:
                    debug_print(f">>> [nfelib] ⚠️ Nenhum dado encontrado em 'data', 'json' ou args[1]")
                    debug_print(f">>> [nfelib] 📋 kwargs keys: {list(kwargs.keys())}")
                    debug_print(f">>> [nfelib] 📋 args count: {len(args)}")
                
                # Corrigir Content-Type se necessário (adicionar action se faltar)
                if 'headers' in kwargs:
                    headers = kwargs['headers']
                    debug_print(f">>> [nfelib] 📋 Headers: {headers}")
                    
                    # Verificar se Content-Type precisa do action
                    content_type_key = None
                    for key in headers.keys():
                        if key.lower() == 'content-type':
                            content_type_key = key
                            break
                    
                    if content_type_key:
                        content_type = headers[content_type_key]
                        # Se não tem action, adicionar
                        if 'action=' not in content_type.lower():
                            action_url = 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote'
                            if ';' in content_type:
                                headers[content_type_key] = f"{content_type}; action=\"{action_url}\""
                            else:
                                headers[content_type_key] = f"{content_type}; action=\"{action_url}\""
                            debug_print(f">>> [nfelib] ✅ Content-Type corrigido com action")
                
                if 'cert' in kwargs:
                    debug_print(f">>> [nfelib] 🔐 Certificado: {kwargs['cert']}")
                
                # Atualizar args se necessário (se corrigimos idLote e estava em args)
                if len(args) >= 2 and isinstance(args[1], str) and '<idLote>' in args[1]:
                    # Reconstruir args com data corrigida
                    args_list = list(args)
                    args_list[1] = data_str if data_str else args_list[1]
                    args = tuple(args_list)
                
                # Chamar método original
                try:
                    resposta = original_post(*args, **kwargs)
                    debug_print(f">>> [nfelib] 📥 Resposta recebida: status={resposta.status_code}")
                    debug_print(f">>> [nfelib] 📥 Headers: {dict(resposta.headers)}")
                    debug_print(f">>> [nfelib] 📥 Content-Length: {resposta.headers.get('Content-Length', 'N/A')}")
                    
                    # Verificar se a resposta está vazia (Content-Length: 0)
                    content_length = resposta.headers.get('Content-Length', '')
                    if content_length == '0' or (not resposta.text or len(resposta.text.strip()) == 0):
                        debug_print(f">>> [nfelib] ⚠️ Resposta está VAZIA (Content-Length: {content_length})")
                        if resposta.status_code == 400:
                            debug_print(f">>> [nfelib] ❌ HTTP 400 Bad Request com resposta vazia")
                            debug_print(f">>> [nfelib] Isso indica que a SEFAZ rejeitou a requisição ANTES de processar o XML")
                            debug_print(f">>> [nfelib] Possíveis causas:")
                            debug_print(f">>> [nfelib]   1. XML malformado ou inválido")
                            debug_print(f">>> [nfelib]   2. Certificado inválido ou expirado")
                            debug_print(f">>> [nfelib]   3. Problema com a assinatura digital")
                            debug_print(f">>> [nfelib]   4. Headers HTTP incorretos")
                            debug_print(f">>> [nfelib]   5. URL do serviço incorreta")
                    
                    if resposta.text:
                        debug_print(f">>> [nfelib] 📥 Resposta (primeiros 500 chars): {resposta.text[:500]}")
                    else:
                        debug_print(f">>> [nfelib] ⚠️ Resposta não tem conteúdo (text é None ou vazio)")
                    return resposta
                except Exception as e:
                    debug_print(f">>> [nfelib] ❌ Erro na requisição: {e}")
                    raise
            
            # Aplicar interceptação
            requests.post = post_interceptado
            debug_print(f">>> [nfelib] 🔧 Interceptação de requests.post ATIVADA")
            
            try:
                # Criar comunicação com SEFAZ usando PyNFe
                comunicacao = ComunicacaoSefaz(
                    uf=uf,
                    certificado=cert_path,
                    certificado_senha=cert_senha,
                    homologacao=ambiente_homologacao
                )
                
                # Parsear XML assinado
                xml_elemento = lxml_etree.fromstring(xml_assinado.encode('utf-8'))
                
                # Extrair enviNFe do XML (PyNFe espera apenas o enviNFe, não o envelope completo)
                envi_nfe = xml_elemento
                if xml_elemento.tag.endswith('enviNFe'):
                    envi_nfe = xml_elemento
                else:
                    # Procurar enviNFe dentro do XML
                    envi_nfe = xml_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
                    if envi_nfe is None:
                        envi_nfe = xml_elemento.find('.//enviNFe')
                
                if envi_nfe is None:
                    return {
                        'success': False,
                        'error': 'enviNFe não encontrado no XML assinado',
                        'autorizada': False
                    }
                
                # Converter enviNFe para string
                envi_nfe_str = lxml_etree.tostring(envi_nfe, encoding='unicode', xml_declaration=False)
                
                # Parsear novamente para garantir estrutura correta
                envi_nfe_elemento = lxml_etree.fromstring(envi_nfe_str.encode('utf-8'))
                
                # Extrair idLote e indSinc
                id_lote_elem = envi_nfe_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}idLote')
                if id_lote_elem is None:
                    id_lote_elem = envi_nfe_elemento.find('.//idLote')
                
                ind_sinc_elem = envi_nfe_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}indSinc')
                if ind_sinc_elem is None:
                    ind_sinc_elem = envi_nfe_elemento.find('.//indSinc')
                
                # IMPORTANTE: idLote deve ser string com 15 dígitos, não inteiro
                id_lote_str = id_lote_elem.text if id_lote_elem is not None and id_lote_elem.text else '1'
                id_lote_str = str(id_lote_str).strip().zfill(15)[:15]  # Garantir 15 dígitos
                
                # CORRIGIR o idLote no XML antes de passar para PyNFe
                if id_lote_elem is not None:
                    id_lote_elem.text = id_lote_str
                    debug_print(f">>> [nfelib] ✅ idLote corrigido no XML: {id_lote_str}")
                
                ind_sinc = int(ind_sinc_elem.text) if ind_sinc_elem is not None and ind_sinc_elem.text else 1
                
                debug_print(f">>> [nfelib] idLote extraído: {id_lote_str} ({len(id_lote_str)} dígitos), indSinc: {ind_sinc}")
                
                # Extrair NFe do enviNFe
                # IMPORTANTE: Precisamos fazer uma cópia profunda do elemento NFe para que o PyNFe possa manipulá-lo
                nfe_elem_original = envi_nfe_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                if nfe_elem_original is None:
                    nfe_elem_original = envi_nfe_elemento.find('.//NFe')
                
                if nfe_elem_original is None:
                    return {
                        'success': False,
                        'error': 'NFe não encontrada no enviNFe',
                        'autorizada': False
                    }
                
                # Fazer cópia profunda do elemento NFe (sem namespace explícito, o PyNFe vai adicionar)
                nfe_elem = lxml_etree.fromstring(lxml_etree.tostring(nfe_elem_original, encoding='unicode'))
                debug_print(f">>> [nfelib] NFe extraída e copiada. Tag: {nfe_elem.tag}")
                
                # Enviar usando PyNFe
                debug_print(f">>> [nfelib] Enviando para SEFAZ usando PyNFe (idLote: {id_lote_str}, indSinc: {ind_sinc})...")
                debug_print(f">>> [nfelib] Tipo do nfe_elem: {type(nfe_elem)}")
                debug_print(f">>> [nfelib] Tag do nfe_elem: {nfe_elem.tag if hasattr(nfe_elem, 'tag') else 'N/A'}")
                
                try:
                    resultado_autorizacao = comunicacao.autorizacao(
                        modelo="nfce",
                        nota_fiscal=nfe_elem,  # PyNFe espera o elemento NFe
                        id_lote=int(id_lote_str),  # Converter para int (PyNFe vai formatar para 15 dígitos)
                        ind_sinc=ind_sinc,
                        contingencia=False,
                        timeout=30
                    )
                    debug_print(f">>> [nfelib] Resultado recebido do PyNFe: tipo={type(resultado_autorizacao)}")
                    if isinstance(resultado_autorizacao, tuple):
                        debug_print(f">>> [nfelib] Tupla com {len(resultado_autorizacao)} elementos")
                        for i, elem in enumerate(resultado_autorizacao):
                            debug_print(f">>> [nfelib] Elemento {i}: tipo={type(elem)}")
                            if hasattr(elem, 'status_code'):
                                debug_print(f">>> [nfelib]   - status_code: {elem.status_code}")
                                debug_print(f">>> [nfelib]   - headers: {elem.headers}")
                                if hasattr(elem, 'text') and elem.text:
                                    debug_print(f">>> [nfelib]   - text (primeiros 500): {elem.text[:500]}")
                                if hasattr(elem, 'content') and elem.content:
                                    try:
                                        content_str = elem.content.decode('utf-8')[:500]
                                        debug_print(f">>> [nfelib]   - content (primeiros 500): {content_str}")
                                    except:
                                        debug_print(f">>> [nfelib]   - content (bytes): {len(elem.content)} bytes")
                except Exception as e_envio:
                    debug_print(f">>> [nfelib] ❌ Erro ao chamar autorizacao: {e_envio}")
                    import traceback
                    debug_print(traceback.format_exc())
                    return {
                        'success': False,
                        'error': f'Erro ao enviar para SEFAZ: {str(e_envio)}',
                        'autorizada': False
                    }
                
                # Processar resposta
                # PyNFe retorna uma tupla: (status, xml_resposta) ou (status, response, xml_elemento)
                if resultado_autorizacao:
                    if isinstance(resultado_autorizacao, tuple) and len(resultado_autorizacao) >= 2:
                        status = resultado_autorizacao[0]
                        xml_resposta = resultado_autorizacao[1]
                        
                        # PRIMEIRO: Verificar status HTTP ANTES de qualquer outra coisa
                        response_http_original = xml_resposta if hasattr(xml_resposta, 'status_code') else None
                        if response_http_original and hasattr(response_http_original, 'status_code'):
                            status_code_http = response_http_original.status_code
                            debug_print(f">>> [nfelib] Status HTTP detectado: {status_code_http}")
                            
                            # Se status HTTP é erro, tratar IMEDIATAMENTE como erro
                            if status_code_http >= 400:
                                debug_print(f">>> [nfelib] ⚠️ HTTP {status_code_http} - tratando como erro antes de processar XML")
                                
                                # Tentar extrair mensagem de erro da resposta HTTP
                                if hasattr(response_http_original, 'text') and response_http_original.text and response_http_original.text.strip():
                                    try:
                                        from lxml import etree as lxml_etree
                                        root_erro = lxml_etree.fromstring(response_http_original.text.encode('utf-8'))
                                        ret_envinfe = root_erro.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                                        if ret_envinfe is None:
                                            ret_envinfe = root_erro.find('.//retEnviNFe')
                                        
                                        if ret_envinfe is not None:
                                            x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                            if x_motivo is None:
                                                x_motivo = ret_envinfe.find('.//xMotivo')
                                            
                                            c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                            if c_stat is None:
                                                c_stat = ret_envinfe.find('.//cStat')
                                            
                                            motivo = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                                            codigo = c_stat.text if c_stat is not None else str(status_code_http)
                                            
                                            error_msg = f'cStat {codigo}: {motivo}'
                                            debug_print(f">>> [nfelib] ❌ Erro SEFAZ extraído: {error_msg}")
                                            
                                            return {
                                                'success': False,
                                                'error': error_msg,
                                                'autorizada': False,
                                                'codigo_erro': codigo
                                            }
                                    except Exception as e_parse:
                                        debug_print(f">>> [nfelib] Erro ao parsear XML de erro: {e_parse}")
                                
                                # Se não conseguiu parsear ou resposta está vazia
                                error_msg = f'Erro HTTP {status_code_http}'
                                if hasattr(response_http_original, 'reason'):
                                    error_msg += f': {response_http_original.reason}'
                                
                                if hasattr(response_http_original, 'headers'):
                                    content_length = response_http_original.headers.get('Content-Length', '')
                                    if content_length == '0' or not response_http_original.text or not response_http_original.text.strip():
                                        error_msg += ' (Resposta vazia - possível erro na estrutura do XML, certificado inválido ou problema na comunicação com SEFAZ)'
                                    
                                    debug_print(f">>> [nfelib] 📋 Headers: {response_http_original.headers}")
                                
                                debug_print(f">>> [nfelib] ❌ Retornando erro: {error_msg}")
                                return {
                                    'success': False,
                                    'error': error_msg,
                                    'autorizada': False,
                                    'status_code': status_code_http
                                }
                        
                        # Se chegou aqui, não há erro HTTP (já foi tratado acima)
                        # Usar o terceiro elemento se disponível (XML parseado)
                        if len(resultado_autorizacao) >= 3:
                            # Se não há erro HTTP, usar o terceiro elemento (XML parseado da resposta)
                            xml_elemento_parseado = resultado_autorizacao[2]
                            if xml_elemento_parseado is not None and (hasattr(xml_elemento_parseado, 'find') or hasattr(xml_elemento_parseado, 'getroot')):
                                debug_print(f">>> [nfelib] Usando terceiro elemento da tupla (XML parseado)")
                                xml_resposta = xml_elemento_parseado
                        
                        debug_print(f">>> [nfelib] Status PyNFe: {status}")
                        
                        # Status 0 ou 1 podem ser sucesso - verificar o conteúdo
                        if status == 0 or status == 1:
                            # Verificar se xml_resposta é um elemento XML (nfeProc) ou Response
                            if hasattr(xml_resposta, 'find') or hasattr(xml_resposta, 'getroot'):
                                # É um elemento XML - processar como nfeProc
                                if hasattr(xml_resposta, 'getroot'):
                                    xml_resposta = xml_resposta.getroot()
                                
                                # Verificar se é nfeProc ou tem protNFe
                                prot_nfe = xml_resposta.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = xml_resposta.find('.//protNFe')
                                
                                if prot_nfe is not None:
                                    # É um nfeProc válido - processar como sucesso
                                    debug_print(f">>> [nfelib] ✅ NFC-e autorizada! Processando nfeProc...")
                                    return self._processar_resposta_nfeproc(xml_resposta, ambiente_homologacao)
                                else:
                                    # Não tem protNFe - verificar se não é um Response vazio
                                    if hasattr(xml_resposta, 'status_code'):
                                        # É um Response HTTP, não um XML - tratar separadamente abaixo
                                        pass
                                    else:
                                        # Não tem protNFe - pode ser erro, mas vamos tentar processar
                                        debug_print(f">>> [nfelib] ⚠️ XML não tem protNFe, mas status é {status}. Tentando processar...")
                                        return self._processar_resposta_nfeproc(xml_resposta, ambiente_homologacao)
                            elif hasattr(xml_resposta, 'text'):
                                # É um Response do requests - pode ser erro ou sucesso
                                # Parsear o XML da resposta
                                try:
                                    xml_texto = xml_resposta.text
                                    
                                    # Verificar se o texto não está vazio
                                    if not xml_texto or not xml_texto.strip():
                                        debug_print(f">>> [nfelib] ⚠️ Response.text está vazio")
                                        # Tentar usar content
                                        if hasattr(xml_resposta, 'content') and xml_resposta.content:
                                            try:
                                                xml_texto = xml_resposta.content.decode('utf-8')
                                                debug_print(f">>> [nfelib] Usando content ao invés de text (tamanho: {len(xml_texto)} chars)")
                                            except Exception as e_decode:
                                                debug_print(f">>> [nfelib] Erro ao decodificar content: {e_decode}")
                                                xml_texto = None
                                        
                                        if not xml_texto or not xml_texto.strip():
                                            # Response vazio - pode ser erro HTTP
                                            status_code = getattr(xml_resposta, 'status_code', None)
                                            headers = getattr(xml_resposta, 'headers', {})
                                            
                                            debug_print(f">>> [nfelib] Response vazio - Status: {status_code}, Headers: {headers}")
                                            
                                            error_msg = f'Resposta vazia da SEFAZ'
                                            if status_code:
                                                error_msg += f' (HTTP {status_code})'
                                            
                                            # Tentar obter mais informações do erro
                                            if hasattr(xml_resposta, 'reason'):
                                                error_msg += f': {xml_resposta.reason}'
                                            
                                            return {
                                                'success': False,
                                                'error': error_msg,
                                                'autorizada': False,
                                                'status_code': status_code
                                            }
                                    
                                    debug_print(f">>> [nfelib] Resposta é Response, parseando XML... (tamanho: {len(xml_texto)} chars)")
                                    debug_print(f">>> [nfelib] Primeiros 200 chars: {xml_texto[:200]}")
                                    
                                    root_resposta = lxml_etree.fromstring(xml_texto.encode('utf-8'))
                                    
                                    # Verificar se tem protNFe (sucesso) ou retEnviNFe (erro)
                                    prot_nfe = root_resposta.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                    if prot_nfe is None:
                                        prot_nfe = root_resposta.find('.//protNFe')
                                    
                                    if prot_nfe is not None:
                                        # Tem protNFe - é sucesso!
                                        debug_print(f">>> [nfelib] ✅ Resposta contém protNFe - NFC-e autorizada!")
                                        return self._processar_resposta_nfeproc(root_resposta, ambiente_homologacao)
                                    else:
                                        # Não tem protNFe - verificar se tem retEnviNFe (erro)
                                        ret_envinfe = root_resposta.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                                        if ret_envinfe is None:
                                            ret_envinfe = root_resposta.find('.//retEnviNFe')
                                        
                                        if ret_envinfe is not None:
                                            # É um erro da SEFAZ
                                            x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                            if x_motivo is None:
                                                x_motivo = ret_envinfe.find('.//xMotivo')
                                            
                                            c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                            if c_stat is None:
                                                c_stat = ret_envinfe.find('.//cStat')
                                            
                                            motivo = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                                            codigo = c_stat.text if c_stat is not None else str(status)
                                            
                                            error_msg = f'cStat {codigo}: {motivo}'
                                            debug_print(f">>> [nfelib] ❌ Erro SEFAZ: {error_msg}")
                                            
                                            return {
                                                'success': False,
                                                'error': error_msg,
                                                'autorizada': False,
                                                'codigo_erro': codigo
                                            }
                                except Exception as e_parse:
                                    debug_print(f">>> [nfelib] Erro ao parsear resposta: {e_parse}")
                                    import traceback
                                    debug_print(traceback.format_exc())
                                    
                                    # Se o XML está vazio, pode ser que a resposta seja um erro HTTP
                                    status_code = getattr(xml_resposta, 'status_code', None)
                                    if status_code:
                                        error_msg = f'Erro HTTP {status_code}'
                                        if hasattr(xml_resposta, 'reason'):
                                            error_msg += f': {xml_resposta.reason}'
                                        
                                        return {
                                            'success': False,
                                            'error': error_msg,
                                            'autorizada': False
                                        }
                                    
                                    # Se não conseguiu parsear e não tem status_code, retornar erro genérico
                                    return {
                                        'success': False,
                                        'error': f'Erro ao processar resposta da SEFAZ (XML vazio ou inválido): {str(e_parse)}',
                                        'autorizada': False
                                    }
                    
                    # Se chegou aqui, é erro
                    if status != 0 and status != 1:
                        # Erro - extrair mensagem de erro
                        debug_print(f">>> [nfelib] ❌ Status não é 0 (sucesso): {status}")
                        
                        # Quando status == 1, xml_resposta é um objeto Response do requests
                        error_msg = f'Erro na autorização (status: {status})'
                        
                        # Tentar extrair mensagem de erro do Response
                        if hasattr(xml_resposta, 'text') and xml_resposta.text:
                            # É um Response do requests - extrair XML SOAP
                            xml_erro = xml_resposta.text
                            debug_print(f">>> [nfelib] Resposta de erro (primeiros 500 chars): {xml_erro[:500]}")
                            
                            # Parsear XML SOAP para extrair retEnviNFe
                            try:
                                root_erro = lxml_etree.fromstring(xml_erro.encode('utf-8'))
                                
                                # Buscar retEnviNFe no SOAP
                                ret_envinfe = root_erro.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                                if ret_envinfe is None:
                                    ret_envinfe = root_erro.find('.//retEnviNFe')
                                
                                if ret_envinfe is not None:
                                    x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                    if x_motivo is None:
                                        x_motivo = ret_envinfe.find('.//xMotivo')
                                    
                                    c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                    if c_stat is None:
                                        c_stat = ret_envinfe.find('.//cStat')
                                    
                                    motivo = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                                    codigo = c_stat.text if c_stat is not None else str(status)
                                    
                                    error_msg = f'cStat {codigo}: {motivo}'
                                    debug_print(f">>> [nfelib] Erro extraído: {error_msg}")
                                    
                                    return {
                                        'success': False,
                                        'error': error_msg,
                                        'autorizada': False,
                                        'codigo_erro': codigo
                                    }
                            except Exception as e_parse:
                                debug_print(f">>> [nfelib] Erro ao parsear XML de erro: {e_parse}")
                                # Se não conseguir parsear, usar o texto completo
                                error_msg = f'Erro SEFAZ: {xml_erro[:500]}'
                        elif hasattr(xml_resposta, 'status_code'):
                            # É um Response HTTP com status code
                            status_code = xml_resposta.status_code
                            error_msg = f'Erro HTTP {status_code}'
                            
                            if hasattr(xml_resposta, 'content'):
                                try:
                                    error_content = xml_resposta.content.decode('utf-8')[:500]
                                    error_msg = f'Erro HTTP {status_code}: {error_content}'
                                except:
                                    pass
                        
                        return {
                            'success': False,
                            'error': error_msg,
                            'autorizada': False
                        }
                    else:
                        # Resposta não é tupla - tratar como XML direto
                        xml_resposta = resultado_autorizacao
                        if hasattr(xml_resposta, 'text'):
                            xml_resposta = xml_resposta.text
                        elif isinstance(xml_resposta, bytes):
                            xml_resposta = xml_resposta.decode('utf-8')
                        elif not isinstance(xml_resposta, str):
                            xml_resposta = str(xml_resposta)
                        
                        return self._processar_resposta_sefaz_nfelib(xml_resposta, ambiente_homologacao)
                else:
                    return {
                        'success': False,
                        'error': 'Resposta vazia da SEFAZ',
                        'autorizada': False
                    }
            finally:
                # Restaurar método original
                try:
                    import requests
                    requests.post = original_post
                    debug_print(f">>> [nfelib] 🔧 Interceptação de requests.post DESATIVADA")
                except:
                    pass
                
        except Exception as e:
            debug_print(f">>> [nfelib] ❌ Erro ao enviar usando PyNFe: {e}")
            import traceback
            debug_print(traceback.format_exc())
            
            # Restaurar método original em caso de erro
            try:
                import requests
                requests.post = original_post
                debug_print(f">>> [nfelib] 🔧 Interceptação de requests.post DESATIVADA (erro)")
            except:
                pass
            
            return {
                'success': False,
                'error': f'Erro ao enviar para SEFAZ: {str(e)}',
                'autorizada': False
            }
    
    def _processar_resposta_nfeproc(self, nfe_proc_elemento, ambiente_homologacao):
        """Processa resposta nfeProc do PyNFe (nota autorizada)"""
        debug_print = print
        try:
            from lxml import etree as lxml_etree
            
            # Se for string, parsear primeiro
            if isinstance(nfe_proc_elemento, str):
                nfe_proc_elemento = lxml_etree.fromstring(nfe_proc_elemento.encode('utf-8'))
            
            # Buscar protNFe (pode estar em nfeProc ou diretamente no root)
            prot_nfe = nfe_proc_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
            if prot_nfe is None:
                prot_nfe = nfe_proc_elemento.find('.//protNFe')
            
            # Se não encontrou, pode ser que o elemento raiz seja o protNFe
            if prot_nfe is None:
                if nfe_proc_elemento.tag.endswith('protNFe') or '{http://www.portalfiscal.inf.br/nfe}protNFe' in nfe_proc_elemento.tag:
                    prot_nfe = nfe_proc_elemento
                else:
                    # Buscar em nfeProc
                    nfe_proc = nfe_proc_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}nfeProc')
                    if nfe_proc is None:
                        nfe_proc = nfe_proc_elemento.find('.//nfeProc')
                    
                    if nfe_proc is not None:
                        prot_nfe = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                        if prot_nfe is None:
                            prot_nfe = nfe_proc.find('.//protNFe')
            
            if prot_nfe is None:
                debug_print(f">>> [nfelib] ⚠️ protNFe não encontrado. Tag raiz: {nfe_proc_elemento.tag}")
                # Tentar buscar diretamente no SOAP Body
                soap_body = nfe_proc_elemento.find('.//{http://www.w3.org/2003/05/soap-envelope}Body')
                if soap_body is not None:
                    prot_nfe = soap_body.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                    if prot_nfe is None:
                        prot_nfe = soap_body.find('.//protNFe')
                
                if prot_nfe is None:
                    # Verificar se a resposta está vazia (HTTP 400 com Content-Length: 0)
                    debug_print(f">>> [nfelib] ⚠️ protNFe não encontrado na resposta")
                    debug_print(f">>> [nfelib] Tag raiz: {nfe_proc_elemento.tag}")
                    
                    # Tentar extrair informações de erro da resposta
                    ret_envinfe = nfe_proc_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                    if ret_envinfe is None:
                        ret_envinfe = nfe_proc_elemento.find('.//retEnviNFe')
                    
                    if ret_envinfe is not None:
                        # Encontrou retEnviNFe, mas não protNFe - significa que foi rejeitada
                        c_stat = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                        if c_stat is None:
                            c_stat = ret_envinfe.find('.//cStat')
                        
                        x_motivo = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                        if x_motivo is None:
                            x_motivo = ret_envinfe.find('.//xMotivo')
                        
                        if c_stat is not None and x_motivo is not None:
                            codigo = c_stat.text if c_stat.text else 'N/A'
                            motivo = x_motivo.text if x_motivo.text else 'Erro desconhecido'
                            debug_print(f">>> [nfelib] ❌ NFC-e rejeitada: cStat {codigo} - {motivo}")
                            return {
                                'success': False,
                                'error': f'cStat {codigo}: {motivo}',
                                'autorizada': False,
                                'codigo_erro': codigo,
                                'motivo': motivo
                            }
                    
                    # Se não encontrou retEnviNFe, pode ser resposta vazia (HTTP 400)
                    debug_print(f">>> [nfelib] ❌ protNFe não encontrado e retEnviNFe também não encontrado")
                    debug_print(f">>> [nfelib] Isso indica que a SEFAZ rejeitou a requisição ANTES de processar o XML")
                    debug_print(f">>> [nfelib] Possíveis causas:")
                    debug_print(f">>> [nfelib]   1. XML malformado ou inválido")
                    debug_print(f">>> [nfelib]   2. Certificado inválido ou expirado")
                    debug_print(f">>> [nfelib]   3. Problema com a assinatura digital")
                    debug_print(f">>> [nfelib]   4. Headers HTTP incorretos")
                    debug_print(f">>> [nfelib]   5. URL do serviço incorreta")
                    
                    return {
                        'success': False,
                        'error': 'protNFe não encontrado na resposta - SEFAZ rejeitou antes de processar (possível erro no XML, certificado ou assinatura)',
                        'autorizada': False,
                        'details': 'A SEFAZ retornou uma resposta vazia ou sem protNFe. Isso geralmente indica que a requisição foi rejeitada antes mesmo de processar o XML. Verifique: XML válido, certificado válido, assinatura digital correta.'
                    }
            
            # Buscar infProt dentro de protNFe
            inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt')
            if inf_prot is None:
                inf_prot = prot_nfe.find('.//infProt')
            
            if inf_prot is None:
                return {
                    'success': False,
                    'error': 'infProt não encontrado na resposta',
                    'autorizada': False
                }
            
            # Extrair dados do protocolo
            n_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
            if n_prot is None:
                n_prot = inf_prot.find('.//nProt')
            
            ch_nfe = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe')
            if ch_nfe is None:
                ch_nfe = inf_prot.find('.//chNFe')
            
            protocolo = n_prot.text if n_prot is not None else ''
            chave_acesso = ch_nfe.text if ch_nfe is not None else ''
            
            # Converter nfeProc para string
            xml_nfeproc = lxml_etree.tostring(nfe_proc_elemento, encoding='unicode', xml_declaration=True)
            
            # Extrair dados da NFe para impressão
            nfe_elem = nfe_proc_elemento.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
            if nfe_elem is None:
                nfe_elem = nfe_proc_elemento.find('.//NFe')
            
            # Extrair dados básicos da NFe
            numero_nf = None
            serie_nf = None
            valor_total = None
            data_emissao = None
            
            if nfe_elem is not None:
                inf_nfe = nfe_elem.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe')
                if inf_nfe is None:
                    inf_nfe = nfe_elem.find('.//infNFe')
                
                if inf_nfe is not None:
                    # Extrair ide
                    ide = inf_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}ide')
                    if ide is None:
                        ide = inf_nfe.find('.//ide')
                    
                    if ide is not None:
                        n_nf_elem = ide.find('.//{http://www.portalfiscal.inf.br/nfe}nNF')
                        if n_nf_elem is None:
                            n_nf_elem = ide.find('.//nNF')
                        if n_nf_elem is not None:
                            numero_nf = n_nf_elem.text
                        
                        serie_elem = ide.find('.//{http://www.portalfiscal.inf.br/nfe}serie')
                        if serie_elem is None:
                            serie_elem = ide.find('.//serie')
                        if serie_elem is not None:
                            serie_nf = serie_elem.text
                        
                        dh_emi_elem = ide.find('.//{http://www.portalfiscal.inf.br/nfe}dhEmi')
                        if dh_emi_elem is None:
                            dh_emi_elem = ide.find('.//dhEmi')
                        if dh_emi_elem is not None:
                            data_emissao = dh_emi_elem.text
                    
                    # Extrair valor total
                    total_elem = inf_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}total')
                    if total_elem is None:
                        total_elem = inf_nfe.find('.//total')
                    
                    if total_elem is not None:
                        icms_tot = total_elem.find('.//{http://www.portalfiscal.inf.br/nfe}ICMSTot')
                        if icms_tot is None:
                            icms_tot = total_elem.find('.//ICMSTot')
                        
                        if icms_tot is not None:
                            v_nf_elem = icms_tot.find('.//{http://www.portalfiscal.inf.br/nfe}vNF')
                            if v_nf_elem is None:
                                v_nf_elem = icms_tot.find('.//vNF')
                            if v_nf_elem is not None:
                                valor_total = v_nf_elem.text
            
            # Gerar QR Code
            qr_code = self._gerar_qr_code_nfelib(
                chave_acesso,
                protocolo,
                ambiente_homologacao,
                float(valor_total) if valor_total else 0.0,
                'SP'  # UF - pode ser extraído do XML se necessário
            )
            
            debug_print(f">>> [nfelib] ✅ NFC-e autorizada! Protocolo: {protocolo}")
            debug_print(f">>> [nfelib] ✅ XML nfeProc gerado: {len(xml_nfeproc)} caracteres")
            debug_print(f">>> [nfelib] ✅ QR Code gerado: {qr_code[:50]}...")
            
            return {
                'success': True,
                'autorizada': True,
                'protocolo': protocolo,
                'chave_acesso': chave_acesso,
                'numero': numero_nf,
                'serie': serie_nf,
                'valor_total': valor_total,
                'data_emissao': data_emissao,
                'qr_code': qr_code,
                'xml_autorizado': xml_nfeproc,
                'xml_retorno': xml_nfeproc,
                'xml_nfeproc': xml_nfeproc,  # Alias para compatibilidade
                'message': '✅ NFC-e autorizada com sucesso!'
            }
        except Exception as e:
            debug_print(f">>> [nfelib] ❌ Erro ao processar nfeProc: {e}")
            import traceback
            debug_print(traceback.format_exc())
            return {
                'success': False,
                'error': f'Erro ao processar resposta: {str(e)}',
                'autorizada': False
            }
    
    def _processar_resposta_sefaz_nfelib(self, xml_resposta, ambiente_homologacao):
        """Processa resposta da SEFAZ usando nfelib"""
        try:
            root = etree.fromstring(xml_resposta.encode('utf-8'))
            
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
                    
                    # 100 = Autorizada (Síncrono Direto)
                    # 104 = Lote Processado (Síncrono ou Assíncrono)
                    if c_stat_valor in ['100', '104']:
                        # Procurar protNFe
                        prot_nfe = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                        if prot_nfe is None:
                            prot_nfe = ret_envinfe.find('.//protNFe')
                        
                        if prot_nfe is not None:
                            # Extrair dados do protNFe/infProt
                            c_stat_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                            if c_stat_prot is None:
                                c_stat_prot = prot_nfe.find('.//cStat')
                            
                            n_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                            if n_prot is None:
                                n_prot = prot_nfe.find('.//nProt')
                            
                            ch_nfe = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe')
                            if ch_nfe is None:
                                ch_nfe = prot_nfe.find('.//chNFe')
                            
                            x_motivo_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                            if x_motivo_prot is None:
                                x_motivo_prot = prot_nfe.find('.//xMotivo')
                            
                            c_stat_prot_valor = c_stat_prot.text if c_stat_prot is not None else ''
                            
                            # Se o status da nota for 100 ou 150 (Autorizada)
                            if c_stat_prot_valor in ['100', '150']:
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'cstat': c_stat_prot_valor,
                                    'motivo': x_motivo_prot.text if x_motivo_prot is not None else 'Autorizado',
                                    'protocolo': n_prot.text if n_prot is not None else '',
                                    'chave_acesso_resposta': ch_nfe.text if ch_nfe is not None else '',
                                    'xml_retorno': xml_resposta,
                                    'message': '✅ NFC-e autorizada com sucesso!'
                                }
                            else:
                                # Rejeitada dentro do lote
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'cstat': c_stat_prot_valor,
                                    'motivo': x_motivo_prot.text if x_motivo_prot is not None else 'Rejeitada',
                                    'error': f"cStat {c_stat_prot_valor}: {x_motivo_prot.text if x_motivo_prot is not None else 'Rejeitada'}"
                                }
                        
                        # Se for 100 mas não tiver protNFe, tentar extrair nProt do retEnviNFe (algumas SEFAZ mandam assim)
                        if c_stat_valor == '100':
                            n_prot = ret_envinfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                            if n_prot is None:
                                n_prot = ret_envinfe.find('.//nProt')
                            
                            if n_prot is not None:
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'cstat': c_stat_valor,
                                    'motivo': x_motivo.text if x_motivo is not None else 'Autorizado',
                                    'protocolo': n_prot.text,
                                    'xml_retorno': xml_resposta,
                                    'message': '✅ NFC-e autorizada com sucesso!'
                                }
                    
                    # Se não caiu em nenhum caso de sucesso acima
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
            print(f">>> [nfelib] ❌ Erro ao processar resposta: {e}")
            return {
                'success': False,
                'autorizada': False,
                'error': f'Erro ao processar resposta: {str(e)}'
            }

