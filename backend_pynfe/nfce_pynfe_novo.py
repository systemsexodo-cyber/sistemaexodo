"""
NFC-e usando PyNFe - Versão Nova e Limpa
Baseado na instalação do PyNFe do GitHub TadaSoftware/PyNFe
"""

import os
import base64
import tempfile
from typing import Dict, List, Optional, Any
from datetime import datetime

try:
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    from pynfe.entidades import Emitente, Cliente, NotaFiscal
    try:
        from pynfe.utils import obter_municipio_por_codigo
    except ImportError:
        obter_municipio_por_codigo = None
    PYNFE_DISPONIVEL = True
except ImportError as e:
    PYNFE_DISPONIVEL = False
    print(f"⚠️ PyNFe não disponível: {e}")


class NFCePyNFeNovo:
    """
    Classe para emissão de NFC-e usando PyNFe (versão nova e limpa)
    """
    
    def __init__(self):
        self.debug = True
        self.cert_path = None
    
    def _preparar_certificado(self, certificado_base64: str, senha: str) -> str:
        """
        Prepara certificado digital salvando em arquivo temporário
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
            
        Returns:
            Caminho do arquivo temporário
        """
        try:
            # Decodificar base64
            cert_bytes = base64.b64decode(certificado_base64)
            
            # Criar arquivo temporário
            temp_dir = tempfile.gettempdir()
            cert_file = os.path.join(temp_dir, f"cert_nfce_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pfx")
            
            with open(cert_file, 'wb') as f:
                f.write(cert_bytes)
            
            self.cert_path = cert_file
            print(f"✅ Certificado salvo em: {cert_file}")
            return cert_file
            
        except Exception as e:
            print(f"❌ Erro ao preparar certificado: {e}")
            raise
    
    def _criar_emitente(self, empresa_data: Dict) -> Emitente:
        """
        Cria objeto Emitente do PyNFe
        
        Args:
            empresa_data: Dados da empresa
            
        Returns:
            Objeto Emitente
        """
        uf = empresa_data.get('uf', 'SP').upper()
        codigo_ibge = empresa_data.get('codigoIBGE') or empresa_data.get('codigoIbge')
        
        # Obter município - PyNFe precisa do NOME do município (não código)
        # Ele converte o nome para código durante a serialização
        municipio = empresa_data.get('municipio', '') or empresa_data.get('cidade', '')
        
        # Limpar município: remover qualquer "/UF" no final
        if municipio:
            municipio = municipio.strip()
            # Remover padrões como "/SP", "/SP/SP", etc.
            while municipio and '/' in municipio:
                partes = municipio.split('/')
                if len(partes) > 1:
                    # Se a última parte parece ser UF (2 letras), remover
                    if len(partes[-1].strip()) == 2:
                        municipio = '/'.join(partes[:-1]).strip()
                    else:
                        break
                else:
                    break
        
        # Se temos código IBGE, usar para obter o nome oficial do município
        # Isso garante que o nome está correto conforme a base do IBGE
        if codigo_ibge:
            try:
                from pynfe.utils import obter_municipio_por_codigo
                municipio_oficial = obter_municipio_por_codigo(str(codigo_ibge), uf)
                print(f"✅ Município obtido pelo código IBGE {codigo_ibge}: {municipio_oficial}")
                municipio = municipio_oficial  # Usar nome oficial do IBGE
            except Exception as e:
                print(f"⚠️ Não foi possível obter município pelo código IBGE {codigo_ibge}: {e}")
                # Se não conseguir pelo código, tentar validar o nome informado
                if municipio:
                    try:
                        from pynfe.utils import obter_codigo_por_municipio
                        codigo_validado = obter_codigo_por_municipio(municipio, uf)
                        print(f"✅ Município '{municipio}' validado - Código IBGE: {codigo_validado}")
                    except Exception as e2:
                        print(f"⚠️ Município '{municipio}' não encontrado na base do IBGE: {e2}")
        
        # Se ainda não tem município, usar valor padrão baseado na UF
        if not municipio or not municipio.strip():
            municipios_padrao = {
                'SP': 'SAO PAULO',
                'RJ': 'RIO DE JANEIRO',
                'MG': 'BELO HORIZONTE',
                'PR': 'CURITIBA',
                'RS': 'PORTO ALEGRE',
                'SC': 'FLORIANOPOLIS',
                'BA': 'SALVADOR',
                'GO': 'GOIANIA',
                'PE': 'RECIFE',
                'CE': 'FORTALEZA'
            }
            municipio = municipios_padrao.get(uf, 'SAO PAULO')
            print(f"⚠️ Município não informado, usando padrão: {municipio}")
        
        # Garantir que município não está vazio e está limpo
        municipio = municipio.strip().upper()
        if not municipio:
            raise ValueError(f"Município é obrigatório e não foi informado. UF: {uf}")
        
        emitente = Emitente(
            razao_social=empresa_data.get('razaoSocial', ''),
            nome_fantasia=empresa_data.get('nomeFantasia', ''),
            cnpj=empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', ''),
            codigo_de_regime_tributario=empresa_data.get('regimeTributario', '1'),
            inscricao_estadual=empresa_data.get('inscricaoEstadual', ''),
            inscricao_municipal=empresa_data.get('inscricaoMunicipal', ''),
            cnae_fiscal=empresa_data.get('cnaeFiscal', ''),
            endereco_logradouro=empresa_data.get('endereco', ''),
            endereco_numero=empresa_data.get('numero', ''),
            endereco_complemento=empresa_data.get('complemento', ''),
            endereco_bairro=empresa_data.get('bairro', ''),
            endereco_municipio=municipio,  # NOME do município (PyNFe converte para código) - já limpo anteriormente
            endereco_uf=uf,
            endereco_cep=empresa_data.get('cep', '').replace('-', '').replace('.', ''),
            endereco_pais='1058',  # Brasil
            telefone=empresa_data.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', ''),
            email=empresa_data.get('email', '')
        )
        
        print(f"✅ Emitente criado - Município: {municipio}/{uf}")
        
        return emitente
    
    def _criar_cliente(self, consumidor: Optional[Dict], uf_empresa: str = 'SP', municipio_empresa: str = 'SAO PAULO') -> Cliente:
        """
        Cria objeto Cliente do PyNFe
        
        Args:
            consumidor: Dados do consumidor (opcional)
            uf_empresa: UF da empresa
            municipio_empresa: Município da empresa (usado como padrão)
            
        Returns:
            Objeto Cliente
        """
        # Municípios padrão por UF (para cliente não identificado)
        municipios_padrao = {
            'SP': 'SAO PAULO',
            'RJ': 'RIO DE JANEIRO',
            'MG': 'BELO HORIZONTE',
            'PR': 'CURITIBA',
            'RS': 'PORTO ALEGRE',
            'SC': 'FLORIANOPOLIS',
            'BA': 'SALVADOR',
            'GO': 'GOIANIA',
            'PE': 'RECIFE',
            'CE': 'FORTALEZA'
        }
        
        if not consumidor:
            # Cliente não identificado - usar município da empresa ou padrão
            municipio_cliente = municipio_empresa if municipio_empresa else municipios_padrao.get(uf_empresa, 'SAO PAULO')
            
            # Limpar município (remover "/UF" se houver)
            municipio_cliente = municipio_cliente.strip()
            if '/' in municipio_cliente:
                partes = municipio_cliente.split('/')
                municipio_cliente = partes[0].strip()
            
            return Cliente(
                razao_social='CONSUMIDOR NAO IDENTIFICADO',
                tipo_documento='CPF',
                numero_documento='00000000000',
                indicador_ie=9,  # Não contribuinte
                endereco_logradouro='',
                endereco_numero='',
                endereco_complemento='',
                endereco_bairro='',
                endereco_municipio=municipio_cliente.upper(),  # NOME do município (PyNFe converte para código)
                endereco_uf=uf_empresa,
                endereco_cep='00000000',
                endereco_pais='1058',
                telefone='',
                email=''
            )
        
        # Cliente identificado
        cpf_cnpj = consumidor.get('cpfCnpj', '').replace('.', '').replace('/', '').replace('-', '')
        tipo_doc = 'CNPJ' if len(cpf_cnpj) == 14 else 'CPF'
        
        # Obter município do consumidor
        municipio_cliente = consumidor.get('municipio', '') or consumidor.get('cidade', '')
        uf_cliente = consumidor.get('uf', uf_empresa).upper()
        
        # Limpar município (remover "/UF" se houver)
        if municipio_cliente:
            municipio_cliente = municipio_cliente.strip()
            if '/' in municipio_cliente:
                partes = municipio_cliente.split('/')
                municipio_cliente = partes[0].strip()
        
        # Se não tem município, usar município da empresa ou padrão
        if not municipio_cliente:
            municipio_cliente = municipio_empresa if municipio_empresa else municipios_padrao.get(uf_cliente, 'SAO PAULO')
            # Limpar novamente
            if '/' in municipio_cliente:
                partes = municipio_cliente.split('/')
                municipio_cliente = partes[0].strip()
        
        return Cliente(
            razao_social=consumidor.get('nome', 'CONSUMIDOR'),
            tipo_documento=tipo_doc,
            numero_documento=cpf_cnpj,
            indicador_ie=9,  # Não contribuinte
            endereco_logradouro=consumidor.get('endereco', ''),
            endereco_numero=consumidor.get('numero', ''),
            endereco_complemento=consumidor.get('complemento', ''),
            endereco_bairro=consumidor.get('bairro', ''),
            endereco_municipio=municipio_cliente.upper(),  # NOME do município (PyNFe converte para código)
            endereco_uf=uf_cliente,
            endereco_cep=consumidor.get('cep', '').replace('-', '').replace('.', ''),
            endereco_pais='1058',
            telefone=consumidor.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', ''),
            email=consumidor.get('email', '')
        )
    
    def _adicionar_produtos(self, notafiscal: NotaFiscal, produtos: List[Dict]):
        """
        Adiciona produtos à nota fiscal
        
        Args:
            notafiscal: Objeto NotaFiscal
            produtos: Lista de produtos
        """
        from decimal import Decimal
        
        for idx, produto_data in enumerate(produtos, start=1):
            notafiscal.adicionar_produto_servico(
                codigo=str(produto_data.get('codigo', f'PROD{idx}')),
                descricao=produto_data.get('descricao', ''),
                ncm=produto_data.get('ncm', '00000000'),
                cfop=produto_data.get('cfop', '5102'),  # Venda no mesmo estado
                unidade_comercial=produto_data.get('unidade', 'UN'),
                quantidade_comercial=Decimal(str(produto_data.get('quantidade', 1))),
                valor_unitario_comercial=Decimal(str(produto_data.get('valorUnitario', 0))),
                valor_total_bruto=Decimal(str(produto_data.get('valorTotal', 0))),
                ean=produto_data.get('ean', 'SEM GTIN'),
                ean_tributavel=produto_data.get('ean', 'SEM GTIN'),
                unidade_tributavel=produto_data.get('unidade', 'UN'),
                quantidade_tributavel=Decimal(str(produto_data.get('quantidade', 1))),
                valor_unitario_tributavel=Decimal(str(produto_data.get('valorUnitario', 0))),
                ind_total=1,  # Valor do item compõe o valor total da NF-e
                icms_origem=0,  # Nacional
                icms_csosn='102',  # Tributada pelo Simples Nacional sem permissão de crédito
                icms_modalidade='00',
                pis_modalidade='51',  # Operação tributada
                cofins_modalidade='51',  # Operação tributada
                pis_valor_base_calculo=Decimal('0.00'),
                pis_aliquota_percentual=Decimal('0.00'),
                pis_valor=Decimal('0.00'),
                cofins_valor_base_calculo=Decimal('0.00'),
                cofins_aliquota_percentual=Decimal('0.00'),
                cofins_valor=Decimal('0.00'),
                valor_tributos_aprox='0.00',
                informacoes_adicionais=produto_data.get('observacoes', '')
            )
    
    def _adicionar_pagamentos(self, notafiscal: NotaFiscal, pagamentos: List[Dict]):
        """
        Adiciona pagamentos à nota fiscal
        
        Args:
            notafiscal: Objeto NotaFiscal
            pagamentos: Lista de pagamentos
        """
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
            '99': 'Outros'
        }
        
        # Mapear tipos de pagamento por string
        tipo_map = {
            'dinheiro': '01',
            'credito': '03',
            'debito': '04',
            'pix': '99',
            'outros': '99'
        }
        
        for pagamento_data in pagamentos:
            tipo = pagamento_data.get('tipo', '01')
            
            # Se for string, mapear para código
            if isinstance(tipo, str) and tipo.lower() in tipo_map:
                tipo = tipo_map[tipo.lower()]
            
            # Garantir que é string
            tipo = str(tipo)
            
            descricao = tipos_pagamento.get(tipo, 'Outros')
            valor = float(pagamento_data.get('valor', 0))
            
            # Usar o método adicionar_pagamento do PyNFe
            notafiscal.adicionar_pagamento(
                t_pag=tipo,
                x_pag=descricao,
                v_pag=valor,
                ind_pag=0  # Pagamento à vista
            )
    
    def emitir(
        self,
        empresa_data: Dict,
        produtos: List[Dict],
        pagamentos: List[Dict],
        consumidor: Optional[Dict] = None,
        observacoes: str = '',
        numero_nfce: int = 1,
        ambiente_homologacao: bool = True
    ) -> Dict[str, Any]:
        """
        Emite NFC-e usando PyNFe
        
        Args:
            empresa_data: Dados da empresa
            produtos: Lista de produtos
            pagamentos: Lista de pagamentos
            consumidor: Dados do consumidor (opcional)
            observacoes: Observações
            numero_nfce: Número da NFC-e
            ambiente_homologacao: Se True, usa ambiente de homologação
            
        Returns:
            Dicionário com resultado da emissão
        """
        if not PYNFE_DISPONIVEL:
            return {
                'success': False,
                'error': 'PyNFe não está instalado. Execute: pip install pynfe',
                'error_type': 'PyNFENotInstalled'
            }
        
        try:
            print("=" * 70)
            print("🚀 EMISSÃO NFC-e - PyNFe (Versão Nova)")
            print("=" * 70)
            
            # 1. Preparar certificado
            print("\n[1/5] Preparando certificado...")
            certificado_base64 = empresa_data.get('certificado_base64') or empresa_data.get('certificadoDigitalUrl', '')
            senha = empresa_data.get('senhaCertificado') or empresa_data.get('senha_certificado', '')
            
            if not certificado_base64 or not senha:
                return {
                    'success': False,
                    'error': 'Certificado digital não fornecido',
                    'error_type': 'CertificateMissing'
                }
            
            cert_path = self._preparar_certificado(certificado_base64, senha)
            print("✅ Certificado preparado")
            
            # 2. Criar emitente
            print("\n[2/5] Criando emitente...")
            emitente = self._criar_emitente(empresa_data)
            print(f"✅ Emitente: {emitente.razao_social}")
            
            # 3. Criar cliente
            print("\n[3/5] Criando cliente...")
            # Usar município do emitente (já validado e limpo)
            municipio_empresa = emitente.endereco_municipio
            cliente = self._criar_cliente(consumidor, emitente.endereco_uf, municipio_empresa)
            print("✅ Cliente criado")
            
            # 4. Criar nota fiscal
            print("\n[4/5] Criando nota fiscal...")
            uf = empresa_data.get('uf', 'SP').upper()
            
            # Calcular totais
            valor_total = sum(float(p.get('valorTotal', 0)) for p in produtos)
            
            notafiscal = NotaFiscal(
                emitente=emitente,
                cliente=cliente,
                uf=uf,
                natureza_operacao='VENDA',
                forma_pagamento=0,  # À vista
                modelo=65,  # NFC-e
                serie=empresa_data.get('serie', '1'),
                numero_nf=numero_nfce,
                data_emissao=datetime.now(),
                data_saida_entrada=datetime.now(),
                tipo_documento=1,  # Entrada
                municipio=emitente.endereco_municipio,
                tipo_impressao=4,  # NFC-e
                forma_emissao=1,  # Normal
                cliente_final=1,  # Sim
                indicador_destino=1,  # Operação interna
                indicador_presencial=1,  # Operação presencial
                finalidade_emissao=1,  # Normal
                processo_emissao=0,  # Aplicativo do contribuinte
                valor_total=valor_total,
                valor_frete=0,
                valor_seguro=0,
                valor_desconto=0,
                valor_ii=0,
                valor_ipi=0,
                valor_pis=0,
                valor_cofins=0,
                valor_outras_despesas=0,
                valor_icms=0,
                valor_icms_desonerado=0,
                valor_fcp=0,
                valor_fcp_st=0,
                valor_fcp_st_ret=0,
                valor_icms_st=0,
                valor_icms_st_ret=0,
                valor_icms_uf_remet=0,
                valor_icms_uf_dest=0,
                valor_icms_fcp_uf_dest=0
            )
            
            # Adicionar produtos
            self._adicionar_produtos(notafiscal, produtos)
            print(f"✅ {len(produtos)} produto(s) adicionado(s)")
            
            # Adicionar pagamentos
            self._adicionar_pagamentos(notafiscal, pagamentos)
            print(f"✅ {len(pagamentos)} pagamento(s) adicionado(s)")
            
            # Garantir que nota fiscal está no _fonte_dados
            # (NotaFiscal já se adiciona automaticamente, mas garantimos)
            from pynfe.entidades.fonte_dados import _fonte_dados
            _fonte_dados.adicionar_objeto(notafiscal)
            
            # 5. Processar e enviar
            print("\n[5/5] Processando e enviando para SEFAZ...")
            
            # Criar comunicação com SEFAZ
            comunicacao = ComunicacaoSefaz(
                uf=uf,
                certificado=cert_path,
                certificado_senha=senha,  # CORRETO: certificado_senha, não senha
                homologacao=ambiente_homologacao
            )
            
            # Serializar e assinar
            from pynfe.processamento.serializacao import SerializacaoXML
            from pynfe.processamento.assinatura import AssinaturaA1
            
            # Serializar XML
            # IMPORTANTE: SerializacaoXML precisa receber _fonte_dados (objeto), não lista
            serializador = SerializacaoXML(_fonte_dados, homologacao=ambiente_homologacao)
            xml = serializador.exportar()
            
            # xml retorna um elemento raiz (NFe), não uma lista
            xml_nfe = xml
            
            # IMPORTANTE: Verificar se há IDs duplicados no XML antes de assinar
            # Isso evita o erro "Ambiguous reference URI"
            from lxml import etree as lxml_etree
            import random
            
            # Converter para string e parsear novamente para garantir estrutura correta
            xml_string = lxml_etree.tostring(xml_nfe, encoding='unicode', pretty_print=False)
            xml_parsed = lxml_etree.fromstring(xml_string.encode('utf-8'))
            
            # Verificar IDs duplicados e elementos duplicados
            ids_encontrados = {}
            elementos_para_remover = []
            
            for elem in xml_parsed.iter():
                if 'Id' in elem.attrib:
                    id_value = elem.attrib['Id']
                    if id_value in ids_encontrados:
                        print(f'⚠️ ID duplicado encontrado: {id_value}')
                        print(f'⚠️ Primeiro elemento: {ids_encontrados[id_value].tag}')
                        print(f'⚠️ Segundo elemento: {elem.tag}')
                        
                        # CRÍTICO: Se são ambos infNFe, remover o segundo completamente
                        # Renomear o ID quebra o schema XML e a assinatura digital
                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                        tag_primeiro = ids_encontrados[id_value].tag.split('}')[-1] if '}' in ids_encontrados[id_value].tag else ids_encontrados[id_value].tag
                        
                        if tag_local == 'infNFe' and tag_primeiro == 'infNFe':
                            # Dois infNFe com mesmo ID - remover o segundo
                            print(f'⚠️ Removendo elemento infNFe duplicado (mantendo apenas o primeiro)')
                            elementos_para_remover.append(elem)
                        elif elem.tag != ids_encontrados[id_value].tag:
                            # Tags diferentes - remover o ID do segundo
                            del elem.attrib['Id']
                            print(f'⚠️ ID removido do segundo elemento (tag diferente)')
                        else:
                            # Mesma tag mas não é infNFe - remover o elemento duplicado
                            print(f'⚠️ Removendo elemento duplicado: {tag_local}')
                            elementos_para_remover.append(elem)
                    else:
                        ids_encontrados[id_value] = elem
            
            # Remover elementos duplicados
            for elem in elementos_para_remover:
                parent = elem.getparent()
                if parent is not None:
                    parent.remove(elem)
                    print(f'✅ Elemento duplicado removido: {elem.tag}')
            
            if ids_encontrados:
                print(f'✅ XML verificado, {len(ids_encontrados)} IDs únicos encontrados')
            
            # Validar que há apenas um infNFe
            inf_nfe_elements = xml_parsed.findall('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or xml_parsed.findall('.//infNFe')
            if len(inf_nfe_elements) > 1:
                print(f'⚠️ AVISO: Ainda há {len(inf_nfe_elements)} elementos infNFe (deve haver apenas 1)')
                # Remover todos exceto o primeiro
                for inf_nfe in inf_nfe_elements[1:]:
                    parent = inf_nfe.getparent()
                    if parent is not None:
                        parent.remove(inf_nfe)
                        print(f'✅ Elemento infNFe duplicado removido')
            
            # Usar XML parseado (sem IDs duplicados e sem elementos duplicados)
            xml_nfe = xml_parsed
            
            # CORREÇÃO CRÍTICA: Corrigir campos ANTES de assinar
            # Corrigir cMunFG e verProc no XML antes da assinatura
            codigo_ibge_empresa = empresa_data.get('codigoIBGE') or empresa_data.get('codigoIbge') or empresa_data.get('codigo_municipio_ibge')
            
            # Procurar e corrigir no xml_nfe ANTES de assinar
            for elem in xml_nfe.iter():
                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                
                # Corrigir cMunFG: deve ser código IBGE (7 dígitos), não texto
                if tag_limpa == 'cMunFG':
                    if codigo_ibge_empresa:
                        codigo_ibge_str = str(codigo_ibge_empresa).strip().zfill(7)
                        if len(codigo_ibge_str) > 7:
                            codigo_ibge_str = codigo_ibge_str[-7:]
                        elem.text = codigo_ibge_str
                        print(f'✅ cMunFG corrigido ANTES da assinatura: {codigo_ibge_str}')
                    elif elem.text and not elem.text.strip().isdigit():
                        # Tentar obter do cMun do emitente
                        for emit_elem in xml_nfe.iter():
                            emit_tag = emit_elem.tag.split('}')[-1] if '}' in emit_elem.tag else emit_elem.tag
                            if emit_tag == 'cMun' and emit_elem.text and emit_elem.text.strip().isdigit():
                                codigo_ibge_str = emit_elem.text.strip().zfill(7)
                                if len(codigo_ibge_str) > 7:
                                    codigo_ibge_str = codigo_ibge_str[-7:]
                                elem.text = codigo_ibge_str
                                print(f'✅ cMunFG corrigido usando cMun do emitente (ANTES da assinatura): {codigo_ibge_str}')
                                break
                
                # Corrigir verProc: não deve conter "PyNFe"
                if tag_limpa == 'verProc':
                    if elem.text and ('PyNFe' in elem.text or 'pynfe' in elem.text.lower()):
                        elem.text = 'Sistema Exodo'
                        print('✅ verProc corrigido ANTES da assinatura: Sistema Exodo')
            
            # Assinar XML (já corrigido)
            assinador = AssinaturaA1(cert_path, senha)
            xml_assinado = assinador.assinar(xml_nfe)
            
            # xml_assinado também pode ser uma lista, pegar o primeiro elemento
            if isinstance(xml_assinado, list) and len(xml_assinado) > 0:
                xml_assinado_nfe = xml_assinado[0]
            else:
                xml_assinado_nfe = xml_assinado
            
            # Validar formato do XML antes de enviar
            # O XML deve ser um elemento <NFe>, não <infNFe>
            from lxml import etree as lxml_etree
            
            # Verificar se é NFe ou infNFe
            tag_raiz = xml_assinado_nfe.tag.split('}')[-1] if '}' in xml_assinado_nfe.tag else xml_assinado_nfe.tag
            
            if tag_raiz == 'infNFe':
                # Se é infNFe, criar wrapper NFe
                print('⚠️ XML é infNFe, criando wrapper NFe...')
                nfe_wrapper = lxml_etree.Element('NFe', xmlns='http://www.portalfiscal.inf.br/nfe')
                nfe_wrapper.append(xml_assinado_nfe)
                xml_assinado_nfe = nfe_wrapper
                print('✅ Wrapper NFe criado')
            elif tag_raiz != 'NFe':
                # Tentar encontrar NFe dentro
                nfe_encontrado = xml_assinado_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or xml_assinado_nfe.find('.//NFe')
                if nfe_encontrado is not None:
                    xml_assinado_nfe = nfe_encontrado
                    print('✅ Elemento NFe encontrado dentro do XML')
                else:
                    raise ValueError(f'XML deve ser um elemento NFe, recebido: {tag_raiz}')
            
            # NOVA ABORDAGEM: Criar XML do lote MANUALMENTE seguindo padrão SEFAZ
            # Não usar PyNFe para criar o lote - criar enviNFe manualmente
            from lxml import etree as lxml_etree
            
            # Garantir que id_lote tem 15 dígitos (schema XSD exige)
            id_lote_corrigido = str(numero_nfce).zfill(15)
            if len(id_lote_corrigido) > 15:
                id_lote_corrigido = id_lote_corrigido[-15:]
            
            print(f'📋 idLote: {id_lote_corrigido} ({len(id_lote_corrigido)} dígitos)')
            
            # Criar enviNFe manualmente (padrão SEFAZ)
            ns_nfe = 'http://www.portalfiscal.inf.br/nfe'
            # Criar elemento sem nsmap primeiro, depois definir xmlns e versao
            # Isso evita xmlns duplicado
            envi_nfe_manual = lxml_etree.Element('enviNFe')
            envi_nfe_manual.set('xmlns', ns_nfe)
            envi_nfe_manual.set('versao', '4.00')
            
            # idLote (PRIMEIRO elemento, 15 dígitos)
            id_lote_elem = lxml_etree.SubElement(envi_nfe_manual, 'idLote')
            id_lote_elem.text = id_lote_corrigido
            
            # indSinc (SEGUNDO elemento, obrigatório para NFC-e = 1)
            ind_sinc_elem = lxml_etree.SubElement(envi_nfe_manual, 'indSinc')
            ind_sinc_elem.text = '1'
            
            # NFe (TERCEIRO elemento) - adicionar o XML assinado
            # IMPORTANTE: NFe não deve ter xmlns próprio (herda do enviNFe)
            # E os elementos dentro do NFe devem herdar o namespace do enviNFe
            
            # Função recursiva para copiar elementos sem prefixos, garantindo herança de namespace
            def copiar_elemento_sem_prefixo(elem_orig, ns_uri):
                """Cria novo elemento sem prefixo de namespace, garantindo herança do namespace do pai"""
                # Extrair nome local (sem namespace)
                if elem_orig.tag.startswith('{'):
                    nome_local = elem_orig.tag.split('}')[-1]
                else:
                    nome_local = elem_orig.tag
                
                # Criar novo elemento sem prefixo (herda namespace do pai enviNFe)
                novo_elem = lxml_etree.Element(nome_local)
                
                # Copiar atributos (exceto xmlns)
                for attr, valor in elem_orig.attrib.items():
                    if not attr.startswith('xmlns'):
                        novo_elem.set(attr, valor)
                
                # Copiar texto e tail
                novo_elem.text = elem_orig.text
                novo_elem.tail = elem_orig.tail
                
                # Processar filhos recursivamente
                for filho in elem_orig:
                    novo_filho = copiar_elemento_sem_prefixo(filho, ns_uri)
                    novo_elem.append(novo_filho)
                
                return novo_elem
            
            # CRÍTICO: Não copiar o XML assinado - usar diretamente
            # Copiar elementos quebra a assinatura digital porque cria novos elementos
            # A assinatura está vinculada aos elementos específicos do XML original
            
            # CRÍTICO: Remover o NFe do pai atual (se tiver) ANTES de adicionar ao enviNFe
            # Isso preserva a assinatura digital porque não estamos copiando, apenas movendo
            parent_atual = xml_assinado_nfe.getparent()
            if parent_atual is not None:
                # Remover do pai atual (isso não quebra a assinatura, apenas move o elemento)
                parent_atual.remove(xml_assinado_nfe)
                print('✅ NFe removido do pai atual (preservando assinatura)')
            
            # Remover namespace do NFe se existir (herda do enviNFe)
            if 'xmlns' in xml_assinado_nfe.attrib:
                del xml_assinado_nfe.attrib['xmlns']
                print('✅ Namespace removido do NFe (herda do enviNFe)')
            
            # Adicionar diretamente ao enviNFe (sem cópia - preserva assinatura)
            envi_nfe_manual.append(xml_assinado_nfe)
            print('✅ NFe adicionada diretamente ao enviNFe (sem cópia - assinatura preservada)')
            
            # Verificar se o NFe foi adicionado corretamente
            nfe_filhos = [child for child in envi_nfe_manual if child.tag.endswith('NFe') or child.tag == 'NFe']
            if not nfe_filhos:
                print('⚠️ AVISO: NFe não foi adicionado ao enviNFe!')
                print(f'   📋 Filhos atuais do enviNFe: {[child.tag for child in envi_nfe_manual]}')
                # Tentar adicionar novamente
                if xml_assinado_nfe.getparent() is None:
                    envi_nfe_manual.append(xml_assinado_nfe)
                    print('✅ NFe adicionado novamente')
                else:
                    # Fazer cópia e adicionar
                    from lxml.etree import tostring, fromstring
                    xml_assinado_str = tostring(xml_assinado_nfe, encoding='unicode')
                    xml_assinado_copia = fromstring(xml_assinado_str)
                    if 'xmlns' in xml_assinado_copia.attrib:
                        del xml_assinado_copia.attrib['xmlns']
                    envi_nfe_manual.append(xml_assinado_copia)
                    print('✅ NFe copiado e adicionado novamente')
            else:
                print(f'✅ NFe confirmado no enviNFe: {len(nfe_filhos)} elemento(s) encontrado(s)')
                print(f'   📋 Tag do NFe: {nfe_filhos[0].tag}')
                print(f'   📋 Filhos do enviNFe: {[child.tag.split("}")[-1] if "}" in child.tag else child.tag for child in envi_nfe_manual]}')
            
            print('✅ XML do lote criado manualmente (padrão SEFAZ)')
            print(f'   📋 Estrutura: enviNFe > idLote, indSinc, NFe')
            
            # Verificar novamente antes de interceptar
            nfe_filhos_final = [child for child in envi_nfe_manual if child.tag.endswith('NFe') or child.tag == 'NFe']
            if not nfe_filhos_final:
                print('❌ ERRO CRÍTICO: NFe não está no enviNFe antes de interceptar!')
                # Serializar para debug
                try:
                    from lxml.etree import tostring
                    debug_xml = tostring(envi_nfe_manual, encoding='unicode')
                    print(f'   📄 XML do enviNFe (debug): {debug_xml[:500]}')
                except Exception as e:
                    print(f'   ⚠️ Erro ao serializar para debug: {e}')
            
            # Interceptar requests.post para usar nosso XML do lote manual
            import requests
            original_post = requests.post
            xml_lote_corrigido = None
            
            def post_interceptado(*args, **kwargs):
                """Intercepta requisição HTTP para substituir XML do lote pelo nosso XML manual"""
                # Capturar variáveis do escopo externo
                nonlocal xml_lote_corrigido
                # IMPORTANTE: envi_nfe_manual é capturado do closure, mas precisamos garantir
                # que estamos usando a versão atualizada com o NFe
                
                # Verificar se envi_nfe_manual tem NFe ANTES de usar
                nfe_filhos_closure = [child for child in envi_nfe_manual if child.tag.endswith('NFe') or child.tag == 'NFe']
                if not nfe_filhos_closure:
                    print('   ⚠️ AVISO: enviNFe no closure não tem NFe, recriando...')
                    # Se não tem NFe, adicionar novamente
                    if xml_assinado_nfe.getparent() is None:
                        if 'xmlns' in xml_assinado_nfe.attrib:
                            del xml_assinado_nfe.attrib['xmlns']
                        envi_nfe_manual.append(xml_assinado_nfe)
                        print('   ✅ NFe adicionado ao enviNFe no closure')
                    else:
                        from lxml.etree import tostring, fromstring
                        xml_assinado_str = tostring(xml_assinado_nfe, encoding='unicode')
                        xml_assinado_copia = fromstring(xml_assinado_str)
                        if 'xmlns' in xml_assinado_copia.attrib:
                            del xml_assinado_copia.attrib['xmlns']
                        envi_nfe_manual.append(xml_assinado_copia)
                        print('   ✅ NFe copiado e adicionado ao enviNFe no closure')
                
                # Obter body da requisição
                body = kwargs.get('data') or kwargs.get('body')
                body_em_args = False
                body_index = None
                
                if not body and len(args) > 1:
                    body = args[1]
                    body_em_args = True
                    body_index = 1
                
                # Verificar se contém enviNFe (lote) - se sim, substituir pelo nosso XML manual
                if body and isinstance(body, (str, bytes)):
                    xml_str = body.decode('utf-8') if isinstance(body, bytes) else body
                    
                    if 'enviNFe' in xml_str or 'nfeDadosMsg' in xml_str:
                        print('🔧 Interceptando XML do lote - substituindo pelo XML manual (padrão SEFAZ)...')
                        
                        try:
                            from lxml import etree as lxml_etree
                            
                            # Construir envelope SOAP com nosso enviNFe manual
                            # O PyNFe envia em envelope SOAP, então precisamos manter a estrutura SOAP
                            
                            # Verificar se o XML original está em envelope SOAP
                            xml_str_original = xml_str
                            tem_soap = 'soap:Envelope' in xml_str_original or 'soap:Body' in xml_str_original
                            
                            if tem_soap:
                                # Parsear envelope SOAP original para manter estrutura
                                # Remover declaração XML se existir (causa erro no lxml)
                                xml_para_parse = xml_str_original
                                if xml_para_parse.strip().startswith('<?xml'):
                                    # Remover declaração XML
                                    xml_para_parse = xml_para_parse.split('?>', 1)[1] if '?>' in xml_para_parse else xml_para_parse
                                
                                try:
                                    xml_parsed = lxml_etree.fromstring(xml_para_parse.encode('utf-8'))
                                except Exception as e1:
                                    try:
                                        xml_parsed = lxml_etree.fromstring(xml_para_parse)
                                    except Exception as e2:
                                        print(f'⚠️ Erro ao parsear XML SOAP: {e2}')
                                        raise
                                
                                # Procurar nfeDadosMsg no SOAP
                                nfe_dados_msg = None
                                for elem in xml_parsed.iter():
                                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                    if tag_limpa == 'nfeDadosMsg':
                                        nfe_dados_msg = elem
                                        break
                                
                                if nfe_dados_msg is not None:
                                    # Limpar nfeDadosMsg e adicionar nosso enviNFe manual
                                    nfe_dados_msg.clear()
                                    
                                    # IMPORTANTE: Verificar se envi_nfe_manual tem o NFe antes de copiar
                                    nfe_filhos_antes = [child for child in envi_nfe_manual if child.tag.endswith('NFe') or child.tag == 'NFe']
                                    if not nfe_filhos_antes:
                                        print('   ❌ ERRO: enviNFe não tem NFe antes de copiar para SOAP!')
                                        print(f'   📋 Filhos do enviNFe: {[child.tag for child in envi_nfe_manual]}')
                                    else:
                                        print(f'   ✅ enviNFe tem {len(nfe_filhos_antes)} NFe(s) antes de copiar')
                                    
                                    # IMPORTANTE: Copiar o enviNFe manual para dentro do nfeDadosMsg
                                    # Não podemos usar append direto porque pode haver problemas de namespace
                                    from lxml.etree import tostring, fromstring
                                    envi_nfe_str = tostring(envi_nfe_manual, encoding='unicode')
                                    
                                    # Verificar se o NFe está no XML serializado
                                    if '<NFe' not in envi_nfe_str and '</NFe>' not in envi_nfe_str:
                                        print('   ❌ ERRO: NFe não está no XML serializado!')
                                        print(f'   📄 XML serializado (primeiros 500 chars): {envi_nfe_str[:500]}')
                                    else:
                                        print('   ✅ NFe encontrado no XML serializado')
                                    
                                    envi_nfe_copia = fromstring(envi_nfe_str)
                                    
                                    # Verificar se o NFe está na cópia
                                    nfe_filhos_copia = [child for child in envi_nfe_copia if child.tag.endswith('NFe') or child.tag == 'NFe']
                                    if not nfe_filhos_copia:
                                        print('   ❌ ERRO: NFe não está na cópia após parsear!')
                                    else:
                                        print(f'   ✅ NFe confirmado na cópia: {len(nfe_filhos_copia)} elemento(s)')
                                    
                                    nfe_dados_msg.append(envi_nfe_copia)
                                    print('   ✅ enviNFe manual inserido no envelope SOAP')
                                    
                                    # Verificar novamente após inserir
                                    nfe_filhos_apos = [child for child in nfe_dados_msg[0] if child.tag.endswith('NFe') or child.tag == 'NFe']
                                    if nfe_filhos_apos:
                                        print(f'   ✅ NFe confirmado no enviNFe após inserção ({len(nfe_filhos_apos)} encontrado(s))')
                                    else:
                                        print('   ❌ ERRO: NFe não encontrado no enviNFe após inserção!')
                                        print(f'   📋 Filhos do enviNFe após inserção: {[child.tag for child in nfe_dados_msg[0]]}')
                                    
                                    # Serializar envelope SOAP com nosso enviNFe
                                    xml_final = lxml_etree.tostring(
                                        xml_parsed,
                                        encoding='unicode',
                                        xml_declaration=False,
                                        pretty_print=False
                                    )
                                else:
                                    # Se não encontrou nfeDadosMsg, criar estrutura SOAP completa
                                    print('   ⚠️ nfeDadosMsg não encontrado, criando estrutura SOAP completa...')
                                    # Criar envelope SOAP do zero
                                    soap_env = lxml_etree.Element(
                                        '{http://www.w3.org/2003/05/soap-envelope}Envelope',
                                        nsmap={
                                            'soap': 'http://www.w3.org/2003/05/soap-envelope',
                                            'xsi': 'http://www.w3.org/2001/XMLSchema-instance',
                                            'xsd': 'http://www.w3.org/2001/XMLSchema'
                                        }
                                    )
                                    soap_body = lxml_etree.SubElement(
                                        soap_env,
                                        '{http://www.w3.org/2003/05/soap-envelope}Body'
                                    )
                                    nfe_dados_msg_novo = lxml_etree.SubElement(
                                        soap_body,
                                        '{http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4}nfeDadosMsg'
                                    )
                                    nfe_dados_msg_novo.append(envi_nfe_manual)
                                    
                                    xml_final = lxml_etree.tostring(
                                        soap_env,
                                        encoding='unicode',
                                        xml_declaration=False,
                                        pretty_print=False
                                    )
                            else:
                                # Não está em SOAP, usar apenas enviNFe
                                xml_final = lxml_etree.tostring(
                                    envi_nfe_manual,
                                    encoding='unicode',
                                    xml_declaration=False,
                                    pretty_print=False
                                )
                            
                            # Remover quebras de linha
                            xml_final = xml_final.replace('\n', '').replace('\r', '')
                            
                            # CORREÇÃO FINAL: Substituir campos problemáticos por string (último recurso)
                            # IMPORTANTE: Aplicar correções em TODOS os casos
                            import re
                            
                            # Padrão: <cMunFG>SAO JOSE DOS CAMPOS</cMunFG> -> <cMunFG>3549904</cMunFG>
                            codigo_ibge_final = empresa_data.get('codigoIBGE') or empresa_data.get('codigoIbge') or empresa_data.get('codigo_municipio_ibge')
                            if not codigo_ibge_final:
                                # Tentar extrair do XML (cMun do emitente)
                                cMun_match = re.search(r'<cMun>(\d{7})</cMun>', xml_final)
                                if cMun_match:
                                    codigo_ibge_final = cMun_match.group(1)
                                    print(f'📋 Código IBGE extraído do XML: {codigo_ibge_final}')
                            
                            if codigo_ibge_final:
                                codigo_ibge_str = str(codigo_ibge_final).strip().zfill(7)
                                if len(codigo_ibge_str) > 7:
                                    codigo_ibge_str = codigo_ibge_str[-7:]
                                # Substituir QUALQUER valor de cMunFG (garantir que seja código IBGE)
                                xml_antes = xml_final
                                xml_final = re.sub(
                                    r'<cMunFG>[^<]*</cMunFG>',
                                    f'<cMunFG>{codigo_ibge_str}</cMunFG>',
                                    xml_final
                                )
                                if xml_antes != xml_final:
                                    print(f'✅ cMunFG corrigido no XML final: {codigo_ibge_str}')
                                else:
                                    print(f'⚠️ cMunFG não foi encontrado ou já estava correto')
                            else:
                                print('⚠️ Código IBGE não encontrado para corrigir cMunFG')
                            
                            # Corrigir verProc se contiver PyNFe (sempre verificar)
                            xml_antes_verproc = xml_final
                            if 'PyNFe' in xml_final or 'pynfe' in xml_final.lower():
                                xml_final = re.sub(
                                    r'<verProc>[^<]*</verProc>',
                                    '<verProc>Sistema Exodo</verProc>',
                                    xml_final,
                                    flags=re.IGNORECASE
                                )
                                if xml_antes_verproc != xml_final:
                                    print('✅ verProc corrigido no XML final: Sistema Exodo')
                            else:
                                # Verificar se já está correto
                                if '<verProc>Sistema Exodo</verProc>' in xml_final:
                                    print('✅ verProc já está correto: Sistema Exodo')
                            
                            # CRÍTICO: Remover namespace do NFe (deve herdar do enviNFe)
                            # O schema XSD exige que o NFe dentro do enviNFe NÃO tenha xmlns próprio
                            if '<NFe' in xml_final:
                                import re
                                # Remover xmlns do NFe (deve herdar do enviNFe)
                                xml_final = re.sub(
                                    r'<NFe\s+xmlns="[^"]*"',
                                    '<NFe',
                                    xml_final
                                )
                                # Remover xmlns duplicado se existir
                                xml_final = re.sub(
                                    r'<NFe\s+xmlns="[^"]*"\s+xmlns="[^"]*"',
                                    '<NFe',
                                    xml_final
                                )
                                print('✅ Namespace removido do NFe (herda do enviNFe)')
                            
                            # Adicionar declaração XML se o original tinha
                            if xml_str_original.strip().startswith('<?xml'):
                                xml_final = '<?xml version="1.0" encoding="UTF-8"?>' + xml_final
                            
                            xml_lote_corrigido = xml_final
                            print('✅ XML do lote substituído pelo XML manual (padrão SEFAZ)')
                            
                            # Salvar XML para debug
                            try:
                                import datetime
                                timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
                                log_dir = os.path.join(os.getcwd(), 'logs', 'empresas', empresa_data.get('cnpj', 'UNKNOWN'))
                                os.makedirs(log_dir, exist_ok=True)
                                xml_filename = os.path.join(log_dir, f'lote_enviNFe_manual_{timestamp}.xml')
                                with open(xml_filename, 'w', encoding='utf-8') as f:
                                    f.write(xml_final)
                                print(f'   📄 XML manual salvo em: {xml_filename}')
                            except Exception as e_save:
                                print(f'   ⚠️ Erro ao salvar XML: {e_save}')
                            
                            # Atualizar body da requisição
                            if 'data' in kwargs:
                                kwargs['data'] = xml_final
                            elif 'body' in kwargs:
                                kwargs['body'] = xml_final
                            elif body_em_args and body_index is not None:
                                # Remover do args e adicionar em kwargs
                                new_args = list(args)
                                new_args.pop(body_index)
                                kwargs['data'] = xml_final
                                args = tuple(new_args)
                                
                        except Exception as e_correcao:
                            print(f'⚠️ Erro ao substituir XML do lote: {e_correcao}')
                            import traceback
                            traceback.print_exc()
                            
                # Chamar método original com XML substituído (se foi substituído)
                if body_em_args and 'data' in kwargs and len(args) > 1:
                    # Remover body dos args e usar kwargs['data']
                    new_args = (args[0],) + args[2:] if len(args) > 2 else (args[0],)
                    return original_post(*new_args, **kwargs)
                else:
                    return original_post(*args, **kwargs)
            
            # IMPORTANTE: Desabilitar interceptação temporariamente para testar
            # Se o PyNFe gerar o XML corretamente, não precisamos interceptar
            usar_interceptacao = True  # Mudar para False para testar sem interceptação
            
            if usar_interceptacao:
                # Aplicar monkey patch
                requests.post = post_interceptado
                print('🔧 Interceptação de requests.post ATIVADA')
            else:
                print('⚠️ Interceptação de requests.post DESATIVADA - usando XML do PyNFe diretamente')
            
            try:
                # Enviar para SEFAZ
                # O método autorizacao retorna uma tupla:
                # - Sucesso síncrono (ind_sinc=1): (0, raiz) onde raiz é o XML nfeProc
                # - Erro: (1, retorno, nota_fiscal) onde retorno é o objeto Response
                resultado = comunicacao.autorizacao(
                    modelo='nfce',  # String 'nfce', não int 65
                    nota_fiscal=xml_assinado_nfe,  # Elemento XML NFe, não string
                    id_lote=id_lote_corrigido,  # idLote com 15 dígitos (schema XSD exige)
                    ind_sinc=1,  # Síncrono (NFC-e sempre síncrono)
                    contingencia=False,
                    timeout=60
                )
            finally:
                # Restaurar método original
                requests.post = original_post
            
            # Processar resultado
            # resultado é uma tupla: (status, xml_resposta) ou (status, retorno, nota_fiscal)
            if isinstance(resultado, tuple) and len(resultado) >= 2:
                status = resultado[0]
                
                if status == 0:  # Sucesso
                    # resultado[1] é o XML nfeProc com a nota autorizada
                    raiz = resultado[1]
                    
                    # Extrair dados do protocolo
                    from lxml import etree
                    ns = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                    
                    # Buscar protNFe
                    prot_nfe = raiz.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                    if prot_nfe is None:
                        prot_nfe = raiz.find('.//protNFe')
                    
                    if prot_nfe is not None:
                        inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt')
                        if inf_prot is None:
                            inf_prot = prot_nfe.find('.//infProt')
                        
                        if inf_prot is not None:
                            c_stat = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                            if c_stat is None:
                                c_stat = inf_prot.find('.//cStat')
                            
                            if c_stat is not None and c_stat.text == '100':
                                # Autorizada
                                n_prot = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt')
                                if n_prot is None:
                                    n_prot = inf_prot.find('.//nProt')
                                
                                chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe')
                                if chave is None:
                                    chave = inf_prot.find('.//chNFe')
                                
                                # Converter XML para string
                                xml_str = etree.tostring(raiz, encoding='unicode', pretty_print=True)
                                
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'numero': numero_nfce,
                                    'protocolo': n_prot.text if n_prot is not None else '',
                                    'chave_acesso': chave.text if chave is not None else '',
                                    'xml': xml_str,
                                    'mensagem': 'NFC-e autorizada com sucesso'
                                }
                            else:
                                # Não autorizada
                                x_motivo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                if x_motivo is None:
                                    x_motivo = inf_prot.find('.//xMotivo')
                                
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'error': f'NFC-e não autorizada: {c_stat.text if c_stat is not None else "Desconhecido"} - {x_motivo.text if x_motivo is not None else ""}',
                                    'error_type': 'NotAuthorized',
                                    'cstat': c_stat.text if c_stat is not None else '',
                                    'xmotivo': x_motivo.text if x_motivo is not None else ''
                                }
                
                elif status == 1:  # Erro
                    # resultado[1] é o objeto Response com erro
                    retorno = resultado[1]
                    error_msg = 'Erro ao enviar NFC-e para SEFAZ'
                    
                    # Tentar obter mais detalhes do erro
                    if hasattr(retorno, 'text') and retorno.text:
                        error_msg = f'Erro SEFAZ: {retorno.text[:1000]}'
                    elif hasattr(retorno, 'status_code'):
                        status_code = retorno.status_code
                        error_msg = f'Erro HTTP {status_code}'
                        
                        # Para HTTP 400, tentar obter mais detalhes
                        if status_code == 400:
                            if hasattr(retorno, 'content'):
                                try:
                                    error_content = retorno.content.decode('utf-8')[:1000]
                                    error_msg = f'Erro HTTP 400 (Bad Request): {error_content}'
                                except:
                                    error_msg = f'Erro HTTP 400 (Bad Request) - Verifique o XML do lote'
                    
                    # Log detalhado do erro
                    print(f'❌ Erro na comunicação com SEFAZ: {error_msg}')
                    if hasattr(retorno, 'headers'):
                        print(f'   Headers: {retorno.headers}')
                    
                    return {
                        'success': False,
                        'autorizada': False,
                        'error': error_msg,
                        'error_type': 'SEFAZError',
                        'resultado': str(retorno),
                        'status_code': getattr(retorno, 'status_code', None)
                    }
            
            # Se chegou aqui, formato de retorno inesperado
            return {
                'success': False,
                'autorizada': False,
                'error': 'Formato de retorno inesperado da SEFAZ',
                'error_type': 'UnexpectedResponse',
                'resultado': str(resultado)
            }
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e: {str(e)}',
                'error_type': 'EmissionError',
                'traceback': traceback.format_exc()
            }
        
        finally:
            # Limpar certificado temporário
            if self.cert_path and os.path.exists(self.cert_path):
                try:
                    os.remove(self.cert_path)
                except:
                    pass


def criar_servico_nfce_pynfe_novo():
    """
    Cria e retorna instância do serviço NFC-e PyNFe novo
    
    Returns:
        Instância de NFCePyNFeNovo ou None se PyNFe não estiver disponível
    """
    if not PYNFE_DISPONIVEL:
        print("❌ PyNFe não está disponível")
        return None
    
    return NFCePyNFeNovo()

