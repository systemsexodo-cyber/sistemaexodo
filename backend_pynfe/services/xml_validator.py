"""
Validador de XML para NFC-e usando schemas XSD oficiais da SEFAZ
"""

import os
import re
from lxml import etree as lxml_etree
from typing import List, Dict, Tuple, Optional


class XMLValidator:
    """Validador de XML para NFC-e"""
    
    def __init__(self, schema_paths: Optional[Dict[str, str]] = None):
        """
        Inicializa o validador com caminhos para schemas XSD.
        
        Args:
            schema_paths: Dicionário com caminhos para schemas XSD:
                {
                    'enviNFe': 'caminho/para/enviNFe_v4.00.xsd',
                    'nfe': 'caminho/para/nfe_v4.00.xsd',
                    'tiposBasico': 'caminho/para/tiposBasico_v4.00.xsd'
                }
        """
        self.namespace_nfe = "http://www.portalfiscal.inf.br/nfe"
        self.versao_schema = "4.00"
        self.schema_paths = schema_paths or {}
        self.xsd_schemas = {}
        
        # Tentar carregar schemas XSD se caminhos fornecidos
        if self.schema_paths:
            self._carregar_schemas_xsd()
    
    def _carregar_schemas_xsd(self):
        """Carrega schemas XSD para validação"""
        try:
            for nome, caminho in self.schema_paths.items():
                if os.path.exists(caminho):
                    try:
                        schema_doc = lxml_etree.parse(caminho)
                        self.xsd_schemas[nome] = lxml_etree.XMLSchema(schema_doc)
                        print(f"✅ Schema XSD carregado: {nome} ({caminho})")
                    except Exception as e:
                        print(f"⚠️ Erro ao carregar schema {nome}: {e}")
                else:
                    print(f"⚠️ Schema não encontrado: {caminho}")
        except Exception as e:
            print(f"⚠️ Erro ao carregar schemas XSD: {e}")
    
    def validar_com_xsd(self, xml_str: str) -> Tuple[bool, List[str]]:
        """
        Valida XML usando schemas XSD oficiais.
        
        Returns:
            (valido, erros)
        """
        erros = []
        
        if not self.xsd_schemas:
            return True, []  # Se não há schemas, não valida (não é erro)
        
        try:
            xml_tree = lxml_etree.fromstring(xml_str.encode('utf-8'))
            
            # Validar com schema do enviNFe se disponível
            if 'enviNFe' in self.xsd_schemas:
                try:
                    if not self.xsd_schemas['enviNFe'].validate(xml_tree):
                        erros_xsd = self.xsd_schemas['enviNFe'].error_log
                        for erro in erros_xsd:
                            erros.append(f"XSD enviNFe: {erro.message} (linha {erro.line})")
                except Exception as e:
                    erros.append(f"Erro ao validar com schema enviNFe: {e}")
            
            # Validar com schema da NFe se disponível
            if 'nfe' in self.xsd_schemas:
                nfe_elem = xml_tree.find('.//NFe') or xml_tree.find('.//{http://www.portalfiscal.inf.br/nfe}NFe')
                if nfe_elem is not None:
                    try:
                        if not self.xsd_schemas['nfe'].validate(nfe_elem):
                            erros_xsd = self.xsd_schemas['nfe'].error_log
                            for erro in erros_xsd:
                                erros.append(f"XSD NFe: {erro.message} (linha {erro.line})")
                    except Exception as e:
                        erros.append(f"Erro ao validar com schema NFe: {e}")
            
        except Exception as e:
            erros.append(f"Erro ao validar com XSD: {e}")
        
        return len(erros) == 0, erros
        
    def validar_estrutura_envinfe(self, xml_str: str) -> Tuple[bool, List[str], Dict]:
        """
        Valida a estrutura básica do enviNFe sem precisar do schema XSD.
        
        Returns:
            (valido, erros, detalhes)
        """
        erros = []
        detalhes = {
            'versao': None,
            'namespace': None,
            'idLote': None,
            'indSinc': None,
            'nfe_presente': False,
            'infNFe_presente': False,
            'elementos_obrigatorios': {}
        }
        
        try:
            # Parsear XML
            try:
                xml_tree = lxml_etree.fromstring(xml_str.encode('utf-8'))
            except Exception as e:
                erros.append(f"XML inválido: {str(e)}")
                return False, erros, detalhes
            
            # Verificar se é enviNFe
            tag_raiz = xml_tree.tag.split('}')[-1] if '}' in xml_tree.tag else xml_tree.tag
            if tag_raiz != 'enviNFe':
                erros.append(f"Elemento raiz incorreto: {tag_raiz} (esperado: enviNFe)")
                return False, erros, detalhes
            
            # Verificar versão
            versao = xml_tree.get('versao')
            detalhes['versao'] = versao
            if not versao or versao != '4.00':
                erros.append(f"Versão incorreta: {versao} (esperado: 4.00)")
            
            # Verificar namespace
            namespace = xml_tree.nsmap.get(None) if hasattr(xml_tree, 'nsmap') and xml_tree.nsmap else None
            detalhes['namespace'] = namespace
            if not namespace or namespace != self.namespace_nfe:
                erros.append(f"Namespace incorreto: {namespace} (esperado: {self.namespace_nfe})")
            
            # Verificar namespaces extras (não devem existir)
            if hasattr(xml_tree, 'nsmap') and xml_tree.nsmap:
                namespaces_extras = []
                for prefix, uri in xml_tree.nsmap.items():
                    if prefix and prefix not in ['nfe']:
                        namespaces_extras.append(f"{prefix}:{uri}")
                if namespaces_extras:
                    erros.append(f"Namespaces extras encontrados: {', '.join(namespaces_extras)}")
            
            # Verificar prefixos de namespace (não devem existir)
            if 'ns0:' in xml_str or 'xmlns:ns0' in xml_str:
                erros.append("Prefixos de namespace (ns0:) encontrados - devem ser removidos")
            
            # Verificar elementos obrigatórios na ordem correta
            elementos = list(xml_tree)
            detalhes['total_elementos'] = len(elementos)
            
            # 1. idLote (primeiro elemento)
            if len(elementos) == 0:
                erros.append("enviNFe está vazio")
                return False, erros, detalhes
            
            primeiro = elementos[0]
            tag_primeiro = primeiro.tag.split('}')[-1] if '}' in primeiro.tag else primeiro.tag
            if tag_primeiro != 'idLote':
                erros.append(f"Primeiro elemento incorreto: {tag_primeiro} (esperado: idLote)")
            else:
                id_lote_texto = primeiro.text or ''
                detalhes['idLote'] = id_lote_texto
                if not id_lote_texto.strip().isdigit():
                    erros.append(f"idLote inválido: {id_lote_texto} (deve ser numérico)")
                elif len(id_lote_texto.strip()) != 15:
                    erros.append(f"idLote com tamanho incorreto: {len(id_lote_texto.strip())} dígitos (esperado: 15)")
            
            # 2. indSinc (segundo elemento)
            if len(elementos) < 2:
                erros.append("indSinc ausente (deve ser o segundo elemento)")
            else:
                segundo = elementos[1]
                tag_segundo = segundo.tag.split('}')[-1] if '}' in segundo.tag else segundo.tag
                if tag_segundo != 'indSinc':
                    erros.append(f"Segundo elemento incorreto: {tag_segundo} (esperado: indSinc)")
                else:
                    ind_sinc_texto = segundo.text or ''
                    detalhes['indSinc'] = ind_sinc_texto
                    if ind_sinc_texto != '1':
                        erros.append(f"indSinc incorreto: {ind_sinc_texto} (esperado: 1 para NFC-e)")
            
            # 3. NFe (terceiro elemento)
            if len(elementos) < 3:
                erros.append("NFe ausente (deve ser o terceiro elemento)")
            else:
                terceiro = elementos[2]
                tag_terceiro = terceiro.tag.split('}')[-1] if '}' in terceiro.tag else terceiro.tag
                if tag_terceiro != 'NFe':
                    erros.append(f"Terceiro elemento incorreto: {tag_terceiro} (esperado: NFe)")
                else:
                    detalhes['nfe_presente'] = True
                    
                    # Verificar infNFe dentro da NFe
                    ns_nfe = {"nfe": self.namespace_nfe}
                    inf_nfe = terceiro.find('nfe:infNFe', ns_nfe) or terceiro.find('infNFe')
                    if inf_nfe is None:
                        erros.append("infNFe ausente dentro da NFe")
                    else:
                        detalhes['infNFe_presente'] = True
                        
                        # Validar elementos obrigatórios da infNFe
                        elementos_obrigatorios = {
                            'ide': 'Identificação',
                            'emit': 'Emitente',
                            'det': 'Produtos/Serviços',
                            'total': 'Totalização',
                            'pag': 'Pagamento'
                        }
                        
                        for elem_tag, descricao in elementos_obrigatorios.items():
                            elem = inf_nfe.find(f'nfe:{elem_tag}', ns_nfe) or inf_nfe.find(elem_tag)
                            detalhes['elementos_obrigatorios'][elem_tag] = elem is not None
                            if elem is None:
                                erros.append(f"{descricao} ({elem_tag}) ausente na infNFe")
                        
                        # Validar campos específicos
                        self._validar_campos_infnfe(inf_nfe, erros, detalhes, ns_nfe)
            
            # Verificar se há elementos extras além dos 3 obrigatórios
            if len(elementos) > 3:
                elementos_extras = []
                for i, elem in enumerate(elementos[3:], start=4):
                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                    elementos_extras.append(f"Posição {i}: {tag_limpa}")
                if elementos_extras:
                    erros.append(f"Elementos extras encontrados: {', '.join(elementos_extras)}")
            
            valido = len(erros) == 0
            return valido, erros, detalhes
            
        except Exception as e:
            erros.append(f"Erro ao validar estrutura: {str(e)}")
            return False, erros, detalhes
    
    def _validar_campos_infnfe(self, inf_nfe, erros: List[str], detalhes: Dict, ns_nfe: Dict):
        """Valida campos específicos da infNFe"""
        
        # Validar versão da infNFe
        versao_inf = inf_nfe.get('versao')
        if versao_inf != '4.00':
            erros.append(f"Versão da infNFe incorreta: {versao_inf} (esperado: 4.00)")
        
        # Validar Id da infNFe
        id_inf = inf_nfe.get('Id')
        if not id_inf or not id_inf.startswith('NFe'):
            erros.append(f"Id da infNFe inválido: {id_inf} (deve começar com 'NFe')")
        
        # Validar ide
        ide = inf_nfe.find('nfe:ide', ns_nfe) or inf_nfe.find('ide')
        if ide is not None:
            # cMunFG
            c_mun_fg = ide.find('nfe:cMunFG', ns_nfe) or ide.find('cMunFG')
            if c_mun_fg is None:
                erros.append("cMunFG ausente no ide")
            else:
                c_mun_fg_texto = c_mun_fg.text or ''
                if not c_mun_fg_texto.strip().isdigit():
                    erros.append(f"cMunFG inválido: {c_mun_fg_texto} (deve ser código IBGE de 7 dígitos)")
                elif len(c_mun_fg_texto.strip()) != 7:
                    erros.append(f"cMunFG com tamanho incorreto: {len(c_mun_fg_texto.strip())} dígitos (esperado: 7)")
            
            # verProc
            ver_proc = ide.find('nfe:verProc', ns_nfe) or ide.find('verProc')
            if ver_proc is None:
                erros.append("verProc ausente no ide")
            elif not ver_proc.text or not ver_proc.text.strip():
                erros.append("verProc vazio")
        
        # Validar emit
        emit = inf_nfe.find('nfe:emit', ns_nfe) or inf_nfe.find('emit')
        if emit is not None:
            # CRT
            crts = emit.findall('nfe:CRT', ns_nfe) + emit.findall('CRT')
            if len(crts) == 0:
                erros.append("CRT ausente no emit")
            elif len(crts) > 1:
                erros.append(f"CRT duplicado: {len(crts)} elementos encontrados (deve haver apenas 1)")
            else:
                crt_texto = crts[0].text or ''
                if not crt_texto.strip():
                    erros.append("CRT vazio")
                elif crt_texto.strip() not in ['1', '2', '3']:
                    erros.append(f"CRT inválido: {crt_texto} (deve ser 1, 2 ou 3)")
            
            # xPais
            ender_emit = emit.find('nfe:enderEmit', ns_nfe) or emit.find('enderEmit')
            if ender_emit is not None:
                x_pais = ender_emit.find('nfe:xPais', ns_nfe) or ender_emit.find('xPais')
                if x_pais is not None and x_pais.text and x_pais.text.upper() == 'BRASIL':
                    erros.append("xPais deve ser 'Brasil' (não 'BRASIL')")
    
    def validar_valores_decimais(self, xml_str: str) -> Tuple[bool, List[str]]:
        """
        Valida valores decimais conforme padrão TDec_1302 (13 dígitos antes, 2 depois).
        """
        erros = []
        pattern_tdec_1302 = re.compile(r'^(0|0\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\.[0-9]{2})?)$')
        
        campos_decimais = [
            'vBC', 'vICMS', 'vICMSDeson', 'vFCP', 'vBCST', 'vST', 'vFCPST', 'vFCPSTRet',
            'vProd', 'vFrete', 'vSeg', 'vDesc', 'vII', 'vIPI', 'vIPIDevol',
            'vPIS', 'vCOFINS', 'vOutro', 'vNF',
            'vUnCom', 'vUnTrib', 'vProd', 'vTotTrib',
            'vBC', 'vICMS', 'pICMS', 'vPIS', 'pPIS', 'vCOFINS', 'pCOFINS'
        ]
        
        try:
            xml_tree = lxml_etree.fromstring(xml_str.encode('utf-8'))
            
            for elem in xml_tree.iter():
                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                
                if tag_limpa in campos_decimais and elem.text:
                    valor = elem.text.strip()
                    if not pattern_tdec_1302.match(valor):
                        erros.append(f"Campo {tag_limpa} com valor decimal inválido: {valor} (padrão TDec_1302 esperado)")
                    
                    # Verificar tamanho da parte inteira
                    if '.' in valor:
                        parte_inteira = valor.split('.')[0]
                        if len(parte_inteira) > 13:
                            erros.append(f"Campo {tag_limpa} excede 13 dígitos na parte inteira: {parte_inteira}")
                    
        except Exception as e:
            erros.append(f"Erro ao validar valores decimais: {str(e)}")
        
        return len(erros) == 0, erros
    
    def validar_completo(self, xml_str: str) -> Dict:
        """
        Validação completa do XML do lote.
        
        Returns:
            {
                'valido': bool,
                'erros': List[str],
                'avisos': List[str],
                'detalhes': Dict,
                'estrutura_valida': bool,
                'decimais_validos': bool,
                'xsd_valido': bool
            }
        """
        resultado = {
            'valido': False,
            'erros': [],
            'avisos': [],
            'detalhes': {},
            'estrutura_valida': False,
            'decimais_validos': False,
            'xsd_valido': True  # True por padrão se não há schemas
        }
        
        # 1. Validar estrutura
        estrutura_valida, erros_estrutura, detalhes_estrutura = self.validar_estrutura_envinfe(xml_str)
        resultado['estrutura_valida'] = estrutura_valida
        resultado['erros'].extend(erros_estrutura)
        resultado['detalhes'].update(detalhes_estrutura)
        
        # 2. Validar valores decimais
        decimais_validos, erros_decimais = self.validar_valores_decimais(xml_str)
        resultado['decimais_validos'] = decimais_validos
        resultado['erros'].extend(erros_decimais)
        
        # 3. Validar com XSD se schemas disponíveis
        if self.xsd_schemas:
            xsd_valido, erros_xsd = self.validar_com_xsd(xml_str)
            resultado['xsd_valido'] = xsd_valido
            resultado['erros'].extend(erros_xsd)
        
        # 4. Verificar avisos (problemas que não impedem, mas devem ser corrigidos)
        if 'ns0:' in xml_str:
            resultado['avisos'].append("Prefixos ns0: encontrados (devem ser removidos)")
        
        if 'PyNFe' in xml_str and '<verProc>' in xml_str:
            resultado['avisos'].append("verProc contém 'PyNFe' (deve ser 'Sistema Exodo')")
        
        if xml_str.count('<CRT>') > 1:
            resultado['avisos'].append("CRT duplicado encontrado")
        
        # 5. Resultado final
        resultado['valido'] = estrutura_valida and decimais_validos and resultado['xsd_valido'] and len(resultado['erros']) == 0
        
        return resultado
    
    def gerar_relatorio(self, resultado_validacao: Dict) -> str:
        """
        Gera relatório de validação em formato legível.
        """
        relatorio = []
        relatorio.append("=" * 70)
        relatorio.append("RELATÓRIO DE VALIDAÇÃO DO XML DO LOTE")
        relatorio.append("=" * 70)
        relatorio.append("")
        
        # Status geral
        if resultado_validacao['valido']:
            relatorio.append("✅ STATUS: XML VÁLIDO")
        else:
            relatorio.append("❌ STATUS: XML INVÁLIDO")
        relatorio.append("")
        
        # Estrutura
        if resultado_validacao['estrutura_valida']:
            relatorio.append("✅ Estrutura: Válida")
        else:
            relatorio.append("❌ Estrutura: Inválida")
        
        # Decimais
        if resultado_validacao['decimais_validos']:
            relatorio.append("✅ Valores Decimais: Válidos")
        else:
            relatorio.append("❌ Valores Decimais: Inválidos")
        
        # XSD
        if 'xsd_valido' in resultado_validacao:
            if resultado_validacao['xsd_valido']:
                relatorio.append("✅ Validação XSD: Válida")
            else:
                relatorio.append("❌ Validação XSD: Inválida")
        relatorio.append("")
        
        # Detalhes
        detalhes = resultado_validacao['detalhes']
        relatorio.append("DETALHES:")
        relatorio.append(f"  Versão: {detalhes.get('versao', 'N/A')}")
        relatorio.append(f"  Namespace: {detalhes.get('namespace', 'N/A')}")
        relatorio.append(f"  idLote: {detalhes.get('idLote', 'N/A')}")
        relatorio.append(f"  indSinc: {detalhes.get('indSinc', 'N/A')}")
        relatorio.append(f"  NFe presente: {'Sim' if detalhes.get('nfe_presente') else 'Não'}")
        relatorio.append(f"  infNFe presente: {'Sim' if detalhes.get('infNFe_presente') else 'Não'}")
        relatorio.append("")
        
        # Elementos obrigatórios
        elementos_obr = detalhes.get('elementos_obrigatorios', {})
        if elementos_obr:
            relatorio.append("ELEMENTOS OBRIGATÓRIOS:")
            for elem, presente in elementos_obr.items():
                status = "✅" if presente else "❌"
                relatorio.append(f"  {status} {elem}")
            relatorio.append("")
        
        # Erros
        if resultado_validacao['erros']:
            relatorio.append("ERROS ENCONTRADOS:")
            for i, erro in enumerate(resultado_validacao['erros'], 1):
                relatorio.append(f"  {i}. {erro}")
            relatorio.append("")
        
        # Avisos
        if resultado_validacao['avisos']:
            relatorio.append("AVISOS:")
            for i, aviso in enumerate(resultado_validacao['avisos'], 1):
                relatorio.append(f"  {i}. {aviso}")
            relatorio.append("")
        
        relatorio.append("=" * 70)
        
        return "\n".join(relatorio)

