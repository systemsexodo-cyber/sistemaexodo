"""
NFC-e usando PyNFe - Implementação com PyNFe instalado em modo desenvolvimento
Funciona para estados que usam WSDL (não funciona bem para SP)
"""

import base64
import tempfile
import os
from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, List, Optional, Any

# Importar PyNFe (instalado em modo desenvolvimento)
# Primeiro tentar importar do PyNFe instalado globalmente
# Se falhar, tentar do diretório local PyNFe
import sys
import os

# Adicionar caminho do PyNFe instalado ao sys.path se necessário
pynfe_path = os.path.join(os.path.dirname(__file__), '..', '..', 'PyNFe')
if os.path.exists(pynfe_path) and pynfe_path not in sys.path:
    sys.path.insert(0, pynfe_path)
    print(f"[INFO] Adicionado PyNFe ao sys.path: {pynfe_path}")

PYNFE_DISPONIVEL = False
try:
    from pynfe.entidades.cliente import Cliente
    from pynfe.entidades.emitente import Emitente
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.entidades.fonte_dados import _fonte_dados
    from pynfe.processamento.assinatura import AssinaturaA1
    from pynfe.processamento.serializacao import SerializacaoXML
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    from pynfe.utils.flags import CODIGO_BRASIL
    PYNFE_DISPONIVEL = True
    print("[OK] PyNFe importado com sucesso")
except ImportError as e:
    PYNFE_DISPONIVEL = False
    print(f"[AVISO] PyNFe não disponível: {e}")
    print(f"[INFO] Caminho tentado: {pynfe_path}")
    print(f"[INFO] Caminho existe: {os.path.exists(pynfe_path)}")


class NFCePyNFe:
    """
    Classe para emissão de NFC-e usando PyNFe
    Funciona para estados que usam WSDL (não funciona bem para SP)
    """
    
    def __init__(self):
        """Inicializa o serviço"""
        if not PYNFE_DISPONIVEL:
            raise ImportError(
                "PyNFe não está instalado. "
                "Instale o PyNFe: pip install pynfe"
            )
        self.certificado_path = None
        self.senha_certificado = None
    
    def _preparar_certificado(self, certificado_base64: str, senha: str) -> str:
        """
        Prepara certificado salvando em arquivo temporário
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
        
        Returns:
            Caminho do arquivo temporário
        """
        cert_bytes = base64.b64decode(certificado_base64)
        cert_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pfx')
        cert_file.write(cert_bytes)
        cert_file.close()
        
        self.certificado_path = cert_file.name
        self.senha_certificado = senha.encode('utf-8') if isinstance(senha, str) else senha
        
        return cert_file.name
    
    def _criar_emitente(self, empresa_data: Dict) -> Emitente:
        """Cria objeto Emitente do PyNFe"""
        return Emitente(
            razao_social=empresa_data.get('razao_social', empresa_data.get('razaoSocial', '')),
            nome_fantasia=empresa_data.get('nome_fantasia', empresa_data.get('nomeFantasia', '')),
            cnpj=empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', ''),
            codigo_de_regime_tributario=empresa_data.get('crt', '3'),
            inscricao_estadual=empresa_data.get('inscricao_estadual', empresa_data.get('inscricaoEstadual', '')),
            inscricao_municipal=empresa_data.get('inscricao_municipal', ''),
            cnae_fiscal=empresa_data.get('cnae', ''),
            endereco_logradouro=empresa_data.get('endereco', ''),
            endereco_numero=empresa_data.get('numero', ''),
            endereco_bairro=empresa_data.get('bairro', ''),
            endereco_municipio=empresa_data.get('cidade', ''),
            endereco_uf=empresa_data.get('uf', 'SP'),
            endereco_cep=empresa_data.get('cep', '').replace('-', ''),
            endereco_pais=CODIGO_BRASIL,
            endereco_telefone=empresa_data.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', ''),
        )
    
    def _criar_cliente(self, consumidor: Optional[Dict]) -> Cliente:
        """Cria objeto Cliente do PyNFe"""
        if consumidor and consumidor.get('cpf'):
            return Cliente(
                razao_social=consumidor.get('nome', 'CONSUMIDOR FINAL'),
                tipo_documento='CPF',
                numero_documento=consumidor.get('cpf', '').replace('.', '').replace('-', ''),
                indicador_ie=9,  # 9=Não contribuinte
                endereco_logradouro='',
                endereco_numero='0',
                endereco_bairro='',
                endereco_municipio='',
                endereco_uf='',
                endereco_cep='',
                endereco_pais=CODIGO_BRASIL,
            )
        else:
            return Cliente(
                razao_social='CONSUMIDOR FINAL',
                tipo_documento='CPF',
                numero_documento='00000000000',
                indicador_ie=9,
                endereco_logradouro='',
                endereco_numero='0',
                endereco_bairro='',
                endereco_municipio='',
                endereco_uf='',
                endereco_cep='',
                endereco_pais=CODIGO_BRASIL,
            )
    
    def _criar_notafiscal(
        self,
        emitente: Emitente,
        cliente: Cliente,
        empresa_data: Dict,
        numero_nfce: int
    ) -> NotaFiscal:
        """Cria objeto NotaFiscal do PyNFe"""
        ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
        tipo_ambiente = 2 if ambiente_homologacao else 1
        
        # Data/hora atual
        now = datetime.now(timezone.utc)
        
        return NotaFiscal(
            emitente=emitente,
            cliente=cliente,
            uf=empresa_data.get('uf', 'SP'),
            natureza_operacao=empresa_data.get('natureza_operacao', 'VENDA'),
            modelo=65,  # NFC-e
            serie=str(empresa_data.get('serie_nfce', 1)),
            numero_nf=str(numero_nfce),
            data_emissao=now,
            data_saida_entrada=now,
            tipo_documento=1,  # Saída
            municipio=empresa_data.get('codigo_municipio_ibge', empresa_data.get('codigoIBGE', '3550308')),
            tipo_impressao_danfe=4,  # 4=DANFE NFC-e
            forma_emissao='1',  # Normal
            cliente_final=1,  # Consumidor final
            indicador_destino=1,  # Operação interna
            indicador_presencial=1,  # Presencial
            finalidade_emissao=1,  # Normal
            processo_emissao='0',  # Emissão própria
            transporte_modalidade_frete=1,
            informacoes_adicionais_interesse_fisco=empresa_data.get('observacoes', ''),
            totais_tributos_aproximado=Decimal('0.00'),
        )
    
    def _adicionar_produtos(self, notafiscal: NotaFiscal, produtos: List[Dict]):
        """Adiciona produtos à nota fiscal"""
        for produto in produtos:
            icms_data = produto.get('icms', {})
            
            notafiscal.adicionar_produto_servico(
                codigo=str(produto.get('codigo', produto.get('id', ''))),
                descricao=produto.get('descricao', produto.get('nome', '')),
                ncm=produto.get('ncm', '00000000'),
                cest=produto.get('cest', ''),
                ean=produto.get('codigo_barras', produto.get('codigoBarras', 'SEM GTIN')),
                cfop=produto.get('cfop', '5102'),
                unidade_comercial=produto.get('unidade', 'UN'),
                quantidade_comercial=Decimal(str(produto.get('quantidade', 1.0))),
                valor_unitario_comercial=Decimal(str(produto.get('valor_unitario', produto.get('valorUnitario', 0.0)))),
                valor_total_bruto=Decimal(str(produto.get('valor_total', produto.get('valorTotal', 0.0)))),
                unidade_tributavel=produto.get('unidade', 'UN'),
                quantidade_tributavel=Decimal(str(produto.get('quantidade', 1.0))),
                valor_unitario_tributavel=Decimal(str(produto.get('valor_unitario', produto.get('valorUnitario', 0.0)))),
                ean_tributavel=produto.get('codigo_barras', produto.get('codigoBarras', 'SEM GTIN')),
                ind_total=1,
                icms_modalidade=icms_data.get('modalidade', '00'),
                icms_origem=icms_data.get('origem', 0),
                icms_csosn=icms_data.get('cst', icms_data.get('csosn', '')),
                pis_modalidade='51',
                cofins_modalidade='51',
                pis_valor_base_calculo=Decimal('0.00'),
                pis_aliquota_percentual=Decimal('0.00'),
                pis_valor=Decimal('0.00'),
                cofins_valor_base_calculo=Decimal('0.00'),
                cofins_aliquota_percentual=Decimal('0.00'),
                cofins_valor=Decimal('0.00'),
                valor_tributos_aprox='0.00',
                informacoes_adicionais=produto.get('observacoes', ''),
            )
    
    def _adicionar_pagamentos(self, notafiscal: NotaFiscal, pagamentos: List[Dict]):
        """Adiciona pagamentos à nota fiscal"""
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
        
        for pagamento in pagamentos:
            tipo = str(pagamento.get('tipo', '01'))
            descricao = tipos_pagamento.get(tipo, 'Outros')
            valor = Decimal(str(pagamento.get('valor', 0.0)))
            
            notafiscal.adicionar_pagamento(
                t_pag=tipo,
                x_pag=descricao,
                v_pag=valor,
                ind_pag=0
            )
    
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
        Emite NFC-e usando PyNFe
        
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
            print("EMISSÃO NFC-e - PyNFe")
            print("=" * 60)
            
            # 1. Preparar certificado
            print("\n[1/6] Preparando certificado...")
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
            print("\n[2/6] Criando emitente...")
            emitente = self._criar_emitente(empresa_data)
            print("✅ Emitente criado")
            
            # 3. Criar cliente
            print("\n[3/6] Criando cliente...")
            cliente = self._criar_cliente(consumidor)
            print("✅ Cliente criado")
            
            # 4. Criar nota fiscal
            print("\n[4/6] Criando nota fiscal...")
            notafiscal = self._criar_notafiscal(emitente, cliente, empresa_data, numero_nfce)
            
            # Adicionar produtos
            self._adicionar_produtos(notafiscal, produtos)
            
            # Adicionar pagamentos
            self._adicionar_pagamentos(notafiscal, pagamentos)
            
            if observacoes:
                notafiscal.informacoes_adicionais_interesse_fisco = observacoes
            
            print("✅ Nota fiscal criada")
            
            # 5. Serializar XML
            print("\n[5/6] Serializando XML...")
            ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
            serializador = SerializacaoXML(_fonte_dados, homologacao=ambiente_homologacao)
            xml = serializador.exportar()
            print("✅ XML serializado")
            
            # xml é uma lista de elementos, pegar o primeiro (NFe)
            if isinstance(xml, list) and len(xml) > 0:
                xml_nfe = xml[0]
            else:
                xml_nfe = xml
            
            # 6. Assinar XML
            print("\n[6/6] Assinando XML...")
            assinador = AssinaturaA1(cert_path, self.senha_certificado)
            xml_assinado = assinador.assinar(xml)
            print("✅ XML assinado")
            
            # xml_assinado também é uma lista, pegar o primeiro elemento
            if isinstance(xml_assinado, list) and len(xml_assinado) > 0:
                xml_assinado_nfe = xml_assinado[0]
            else:
                xml_assinado_nfe = xml_assinado
            
            # 7. Enviar para SEFAZ
            print("\n[7/7] Enviando para SEFAZ...")
            uf = empresa_data.get('uf', 'SP')
            comunicacao = ComunicacaoSefaz(uf, cert_path, self.senha_certificado, ambiente_homologacao)
            
            # Usar método autorizacao (retorna tupla)
            # ind_sinc=1 para sincrono (retorna protocolo imediatamente)
            status, resultado = comunicacao.autorizacao(
                modelo='65',
                nota_fiscal=xml_assinado_nfe,
                id_lote=1,
                ind_sinc=1  # Síncrono
            )
            
            # Processar resultado
            if status == 0:  # Sucesso
                # resultado é o XML com protNFe
                from lxml import etree
                ns = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                
                # Extrair dados do protocolo
                prot_nfe = resultado.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe', ns)
                if prot_nfe is not None:
                    inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt', ns)
                    if inf_prot is not None:
                        c_stat = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat', ns)
                        x_motivo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo', ns)
                        chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe', ns)
                        protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt', ns)
                        
                        if c_stat is not None and c_stat.text in ['100', '150']:  # Autorizada
                            xml_str = etree.tostring(resultado, encoding='unicode')
                            
                            return {
                                'success': True,
                                'autorizada': True,
                                'status': 'autorizada',
                                'chave_acesso': chave.text if chave is not None else '',
                                'protocolo': protocolo.text if protocolo is not None else '',
                                'mensagem': x_motivo.text if x_motivo is not None else 'Autorizada',
                                'xml': xml_str
                            }
                        else:
                            # Rejeição no protocolo
                            return {
                                'success': False,
                                'autorizada': False,
                                'status': 'rejeitada',
                                'error': x_motivo.text if x_motivo is not None else 'Erro desconhecido',
                                'codigo_erro': c_stat.text if c_stat is not None else '',
                                'error_type': 'SEFAZRejection'
                            }
            
            # Erro no envio
            # resultado pode ser Response ou XML de erro
            if hasattr(resultado, 'text'):
                # É um Response object
                error_msg = f"Erro HTTP {resultado.status_code}"
                if resultado.text:
                    # Tentar extrair mensagem do XML
                    try:
                        from lxml import etree
                        erro_xml = etree.fromstring(resultado.text.encode('utf-8'))
                        ns = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                        x_motivo = erro_xml.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo', ns)
                        if x_motivo is not None:
                            error_msg = x_motivo.text
                    except:
                        pass
                
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'rejeitada',
                    'error': error_msg,
                    'error_type': 'SEFAZRejection',
                    'resposta_sefaz': resultado.text[:500] if resultado.text else ''
                }
            else:
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'rejeitada',
                    'error': 'Erro desconhecido na comunicação com SEFAZ',
                    'error_type': 'SEFAZError'
                }
            
        except Exception as e:
            import traceback
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e: {str(e)}',
                'error_type': 'UnexpectedError',
                'details': traceback.format_exc()
            }
        finally:
            # Limpar arquivo temporário
            if self.certificado_path and os.path.exists(self.certificado_path):
                try:
                    os.unlink(self.certificado_path)
                except:
                    pass


def criar_servico_nfce_pynfe():
    """
    Factory para criar serviço NFC-e com PyNFe
    
    Returns:
        Instância de NFCePyNFe ou None se PyNFe não disponível
    """
    if PYNFE_DISPONIVEL:
        return NFCePyNFe()
    else:
        return None

