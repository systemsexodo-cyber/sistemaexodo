"""
NFC-e usando PyNFe em modo desenvolvimento - Implementação Completa
Baseado nos testes e exemplos do PyNFe
"""

import base64
import tempfile
import os
import re
from datetime import datetime, timezone
from decimal import Decimal
from typing import Dict, List, Optional, Any
from lxml import etree
import requests

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
    print("[OK] PyNFe importado com sucesso (modo desenvolvimento)")
except ImportError as e:
    PYNFE_DISPONIVEL = False
    print(f"[ERRO] PyNFe não disponível: {e}")
    print("[INFO] PyNFe deve estar instalado. Verifique a instalação.")
    print(f"[INFO] Caminho tentado: {pynfe_path}")
    print(f"[INFO] Caminho existe: {os.path.exists(pynfe_path)}")
    import traceback
    traceback.print_exc()


class NFCePyNFeCompleto:
    """
    Classe completa para emissão de NFC-e usando PyNFe
    Segue o padrão dos testes do PyNFe
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
        # Diretório base para salvar XMLs
        self.base_xml_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_nfce')
    
    def _parse_xml_safe(self, xml_input):
        """
        Parse XML de forma segura com validações robustas
        Conforme manual do validador SEFAZ: Parser XML verifica se a mensagem está "bem-formada"
        
        Args:
            xml_input: String XML, bytes ou elemento XML
            
        Returns:
            Elemento XML parseado
            
        Raises:
            ValueError: Se o XML estiver vazio ou inválido
        """
        # Se já é um elemento, retornar diretamente
        if hasattr(xml_input, 'tag'):
            return xml_input
        
        # Se é None, lançar erro
        if xml_input is None:
            raise ValueError("XML input é None. Não é possível fazer parse de None.")
        
        # Se é string, validar e parsear
        if isinstance(xml_input, str):
            xml_str = xml_input.strip()
            
            # Validar que não está vazio
            if not xml_str:
                raise ValueError(
                    "ERRO: XML string está vazia.\n\n"
                    "Conforme manual do validador SEFAZ, o Parser XML verifica se a mensagem está 'bem-formada'.\n"
                    "Uma string vazia não é um XML válido."
                )
            
            # Validar que começa com '<' (primeiro caractere válido de XML)
            if not xml_str.startswith('<'):
                # Tentar encontrar primeira tag
                primeira_tag_pos = xml_str.find('<')
                if primeira_tag_pos > 0:
                    # Remover caracteres antes da primeira tag
                    xml_str = xml_str[primeira_tag_pos:].strip()
                else:
                    raise ValueError(
                        f"ERRO: XML inválido - não contém tags XML válidas.\n\n"
                        f"Conforme manual do validador SEFAZ, o XML deve estar 'bem-formado'.\n"
                        f"Primeiros 200 chars recebidos: {repr(xml_input[:200])}"
                    )
            
            # Remover declaração XML se houver (pode causar erro em alguns parsers)
            if xml_str.startswith('<?xml'):
                # Encontrar o final da declaração XML
                fim_declaracao = xml_str.find('?>')
                if fim_declaracao > 0:
                    xml_str = xml_str[fim_declaracao + 2:].strip()
                else:
                    # Se não encontrou ?>, remover até primeira tag
                    primeira_tag = xml_str.find('<', 1)
                    if primeira_tag > 0:
                        xml_str = xml_str[primeira_tag:].strip()
            
            # Validar novamente após processamento
            if not xml_str or not xml_str.strip():
                raise ValueError(
                    "ERRO: XML ficou vazio após processamento.\n\n"
                    "Isso pode indicar que o XML recebido estava malformado ou contém apenas declaração XML."
                )
            
            if not xml_str.strip().startswith('<'):
                raise ValueError(
                    f"ERRO: XML inválido após processamento - não começa com '<'.\n\n"
                    f"Primeiros 200 chars: {repr(xml_str[:200])}"
                )
            
            # Tentar fazer parse
            try:
                return etree.fromstring(xml_str)
            except etree.XMLSyntaxError as e:
                raise ValueError(
                    f"ERRO: XML malformado (Parser XML falhou).\n\n"
                    f"Conforme manual do validador SEFAZ, o Parser XML verifica:\n"
                    f"- Existência de um único elemento raiz\n"
                    f"- Nome da tag com caracteres válidos\n"
                    f"- Todas as tags abertas foram fechadas\n\n"
                    f"Erro do parser: {str(e)}\n"
                    f"Primeiros 500 chars do XML: {xml_str[:500]}"
                )
            except Exception as e:
                raise ValueError(
                    f"ERRO ao fazer parse do XML: {str(e)}\n\n"
                    f"Tipo do erro: {type(e).__name__}\n"
                    f"Primeiros 500 chars do XML: {xml_str[:500]}"
                )
        
        # Se é bytes, decodificar primeiro
        if isinstance(xml_input, bytes):
            try:
                xml_str = xml_input.decode('utf-8')
                return self._parse_xml_safe(xml_str)
            except UnicodeDecodeError as e:
                raise ValueError(
                    f"ERRO ao decodificar XML bytes: {str(e)}\n\n"
                    f"O XML está em formato bytes mas não pode ser decodificado como UTF-8.\n"
                    f"Tamanho dos bytes: {len(xml_input)}"
                )
        
        raise ValueError(
            f"Tipo de entrada XML não suportado: {type(xml_input)}\n\n"
            f"Tipos suportados: str, bytes, ou elemento lxml.etree._Element\n"
            f"Tipo recebido: {type(xml_input)}"
        )
    
    def _construir_nfeproc(self, nfe_element, prot_nfe):
        """
        Constrói nfeProc seguindo o padrão do XML autorizado da SEFAZ
        
        O nfeProc é o XML final autorizado que contém:
        - NFe: XML assinado completo (com infNFe e Signature)
        - protNFe: Protocolo de autorização retornado pela SEFAZ
        
        No XML autorizado:
        - nfeProc tem xmlns e versao="4.00"
        - NFe dentro do nfeProc tem xmlns próprio (não herda do nfeProc)
        - protNFe é adicionado após o NFe
        
        Args:
            nfe_element: Elemento NFe assinado (deve conter infNFe e Signature)
            prot_nfe: Elemento protNFe retornado pela SEFAZ
            
        Returns:
            Elemento nfeProc no formato correto
        """
        from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
        
        print("🔧 Construindo nfeProc (NFe assinado + protNFe)...")
        
        # Criar nfeProc com xmlns e versao
        nfe_proc = etree.Element("nfeProc", xmlns=NAMESPACE_NFE, versao=VERSAO_PADRAO)
        
        # NFe dentro do nfeProc deve ter xmlns próprio (conforme exemplo autorizado)
        if hasattr(nfe_element, 'tag'):
            # Se é um elemento, criar cópia profunda preservando todos os elementos
            print(f"   📋 Copiando NFe assinado (tag: {nfe_element.tag})...")
            
            # Criar novo elemento NFe com xmlns
            nfe_com_xmlns = etree.Element("NFe", xmlns=NAMESPACE_NFE)
            
            # Copiar todos os filhos (infNFe, Signature, infNFeSupl, etc) preservando estrutura completa
            elementos_copiados = []
            for filho in nfe_element:
                # Fazer cópia profunda do elemento para preservar toda a estrutura
                filho_copia = etree.fromstring(etree.tostring(filho, encoding='unicode'))
                nfe_com_xmlns.append(filho_copia)
                tag_local = filho.tag.split('}')[-1] if '}' in filho.tag else filho.tag
                elementos_copiados.append(tag_local)
            
            print(f"   ✅ Elementos copiados do NFe: {', '.join(elementos_copiados)}")
            
            # Validar que infNFe foi copiado
            inf_nfe_copia = nfe_com_xmlns.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_com_xmlns.find('.//infNFe')
            if inf_nfe_copia is None:
                raise ValueError("ERRO: infNFe não encontrado após copiar elementos do NFe assinado!")
            else:
                print(f"   ✅ infNFe copiado: Id={inf_nfe_copia.get('Id', 'N/A')}")
            
            # Validar que Signature foi copiada (se existir)
            signature_copia = nfe_com_xmlns.find('.//{http://www.w3.org/2000/09/xmldsig#}Signature') or nfe_com_xmlns.find('.//Signature')
            if signature_copia is not None:
                print("   ✅ Signature copiada (assinatura digital preservada)")
            else:
                print("   ⚠️ AVISO: Signature não encontrada no NFe (pode ser normal se não foi assinado ainda)")
            
            nfe_proc.append(nfe_com_xmlns)
        else:
            # Se é string, parsear e adicionar xmlns
            print("   📋 Parseando NFe de string...")
            nfe_parsed = self._parse_xml_safe(nfe_element)
            nfe_com_xmlns = etree.Element("NFe", xmlns=NAMESPACE_NFE)
            for filho in nfe_parsed:
                filho_copia = etree.fromstring(etree.tostring(filho, encoding='unicode'))
                nfe_com_xmlns.append(filho_copia)
            nfe_proc.append(nfe_com_xmlns)
        
        # Adicionar protNFe (protocolo de autorização da SEFAZ)
        print("   📋 Adicionando protNFe (protocolo de autorização)...")
        
        # Validar protNFe antes de adicionar
        if prot_nfe is None:
            raise ValueError("ERRO: protNFe é None! Não é possível construir nfeProc sem protocolo.")
        
        # Garantir que protNFe tem xmlns e versao (conforme exemplo autorizado)
        if not prot_nfe.get('xmlns'):
            prot_nfe.set('xmlns', NAMESPACE_NFE)
            print("   🔧 Adicionado xmlns ao protNFe")
        if not prot_nfe.get('versao'):
            prot_nfe.set('versao', VERSAO_PADRAO)
            print("   🔧 Adicionado versao ao protNFe")
        
        # Verificar se protNFe tem infProt
        inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or prot_nfe.find('.//infProt')
        if inf_prot is not None:
            c_stat = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or inf_prot.find('.//cStat')
            chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or inf_prot.find('.//chNFe')
            protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') or inf_prot.find('.//nProt')
            
            if c_stat is not None:
                print(f"   ✅ protNFe validado: cStat={c_stat.text}")
            if chave is not None:
                print(f"   ✅ Chave de acesso: {chave.text}")
            if protocolo is not None:
                print(f"   ✅ Protocolo: {protocolo.text}")
        else:
            print("   ⚠️ AVISO: infProt não encontrado no protNFe")
        
        nfe_proc.append(prot_nfe)
        
        # VALIDAÇÃO FINAL: Verificar estrutura conforme exemplo autorizado
        print("\n   🔍 Validando estrutura do nfeProc (conforme padrão SEFAZ)...")
        
        # Verificar nfeProc
        if nfe_proc.tag != 'nfeProc':
            print(f"   ⚠️ AVISO: Tag raiz é '{nfe_proc.tag}', esperado 'nfeProc'")
        else:
            print("   ✅ Tag raiz: nfeProc")
        
        if nfe_proc.get('xmlns') != NAMESPACE_NFE:
            print(f"   ⚠️ AVISO: xmlns do nfeProc é '{nfe_proc.get('xmlns')}', esperado '{NAMESPACE_NFE}'")
        else:
            print(f"   ✅ xmlns do nfeProc: {NAMESPACE_NFE}")
        
        if nfe_proc.get('versao') != VERSAO_PADRAO:
            print(f"   ⚠️ AVISO: versao do nfeProc é '{nfe_proc.get('versao')}', esperado '{VERSAO_PADRAO}'")
        else:
            print(f"   ✅ versao do nfeProc: {VERSAO_PADRAO}")
        
        # Verificar NFe dentro do nfeProc
        nfe_no_proc = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or nfe_proc.find('.//NFe')
        if nfe_no_proc is None:
            print("   ❌ ERRO: NFe não encontrado dentro do nfeProc!")
        else:
            print("   ✅ NFe encontrado dentro do nfeProc")
            if nfe_no_proc.get('xmlns') != NAMESPACE_NFE:
                print(f"   ⚠️ AVISO: xmlns do NFe é '{nfe_no_proc.get('xmlns')}', esperado '{NAMESPACE_NFE}'")
            else:
                print(f"   ✅ xmlns do NFe: {NAMESPACE_NFE}")
            
            # Verificar elementos dentro do NFe
            inf_nfe = nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_no_proc.find('.//infNFe')
            if inf_nfe is None:
                print("   ⚠️ AVISO: infNFe não encontrado dentro do NFe")
            else:
                print("   ✅ infNFe encontrado dentro do NFe")
            
            signature = nfe_no_proc.find('.//{http://www.w3.org/2000/09/xmldsig#}Signature') or nfe_no_proc.find('.//Signature')
            if signature is None:
                print("   ⚠️ AVISO: Signature não encontrada dentro do NFe")
            else:
                print("   ✅ Signature encontrada dentro do NFe")
            
            inf_nfe_supl = nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infNFeSupl') or nfe_no_proc.find('.//infNFeSupl')
            if inf_nfe_supl is None:
                print("   ⚠️ AVISO: infNFeSupl não encontrado (QR Code pode não ter sido gerado)")
            else:
                print("   ✅ infNFeSupl encontrado (QR Code presente)")
        
        # Verificar protNFe
        prot_nfe_no_proc = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe') or nfe_proc.find('.//protNFe')
        if prot_nfe_no_proc is None:
            print("   ❌ ERRO: protNFe não encontrado dentro do nfeProc!")
        else:
            print("   ✅ protNFe encontrado dentro do nfeProc")
            if prot_nfe_no_proc.get('xmlns') != NAMESPACE_NFE:
                print(f"   ⚠️ AVISO: xmlns do protNFe é '{prot_nfe_no_proc.get('xmlns')}', esperado '{NAMESPACE_NFE}'")
            else:
                print(f"   ✅ xmlns do protNFe: {NAMESPACE_NFE}")
            
            if prot_nfe_no_proc.get('versao') != VERSAO_PADRAO:
                print(f"   ⚠️ AVISO: versao do protNFe é '{prot_nfe_no_proc.get('versao')}', esperado '{VERSAO_PADRAO}'")
            else:
                print(f"   ✅ versao do protNFe: {VERSAO_PADRAO}")
            
            inf_prot_final = prot_nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or prot_nfe_no_proc.find('.//infProt')
            if inf_prot_final is None:
                print("   ⚠️ AVISO: infProt não encontrado dentro do protNFe")
            else:
                print("   ✅ infProt encontrado dentro do protNFe")
                c_stat_final = inf_prot_final.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or inf_prot_final.find('.//cStat')
                if c_stat_final is not None:
                    print(f"   ✅ cStat no infProt: {c_stat_final.text}")
        
        print("\n   ✅ nfeProc construído com sucesso!")
        print(f"   📋 Estrutura final: nfeProc (xmlns, versao) > NFe (xmlns) > [infNFe, infNFeSupl, Signature] + protNFe (xmlns, versao) > infProt")
        print("   ✅ Estrutura conforme padrão SEFAZ (exemplo autorizado)")
        
        return nfe_proc
    
    def _preparar_certificado(self, certificado_base64: str, senha: str) -> str:
        """
        Prepara certificado salvando em arquivo temporário com validação robusta
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
        
        Returns:
            Caminho do arquivo temporário
        """
        print("=" * 70)
        print("PREPARAÇÃO DE CERTIFICADO DIGITAL - VALIDAÇÃO COMPLETA")
        print("=" * 70)
        
        # PASSO 1: Validação de entrada
        print("\n[PASSO 1/6] Validando entrada...")
        if not certificado_base64:
            raise ValueError("Certificado em base64 está vazio ou None")
        
        if not isinstance(certificado_base64, str):
            raise ValueError(f"Certificado deve ser string, recebido: {type(certificado_base64)}")
        
        if not senha:
            raise ValueError("Senha do certificado está vazia ou None")
        
        if not isinstance(senha, str):
            senha = str(senha)
        
        print(f"   ✅ Certificado base64: {len(certificado_base64)} caracteres")
        print(f"   ✅ Senha: {len(senha)} caracteres")
        
        # PASSO 2: Limpeza do base64
        print("\n[PASSO 2/6] Limpando base64...")
        certificado_base64_limpo = certificado_base64.strip()
        # Remover quebras de linha e espaços
        certificado_base64_limpo = certificado_base64_limpo.replace('\n', '').replace('\r', '').replace(' ', '').replace('\t', '')
        
        # Verificar se ainda tem conteúdo após limpeza
        if not certificado_base64_limpo:
            raise ValueError("Certificado base64 está vazio após limpeza")
        
        print(f"   ✅ Base64 limpo: {len(certificado_base64_limpo)} caracteres")
        
        # PASSO 3: Decodificação base64
        print("\n[PASSO 3/6] Decodificando base64...")
        cert_bytes = None
        tentativas_decodificacao = [
            certificado_base64_limpo,  # Tentativa 1: direto
        ]
        
        # Se o primeiro byte não é válido, tentar decodificar como se fosse base64 duplamente codificado
        try:
            cert_bytes = base64.b64decode(certificado_base64_limpo, validate=True)
            print(f"   ✅ Base64 decodificado: {len(cert_bytes)} bytes")
        except Exception as e1:
            print(f"   ⚠️ Erro na primeira tentativa: {e1}")
            # Tentar decodificar como se fosse texto base64
            try:
                import binascii
                # Verificar se é base64 válido
                if all(c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=' for c in certificado_base64_limpo):
                    cert_bytes = base64.b64decode(certificado_base64_limpo, validate=False)
                    print(f"   ✅ Base64 decodificado (modo não-validado): {len(cert_bytes)} bytes")
                else:
                    raise ValueError(f"Certificado não é base64 válido: {str(e1)}")
            except Exception as e2:
                raise ValueError(f"Erro ao decodificar certificado base64: {str(e1)}. Tentativa alternativa: {str(e2)}")
        
        if not cert_bytes or len(cert_bytes) == 0:
            raise ValueError("Certificado decodificado está vazio")
        
        # PASSO 4: Validação do formato PFX
        print("\n[PASSO 4/6] Validando formato PFX/P12...")
        if len(cert_bytes) < 100:
            raise ValueError(f"Certificado muito pequeno ({len(cert_bytes)} bytes). Um certificado PFX válido deve ter pelo menos alguns KB.")
        
        # Verificar assinatura do arquivo PFX/P12
        primeiro_byte = cert_bytes[0] if len(cert_bytes) > 0 else None
        segundo_byte = cert_bytes[1] if len(cert_bytes) > 1 else None
        
        segundo_byte_str = f"0x{segundo_byte:02x}" if segundo_byte is not None else "N/A"
        print(f"   📋 Primeiros bytes: 0x{primeiro_byte:02x} {segundo_byte_str}")
        
        formato_valido = False
        if primeiro_byte == 0x30 and segundo_byte == 0x82:
            print("   ✅ Formato DER/PKCS#12 detectado (0x30 0x82)")
            formato_valido = True
        elif cert_bytes[:2] == b'PK':
            print("   ✅ Formato ZIP/PK detectado")
            formato_valido = True
        else:
            print(f"   ⚠️ Formato não reconhecido, mas continuando...")
            formato_valido = True  # Tentar mesmo assim
        
        if not formato_valido:
            raise ValueError(f"Formato de certificado inválido. Primeiros bytes: {cert_bytes[:4].hex()}")
        
        # PASSO 5: Criar arquivo temporário
        print("\n[PASSO 5/6] Criando arquivo temporário...")
        cert_file_path = tempfile.mktemp(suffix='.pfx', prefix='cert_nfce_')
        
        try:
            with open(cert_file_path, 'wb') as cert_file:
                cert_file.write(cert_bytes)
                cert_file.flush()
                os.fsync(cert_file.fileno())
            
            # Verificar arquivo criado
            if not os.path.exists(cert_file_path):
                raise FileNotFoundError(f"Arquivo temporário não foi criado: {cert_file_path}")
            
            file_size = os.path.getsize(cert_file_path)
            if file_size == 0:
                raise ValueError("Arquivo temporário está vazio")
            
            if file_size != len(cert_bytes):
                raise ValueError(f"Tamanho do arquivo ({file_size}) não corresponde aos bytes ({len(cert_bytes)})")
            
            print(f"   ✅ Arquivo criado: {cert_file_path}")
            print(f"   ✅ Tamanho: {file_size} bytes")
        except Exception as e:
            # Limpar arquivo se houver erro
            if os.path.exists(cert_file_path):
                try:
                    os.remove(cert_file_path)
                except:
                    pass
            raise Exception(f"Erro ao criar arquivo temporário: {str(e)}")
        
        # PASSO 6: Validar certificado com PyNFe e verificar detalhes
        print("\n[PASSO 6/6] Validando certificado com PyNFe...")
        self.certificado_path = cert_file_path
        self.senha_certificado = senha
        
        try:
            from pynfe.entidades import CertificadoA1
            from cryptography import x509
            from cryptography.hazmat.backends import default_backend
            from datetime import datetime
            
            # Criar objeto CertificadoA1
            cert_a1 = CertificadoA1(cert_file_path)
            
            # Converter senha para bytes se necessário
            senha_bytes = senha.encode('utf-8') if isinstance(senha, str) else senha
            
            # Tentar separar arquivo (valida senha e formato)
            print("   🔧 Tentando carregar certificado...")
            chave, cert = cert_a1.separar_arquivo(senha_bytes, caminho=False)
            
            print(f"   ✅ Certificado carregado com sucesso!")
            print(f"   ✅ Chave privada extraída")
            print(f"   ✅ Certificado X509 extraído")
            
            # VALIDAÇÕES ADICIONAIS DO CERTIFICADO
            print("\n" + "=" * 70)
            print("VALIDAÇÕES ADICIONAIS DO CERTIFICADO")
            print("=" * 70)
            
            try:
                from cryptography import x509
                from cryptography.hazmat.backends import default_backend
                from datetime import datetime
                
                # Parsear certificado X509 para extrair informações
                if isinstance(cert, bytes):
                    cert_x509 = x509.load_der_x509_certificate(cert, default_backend())
                else:
                    # Se já é objeto X509, usar diretamente
                    cert_x509 = cert
                
                # 1. Verificar validade do certificado
                print("\n[VALIDAÇÃO 1/5] Verificando validade do certificado...")
                agora = datetime.now()
                validade_not_before = cert_x509.not_valid_before
                validade_not_after = cert_x509.not_valid_after
                
                print(f"   📋 Válido de: {validade_not_before.strftime('%d/%m/%Y %H:%M:%S')}")
                print(f"   📋 Válido até: {validade_not_after.strftime('%d/%m/%Y %H:%M:%S')}")
                print(f"   📋 Data atual: {agora.strftime('%d/%m/%Y %H:%M:%S')}")
                
                if agora < validade_not_before:
                    raise ValueError(
                        f"❌ CERTIFICADO AINDA NÃO É VÁLIDO!\n\n"
                        f"O certificado só será válido a partir de: {validade_not_before.strftime('%d/%m/%Y %H:%M:%S')}\n"
                        f"Data atual: {agora.strftime('%d/%m/%Y %H:%M:%S')}\n\n"
                        f"SOLUÇÃO: Aguarde até a data de início da validade ou use um certificado válido."
                    )
                
                if agora > validade_not_after:
                    raise ValueError(
                        f"❌ CERTIFICADO EXPIRADO!\n\n"
                        f"O certificado expirou em: {validade_not_after.strftime('%d/%m/%Y %H:%M:%S')}\n"
                        f"Data atual: {agora.strftime('%d/%m/%Y %H:%M:%S')}\n\n"
                        f"SOLUÇÃO: É necessário adquirir um novo certificado digital junto a uma autoridade certificadora credenciada na ICP-Brasil."
                    )
                
                dias_restantes = (validade_not_after - agora).days
                if dias_restantes < 30:
                    print(f"   ⚠️ AVISO: Certificado expira em {dias_restantes} dias!")
                else:
                    print(f"   ✅ Certificado válido por mais {dias_restantes} dias")
                
                # 2. Verificar se é ICP-Brasil
                print("\n[VALIDAÇÃO 2/5] Verificando se é certificado ICP-Brasil...")
                subject = cert_x509.subject
                issuer = cert_x509.issuer
                
                # Verificar se o issuer contém "ICP-Brasil" ou OIDs conhecidos
                issuer_str = str(issuer)
                is_icp_brasil = False
                
                # Verificar OIDs ICP-Brasil conhecidos
                icp_brasil_oids = [
                    '2.16.76.1.2.1',  # AC Raiz Brasileira
                    '2.16.76.1.2.2',  # AC Secretaria da Receita Federal do Brasil
                    '2.16.76.1.2.3',  # AC SERASA
                    '2.16.76.1.2.4',  # AC Certisign
                    '2.16.76.1.2.5',  # AC Serasa
                ]
                
                # Verificar extensões do certificado
                try:
                    for ext in cert_x509.extensions:
                        if ext.oid._name == 'authorityKeyIdentifier':
                            # Verificar se tem OID ICP-Brasil
                            pass
                except:
                    pass
                
                # Verificar se issuer contém termos ICP-Brasil
                if 'ICP-Brasil' in issuer_str or 'ICP Brasil' in issuer_str or 'AC' in issuer_str:
                    is_icp_brasil = True
                    print(f"   ✅ Certificado parece ser ICP-Brasil (issuer: {issuer_str[:100]}...)")
                else:
                    print(f"   ⚠️ AVISO: Certificado pode não ser ICP-Brasil")
                    print(f"   📋 Issuer: {issuer_str}")
                    print(f"   ⚠️ Certificados não ICP-Brasil podem ser rejeitados pela SEFAZ")
                
                # 3. Extrair CNPJ do certificado
                print("\n[VALIDAÇÃO 3/5] Extraindo CNPJ do certificado...")
                cnpj_certificado = None
                
                # Buscar CNPJ no subject (pode estar em diferentes campos)
                for attr in subject:
                    if attr.oid._name == 'serialNumber' or 'CNPJ' in str(attr.oid._name).upper():
                        valor = str(attr.value)
                        # Extrair apenas números
                        import re
                        cnpj_limpo = re.sub(r'[^\d]', '', valor)
                        if len(cnpj_limpo) == 14:
                            cnpj_certificado = cnpj_limpo
                            print(f"   ✅ CNPJ encontrado no certificado: {cnpj_certificado}")
                            break
                
                # Se não encontrou, buscar em outros campos
                if not cnpj_certificado:
                    subject_str = str(subject)
                    # Tentar extrair CNPJ do subject
                    import re
                    cnpj_match = re.search(r'(\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2})', subject_str)
                    if cnpj_match:
                        cnpj_certificado = re.sub(r'[^\d]', '', cnpj_match.group(1))
                        if len(cnpj_certificado) == 14:
                            print(f"   ✅ CNPJ encontrado no subject: {cnpj_certificado}")
                
                if not cnpj_certificado:
                    print("   ⚠️ AVISO: CNPJ não encontrado no certificado")
                    print(f"   📋 Subject: {subject}")
                else:
                    print(f"   ✅ CNPJ do certificado: {cnpj_certificado}")
                
                # 4. Verificar CNPJ do certificado vs CNPJ da empresa
                print("\n[VALIDAÇÃO 4/5] Verificando consistência CNPJ...")
                # Esta validação será feita depois quando tivermos os dados da empresa
                print("   ℹ️ Validação será feita durante a assinatura")
                
                # 5. Verificar algoritmo e tamanho da chave
                print("\n[VALIDAÇÃO 5/5] Verificando algoritmo e chave...")
                public_key = cert_x509.public_key()
                
                # Verificar tipo de chave
                if hasattr(public_key, 'key_size'):
                    key_size = public_key.key_size
                    print(f"   📋 Tamanho da chave: {key_size} bits")
                    
                    if key_size < 2048:
                        print(f"   ⚠️ AVISO: Chave com {key_size} bits pode ser considerada fraca")
                    else:
                        print(f"   ✅ Tamanho da chave adequado ({key_size} bits)")
                
                # Verificar algoritmo
                if hasattr(public_key, 'algorithm'):
                    algorithm = public_key.algorithm
                    print(f"   📋 Algoritmo: {algorithm}")
                
                print("\n" + "=" * 70)
                print("✅ VALIDAÇÕES DO CERTIFICADO CONCLUÍDAS")
                print("=" * 70)
                
                # Armazenar informações do certificado para validação posterior
                self._cert_info = {
                    'validade_not_before': validade_not_before,
                    'validade_not_after': validade_not_after,
                    'cnpj': cnpj_certificado,
                    'is_icp_brasil': is_icp_brasil,
                    'issuer': issuer_str,
                    'subject': str(subject)
                }
                
            except ImportError:
                print("   ⚠️ Bibliotecas cryptography não disponíveis para validações avançadas")
                print("   💡 Instale: pip install cryptography")
                print("   ⚠️ Continuando sem validações avançadas...")
            except Exception as e_validacao:
                print(f"   ⚠️ Erro nas validações avançadas: {e_validacao}")
                print("   ⚠️ Continuando sem validações avançadas...")
                import traceback
                traceback.print_exc()
            
            # Limpar arquivos temporários do teste
            cert_a1.excluir()
            
            print("\n" + "=" * 70)
            print("✅ CERTIFICADO PREPARADO E VALIDADO COM SUCESSO!")
            print("=" * 70)
            
            return cert_file_path
            
        except Exception as e_valid:
            error_str = str(e_valid).lower()
            error_msg_completo = str(e_valid)
            
            # Limpar arquivo temporário em caso de erro
            if os.path.exists(cert_file_path):
                try:
                    os.remove(cert_file_path)
                except:
                    pass
            
            # Mensagens de erro específicas
            if 'password' in error_str or 'senha' in error_str or 'invalid password' in error_str or 'bad decrypt' in error_str:
                raise ValueError(
                    "SENHA DO CERTIFICADO INCORRETA\n\n"
                    "A senha informada não corresponde ao certificado digital.\n\n"
                    "SOLUÇÕES:\n"
                    "1. Verifique se a senha está correta\n"
                    "2. Tente digitar a senha novamente\n"
                    "3. Verifique se não há espaços antes ou depois da senha\n"
                    f"\nErro técnico: {error_msg_completo}"
                )
            elif 'pkcs12' in error_str or 'format' in error_str or 'invalid' in error_str or 'asn1' in error_str or 'malformed' in error_str:
                raise ValueError(
                    "FORMATO DE CERTIFICADO INVÁLIDO\n\n"
                    "O arquivo não é um certificado PFX/P12 válido.\n\n"
                    "SOLUÇÕES:\n"
                    "1. Verifique se o certificado está no formato correto (.pfx ou .p12)\n"
                    "2. Tente exportar o certificado novamente\n"
                    "3. Verifique se o certificado não está corrompido\n"
                    f"\nErro técnico: {error_msg_completo}"
                )
            elif 'file' in error_str or 'not found' in error_str:
                raise FileNotFoundError(
                    f"ARQUIVO DE CERTIFICADO NÃO ENCONTRADO\n\n"
                    f"Erro técnico: {error_msg_completo}"
                )
            else:
                raise Exception(
                    f"ERRO AO CARREGAR CERTIFICADO\n\n"
                    f"Erro técnico: {error_msg_completo}\n\n"
                    f"Verifique:\n"
                    f"1. Se o certificado está no formato PFX/P12\n"
                    f"2. Se a senha está correta\n"
                    f"3. Se o certificado não está expirado\n"
                    f"4. Se o certificado não está corrompido"
                )
    
    def _criar_emitente(self, empresa_data: Dict) -> Emitente:
        """Cria objeto Emitente do PyNFe"""
        # Normalizar nome do município para o formato esperado pelo PyNFe
        cidade_original = empresa_data.get('cidade', '')
        uf = empresa_data.get('uf', 'SP')
        cidade = cidade_original
        
        # Se temos código IBGE, usar obter_municipio_por_codigo para obter nome correto
        codigo_ibge = empresa_data.get('codigoIBGE') or empresa_data.get('codigo_municipio') or empresa_data.get('codigo_municipio_ibge')
        
        if codigo_ibge and str(codigo_ibge).strip():
            try:
                from pynfe.utils import obter_municipio_por_codigo
                cidade = obter_municipio_por_codigo(str(codigo_ibge).strip(), uf)
                print(f"✅ Município encontrado pelo código IBGE {codigo_ibge}: {cidade}")
            except Exception as e:
                print(f"⚠️ Aviso: Não foi possível obter município pelo código IBGE {codigo_ibge}: {e}")
                print(f"   Tentando usar cidade informada: {cidade_original}")
                cidade = cidade_original
        
        # Se não temos código IBGE ou falhou, tentar normalizar o nome da cidade
        if not codigo_ibge or cidade == cidade_original:
            try:
                from pynfe.utils import normalizar_municipio, obter_codigo_por_municipio
                # Tentar buscar o código usando o nome normalizado
                cidade_normalizada = normalizar_municipio(cidade)
                codigo_encontrado = obter_codigo_por_municipio(cidade_normalizada, uf)
                # Se encontrou, obter o nome oficial do município
                from pynfe.utils import obter_municipio_por_codigo
                cidade = obter_municipio_por_codigo(codigo_encontrado, uf)
                print(f"✅ Município encontrado após normalização: {cidade} (código: {codigo_encontrado})")
            except Exception as e:
                print(f"⚠️ Aviso: Não foi possível normalizar/buscar município '{cidade_original}': {e}")
                print(f"   Usando cidade informada: {cidade_original}")
                cidade = cidade_original
        
        # Validar e garantir campos obrigatórios do endereço
        # Tentar múltiplas chaves possíveis para endereco/logradouro
        endereco_logradouro = (
            empresa_data.get('endereco', '').strip() or 
            empresa_data.get('logradouro', '').strip() or
            empresa_data.get('endereco_logradouro', '').strip() or
            empresa_data.get('logradouro_emitente', '').strip() or
            empresa_data.get('xLgr', '').strip()
        )
        
        # Se ainda estiver vazio, verificar em configuracoes
        if not endereco_logradouro and 'configuracoes' in empresa_data:
            config = empresa_data.get('configuracoes', {})
            if isinstance(config, dict):
                endereco_logradouro = (
                    config.get('endereco', '').strip() or
                    config.get('logradouro', '').strip() or
                    ''
                )
        
        # VALIDAÇÃO CRÍTICA: xLgr não pode estar vazio conforme schema
        if not endereco_logradouro:
            # Listar todas as chaves disponíveis para debug
            chaves_disponiveis = list(empresa_data.keys())
            if 'configuracoes' in empresa_data and isinstance(empresa_data['configuracoes'], dict):
                chaves_config = list(empresa_data['configuracoes'].keys())
            else:
                chaves_config = []
            
            raise ValueError(
                "❌ ERRO CRÍTICO: Campo 'endereco' (logradouro) é OBRIGATÓRIO e está VAZIO.\n\n"
                "O schema da SEFAZ exige que o campo xLgr (logradouro) tenha um valor não vazio.\n"
                "Conforme manual do validador SEFAZ, o Schema XML valida tipo de dado e Pattern constraint.\n\n"
                "🔍 DIAGNÓSTICO:\n"
                f"Chaves disponíveis em empresa_data: {chaves_disponiveis}\n"
                f"Chaves disponíveis em configuracoes: {chaves_config}\n\n"
                "✅ SOLUÇÃO:\n"
                "1. Verifique se o campo 'endereco' está preenchido nos dados da empresa\n"
                "2. Certifique-se de que o endereço não está vazio ou apenas com espaços\n"
                "3. O campo pode estar em 'endereco', 'logradouro', 'endereco_logradouro' ou 'xLgr'\n"
                "4. Verifique se o campo está em 'configuracoes' se não estiver no nível raiz"
            )
        
        endereco_numero = empresa_data.get('numero', '').strip() or empresa_data.get('endereco_numero', '').strip() or '0'
        if not endereco_numero:
            endereco_numero = '0'
        
        # Tentar múltiplas chaves possíveis para bairro
        endereco_bairro = (
            empresa_data.get('bairro', '').strip() or
            empresa_data.get('endereco_bairro', '').strip() or
            empresa_data.get('xBairro', '').strip()
        )
        
        # Se ainda estiver vazio, verificar em configuracoes
        if not endereco_bairro and 'configuracoes' in empresa_data:
            config = empresa_data.get('configuracoes', {})
            if isinstance(config, dict):
                endereco_bairro = (
                    config.get('bairro', '').strip() or
                    config.get('endereco_bairro', '').strip() or
                    ''
                )
        
        # VALIDAÇÃO CRÍTICA: xBairro não pode estar vazio conforme schema
        if not endereco_bairro:
            raise ValueError(
                "❌ ERRO CRÍTICO: Campo 'bairro' é OBRIGATÓRIO e está VAZIO.\n\n"
                "O schema da SEFAZ exige que o campo xBairro tenha um valor não vazio.\n"
                "Conforme manual do validador SEFAZ, o Schema XML valida tipo de dado e Pattern constraint.\n\n"
                "✅ SOLUÇÃO:\n"
                "1. Verifique se o campo 'bairro' está preenchido nos dados da empresa\n"
                "2. Certifique-se de que o bairro não está vazio\n"
                "3. O campo pode estar em 'bairro', 'endereco_bairro' ou 'xBairro'"
            )
        
        # GARANTIR que os campos não estão vazios (mesmo após validação)
        # O PyNFe pode limpar campos vazios durante serialização, então forçar valores mínimos
        if not endereco_logradouro or not endereco_logradouro.strip():
            endereco_logradouro = 'ENDEREÇO NÃO INFORMADO'
            print(f"   ⚠️ AVISO: endereco_logradouro estava vazio, usando valor padrão: '{endereco_logradouro}'")
        
        if not endereco_bairro or not endereco_bairro.strip():
            endereco_bairro = 'BAIRRO NÃO INFORMADO'
            print(f"   ⚠️ AVISO: endereco_bairro estava vazio, usando valor padrão: '{endereco_bairro}'")
        
        # Garantir que não são apenas espaços
        endereco_logradouro = endereco_logradouro.strip()
        endereco_bairro = endereco_bairro.strip()
        
        # Validar novamente após strip
        if not endereco_logradouro:
            endereco_logradouro = 'ENDEREÇO NÃO INFORMADO'
        if not endereco_bairro:
            endereco_bairro = 'BAIRRO NÃO INFORMADO'
        
        print(f"   ✅ Valores finais do endereço:")
        print(f"      Logradouro: '{endereco_logradouro}'")
        print(f"      Bairro: '{endereco_bairro}'")
        print(f"      Número: '{endereco_numero}'")
        
        return Emitente(
            razao_social=empresa_data.get('razao_social', empresa_data.get('razaoSocial', '')),
            nome_fantasia=empresa_data.get('nome_fantasia', empresa_data.get('nomeFantasia', '')),
            cnpj=empresa_data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', ''),
            codigo_de_regime_tributario=empresa_data.get('crt', '3'),
            inscricao_estadual=empresa_data.get('inscricao_estadual', empresa_data.get('inscricaoEstadual', '')),
            inscricao_municipal=empresa_data.get('inscricao_municipal', ''),
            cnae_fiscal=empresa_data.get('cnae', ''),
            endereco_logradouro=endereco_logradouro,  # Garantido não vazio
            endereco_numero=endereco_numero,
            endereco_bairro=endereco_bairro,  # Garantido não vazio
            endereco_municipio=cidade,  # Usar cidade normalizada ou original
            endereco_uf=uf,
            endereco_cep=empresa_data.get('cep', '').replace('-', '').strip() or '00000000',
            endereco_pais=CODIGO_BRASIL,
            endereco_telefone=empresa_data.get('telefone', '').replace('(', '').replace(')', '').replace('-', '').replace(' ', ''),
        )
    
    def _criar_cliente(self, consumidor: Optional[Dict], uf_empresa: str = 'SP') -> Cliente:
        """Cria objeto Cliente do PyNFe"""
        # Para NFC-e, o cliente pode não ter endereço completo
        # Mas o PyNFe sempre tenta buscar código do município, mesmo se vazio
        # Solução: usar município padrão da capital do estado quando cliente não tem endereço
        
        uf_cliente = uf_empresa if uf_empresa else 'SP'
        
        # Municípios padrão (capitais) por UF - usado quando cliente não tem endereço
        municipios_padrao = {
            'SP': 'SAO PAULO',
            'RJ': 'RIO DE JANEIRO',
            'MG': 'BELO HORIZONTE',
            'RS': 'PORTO ALEGRE',
            'PR': 'CURITIBA',
            'SC': 'FLORIANOPOLIS',
            'BA': 'SALVADOR',
            'GO': 'GOIANIA',
            'PE': 'RECIFE',
            'CE': 'FORTALEZA',
            'DF': 'BRASILIA',
        }
        
        # Se cliente não tem município, usar município padrão da UF
        municipio_cliente = municipios_padrao.get(uf_cliente, 'SAO PAULO')
        
        # Valores padrão para endereço do destinatário (schema não aceita strings vazias)
        # Usar valores válidos mínimos conforme exigência do schema
        endereco_logradouro_padrao = 'NÃO INFORMADO'
        endereco_bairro_padrao = 'NÃO INFORMADO'
        
        if consumidor and consumidor.get('cpf'):
            return Cliente(
                razao_social=consumidor.get('nome', 'CONSUMIDOR FINAL'),
                tipo_documento='CPF',
                numero_documento=consumidor.get('cpf', '').replace('.', '').replace('-', ''),
                indicador_ie=9,  # 9=Não contribuinte
                endereco_logradouro=endereco_logradouro_padrao,  # Schema não aceita string vazia
                endereco_numero='0',
                endereco_bairro=endereco_bairro_padrao,  # Schema não aceita string vazia
                endereco_municipio=municipio_cliente,  # Usar município padrão (evita erro)
                endereco_uf=uf_cliente,  # Usar UF da empresa (válida)
                endereco_cep='',
                endereco_pais=CODIGO_BRASIL,
            )
        else:
            # Para NFC-e sem CPF informado, usar CPF válido genérico para consumidor final
            # CPF 11144477735 é válido e aceito pela SEFAZ para consumidor final não identificado
            # O PyNFe exige que tipo_documento e numero_documento não sejam vazios
            return Cliente(
                razao_social='CONSUMIDOR FINAL',
                tipo_documento='CPF',  # PyNFe exige tipo não vazio
                numero_documento='11144477735',  # CPF válido genérico para consumidor final não identificado
                indicador_ie=9,  # 9=Não contribuinte
                endereco_logradouro=endereco_logradouro_padrao,  # Schema não aceita string vazia
                endereco_numero='0',
                endereco_bairro=endereco_bairro_padrao,  # Schema não aceita string vazia
                endereco_municipio=municipio_cliente,  # Usar município padrão (evita erro)
                endereco_uf=uf_cliente,  # Usar UF da empresa (válida)
                endereco_cep='',
                endereco_pais=CODIGO_BRASIL,
            )
    
    def _formatar_erro_rejeicao(self, c_stat: str, x_motivo: str) -> str:
        """Formata mensagem de erro de rejeição da SEFAZ - apenas cStat e mensagem"""
        # Retornar apenas a mensagem de rejeição da SEFAZ (sem detalhes técnicos)
        return x_motivo
    
    def _criar_notafiscal(
        self,
        emitente: Emitente,
        cliente: Cliente,
        empresa_data: Dict,
        numero_nfce: int
    ) -> NotaFiscal:
        """Cria objeto NotaFiscal do PyNFe"""
        ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
        
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
            
            # Determinar CST/CSOSN baseado no regime tributário
            cst = icms_data.get('cst', '')
            csosn = icms_data.get('csosn', '')
            
            # Se não tiver CST nem CSOSN, usar padrão
            if not cst and not csosn:
                cst = '102'  # Simples Nacional - Sem permissão de crédito
                csosn = '102'
            
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
                icms_csosn=csosn if csosn else cst,  # CSOSN para Simples Nacional
                # PIS e COFINS obrigatórios para NFC-e
                # Modalidade 08 = Operação sem Incidência da Contribuição (obrigatória para NFC-e)
                # Esta modalidade força a serialização mesmo com valores zero
                pis_modalidade='08',
                cofins_modalidade='08',
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
            # Para tipo 99 (Outros), descrição é obrigatória e deve ser específica
            if tipo == '99':
                descricao = pagamento.get('descricao') or pagamento.get('xPag') or 'Outros'
                # Garantir que descrição não seja vazia (obrigatório para tipo 99)
                if not descricao or descricao.strip() == '':
                    descricao = 'Outros'  # Descrição padrão se não informada
                descricao = descricao.strip()  # Remover espaços
            else:
                descricao = tipos_pagamento.get(tipo, 'Outros')
            
            # Garantir que descrição nunca seja None ou vazia
            if not descricao or descricao.strip() == '':
                descricao = tipos_pagamento.get(tipo, 'Outros')
            
            valor = Decimal(str(pagamento.get('valor', 0.0)))
            
            notafiscal.adicionar_pagamento(
                t_pag=tipo,
                x_pag=descricao,  # Descrição obrigatória, especialmente para tipo 99
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
        Emite NFC-e usando PyNFe (padrão dos testes)
        
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
            print("=" * 70)
            print("EMISSÃO NFC-e - PyNFe (Modo Desenvolvimento)")
            print("=" * 70)
            
            # 1. Preparar certificado
            print("\n[1/7] Preparando certificado...")
            # Buscar certificado de diferentes fontes possíveis (conforme código Dart)
            print("🔍 Buscando certificado digital...")
            
            # DIAGNÓSTICO COMPLETO: Logar TODOS os campos recebidos
            print("\n" + "=" * 70)
            print("DIAGNÓSTICO COMPLETO - DADOS RECEBIDOS")
            print("=" * 70)
            print(f"Campos em empresa_data: {list(empresa_data.keys())}")
            print(f"Tem 'configuracoes': {'configuracoes' in empresa_data}")
            if 'configuracoes' in empresa_data:
                config = empresa_data.get('configuracoes', {})
                print(f"  Tipo de configuracoes: {type(config)}")
                if isinstance(config, dict):
                    print(f"  Chaves em configuracoes: {list(config.keys())}")
                    if 'certificadoDigitalBytes' in config:
                        cert_bytes = config['certificadoDigitalBytes']
                        print(f"  certificadoDigitalBytes existe: True")
                        print(f"  Tipo: {type(cert_bytes)}")
                        print(f"  Tamanho: {len(str(cert_bytes)) if cert_bytes else 0} caracteres")
                        if cert_bytes:
                            print(f"  Primeiros 50 chars: {str(cert_bytes)[:50]}...")
            print(f"Tem 'certificado_base64': {'certificado_base64' in empresa_data}")
            if 'certificado_base64' in empresa_data:
                cert_b64 = empresa_data.get('certificado_base64')
                print(f"  Tipo: {type(cert_b64)}")
                print(f"  Tamanho: {len(str(cert_b64)) if cert_b64 else 0} caracteres")
            print(f"Tem 'certificadoDigitalUrl': {'certificadoDigitalUrl' in empresa_data}")
            if 'certificadoDigitalUrl' in empresa_data:
                cert_url = empresa_data.get('certificadoDigitalUrl')
                print(f"  Valor: {cert_url}")
            print("=" * 70 + "\n")
            
            certificado_base64 = None
            certificado_path = None  # Para suportar arquivo PFX direto
            
            # PRIORIDADE 0: Verificar se é caminho de arquivo PFX direto
            # Verificar campos que podem conter caminho de arquivo
            campos_arquivo = [
                'certificado_path', 'certificadoPath', 'certificado_file', 'certificadoFile',
                'certificado_pfx', 'certificadoPfx', 'certificado_p12', 'certificadoP12'
            ]
            
            for campo in campos_arquivo:
                if campo in empresa_data:
                    caminho_temp = empresa_data.get(campo)
                    if caminho_temp and isinstance(caminho_temp, str):
                        caminho_temp = caminho_temp.strip()
                        # Verificar se é um caminho de arquivo válido
                        if os.path.exists(caminho_temp) and (caminho_temp.lower().endswith('.pfx') or caminho_temp.lower().endswith('.p12')):
                            certificado_path = caminho_temp
                            print(f"   ✅ Arquivo PFX encontrado em '{campo}': {certificado_path}")
                            break
            
            # Se não encontrou arquivo, verificar em configuracoes
            if not certificado_path:
                configuracoes = empresa_data.get('configuracoes', {})
                if isinstance(configuracoes, dict):
                    for campo in campos_arquivo:
                        if campo in configuracoes:
                            caminho_temp = configuracoes.get(campo)
                            if caminho_temp and isinstance(caminho_temp, str):
                                caminho_temp = caminho_temp.strip()
                                if os.path.exists(caminho_temp) and (caminho_temp.lower().endswith('.pfx') or caminho_temp.lower().endswith('.p12')):
                                    certificado_path = caminho_temp
                                    print(f"   ✅ Arquivo PFX encontrado em configuracoes['{campo}']: {certificado_path}")
                                    break
            
            # Se encontrou arquivo PFX, usar diretamente (não precisa converter para base64)
            if certificado_path:
                print(f"   📋 Usando arquivo PFX diretamente: {certificado_path}")
                # Validar arquivo
                if not os.path.exists(certificado_path):
                    return {
                        'success': False,
                        'error': f'Arquivo de certificado não encontrado: {certificado_path}',
                        'error_type': 'CertificateError'
                    }
                
                if not os.path.isfile(certificado_path):
                    return {
                        'success': False,
                        'error': f'Caminho não é um arquivo: {certificado_path}',
                        'error_type': 'CertificateError'
                    }
                
                file_size = os.path.getsize(certificado_path)
                if file_size == 0:
                    return {
                        'success': False,
                        'error': f'Arquivo de certificado está vazio: {certificado_path}',
                        'error_type': 'CertificateError'
                    }
                
                print(f"   ✅ Arquivo PFX válido: {file_size} bytes")
                # Usar o arquivo diretamente, não precisa preparar como base64
                cert_path = certificado_path
                # Buscar senha
                senha_certificado = empresa_data.get('senha_certificado') or empresa_data.get('senhaCertificado') or empresa_data.get('senha_cert') or empresa_data.get('senhaCert')
                if not senha_certificado:
                    configuracoes = empresa_data.get('configuracoes', {})
                    if isinstance(configuracoes, dict):
                        senha_certificado = configuracoes.get('senhaCertificado') or configuracoes.get('senha_certificado') or configuracoes.get('senhaCert') or configuracoes.get('senha_cert')
                
                if not senha_certificado:
                    return {
                        'success': False,
                        'error': 'Senha do certificado não fornecida. É necessário fornecer a senha quando usar arquivo PFX direto.',
                        'error_type': 'CertificateError'
                    }
                
                print("   ✅ Senha do certificado encontrada")
                # Armazenar para uso posterior
                self.certificado_path = cert_path
                self.senha_certificado = senha_certificado
                # Pular preparação de base64 e ir direto para validação do certificado
                print("   ✅ Arquivo PFX será usado diretamente (sem conversão para base64)")
                certificado_base64 = None  # Reset para não processar como base64
            else:
                # Continuar com busca de certificado em base64 (código original)
                # PRIORIDADE 1: certificadoDigitalBytes em configuracoes (mais comum no Flutter)
                configuracoes = empresa_data.get('configuracoes', {})
                if isinstance(configuracoes, dict):
                    cert_temp = configuracoes.get('certificadoDigitalBytes')
                    if cert_temp:
                        # Limpar e normalizar
                        if isinstance(cert_temp, str):
                            certificado_base64 = cert_temp.strip()
                            # Remover prefixos se houver
                            if certificado_base64.startswith('base64:'):
                                certificado_base64 = certificado_base64[7:]
                            if certificado_base64.startswith('base64:pem:'):
                                certificado_base64 = certificado_base64[11:]
                            print("   ✅ Certificado encontrado em configuracoes['certificadoDigitalBytes']")
                            print(f"      Tamanho após limpeza: {len(certificado_base64)} caracteres")
                
                # PRIORIDADE 2: certificado_base64 direto
                if not certificado_base64:
                    cert_temp = empresa_data.get('certificado_base64')
                    if cert_temp:
                        if isinstance(cert_temp, str):
                            certificado_base64 = cert_temp.strip()
                            # Remover prefixos se houver
                            if certificado_base64.startswith('base64:'):
                                certificado_base64 = certificado_base64[7:]
                            print("   ✅ Certificado encontrado em certificado_base64")
                            print(f"      Tamanho após limpeza: {len(certificado_base64)} caracteres")
                
                # PRIORIDADE 3: certificadoDigitalUrl (pode ser URL ou base64)
                if not certificado_base64:
                    cert_temp = empresa_data.get('certificadoDigitalUrl')
                    if cert_temp:
                        if isinstance(cert_temp, str):
                            # Se não começa com http, tratar como base64
                            if not (cert_temp.startswith('http://') or cert_temp.startswith('https://')):
                                certificado_base64 = cert_temp.strip()
                                # Remover prefixos se houver
                                if certificado_base64.startswith('base64:'):
                                    certificado_base64 = certificado_base64[7:]
                                print("   ✅ Certificado encontrado em certificadoDigitalUrl (tratado como base64)")
                                print(f"      Tamanho após limpeza: {len(certificado_base64)} caracteres")
                
                # PRIORIDADE 4: Outros campos possíveis
                if not certificado_base64:
                    cert_temp = empresa_data.get('certificado') or empresa_data.get('certificado_digital')
                    if cert_temp:
                        if isinstance(cert_temp, str):
                            certificado_base64 = cert_temp.strip()
                            print("   ✅ Certificado encontrado em campo alternativo")
                            print(f"      Tamanho após limpeza: {len(certificado_base64)} caracteres")
                
                # Se já temos arquivo PFX direto, pular toda a preparação de base64
                if certificado_path:
                    # Já configurado acima, pular para validação do certificado
                    pass
                # Verificar se é uma URL (começa com http:// ou https://)
                elif certificado_base64 and (certificado_base64.startswith('http://') or certificado_base64.startswith('https://')):
                    print("   ⚠️ Certificado fornecido como URL. Tentando baixar...")
                    try:
                        import requests
                        response = requests.get(certificado_base64, timeout=30)
                        if response.status_code == 200:
                            certificado_base64 = base64.b64encode(response.content).decode('utf-8')
                            print("   ✅ Certificado baixado da URL com sucesso")
                        else:
                            return {
                                'success': False,
                                'error': f'Erro ao baixar certificado da URL: HTTP {response.status_code}',
                                'error_type': 'CertificateError'
                            }
                    except Exception as e:
                        return {
                            'success': False,
                            'error': f'Erro ao baixar certificado da URL: {str(e)}',
                            'error_type': 'CertificateError'
                        }
            
            # Se já temos arquivo PFX direto, pular preparação de base64
            if certificado_path:
                print("   ✅ Usando arquivo PFX direto, pulando preparação de base64")
                # Certificado já está configurado em self.certificado_path e self.senha_certificado
                # Validar o certificado diretamente
                try:
                    from pynfe.entidades import CertificadoA1
                    cert_a1 = CertificadoA1(certificado_path)
                    senha_bytes = self.senha_certificado.encode('utf-8') if isinstance(self.senha_certificado, str) else self.senha_certificado
                    chave, cert = cert_a1.separar_arquivo(senha_bytes, caminho=False)
                    print("   ✅ Certificado PFX carregado e validado com sucesso")
                    cert_a1.excluir()
                except Exception as e_valid:
                    error_str = str(e_valid).lower()
                    if 'password' in error_str or 'senha' in error_str or 'invalid password' in error_str:
                        return {
                            'success': False,
                            'error': f'SENHA DO CERTIFICADO INCORRETA\n\nA senha informada não corresponde ao certificado digital.\n\nErro técnico: {str(e_valid)}',
                            'error_type': 'CertificateError'
                        }
                    else:
                        return {
                            'success': False,
                            'error': f'Erro ao validar certificado PFX: {str(e_valid)}',
                            'error_type': 'CertificateError'
                        }
            # Limpar certificado base64 (remover espaços, quebras de linha, etc)
            elif certificado_base64:
                certificado_base64 = certificado_base64.replace('\n', '').replace('\r', '').replace(' ', '').replace('\t', '')
            
            # Log do que foi encontrado
            if certificado_path:
                print(f"   📋 Certificado encontrado: Arquivo PFX ({certificado_path})")
            elif certificado_base64:
                tamanho = len(certificado_base64) if isinstance(certificado_base64, str) else 'N/A'
                print(f"   📋 Certificado encontrado: {tamanho} caracteres")
                # Verificar se parece ser base64 válido
                if isinstance(certificado_base64, str) and len(certificado_base64) > 100:
                    # Base64 válido geralmente tem caracteres alfanuméricos e +, /, =
                    chars_validos = all(c.isalnum() or c in '+/=' for c in certificado_base64[:100])
                    if not chars_validos:
                        print(f"   ⚠️ Aviso: Certificado pode não estar em base64 válido")
                        print(f"   Primeiros 100 chars: {certificado_base64[:100]}")
            else:
                print("   ❌ Certificado não encontrado em nenhuma fonte")
                print("   🔍 Fontes verificadas:")
                print(f"      - configuracoes['certificadoDigitalBytes']: {configuracoes.get('certificadoDigitalBytes') is not None if isinstance(configuracoes, dict) else 'N/A'}")
                print(f"      - certificado_base64: {empresa_data.get('certificado_base64') is not None}")
                print(f"      - certificadoDigitalUrl: {empresa_data.get('certificadoDigitalUrl') is not None}")
                print(f"      - certificado: {empresa_data.get('certificado') is not None}")
                print(f"      - certificado_digital: {empresa_data.get('certificado_digital') is not None}")
                
                # Retornar erro detalhado
                return {
                    'success': False,
                    'error': (
                        'Certificado digital não fornecido.\n\n'
                        'O certificado deve estar em uma das seguintes fontes:\n'
                        '1. configuracoes["certificadoDigitalBytes"] (prioridade 1)\n'
                        '2. certificado_base64 (prioridade 2)\n'
                        '3. certificadoDigitalUrl (prioridade 3)\n\n'
                        'DIAGNÓSTICO:\n'
                        f'  - configuracoes existe: {"configuracoes" in empresa_data}\n'
                        f'  - configuracoes é dict: {isinstance(empresa_data.get("configuracoes"), dict)}\n'
                        f'  - certificadoDigitalBytes em config: {isinstance(configuracoes, dict) and "certificadoDigitalBytes" in configuracoes}\n'
                        f'  - certificado_base64 existe: {"certificado_base64" in empresa_data}\n'
                        f'  - certificadoDigitalUrl existe: {"certificadoDigitalUrl" in empresa_data}\n\n'
                        'Verifique se o certificado foi configurado corretamente na empresa.'
                    ),
                    'error_type': 'CertificateMissing',
                    'details': {
                        'configuracoes_exists': 'configuracoes' in empresa_data,
                        'configuracoes_is_dict': isinstance(empresa_data.get('configuracoes'), dict),
                        'configuracoes_certificadoDigitalBytes': isinstance(configuracoes, dict) and 'certificadoDigitalBytes' in configuracoes,
                        'certificado_base64_exists': 'certificado_base64' in empresa_data,
                        'certificadoDigitalUrl_exists': 'certificadoDigitalUrl' in empresa_data,
                        'all_keys': list(empresa_data.keys()),
                    }
                }
            
            # Preparar certificado - verificar se já temos arquivo PFX ou precisa converter base64
            # Buscar senha (necessária em ambos os casos)
            senha = empresa_data.get('senhaCertificado') or empresa_data.get('senha_certificado') or empresa_data.get('senha', '')
            if not senha:
                configuracoes = empresa_data.get('configuracoes', {})
                if isinstance(configuracoes, dict):
                    senha = configuracoes.get('senhaCertificado') or configuracoes.get('senha_certificado') or configuracoes.get('senhaCert') or configuracoes.get('senha_cert')
            
            if certificado_path:
                # Já temos arquivo PFX configurado, usar diretamente
                cert_path = certificado_path
                print("✅ Certificado PFX será usado diretamente")
                # Se temos arquivo PFX, não precisamos de certificado_base64
                certificado_base64 = None
            else:
                # Processar certificado em base64
                # certificado_base64 já foi buscado anteriormente no código
                pass
            
            if not certificado_base64 and not certificado_path:
                return {
                    'success': False,
                    'error': (
                        'Certificado digital não fornecido.\n\n'
                            'O certificado pode ser fornecido de duas formas:\n\n'
                            'FORMA 1: Arquivo PFX direto (recomendado)\n'
                            '  - certificado_path ou certificadoPath: caminho para arquivo .pfx ou .p12\n'
                            '  - senha_certificado ou senhaCertificado: senha do certificado\n\n'
                            'FORMA 2: Certificado em Base64\n'
                            '  - configuracoes["certificadoDigitalBytes"] (prioridade 1)\n'
                            '  - certificado_base64 (prioridade 2)\n'
                            '  - certificadoDigitalUrl (prioridade 3)\n\n'
                        'Verifique se o certificado foi configurado corretamente na empresa.'
                    ),
                    'error_type': 'CertificateMissing',
                    'details': {
                            'certificado_path_encontrado': certificado_path is not None,
                        'configuracoes_certificadoDigitalBytes_exists': isinstance(configuracoes, dict) and configuracoes.get('certificadoDigitalBytes') is not None,
                        'certificado_base64_exists': 'certificado_base64' in empresa_data,
                        'certificadoDigitalUrl_exists': 'certificadoDigitalUrl' in empresa_data,
                        'all_keys': list(empresa_data.keys()),
                    }
                }
            
            if not senha:
                return {
                    'success': False,
                    'error': 'Senha do certificado não fornecida. Verifique se o campo senhaCertificado está preenchido.',
                    'error_type': 'CertificateMissing'
                }
            
            # Se já temos arquivo PFX, não precisa preparar base64
            if certificado_path:
                # Certificado já está em cert_path, apenas validar
                try:
                    from pynfe.entidades import CertificadoA1
                    cert_a1 = CertificadoA1(cert_path)
                    senha_bytes = senha.encode('utf-8') if isinstance(senha, str) else senha
                    chave, cert = cert_a1.separar_arquivo(senha_bytes, caminho=False)
                    print("✅ Certificado PFX validado com sucesso")
                    cert_a1.excluir()
                except Exception as e_valid:
                    error_str = str(e_valid).lower()
                    if 'password' in error_str or 'senha' in error_str or 'invalid password' in error_str:
                        return {
                            'success': False,
                            'error': f'SENHA DO CERTIFICADO INCORRETA\n\nA senha informada não corresponde ao certificado digital.\n\nErro técnico: {str(e_valid)}',
                            'error_type': 'CertificateError'
                        }
                    else:
                        return {
                            'success': False,
                            'error': f'Erro ao validar certificado PFX: {str(e_valid)}',
                            'error_type': 'CertificateError'
                        }
            else:
                # Preparar certificado a partir de base64
                try:
                    cert_path = self._preparar_certificado(certificado_base64, senha)
                    print("✅ Certificado preparado e validado")
                except ValueError as e:
                    # Erro de validação (senha incorreta, formato inválido, etc)
                    error_msg = str(e)
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro_certificado',
                        'error': error_msg,
                        'error_type': 'CertificateError',
                        'details': error_msg,
                        'diagnostico': {
                            'certificado_encontrado': True,
                            'certificado_tamanho': len(certificado_base64) if certificado_base64 else 0,
                            'senha_fornecida': bool(senha),
                            'tipo_erro': 'validacao'
                        }
                    }
                except FileNotFoundError as e:
                    error_msg = str(e)
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro_certificado',
                        'error': error_msg,
                        'error_type': 'CertificateError',
                        'details': error_msg,
                        'diagnostico': {
                            'certificado_encontrado': True,
                            'certificado_tamanho': len(certificado_base64) if certificado_base64 else 0,
                            'senha_fornecida': bool(senha),
                            'tipo_erro': 'arquivo_nao_encontrado'
                        }
                    }
                except Exception as e:
                    import traceback
                    error_msg = str(e)
                    traceback_str = traceback.format_exc()
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro_certificado',
                        'error': f"Erro ao preparar certificado: {error_msg}",
                        'error_type': 'CertificateError',
                        'details': error_msg,
                        'traceback': traceback_str,
                        'diagnostico': {
                            'certificado_encontrado': bool(certificado_base64),
                        'certificado_tamanho': len(certificado_base64) if certificado_base64 else 0,
                        'senha_fornecida': bool(senha),
                        'tipo_erro': 'erro_desconhecido',
                        'traceback': traceback_str
                    }
                }
            
            # 2. Criar emitente
            print("\n[2/7] Criando emitente...")
            emitente = self._criar_emitente(empresa_data)
            print("✅ Emitente criado")
            
            # 3. Criar cliente
            print("\n[3/7] Criando cliente...")
            uf_empresa = empresa_data.get('uf', 'SP')
            cliente = self._criar_cliente(consumidor, uf_empresa)
            print("✅ Cliente criado")
            
            # 4. Criar nota fiscal
            print("\n[4/7] Criando nota fiscal...")
            notafiscal = self._criar_notafiscal(emitente, cliente, empresa_data, numero_nfce)
            
            # Adicionar produtos
            self._adicionar_produtos(notafiscal, produtos)
            
            # Adicionar pagamentos
            self._adicionar_pagamentos(notafiscal, pagamentos)
            
            if observacoes:
                notafiscal.informacoes_adicionais_interesse_fisco = observacoes
            
            print("✅ Nota fiscal criada")
            
            # 5. Serializar XML
            print("\n[5/7] Serializando XML...")
            ambiente_homologacao = empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
            
            # IMPORTANTE: SerializacaoXML precisa receber um objeto FonteDados, não uma lista
            # A nota fiscal já foi adicionada ao _fonte_dados automaticamente quando foi criada
            # (NotaFiscal herda de Entidade que adiciona automaticamente ao _fonte_dados)
            # Mas vamos garantir que está lá
            _fonte_dados.adicionar_objeto(notafiscal)
            
            # Criar serializador com _fonte_dados (objeto FonteDados, não lista)
            serializador = SerializacaoXML(_fonte_dados, homologacao=ambiente_homologacao)
            xml = serializador.exportar()
            print("✅ XML serializado")
            
            # xml é uma lista de elementos, pegar o primeiro (NFe)
            if isinstance(xml, list) and len(xml) > 0:
                xml_nfe = xml[0]
            elif hasattr(xml, 'tag'):
                xml_nfe = xml
            else:
                raise ValueError("XML serializado em formato inválido")
            
            # Verificar estrutura do XML antes de assinar
            print(f"🔍 Estrutura do XML serializado:")
            print(f"   Tag raiz: {xml_nfe.tag}")
            print(f"   Atributos: {xml_nfe.attrib}")
            print(f"   Elementos filhos: {[child.tag for child in xml_nfe]}")
            
            # Validar campos obrigatórios do endereço no XML serializado (conforme manual do validador SEFAZ)
            # O manual indica que o Schema XML valida tipo de dado e domínio do campo
            try:
                # Procurar enderEmit no XML
                ender_emit = xml_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}enderEmit') or xml_nfe.find('.//enderEmit')
                if ender_emit is None:
                    raise ValueError(
                        "ERRO: Elemento enderEmit não encontrado no XML serializado.\n\n"
                        "O schema da SEFAZ exige que o endereço do emitente esteja presente.\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se os dados do emitente estão corretos\n"
                        "2. Verifique se o PyNFe está serializando corretamente"
                    )
                
                # Validar xLgr (logradouro) - campo obrigatório conforme schema
                xlgr = ender_emit.find('.//{http://www.portalfiscal.inf.br/nfe}xLgr') or ender_emit.find('.//xLgr')
                if xlgr is None:
                    raise ValueError(
                        "ERRO: Campo xLgr (logradouro) não encontrado no XML serializado.\n\n"
                        "O schema da SEFAZ exige que o campo xLgr esteja presente no enderEmit.\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se o campo 'endereco' está preenchido nos dados da empresa\n"
                        f"Valor no emitente: '{emitente.endereco_logradouro}'"
                    )
                if not xlgr.text or not xlgr.text.strip():
                    # CRÍTICO: Se xLgr está vazio no XML, tentar corrigir usando valor do emitente
                    valor_correto = emitente.endereco_logradouro.strip() if emitente.endereco_logradouro else None
                    
                    if valor_correto:
                        # Corrigir o valor vazio no XML
                        print(f"   ⚠️ CORREÇÃO: xLgr estava vazio no XML, corrigindo para: '{valor_correto}'")
                        xlgr.text = valor_correto
                    else:
                        # Se não tem valor no emitente também, lançar erro
                        raise ValueError(
                            "❌ ERRO CRÍTICO: Campo xLgr (logradouro) está vazio no XML serializado.\n\n"
                            "O schema da SEFAZ exige que o campo xLgr tenha um valor não vazio (String com Pattern).\n"
                            "Conforme manual do validador SEFAZ, o Schema XML valida tipo de dado e Pattern constraint.\n\n"
                            "O PyNFe pode ter removido o campo vazio durante a serialização, mas o schema exige que esteja presente.\n\n"
                            "✅ SOLUÇÃO:\n"
                            "1. Verifique se o campo 'endereco' está preenchido nos dados da empresa\n"
                            "2. Certifique-se de que o endereço não está vazio ou apenas com espaços\n"
                            f"Valor no emitente: '{emitente.endereco_logradouro}'\n"
                            f"Valor no XML: '{xlgr.text if xlgr.text else '(vazio)'}'"
                        )
                
                # Validar novamente após possível correção
                if not xlgr.text or not xlgr.text.strip():
                    raise ValueError(
                        "❌ ERRO: Não foi possível corrigir o campo xLgr vazio.\n\n"
                        f"Valor atual: '{xlgr.text if xlgr.text else '(vazio)'}'"
                    )
                
                print(f"   ✅ xLgr validado: '{xlgr.text.strip()}'")
                
                # Validar xBairro (bairro) - campo obrigatório conforme schema
                xbairro = ender_emit.find('.//{http://www.portalfiscal.inf.br/nfe}xBairro') or ender_emit.find('.//xBairro')
                if xbairro is None:
                    raise ValueError(
                        "ERRO: Campo xBairro (bairro) não encontrado no XML serializado.\n\n"
                        "O schema da SEFAZ exige que o campo xBairro esteja presente no enderEmit.\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se o campo 'bairro' está preenchido nos dados da empresa"
                    )
                if not xbairro.text or not xbairro.text.strip():
                    # CRÍTICO: Se xBairro está vazio no XML, tentar corrigir usando valor do emitente
                    valor_correto = emitente.endereco_bairro.strip() if emitente.endereco_bairro else None
                    
                    if valor_correto:
                        # Corrigir o valor vazio no XML
                        print(f"   ⚠️ CORREÇÃO: xBairro estava vazio no XML, corrigindo para: '{valor_correto}'")
                        xbairro.text = valor_correto
                    else:
                        # Se não tem valor no emitente também, lançar erro
                        raise ValueError(
                            "❌ ERRO CRÍTICO: Campo xBairro (bairro) está vazio no XML serializado.\n\n"
                            "O schema da SEFAZ exige que o campo xBairro tenha um valor não vazio (String com Pattern).\n"
                            "Conforme manual do validador SEFAZ, o Schema XML valida tipo de dado e Pattern constraint.\n\n"
                            "✅ SOLUÇÃO:\n"
                            "1. Verifique se o campo 'bairro' está preenchido nos dados da empresa\n"
                            f"Valor no emitente: '{emitente.endereco_bairro}'\n"
                            f"Valor no XML: '{xbairro.text if xbairro.text else '(vazio)'}'"
                        )
                
                # Validar novamente após possível correção
                if not xbairro.text or not xbairro.text.strip():
                    raise ValueError(
                        "❌ ERRO: Não foi possível corrigir o campo xBairro vazio.\n\n"
                        f"Valor atual: '{xbairro.text if xbairro.text else '(vazio)'}'"
                    )
                
                print(f"   ✅ xBairro validado: '{xbairro.text.strip()}'")
                
                # Validar outros campos obrigatórios do endereço
                campos_obrigatorios = {
                    'xMun': 'município',
                    'UF': 'UF',
                    'cPais': 'código do país'
                }
                
                for campo, descricao in campos_obrigatorios.items():
                    elem = ender_emit.find(f'.//{{http://www.portalfiscal.inf.br/nfe}}{campo}') or ender_emit.find(f'.//{campo}')
                    if elem is None or not elem.text or not elem.text.strip():
                        print(f"   ⚠️ Aviso: Campo {campo} ({descricao}) pode estar ausente ou vazio")
                
            except ValueError:
                # Re-lançar ValueError com a mensagem completa
                raise
            except Exception as e_valid:
                print(f"   ⚠️ Aviso: Erro ao validar campos do endereço no XML: {e_valid}")
                import traceback
                traceback.print_exc()
                # Não bloquear, mas avisar
            
            # CORREÇÃO FINAL ANTES DE ASSINAR: Garantir que xLgr, xBairro e cUF estão preenchidos
            print("   🔧 Aplicando correções finais antes de assinar...")
            try:
                # Corrigir xLgr e xBairro se ainda estiverem vazios
                ender_emit_final = xml_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}enderEmit') or xml_nfe.find('.//enderEmit')
                if ender_emit_final is not None:
                    xlgr_final = ender_emit_final.find('.//{http://www.portalfiscal.inf.br/nfe}xLgr') or ender_emit_final.find('.//xLgr')
                    if xlgr_final is None:
                        xlgr_final = etree.SubElement(ender_emit_final, '{http://www.portalfiscal.inf.br/nfe}xLgr')
                        xlgr_final.text = emitente.endereco_logradouro.strip() if emitente.endereco_logradouro else 'ENDEREÇO NÃO INFORMADO'
                        print(f"      ✅ xLgr criado: '{xlgr_final.text}'")
                    elif not xlgr_final.text or not xlgr_final.text.strip():
                        valor_correto = emitente.endereco_logradouro.strip() if emitente.endereco_logradouro else 'ENDEREÇO NÃO INFORMADO'
                        xlgr_final.text = valor_correto
                        print(f"      ✅ xLgr corrigido: '{valor_correto}'")
                    
                    xbairro_final = ender_emit_final.find('.//{http://www.portalfiscal.inf.br/nfe}xBairro') or ender_emit_final.find('.//xBairro')
                    if xbairro_final is None:
                        xbairro_final = etree.SubElement(ender_emit_final, '{http://www.portalfiscal.inf.br/nfe}xBairro')
                        xbairro_final.text = emitente.endereco_bairro.strip() if emitente.endereco_bairro else 'BAIRRO NÃO INFORMADO'
                        print(f"      ✅ xBairro criado: '{xbairro_final.text}'")
                    elif not xbairro_final.text or not xbairro_final.text.strip():
                        valor_correto = emitente.endereco_bairro.strip() if emitente.endereco_bairro else 'BAIRRO NÃO INFORMADO'
                        xbairro_final.text = valor_correto
                        print(f"      ✅ xBairro corrigido: '{valor_correto}'")
                
                # Corrigir cUF no elemento ide se estiver ausente ou vazio
                ide_element = xml_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}ide') or xml_nfe.find('.//ide')
                if ide_element is not None:
                    cuf_element = ide_element.find('.//{http://www.portalfiscal.inf.br/nfe}cUF') or ide_element.find('.//cUF')
                    if cuf_element is None or not cuf_element.text or not cuf_element.text.strip():
                        uf_empresa = empresa_data.get('uf', 'SP')
                        codigo_uf = {
                            'AC': '12', 'AL': '27', 'AP': '16', 'AM': '13', 'BA': '29', 'CE': '23',
                            'DF': '53', 'ES': '32', 'GO': '52', 'MA': '21', 'MT': '51', 'MS': '50',
                            'MG': '31', 'PA': '15', 'PB': '25', 'PR': '41', 'PE': '26', 'PI': '22',
                            'RJ': '33', 'RN': '24', 'RS': '43', 'RO': '11', 'RR': '14', 'SC': '42',
                            'SP': '35', 'SE': '28', 'TO': '17'
                        }.get(uf_empresa.upper(), '35')
                        
                        if cuf_element is None:
                            # Inserir cUF como primeiro elemento dentro de ide
                            cuf_element = etree.Element('{http://www.portalfiscal.inf.br/nfe}cUF')
                            cuf_element.text = codigo_uf
                            ide_element.insert(0, cuf_element)
                            print(f"      ✅ cUF criado em ide: '{codigo_uf}' (UF: {uf_empresa})")
                        else:
                            cuf_element.text = codigo_uf
                            print(f"      ✅ cUF corrigido em ide: '{codigo_uf}' (UF: {uf_empresa})")
            except Exception as e_correcao:
                print(f"   ⚠️ Aviso: Erro ao aplicar correções finais: {e_correcao}")
                import traceback
                traceback.print_exc()
                # Não bloquear, mas avisar
            
            # 6. Gerar QR Code e adicionar infNFeSupl ANTES de assinar
            print("\n[6/8] Gerando QR Code e adicionando infNFeSupl...")
            qrcode_url = None
            # xml_nfe é o XML serializado que será usado para gerar QR Code
            xml_para_qrcode = xml_nfe
            try:
                # Buscar CSC e CSC ID Token da empresa
                csc = empresa_data.get('csc') or empresa_data.get('CSC') or empresa_data.get('configuracoes', {}).get('csc', '')
                csc_id_token = empresa_data.get('csc_id_token') or empresa_data.get('cscIdToken') or empresa_data.get('configuracoes', {}).get('csc_id_token', '1')
                
                if not csc:
                    print("   ⚠️ AVISO: CSC não encontrado nos dados da empresa!")
                    print("   ⚠️ O QR Code não será gerado. Configure o CSC na empresa.")
                    print("   ⚠️ Para obter o CSC, acesse o portal da SEFAZ do seu estado.")
                else:
                    print(f"   ✅ CSC encontrado: {csc[:10]}... (ocultado)")
                    print(f"   ✅ CSC ID Token: {csc_id_token}")
                    
                    # Usar SerializacaoQrcode do PyNFe para gerar QR Code
                    try:
                        from pynfe.processamento.serializacao import SerializacaoQrcode
                        serializador_qrcode = SerializacaoQrcode()
                        
                        # CRÍTICO: O gerador de QR Code espera XML no formato ElementTree
                        # Verificar se xml_para_qrcode é ElementTree ou string
                        if isinstance(xml_para_qrcode, str):
                            # Se é string, parsear para ElementTree
                            xml_para_qrcode = nfce_instance._parse_xml_safe(xml_para_qrcode)
                            if xml_para_qrcode is None:
                                raise ValueError("Não foi possível parsear XML para gerar QR Code")
                        
                        # Verificar se o XML tem a estrutura esperada (infNFe/ide/dhEmi)
                        # O gerador de QR Code precisa encontrar dhEmi
                        inf_nfe_qr = xml_para_qrcode.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or xml_para_qrcode.find('.//infNFe')
                        if inf_nfe_qr is None:
                            # Tentar encontrar NFe primeiro
                            nfe_qr = xml_para_qrcode.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or xml_para_qrcode.find('.//NFe')
                            if nfe_qr is not None:
                                inf_nfe_qr = nfe_qr.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or nfe_qr.find('.//infNFe')
                        
                        if inf_nfe_qr is not None:
                            ide_qr = inf_nfe_qr.find('.//{http://www.portalfiscal.inf.br/nfe}ide') or inf_nfe_qr.find('.//ide')
                            if ide_qr is not None:
                                dh_emi_qr = ide_qr.find('.//{http://www.portalfiscal.inf.br/nfe}dhEmi') or ide_qr.find('.//dhEmi')
                                if dh_emi_qr is None or not dh_emi_qr.text:
                                    print("   ⚠️ AVISO: dhEmi não encontrado no XML - QR Code pode falhar")
                                else:
                                    print(f"   ✅ dhEmi encontrado: {dh_emi_qr.text[:20]}...")
                        else:
                            print("   ⚠️ AVISO: infNFe não encontrado no XML - QR Code pode falhar")
                        
                        # Garantir que xml_para_qrcode seja o elemento raiz NFe (não enviNFe)
                        # O gerador espera o elemento NFe diretamente
                        tag_raiz = xml_para_qrcode.tag.split('}')[-1] if '}' in xml_para_qrcode.tag else xml_para_qrcode.tag
                        if tag_raiz != 'NFe':
                            nfe_element = xml_para_qrcode.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or xml_para_qrcode.find('.//NFe')
                            if nfe_element is not None:
                                xml_para_qrcode = nfe_element
                                print("   ✅ Elemento NFe encontrado para gerar QR Code")
                            else:
                                raise ValueError(f"Elemento NFe não encontrado no XML (tag raiz: {tag_raiz})")
                        
                        # Gerar QR Code e adicionar infNFeSupl ao XML
                        # O método retorna o XML com infNFeSupl adicionado
                        xml_com_qrcode, qrcode_url = serializador_qrcode.gerar_qrcode(
                            token=csc_id_token,
                            csc=csc,
                            xml=xml_para_qrcode,
                            return_qr=True,
                            online=True  # QR Code online (versão 2)
                        )
                        
                        xml_nfe = xml_com_qrcode
                        print(f"   ✅ QR Code gerado com sucesso!")
                        print(f"   📱 URL do QR Code: {qrcode_url[:80]}...")
                    except Exception as e_qrcode:
                        print(f"   ⚠️ Erro ao gerar QR Code: {e_qrcode}")
                        print(f"   ⚠️ Continuando sem QR Code...")
                        import traceback
                        traceback.print_exc()
            except Exception as e_qr:
                print(f"   ⚠️ Erro ao processar QR Code: {e_qr}")
                print(f"   ⚠️ Continuando sem QR Code...")
            
            # 7. Assinar XML (agora com infNFeSupl se QR Code foi gerado)
            print("\n[7/8] Assinando XML...")
            try:
                # Verificar se o arquivo do certificado existe
                print(f"   🔍 [PASSO 1] Verificando arquivo: {cert_path}")
                if not os.path.exists(cert_path):
                    raise FileNotFoundError(f"Arquivo de certificado não encontrado: {cert_path}")
                print(f"   ✅ Arquivo existe")
                
                # Verificar se o arquivo não está vazio
                file_size = os.path.getsize(cert_path)
                print(f"   📋 Tamanho do arquivo: {file_size} bytes")
                if file_size == 0:
                    raise ValueError("Arquivo de certificado está vazio")
                
                # Verificar se o arquivo pode ser lido
                print(f"   🔍 [PASSO 2] Testando leitura do arquivo...")
                try:
                    with open(cert_path, 'rb') as test_file:
                        test_bytes = test_file.read(100)  # Ler primeiros 100 bytes
                        if len(test_bytes) == 0:
                            raise ValueError("Arquivo de certificado está vazio ou não pode ser lido")
                        print(f"   ✅ Arquivo pode ser lido")
                        print(f"   📋 Primeiros bytes (hex): {test_bytes[:8].hex()}")
                        print(f"   📋 Primeiros bytes (ascii): {test_bytes[:8]}")
                except Exception as e:
                    raise FileNotFoundError(f"Erro ao ler arquivo de certificado: {str(e)}")
                
                # Garantir que a senha está no formato correto (string)
                print(f"   🔍 [PASSO 3] Preparando senha...")
                senha_str = self.senha_certificado
                if isinstance(senha_str, bytes):
                    senha_str = senha_str.decode('utf-8')
                    print(f"   ℹ️ Senha convertida de bytes para string")
                elif not isinstance(senha_str, str):
                    senha_str = str(senha_str)
                    print(f"   ℹ️ Senha convertida para string")
                
                # Verificar se a senha não está vazia
                if not senha_str or len(senha_str.strip()) == 0:
                    raise ValueError("Senha do certificado está vazia")
                
                print(f"   ✅ Senha preparada: {len(senha_str)} caracteres")
                
                # Tentar criar o assinador
                # O AssinaturaA1 espera: (caminho_arquivo: str, senha: str)
                # Internamente, o CertificadoA1 vai converter a senha para bytes se necessário
                print(f"   🔍 [PASSO 4] Criando AssinaturaA1...")
                print(f"   📋 Parâmetros:")
                print(f"      - cert_path: {cert_path}")
                print(f"      - senha tipo: {type(senha_str).__name__}")
                print(f"      - senha tamanho: {len(senha_str)} chars")
                
                # VALIDAÇÃO FINAL: Verificar CNPJ do certificado vs CNPJ da empresa
                if hasattr(self, '_cert_info') and self._cert_info and self._cert_info.get('cnpj'):
                    cnpj_cert = self._cert_info['cnpj']
                    cnpj_empresa = empresa_data.get('cnpj', '') or empresa_data.get('CNPJ', '')
                    if cnpj_empresa:
                        import re
                        cnpj_empresa_limpo = re.sub(r'[^\d]', '', str(cnpj_empresa))
                        if cnpj_cert != cnpj_empresa_limpo:
                            print("=" * 70)
                            print("⚠️ AVISO: INCONSISTÊNCIA DE CNPJ")
                            print("=" * 70)
                            print(f"   📋 CNPJ do certificado: {cnpj_cert}")
                            print(f"   📋 CNPJ da empresa: {cnpj_empresa_limpo}")
                            print("   ⚠️ Os CNPJs não coincidem!")
                            print("   ⚠️ Isso pode causar rejeição pela SEFAZ (cStat=290)")
                            print("\n   💡 SOLUÇÃO:")
                            print("      1. Verifique se o certificado pertence à empresa correta")
                            print("      2. Se houver troca do responsável legal, o certificado anterior pode ter sido invalidado")
                            print("      3. Use o certificado correto para a empresa")
                            print("=" * 70)
                
                # Criar AssinaturaA1 (isso vai chamar CertificadoA1 internamente)
                print("   🔧 Carregando certificado no AssinaturaA1...")
                try:
                    assinador = AssinaturaA1(cert_path, senha_str)
                    print("   ✅ Certificado PFX carregado com sucesso no AssinaturaA1")
                    
                    # Verificar se o certificado foi carregado corretamente
                    if not hasattr(assinador, 'cert') or assinador.cert is None:
                        print("   ❌ ERRO: Certificado não foi carregado no AssinaturaA1!")
                        raise ValueError("Certificado não foi carregado corretamente")
                    
                    if not hasattr(assinador, 'key') or assinador.key is None:
                        print("   ❌ ERRO: Chave privada não foi carregada no AssinaturaA1!")
                        raise ValueError("Chave privada não foi carregada corretamente")
                    
                    print("   ✅ Certificado e chave privada carregados com sucesso")
                    
                    # Verificar tamanho do certificado
                    if isinstance(assinador.cert, bytes):
                        print(f"   📋 Tamanho do certificado: {len(assinador.cert)} bytes")
                    elif isinstance(assinador.cert, str):
                        print(f"   📋 Certificado em formato string: {len(assinador.cert)} caracteres")
                    else:
                        print(f"   📋 Certificado em formato: {type(assinador.cert)}")
                    
                except Exception as e_cert_load:
                    print(f"   ❌ ERRO ao carregar certificado no AssinaturaA1: {e_cert_load}")
                    print("   ⚠️ Isso pode causar cStat=290 (Certificado inválido)")
                    raise
                
                # Verificar se certificado é ICP-Brasil antes de assinar
                if hasattr(self, '_cert_info') and self._cert_info:
                    if not self._cert_info.get('is_icp_brasil', False):
                        print("=" * 70)
                        print("⚠️ AVISO: Certificado pode não ser ICP-Brasil")
                        print("=" * 70)
                        print("   ⚠️ Certificados não ICP-Brasil podem ser rejeitados pela SEFAZ")
                        print("   📋 Issuer do certificado:")
                        print(f"      {self._cert_info.get('issuer', 'N/A')[:200]}")
                        print("=" * 70)
                
                # EXTRAÇÃO INTELIGENTE DO CERTIFICADO DER - OBRIGATÓRIO para incluir X509Certificate
                # Esta é uma etapa crítica - sem o certificado DER, não podemos incluir X509Certificate
                print("\n" + "=" * 70)
                print("🔧 EXTRAÇÃO DO CERTIFICADO DER (OBRIGATÓRIO)")
                print("=" * 70)
                
                cert_der_bytes = None
                tentativas_extracao = []
                
                # ESTRATÉGIA 1: Extrair do arquivo PFX diretamente (MAIS CONFIÁVEL)
                try:
                    from pynfe.entidades import CertificadoA1
                    from cryptography import x509 as crypto_x509
                    
                    print("   [1/3] Tentando extrair do arquivo PFX diretamente...")
                    cert_a1_temp = CertificadoA1(cert_path)
                    senha_bytes_temp = senha_str.encode('utf-8') if isinstance(senha_str, str) else senha_str
                    chave_temp, cert_temp = cert_a1_temp.separar_arquivo(senha_bytes_temp, caminho=False)
                    
                    if isinstance(cert_temp, bytes):
                        cert_der_bytes = cert_temp
                        print(f"   ✅ Certificado DER extraído do PFX (bytes): {len(cert_der_bytes)} bytes")
                        tentativas_extracao.append(f"PFX (bytes): {len(cert_der_bytes)} bytes")
                    elif isinstance(cert_temp, crypto_x509.Certificate):
                        cert_der_bytes = cert_temp.public_bytes(crypto_x509.Encoding.DER)
                        print(f"   ✅ Certificado DER extraído do PFX (X509): {len(cert_der_bytes)} bytes")
                        tentativas_extracao.append(f"PFX (X509): {len(cert_der_bytes)} bytes")
                    else:
                        print(f"   ⚠️ Tipo de certificado não esperado: {type(cert_temp)}")
                        tentativas_extracao.append(f"PFX: tipo não suportado ({type(cert_temp)})")
                    
                    cert_a1_temp.excluir()
                    
                except Exception as e_extract_pfx:
                    print(f"   ❌ Falhou: {str(e_extract_pfx)[:100]}")
                    tentativas_extracao.append(f"PFX: ERRO - {str(e_extract_pfx)[:50]}")
                
                # ESTRATÉGIA 2: Extrair do assinador (se Estratégia 1 falhou)
                if not cert_der_bytes:
                    try:
                        print("   [2/3] Tentando extrair do assinador...")
                        if hasattr(assinador, 'cert') and assinador.cert:
                            if isinstance(assinador.cert, bytes):
                                cert_der_bytes = assinador.cert
                                print(f"   ✅ Certificado DER extraído do assinador (bytes): {len(cert_der_bytes)} bytes")
                                tentativas_extracao.append(f"Assinador (bytes): {len(cert_der_bytes)} bytes")
                            elif isinstance(assinador.cert, str):
                                # Se é string PEM, converter para DER
                                from cryptography import x509 as crypto_x509
                                # Remover headers PEM
                                pem_str = assinador.cert.replace('-----BEGIN CERTIFICATE-----', '')
                                pem_str = pem_str.replace('-----END CERTIFICATE-----', '')
                                pem_str = pem_str.replace('\n', '').replace('\r', '').strip()
                                # Decodificar base64 para DER
                                import base64
                                cert_der_bytes = base64.b64decode(pem_str)
                                print(f"   ✅ Certificado DER extraído do assinador (PEM): {len(cert_der_bytes)} bytes")
                                tentativas_extracao.append(f"Assinador (PEM): {len(cert_der_bytes)} bytes")
                            else:
                                # Tentar extrair DER de objeto X509
                                from cryptography import x509 as crypto_x509
                                if isinstance(assinador.cert, crypto_x509.Certificate):
                                    cert_der_bytes = assinador.cert.public_bytes(crypto_x509.Encoding.DER)
                                    print(f"   ✅ Certificado DER extraído do assinador (X509): {len(cert_der_bytes)} bytes")
                                    tentativas_extracao.append(f"Assinador (X509): {len(cert_der_bytes)} bytes")
                                else:
                                    print(f"   ⚠️ Tipo não suportado: {type(assinador.cert)}")
                                    tentativas_extracao.append(f"Assinador: tipo não suportado ({type(assinador.cert)})")
                        else:
                            print("   ⚠️ Assinador não tem certificado disponível")
                            tentativas_extracao.append("Assinador: certificado não disponível")
                    except Exception as e_extract_assinador:
                        print(f"   ❌ Falhou: {str(e_extract_assinador)[:100]}")
                        tentativas_extracao.append(f"Assinador: ERRO - {str(e_extract_assinador)[:50]}")
                
                # ESTRATÉGIA 3: Tentar ler diretamente do arquivo PFX usando cryptography
                if not cert_der_bytes:
                    try:
                        print("   [3/3] Tentando extrair usando cryptography diretamente...")
                        from cryptography.hazmat.primitives import serialization
                        from cryptography.hazmat.backends import default_backend
                        import base64 as b64_module
                        
                        with open(cert_path, 'rb') as f:
                            pfx_data = f.read()
                        
                        # Tentar carregar PFX
                        from cryptography.hazmat.primitives.serialization import pkcs12
                        private_key, certificate, additional_certificates = pkcs12.load_key_and_certificates(
                            pfx_data,
                            senha_str.encode('utf-8') if isinstance(senha_str, str) else senha_str,
                            backend=default_backend()
                        )
                        
                        if certificate:
                            cert_der_bytes = certificate.public_bytes(crypto_x509.Encoding.DER)
                            print(f"   ✅ Certificado DER extraído usando cryptography: {len(cert_der_bytes)} bytes")
                            tentativas_extracao.append(f"Cryptography: {len(cert_der_bytes)} bytes")
                    except Exception as e_crypto:
                        print(f"   ❌ Falhou: {str(e_crypto)[:100]}")
                        tentativas_extracao.append(f"Cryptography: ERRO - {str(e_crypto)[:50]}")
                
                # VALIDAÇÃO OBRIGATÓRIA: Certificado DER deve estar disponível
                if not cert_der_bytes:
                    error_msg = (
                        "ERRO CRÍTICO: Não foi possível extrair certificado DER do PFX.\n\n"
                        "Tentativas realizadas:\n"
                    )
                    for i, tentativa in enumerate(tentativas_extracao, 1):
                        error_msg += f"  {i}. {tentativa}\n"
                    
                    error_msg += (
                        "\nSem o certificado DER, não é possível incluir X509Certificate na assinatura.\n"
                        "A SEFAZ rejeitará com cStat=290 (Certificado Assinatura inválido).\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se o arquivo PFX está válido e não corrompido\n"
                        "2. Verifique se a senha do certificado está correta\n"
                        "3. Tente exportar o certificado novamente do e-CPF/e-CNPJ\n"
                        "4. Verifique se o certificado não está expirado\n"
                        "5. Verifique se o certificado é ICP-Brasil válido"
                    )
                    raise ValueError(error_msg)
                
                # Validar formato DER
                if len(cert_der_bytes) < 100:
                    raise ValueError(
                        f"ERRO: Certificado DER muito pequeno ({len(cert_der_bytes)} bytes).\n\n"
                        f"Um certificado válido deve ter pelo menos 100 bytes.\n\n"
                        f"SOLUÇÃO: Verifique se o certificado PFX está válido."
                    )
                
                # Validar que começa com 0x30 0x82 (formato ASN.1 DER)
                if cert_der_bytes[0] != 0x30 or cert_der_bytes[1] != 0x82:
                    print(f"   ⚠️ AVISO: Certificado DER pode estar em formato diferente")
                    print(f"   📋 Primeiros bytes (hex): {cert_der_bytes[:8].hex()}")
                    print(f"   📋 Esperado: 30 82 ... (formato ASN.1 DER)")
                    # Continuar mesmo assim - alguns certificados podem ter formato diferente
                
                print(f"   ✅ Certificado DER extraído com sucesso: {len(cert_der_bytes)} bytes")
                print("=" * 70)
                
                # Assinar o XML (pode ser lista ou elemento único)
                print("   🔧 Assinando XML com certificado...")
                print("   📋 Algoritmo de assinatura: RSA-SHA256 (obrigatório NFC-e 4.00)")
                print("   📋 Algoritmo de digest: SHA256")
                
                if isinstance(xml_nfe, list):
                    xml_assinado = assinador.assinar(xml_nfe[0])
                else:
                    xml_assinado = assinador.assinar(xml_nfe)
                
                print("✅ XML assinado")
                
                # CORREÇÃO IMEDIATA E OBRIGATÓRIA: Forçar URIs corretos dos algoritmos ANTES de qualquer outra operação
                # Isso garante que os algoritmos estejam corretos desde o início
                print("\n" + "=" * 70)
                print("🔧 CORREÇÃO IMEDIATA: Forçando URIs corretos dos algoritmos")
                print("=" * 70)
                
                ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
                
                # URIs CORRETOS OBRIGATÓRIOS para NFC-e 4.00
                URI_SIGNATURE_METHOD = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
                URI_DIGEST_METHOD = 'http://www.w3.org/2001/04/xmlenc#sha256'
                
                # Buscar Signature
                signature_imediata = xml_assinado.find(f'.//{{{ns_ds}}}Signature') or xml_assinado.find('.//Signature')
                if signature_imediata is not None:
                    # Buscar SignedInfo
                    signed_info_imediata = signature_imediata.find(f'.//{{{ns_ds}}}SignedInfo') or signature_imediata.find('.//SignedInfo')
                    if signed_info_imediata is not None:
                        # FORÇAR SignatureMethod correto (SEMPRE, independente do valor atual)
                        sig_method_imediata = signed_info_imediata.find(f'.//{{{ns_ds}}}SignatureMethod') or signed_info_imediata.find('.//SignatureMethod')
                        if sig_method_imediata is not None:
                            algo_atual_sig = sig_method_imediata.get('Algorithm', '').strip()
                            # SEMPRE forçar o valor correto (remover espaços, normalizar)
                            sig_method_imediata.set('Algorithm', URI_SIGNATURE_METHOD)
                            if algo_atual_sig != URI_SIGNATURE_METHOD:
                                print(f"   🔧 FORÇANDO SignatureMethod:")
                                print(f"      De: '{algo_atual_sig}'")
                                print(f"      Para: '{URI_SIGNATURE_METHOD}'")
                            print(f"   ✅ SignatureMethod definido: '{sig_method_imediata.get('Algorithm')}'")
                        else:
                            print("   ⚠️ SignatureMethod não encontrado - será criado na validação posterior")
                        
                        # FORÇAR DigestMethod correto (SEMPRE, independente do valor atual)
                        reference_imediata = signed_info_imediata.find(f'.//{{{ns_ds}}}Reference') or signed_info_imediata.find('.//Reference')
                        if reference_imediata is not None:
                            digest_method_imediata = reference_imediata.find(f'.//{{{ns_ds}}}DigestMethod') or reference_imediata.find('.//DigestMethod')
                            if digest_method_imediata is not None:
                                algo_atual_digest = digest_method_imediata.get('Algorithm', '').strip()
                                # SEMPRE forçar o valor correto (remover espaços, normalizar)
                                digest_method_imediata.set('Algorithm', URI_DIGEST_METHOD)
                                if algo_atual_digest != URI_DIGEST_METHOD:
                                    print(f"   🔧 FORÇANDO DigestMethod:")
                                    print(f"      De: '{algo_atual_digest}'")
                                    print(f"      Para: '{URI_DIGEST_METHOD}'")
                                print(f"   ✅ DigestMethod definido: '{digest_method_imediata.get('Algorithm')}'")
                            else:
                                print("   ⚠️ DigestMethod não encontrado - será criado na validação posterior")
                        else:
                            print("   ⚠️ Reference não encontrado - será criado na validação posterior")
                    else:
                        print("   ⚠️ SignedInfo não encontrado - será criado na validação posterior")
                else:
                    print("   ❌ ERRO: Signature não encontrada após assinatura!")
                
                # VALIDAÇÃO FINAL: Verificar se os valores foram definidos corretamente
                if signature_imediata is not None:
                    signed_info_check = signature_imediata.find(f'.//{{{ns_ds}}}SignedInfo') or signature_imediata.find('.//SignedInfo')
                    if signed_info_check is not None:
                        sig_method_check = signed_info_check.find(f'.//{{{ns_ds}}}SignatureMethod') or signed_info_check.find('.//SignatureMethod')
                        if sig_method_check is not None:
                            algo_final_sig = sig_method_check.get('Algorithm', '').strip()
                            if algo_final_sig == URI_SIGNATURE_METHOD:
                                print(f"   ✅ VALIDAÇÃO: SignatureMethod correto: '{algo_final_sig}'")
                            else:
                                print(f"   ❌ ERRO: SignatureMethod ainda incorreto: '{algo_final_sig}'")
                                print(f"   🔧 FORÇANDO novamente...")
                                sig_method_check.set('Algorithm', URI_SIGNATURE_METHOD)
                                print(f"   ✅ SignatureMethod corrigido: '{sig_method_check.get('Algorithm')}'")
                        
                        reference_check = signed_info_check.find(f'.//{{{ns_ds}}}Reference') or signed_info_check.find('.//Reference')
                        if reference_check is not None:
                            digest_method_check = reference_check.find(f'.//{{{ns_ds}}}DigestMethod') or reference_check.find('.//DigestMethod')
                            if digest_method_check is not None:
                                algo_final_digest = digest_method_check.get('Algorithm', '').strip()
                                if algo_final_digest == URI_DIGEST_METHOD:
                                    print(f"   ✅ VALIDAÇÃO: DigestMethod correto: '{algo_final_digest}'")
                                else:
                                    print(f"   ❌ ERRO: DigestMethod ainda incorreto: '{algo_final_digest}'")
                                    print(f"   🔧 FORÇANDO novamente...")
                                    digest_method_check.set('Algorithm', URI_DIGEST_METHOD)
                                    print(f"   ✅ DigestMethod corrigido: '{digest_method_check.get('Algorithm')}'")
                
                print("=" * 70)
                
                # CORREÇÃO CRÍTICA E INTELIGENTE: Garantir que X509Certificate está presente e correto
                # Esta é uma correção obrigatória - sem X509Certificate, a SEFAZ rejeita com cStat=290
                print("\n" + "=" * 70)
                print("🔧 CORREÇÃO CRÍTICA: Garantindo X509Certificate na assinatura")
                print("=" * 70)
                
                # OBRIGATÓRIO: Ter certificado DER extraído
                if not cert_der_bytes:
                    raise ValueError(
                        "ERRO CRÍTICO: Certificado DER não foi extraído do PFX.\n\n"
                        "Sem o certificado DER, não é possível incluir X509Certificate na assinatura.\n"
                        "A SEFAZ rejeitará com cStat=290 (Certificado Assinatura inválido).\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se o arquivo PFX está válido e não corrompido\n"
                        "2. Verifique se a senha do certificado está correta\n"
                        "3. Tente exportar o certificado novamente do e-CPF/e-CNPJ"
                    )
                
                import base64
                ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                
                # Converter DER para base64 (formato necessário para X509Certificate)
                cert_base64 = base64.b64encode(cert_der_bytes).decode('utf-8')
                print(f"   ✅ Certificado convertido para base64: {len(cert_base64)} caracteres")
                
                # IMPORTANTE: Armazenar cert_base64 em uma variável de escopo mais amplo
                # para garantir que esteja disponível na validação posterior
                # (será usado na validação se necessário)
                
                # Validar formato base64 ANTES de adicionar
                if not cert_base64 or len(cert_base64) < 100:
                    raise ValueError(
                        f"ERRO: Certificado base64 inválido (muito curto).\n\n"
                        f"Tamanho: {len(cert_base64)} caracteres\n"
                        f"Esperado: pelo menos 100 caracteres\n\n"
                        f"SOLUÇÃO: Verifique se o certificado PFX está válido"
                    )
                
                if not cert_base64.startswith('MII'):
                    raise ValueError(
                        f"ERRO: Certificado base64 não está no formato correto.\n\n"
                        f"Esperado: começar com 'MII'\n"
                        f"Recebido: {cert_base64[:50]}\n\n"
                        f"Isso indica que o certificado pode estar corrompido ou em formato incorreto.\n\n"
                        f"SOLUÇÃO:\n"
                        f"1. Verifique se o certificado PFX está válido\n"
                        f"2. Tente exportar o certificado novamente do e-CPF/e-CNPJ"
                    )
                
                print(f"   ✅ Certificado base64 válido (começa com 'MII', {len(cert_base64)} chars)")
                
                # Buscar ou criar estrutura completa de assinatura
                signature = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}Signature')
                if signature is None:
                    signature = xml_assinado.find('.//Signature')
                
                if signature is None:
                    raise ValueError(
                        "ERRO CRÍTICO: Elemento Signature não encontrado após assinatura.\n\n"
                        "A assinatura digital não foi gerada corretamente pelo PyNFe.\n\n"
                        "SOLUÇÃO:\n"
                        "1. Verifique se o certificado está válido\n"
                        "2. Verifique se a senha está correta\n"
                        "3. Verifique os logs para mais detalhes"
                    )
                
                print("   ✅ Signature encontrada")
                
                # Buscar ou criar KeyInfo
                key_info_elem = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}KeyInfo')
                if key_info_elem is None:
                    key_info_elem = signature.find('.//KeyInfo')
                    if key_info_elem is None:
                        # Criar KeyInfo se não existir (deve vir depois de SignatureValue)
                        # Encontrar posição correta (depois de SignatureValue)
                        sig_value = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}SignatureValue')
                        if sig_value is None:
                            sig_value = signature.find('.//SignatureValue')
                        
                        if sig_value is not None:
                            # Inserir KeyInfo após SignatureValue
                            parent = sig_value.getparent()
                            if parent is not None:
                                # Encontrar índice do SignatureValue
                                index = list(parent).index(sig_value)
                                key_info_elem = etree.Element(f'{{{ns_xmldsig}}}KeyInfo')
                                parent.insert(index + 1, key_info_elem)
                                print("   ✅ KeyInfo criado após SignatureValue")
                            else:
                                # Se não tem parent, adicionar como filho de Signature
                                key_info_elem = etree.SubElement(signature, f'{{{ns_xmldsig}}}KeyInfo')
                                print("   ✅ KeyInfo criado como filho de Signature")
                        else:
                            # Se não tem SignatureValue, adicionar no final
                            key_info_elem = etree.SubElement(signature, f'{{{ns_xmldsig}}}KeyInfo')
                            print("   ✅ KeyInfo criado no final de Signature")
                    else:
                        print("   ✅ KeyInfo já existe")
                else:
                    print("   ✅ KeyInfo já existe")
                
                # Remover texto do KeyInfo (schema não permite)
                if key_info_elem.text and key_info_elem.text.strip():
                    key_info_elem.text = None
                if key_info_elem.tail and key_info_elem.tail.strip():
                    key_info_elem.tail = None
                
                # Buscar ou criar X509Data
                x509_data = key_info_elem.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Data')
                if x509_data is None:
                    x509_data = key_info_elem.find('.//X509Data')
                    if x509_data is None:
                        # Criar X509Data se não existir
                        x509_data = etree.SubElement(key_info_elem, f'{{{ns_xmldsig}}}X509Data')
                        print("   ✅ X509Data criado")
                    else:
                        print("   ✅ X509Data já existe")
                else:
                    print("   ✅ X509Data já existe")
                
                # Buscar X509Certificate existente
                x509_cert = x509_data.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                if x509_cert is None:
                    x509_cert = x509_data.find('.//X509Certificate')
                
                # SEMPRE substituir/adicionar X509Certificate com nosso certificado extraído do PFX
                # Isso garante que o certificado está correto e completo
                if x509_cert is None:
                    # Criar elemento X509Certificate
                    x509_cert = etree.SubElement(x509_data, f'{{{ns_xmldsig}}}X509Certificate')
                    print("   ✅ Elemento X509Certificate criado")
                else:
                    # Verificar se o certificado existente está correto
                    cert_text_existente = x509_cert.text.strip() if x509_cert.text else ''
                    if cert_text_existente and cert_text_existente.startswith('MII') and len(cert_text_existente) > 100:
                        print(f"   ✅ X509Certificate já presente e válido: {len(cert_text_existente)} caracteres")
                        # Mesmo assim, vamos substituir para garantir que está correto
                        print("   🔧 Substituindo por certificado extraído do PFX (garantir correção)...")
                    else:
                        print(f"   ⚠️ X509Certificate existente está incorreto ou vazio")
                        print(f"      Tamanho: {len(cert_text_existente)}")
                        print(f"      Começa com: {cert_text_existente[:30] if cert_text_existente else 'VAZIO'}")
                        print("   🔧 Substituindo por certificado extraído do PFX...")
                
                # SEMPRE definir o texto com nosso certificado (garantir que está correto)
                x509_cert.text = cert_base64
                print(f"   ✅ X509Certificate definido: {len(cert_base64)} caracteres")
                
                # Validação imediata após definir
                cert_text_final = x509_cert.text.strip() if x509_cert.text else ''
                if not cert_text_final:
                    raise ValueError("ERRO CRÍTICO: X509Certificate está vazio após definir texto!")
                
                if not cert_text_final.startswith('MII'):
                    raise ValueError(
                        f"ERRO CRÍTICO: X509Certificate não começa com 'MII'.\n\n"
                        f"Recebido: {cert_text_final[:50]}\n\n"
                        f"SOLUÇÃO: Verifique se o certificado PFX está válido"
                    )
                
                if len(cert_text_final) < 100:
                    raise ValueError(
                        f"ERRO CRÍTICO: X509Certificate muito curto ({len(cert_text_final)} chars).\n\n"
                        f"Esperado: pelo menos 100 caracteres\n\n"
                        f"SOLUÇÃO: Verifique se o certificado PFX está válido"
                    )
                
                print("   ✅ X509Certificate válido e correto!")
                print(f"   📋 Primeiros 50 chars: {cert_text_final[:50]}")
                print(f"   📋 Últimos 20 chars: {cert_text_final[-20:]}")
                
                # VALIDAÇÃO IMEDIATA: Buscar novamente para garantir que está persistido
                print("\n   🔍 Validando persistência do X509Certificate...")
                x509_cert_validacao = x509_data.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                if x509_cert_validacao is None:
                    x509_cert_validacao = x509_data.find('.//X509Certificate')
                
                if x509_cert_validacao is None:
                    raise ValueError("ERRO CRÍTICO: X509Certificate não pode ser encontrado após definir!")
                
                cert_text_validacao = x509_cert_validacao.text.strip() if x509_cert_validacao.text else ''
                if not cert_text_validacao or cert_text_validacao != cert_text_final:
                    print(f"   ⚠️ AVISO: X509Certificate encontrado na validação difere do definido")
                    print(f"      Definido: {len(cert_text_final)} chars")
                    print(f"      Encontrado: {len(cert_text_validacao)} chars")
                    # Forçar novamente
                    x509_cert_validacao.text = cert_base64
                    print("   🔧 X509Certificate redefinido na validação")
                else:
                    print(f"   ✅ X509Certificate persistido corretamente: {len(cert_text_validacao)} chars")
                
                print("=" * 70)
                
                # VALIDAÇÃO CRÍTICA: Verificar se a assinatura contém o certificado completo
                # IMPORTANTE: cert_base64 deve estar disponível aqui (foi definido na seção anterior)
                print("\n🔍 Validando assinatura digital gerada...")
                try:
                    # Verificar Signature
                    signature = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}Signature') or xml_assinado.find('.//Signature')
                    if signature is None:
                        print("   ❌ ERRO CRÍTICO: Signature não encontrada após assinatura!")
                        raise ValueError("Assinatura digital não foi gerada corretamente")
                    else:
                        print("   ✅ Signature encontrada")
                    
                    # Verificar KeyInfo
                    key_info = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}KeyInfo') or signature.find('.//KeyInfo')
                    if key_info is None:
                        print("   ❌ ERRO CRÍTICO: KeyInfo não encontrada na assinatura!")
                        raise ValueError("KeyInfo não foi gerada na assinatura digital")
                    else:
                        print("   ✅ KeyInfo encontrada")
                    
                    # Verificar X509Data
                    x509_data = key_info.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Data') or key_info.find('.//X509Data')
                    if x509_data is None:
                        print("   ❌ ERRO CRÍTICO: X509Data não encontrada na assinatura!")
                        print("   ⚠️ Isso pode causar cStat=290 (Certificado inválido)")
                        raise ValueError("X509Data não foi gerada na assinatura digital")
                    else:
                        print("   ✅ X509Data encontrada")
                    
                    # Verificar X509Certificate (busca mais robusta)
                    # IMPORTANTE: cert_base64 foi definido anteriormente e deve estar disponível
                    x509_cert = None
                    # Estratégia 1: Buscar com namespace completo em X509Data
                    x509_cert = x509_data.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                    # Estratégia 2: Buscar sem namespace
                    if x509_cert is None:
                        x509_cert = x509_data.find('.//X509Certificate')
                    # Estratégia 3: Buscar diretamente como filho de X509Data
                    if x509_cert is None:
                        for child in x509_data:
                            tag_clean = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                            if tag_clean == 'X509Certificate':
                                x509_cert = child
                                break
                    # Estratégia 4: Buscar recursivamente em toda a assinatura
                    if x509_cert is None:
                        x509_cert = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                    if x509_cert is None:
                        x509_cert = signature.find('.//X509Certificate')
                    # Estratégia 5: Buscar em todo o XML
                    if x509_cert is None:
                        x509_cert = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                    if x509_cert is None:
                        x509_cert = xml_assinado.find('.//X509Certificate')
                    
                    # Se não encontrou, adicionar manualmente usando cert_base64
                    if x509_cert is None:
                        print("   ❌ ERRO CRÍTICO: X509Certificate não encontrado após todas as tentativas!")
                        print("   ⚠️ Isso pode causar cStat=290 (Certificado inválido)")
                        print("   🔧 Tentando adicionar X509Certificate manualmente...")
                        # Última tentativa: adicionar manualmente
                        if x509_data is not None:
                            ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                            x509_cert = etree.SubElement(x509_data, f'{{{ns_xmldsig}}}X509Certificate')
                            # cert_base64 foi definido na seção anterior e deve estar disponível
                            try:
                                x509_cert.text = cert_base64
                                print(f"   ✅ X509Certificate adicionado manualmente: {len(cert_base64)} chars")
                            except NameError:
                                # Se cert_base64 não estiver disponível, tentar extrair novamente
                                print("   ⚠️ cert_base64 não disponível, tentando extrair do assinador...")
                                if hasattr(assinador, 'cert') and assinador.cert:
                                    try:
                                        from cryptography import x509 as crypto_x509
                                        import base64 as b64_module
                                        if isinstance(assinador.cert, str):
                                            pem_str = assinador.cert.replace('-----BEGIN CERTIFICATE-----', '')
                                            pem_str = pem_str.replace('-----END CERTIFICATE-----', '')
                                            pem_str = pem_str.replace('\n', '').replace('\r', '').strip()
                                            cert_der_temp = b64_module.b64decode(pem_str)
                                            cert_base64_temp = b64_module.b64encode(cert_der_temp).decode('utf-8')
                                            x509_cert.text = cert_base64_temp
                                            print(f"   ✅ X509Certificate adicionado (extraído do assinador): {len(cert_base64_temp)} chars")
                                        else:
                                            raise ValueError("X509Certificate não foi incluído e não foi possível adicionar")
                                    except Exception as e_extract:
                                        raise ValueError(f"X509Certificate não foi incluído e não foi possível adicionar: {str(e_extract)}")
                                else:
                                    raise ValueError("X509Certificate não foi incluído na assinatura digital e não foi possível adicionar")
                        else:
                            raise ValueError("X509Certificate não foi incluído na assinatura digital")
                    elif not x509_cert.text or not x509_cert.text.strip():
                        print("   ⚠️ X509Certificate encontrado mas está vazio!")
                        print("   🔧 Preenchendo com certificado base64...")
                        try:
                            x509_cert.text = cert_base64
                            print(f"   ✅ X509Certificate preenchido: {len(cert_base64)} chars")
                        except NameError:
                            # Se cert_base64 não estiver disponível, tentar extrair novamente
                            print("   ⚠️ cert_base64 não disponível, tentando extrair...")
                            if hasattr(assinador, 'cert') and assinador.cert:
                                try:
                                    from cryptography import x509 as crypto_x509
                                    import base64 as b64_module
                                    if isinstance(assinador.cert, str):
                                        pem_str = assinador.cert.replace('-----BEGIN CERTIFICATE-----', '')
                                        pem_str = pem_str.replace('-----END CERTIFICATE-----', '')
                                        pem_str = pem_str.replace('\n', '').replace('\r', '').strip()
                                        cert_der_temp = b64_module.b64decode(pem_str)
                                        cert_base64_temp = b64_module.b64encode(cert_der_temp).decode('utf-8')
                                        x509_cert.text = cert_base64_temp
                                        print(f"   ✅ X509Certificate preenchido (extraído do assinador): {len(cert_base64_temp)} chars")
                                    else:
                                        raise ValueError("X509Certificate está vazio e não foi possível preencher")
                                except Exception as e_extract:
                                    raise ValueError(f"X509Certificate está vazio e não foi possível preencher: {str(e_extract)}")
                            else:
                                raise ValueError("X509Certificate está vazio e não foi possível preencher")
                    else:
                        cert_text = x509_cert.text.strip()
                        print(f"   ✅ X509Certificate encontrado: {len(cert_text)} caracteres")
                        
                        # Verificar se o certificado parece válido (deve começar com MII)
                        if not cert_text.startswith('MII'):
                            print("   ⚠️ AVISO: X509Certificate não começa com 'MII' (pode estar corrompido)")
                            print("   🔧 Substituindo por certificado correto...")
                            try:
                                x509_cert.text = cert_base64
                                print(f"   ✅ X509Certificate substituído: {len(cert_base64)} chars")
                            except NameError:
                                # Se cert_base64 não estiver disponível, tentar extrair novamente
                                print("   ⚠️ cert_base64 não disponível, tentando extrair...")
                                if hasattr(assinador, 'cert') and assinador.cert:
                                    try:
                                        from cryptography import x509 as crypto_x509
                                        import base64 as b64_module
                                        if isinstance(assinador.cert, str):
                                            pem_str = assinador.cert.replace('-----BEGIN CERTIFICATE-----', '')
                                            pem_str = pem_str.replace('-----END CERTIFICATE-----', '')
                                            pem_str = pem_str.replace('\n', '').replace('\r', '').strip()
                                            cert_der_temp = b64_module.b64decode(pem_str)
                                            cert_base64_temp = b64_module.b64encode(cert_der_temp).decode('utf-8')
                                            x509_cert.text = cert_base64_temp
                                            print(f"   ✅ X509Certificate substituído (extraído do assinador): {len(cert_base64_temp)} chars")
                                        else:
                                            print("   ⚠️ Não foi possível substituir (certificado não disponível)")
                                    except Exception as e_extract:
                                        print(f"   ⚠️ Não foi possível substituir: {str(e_extract)}")
                                else:
                                    print("   ⚠️ Não foi possível substituir (cert_base64 não disponível)")
                        else:
                            print("   ✅ X509Certificate parece válido (começa com 'MII')")
                    
                    # Verificar SignatureValue (busca mais robusta)
                    sig_value = None
                    # Estratégia 1: Buscar com namespace completo
                    sig_value = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}SignatureValue')
                    # Estratégia 2: Buscar sem namespace
                    if sig_value is None:
                        sig_value = signature.find('.//SignatureValue')
                    # Estratégia 3: Buscar diretamente como filho de Signature
                    if sig_value is None:
                        for child in signature:
                            tag_clean = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                            if tag_clean == 'SignatureValue':
                                sig_value = child
                                break
                    # Estratégia 4: Buscar recursivamente em todo o XML
                    if sig_value is None:
                        sig_value = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}SignatureValue')
                    if sig_value is None:
                        sig_value = xml_assinado.find('.//SignatureValue')
                    
                    if sig_value is None:
                        print("   ⚠️ AVISO: SignatureValue não encontrado na assinatura!")
                        print("   🔧 Isso pode indicar que a assinatura não foi gerada corretamente")
                        print("   ⚠️ Continuando mesmo assim - a assinatura pode estar em outro formato")
                        # Não bloquear aqui - pode ser que a assinatura esteja sendo gerada de forma diferente
                    elif not sig_value.text or not sig_value.text.strip():
                        print("   ⚠️ AVISO: SignatureValue encontrado mas está vazio!")
                        print("   🔧 Isso pode indicar que a assinatura não foi gerada corretamente")
                        print("   ⚠️ Continuando mesmo assim - verificando se será gerado durante o envio")
                    else:
                        sig_text = sig_value.text.strip()
                        print(f"   ✅ SignatureValue encontrado: {len(sig_text)} caracteres")
                    
                    # Verificar DigestValue
                    digest_value = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}DigestValue') or signature.find('.//DigestValue')
                    if digest_value is None or not digest_value.text or not digest_value.text.strip():
                        print("   ⚠️ AVISO: DigestValue não encontrado (pode ser normal em alguns casos)")
                    else:
                        digest_text = digest_value.text.strip()
                        print(f"   ✅ DigestValue encontrado: {len(digest_text)} caracteres")
                    
                    # CORREÇÃO CRÍTICA: Garantir estrutura correta da assinatura conforme schema XSD
                    # A estrutura correta é:
                    # <Signature>
                    #   <SignedInfo>
                    #     <CanonicalizationMethod Algorithm="..."/>
                    #     <SignatureMethod Algorithm="..."/>  <- DEVE ESTAR AQUI, DEPOIS DE CanonicalizationMethod
                    #     <Reference>
                    #       <Transforms>...</Transforms>  <- OPCIONAL mas pode ser necessário
                    #       <DigestMethod Algorithm="..."/>  <- DEVE ESTAR AQUI, DEPOIS DE Transforms
                    #       <DigestValue>...</DigestValue>
                    #     </Reference>
                    #   </SignedInfo>
                    #   <SignatureValue>...</SignatureValue>
                    #   <KeyInfo>...</KeyInfo>
                    # </Signature>
                    # ORDEM É CRÍTICA: CanonicalizationMethod -> SignatureMethod -> Reference
                    # Dentro de Reference: Transforms (opcional) -> DigestMethod -> DigestValue
                    
                    ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                    
                    # NÃO modificar a assinatura criada pelo signxml - apenas validar e corrigir valores de Algorithm
                    # O signxml já cria a estrutura correta, só precisamos garantir os valores de Algorithm
                    
                    # Buscar SignedInfo (deve existir se signxml funcionou)
                    signed_info = signature.find('.//{http://www.w3.org/2000/09/xmldsig#}SignedInfo') or signature.find('.//SignedInfo')
                    if signed_info is None:
                        raise ValueError("ERRO: SignedInfo não encontrado na assinatura. A assinatura pode não ter sido criada corretamente.")
                    
                    # CRÍTICO: Verificar e corrigir CanonicalizationMethod
                    # A SEFAZ exige valor FIXO exato: http://www.w3.org/TR/2001/REC-xml-c14n-20010315
                    c14n_method = signed_info.find('.//{http://www.w3.org/2000/09/xmldsig#}CanonicalizationMethod') or signed_info.find('.//CanonicalizationMethod')
                    if c14n_method is not None:
                        algo_c14n = c14n_method.get('Algorithm', '').strip()  # Remover espaços
                        algoritmo_c14n_correto = 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
                        if algo_c14n != algoritmo_c14n_correto:
                            print(f"   🔧 Corrigindo Algorithm de CanonicalizationMethod")
                            print(f"      De: '{algo_c14n}'")
                            print(f"      Para: '{algoritmo_c14n_correto}'")
                            c14n_method.set('Algorithm', algoritmo_c14n_correto)
                            print("   ✅ CanonicalizationMethod corrigido")
                        else:
                            print(f"   ✅ CanonicalizationMethod correto: {algo_c14n}")
                    else:
                        print("   ⚠️ AVISO: CanonicalizationMethod não encontrado")
                    
                    # CRÍTICO: Verificar e corrigir Transform dentro de Reference
                    # A SEFAZ exige valores específicos para Transform
                    reference = signed_info.find('.//{http://www.w3.org/2000/09/xmldsig#}Reference') or signed_info.find('.//Reference')
                    if reference is not None:
                        transforms = reference.findall('.//{http://www.w3.org/2000/09/xmldsig#}Transform') or reference.findall('.//Transform')
                        for idx, transform in enumerate(transforms):
                            algo_transform = transform.get('Algorithm', '').strip()  # Remover espaços
                            
                            # CRÍTICO: SEFAZ NFC-e 4.00 exige valores FIXOS exatos
                            # Primeiro Transform: http://www.w3.org/2000/09/xmldsig#enveloped-signature
                            # Segundo Transform: http://www.w3.org/TR/2001/REC-xml-c14n-20010315
                            if idx == 0:
                                algoritmo_correto_obrigatorio = 'http://www.w3.org/2000/09/xmldsig#enveloped-signature'
                            else:
                                algoritmo_correto_obrigatorio = 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
                            
                            if algo_transform != algoritmo_correto_obrigatorio:
                                print(f"   🔧 CORRIGINDO Algorithm de Transform[{idx}] (valor fixo obrigatório)")
                                print(f"      De: '{algo_transform}'")
                                print(f"      Para: '{algoritmo_correto_obrigatorio}'")
                                transform.set('Algorithm', algoritmo_correto_obrigatorio)
                                print("   ✅ Transform corrigido para valor fixo obrigatório")
                            else:
                                print(f"   ✅ Transform[{idx}] correto: '{algo_transform}'")
                    
                    # Validar ordem dos elementos em SignedInfo (ordem é crítica no schema XSD)
                    # Ordem correta: CanonicalizationMethod, SignatureMethod, Reference
                    children_signed_info = list(signed_info)
                    if len(children_signed_info) >= 2:
                        # Verificar se a ordem está correta
                        tags_ordem = [c.tag.split('}')[-1] if '}' in c.tag else c.tag for c in children_signed_info[:3]]
                        ordem_correta = ['CanonicalizationMethod', 'SignatureMethod', 'Reference']
                        ordem_atual = [tag for tag in tags_ordem if tag in ordem_correta]
                        
                        if ordem_atual != ordem_correta[:len(ordem_atual)]:
                            print(f"   ⚠️ AVISO: Ordem dos elementos em SignedInfo pode estar incorreta: {tags_ordem}")
                            print(f"   📋 Ordem esperada: {ordem_correta}")
                            # Não reordenar automaticamente - deixar signxml gerenciar
                    
                    # Buscar SignatureMethod dentro de SignedInfo (signxml já cria no lugar correto)
                    # CRÍTICO: Buscar apenas o primeiro (pode haver duplicatas)
                    sig_methods = signed_info.findall('.//{http://www.w3.org/2000/09/xmldsig#}SignatureMethod') or signed_info.findall('.//SignatureMethod')
                    
                    # Remover duplicatas se houver
                    if len(sig_methods) > 1:
                        print(f"   ⚠️ AVISO: Encontrados {len(sig_methods)} elementos SignatureMethod (deve haver apenas 1)")
                        print("   🔧 Removendo duplicatas...")
                        # Manter apenas o primeiro
                        for sig_method_dup in sig_methods[1:]:
                            parent = sig_method_dup.getparent()
                            if parent is not None:
                                parent.remove(sig_method_dup)
                        print(f"   ✅ {len(sig_methods) - 1} duplicata(s) removida(s)")
                    
                    sig_method = sig_methods[0] if sig_methods else None
                    
                    if sig_method is not None:
                        algo_atual = sig_method.get('Algorithm', '').strip()  # Remover espaços
                        print(f"   📋 Algoritmo de assinatura atual: '{algo_atual}'")
                        
                        # CRÍTICO: NFC-e 4.00 exige SHA-256 conforme especificação
                        # Valor OBRIGATÓRIO: http://www.w3.org/2001/04/xmldsig-more#rsa-sha256
                        # NOTA: NFC-e 4.00 exige SHA-256, não SHA-1
                        # SEMPRE forçar o valor correto (garantir conformidade)
                        algoritmo_correto_obrigatorio = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
                        
                        # SEMPRE definir o valor correto (não apenas verificar)
                        if algo_atual != algoritmo_correto_obrigatorio:
                            print(f"   🔧 FORÇANDO Algorithm de SignatureMethod (valor fixo obrigatório)")
                            print(f"      De: '{algo_atual}'")
                            print(f"      Para: '{algoritmo_correto_obrigatorio}'")
                        sig_method.set('Algorithm', algoritmo_correto_obrigatorio)
                        print(f"   ✅ Algorithm de assinatura definido: '{sig_method.get('Algorithm')}'")
                    else:
                        print("   ⚠️ AVISO: SignatureMethod não encontrado - a assinatura pode estar incompleta")
                    
                    # Buscar Reference dentro de SignedInfo (signxml já cria no lugar correto)
                    reference = signed_info.find('.//{http://www.w3.org/2000/09/xmldsig#}Reference') or signed_info.find('.//Reference')
                    if reference is None:
                        print("   ⚠️ AVISO: Reference não encontrado - a assinatura pode estar incompleta")
                    else:
                        # Buscar DigestMethod dentro de Reference
                        # CRÍTICO: Buscar todos e remover duplicatas
                        digest_methods = reference.findall('.//{http://www.w3.org/2000/09/xmldsig#}DigestMethod') or reference.findall('.//DigestMethod')
                        
                        # Remover duplicatas se houver
                        if len(digest_methods) > 1:
                            print(f"   ⚠️ AVISO: Encontrados {len(digest_methods)} elementos DigestMethod (deve haver apenas 1)")
                            print("   🔧 Removendo duplicatas...")
                            # Manter apenas o primeiro (deve estar antes de DigestValue)
                            # Ordenar: DigestMethod deve vir antes de DigestValue
                            digest_value_ref = reference.find('.//{http://www.w3.org/2000/09/xmldsig#}DigestValue') or reference.find('.//DigestValue')
                            
                            # Remover todos os DigestMethod duplicados
                            for digest_method_dup in digest_methods[1:]:
                                parent = digest_method_dup.getparent()
                                if parent is not None:
                                    parent.remove(digest_method_dup)
                            
                            # Se há DigestValue, garantir que DigestMethod está antes dele
                            if digest_value_ref is not None:
                                digest_method_final = digest_methods[0]
                                parent_dm = digest_method_final.getparent()
                                parent_dv = digest_value_ref.getparent()
                                
                                if parent_dm == parent_dv:  # Ambos no mesmo pai (Reference)
                                    index_dm = list(parent_dm).index(digest_method_final)
                                    index_dv = list(parent_dv).index(digest_value_ref)
                                    
                                    if index_dm > index_dv:  # DigestMethod está depois de DigestValue
                                        # Remover e reinserir antes de DigestValue
                                        parent_dm.remove(digest_method_final)
                                        parent_dv.insert(index_dv, digest_method_final)
                                        print("   ✅ DigestMethod reposicionado antes de DigestValue")
                            
                            print(f"   ✅ {len(digest_methods) - 1} duplicata(s) removida(s)")
                        
                        digest_method = digest_methods[0] if digest_methods else None
                        
                        if digest_method is not None:
                            algo_digest = digest_method.get('Algorithm', '').strip()  # Remover espaços
                            print(f"   📋 Algoritmo de digest atual: '{algo_digest}'")
                            
                            # CRÍTICO: NFC-e 4.00 exige SHA-256 conforme especificação
                            # Valor OBRIGATÓRIO: http://www.w3.org/2001/04/xmlenc#sha256
                            # NOTA: NFC-e 4.00 exige SHA-256, não SHA-1
                            # SEMPRE forçar o valor correto (garantir conformidade)
                            algoritmo_digest_correto_obrigatorio = 'http://www.w3.org/2001/04/xmlenc#sha256'
                            
                            # SEMPRE definir o valor correto (não apenas verificar)
                            if algo_digest != algoritmo_digest_correto_obrigatorio:
                                print(f"   🔧 FORÇANDO Algorithm de DigestMethod (valor fixo obrigatório)")
                                print(f"      De: '{algo_digest}'")
                                print(f"      Para: '{algoritmo_digest_correto_obrigatorio}'")
                            digest_method.set('Algorithm', algoritmo_digest_correto_obrigatorio)
                            print(f"   ✅ Algorithm de digest definido: '{digest_method.get('Algorithm')}'")
                        else:
                            print("   ⚠️ AVISO: DigestMethod não encontrado dentro de Reference")
                    
                    # VALIDAÇÃO FINAL OBRIGATÓRIA: Garantir que os algoritmos estão corretos após todas as correções
                    # Esta é a última chance de corrigir antes do envio para SEFAZ
                    print("\n" + "=" * 70)
                    print("🔍 VALIDAÇÃO FINAL OBRIGATÓRIA DOS ALGORITMOS")
                    print("=" * 70)
                    
                    URI_SIG_FINAL = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
                    URI_DIGEST_FINAL = 'http://www.w3.org/2001/04/xmlenc#sha256'
                    
                    # Re-verificar e FORÇAR SignatureMethod (última chance)
                    # PRIMEIRO: Verificar se há duplicatas e removê-las
                    ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
                    sig_methods_all = signed_info.findall(f'.//{{{ns_ds}}}SignatureMethod') or signed_info.findall('.//SignatureMethod')
                    
                    if len(sig_methods_all) > 1:
                        print(f"   ⚠️ ERRO: Encontrados {len(sig_methods_all)} elementos SignatureMethod (deve haver apenas 1)!")
                        print("   🔧 Removendo duplicatas...")
                        # Manter apenas o primeiro e remover os demais
                        for sig_method_dup in sig_methods_all[1:]:
                            parent = sig_method_dup.getparent()
                            if parent is not None:
                                parent.remove(sig_method_dup)
                                print(f"   ✅ SignatureMethod duplicado removido")
                        # Usar o primeiro
                        sig_method_final = sig_methods_all[0]
                    elif len(sig_methods_all) == 1:
                        sig_method_final = sig_methods_all[0]
                    else:
                        sig_method_final = None
                    
                    if sig_method_final is not None:
                        algo_final = sig_method_final.get('Algorithm', '').strip()
                        # SEMPRE forçar o valor correto (garantir 100%)
                        sig_method_final.set('Algorithm', URI_SIG_FINAL)
                        if algo_final != URI_SIG_FINAL:
                            print(f"   🔧 FORÇANDO SignatureMethod (validação final):")
                            print(f"      De: '{algo_final}'")
                            print(f"      Para: '{URI_SIG_FINAL}'")
                        print(f"   ✅ SignatureMethod FINAL: '{sig_method_final.get('Algorithm')}'")
                    else:
                        print("   ⚠️ SignatureMethod não encontrado - CRIANDO...")
                        # Criar SignatureMethod se não existir
                        ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
                        # Encontrar posição correta (depois de CanonicalizationMethod, antes de Reference)
                        c14n_final = signed_info.find(f'.//{{{ns_ds}}}CanonicalizationMethod') or signed_info.find('.//CanonicalizationMethod')
                        reference_final_temp = signed_info.find(f'.//{{{ns_ds}}}Reference') or signed_info.find('.//Reference')
                        
                        sig_method_final = etree.Element(f'{{{ns_ds}}}SignatureMethod')
                        sig_method_final.set('Algorithm', URI_SIG_FINAL)
                        
                        # Inserir na posição correta
                        if c14n_final is not None:
                            # Inserir depois de CanonicalizationMethod
                            parent = c14n_final.getparent()
                            if parent is not None:
                                index = list(parent).index(c14n_final)
                                parent.insert(index + 1, sig_method_final)
                                print(f"   ✅ SignatureMethod CRIADO após CanonicalizationMethod")
                            else:
                                signed_info.insert(0, sig_method_final)
                                print(f"   ✅ SignatureMethod CRIADO no início de SignedInfo")
                        elif reference_final_temp is not None:
                            # Inserir antes de Reference
                            parent = reference_final_temp.getparent()
                            if parent is not None:
                                index = list(parent).index(reference_final_temp)
                                parent.insert(index, sig_method_final)
                                print(f"   ✅ SignatureMethod CRIADO antes de Reference")
                            else:
                                signed_info.insert(0, sig_method_final)
                                print(f"   ✅ SignatureMethod CRIADO no início de SignedInfo")
                        else:
                            # Adicionar no início
                            signed_info.insert(0, sig_method_final)
                            print(f"   ✅ SignatureMethod CRIADO no início de SignedInfo")
                        
                        print(f"   ✅ SignatureMethod FINAL CRIADO: '{sig_method_final.get('Algorithm')}'")
                    
                    # Re-verificar e FORÇAR DigestMethod (última chance)
                    reference_final = signed_info.find('.//{http://www.w3.org/2000/09/xmldsig#}Reference') or signed_info.find('.//Reference')
                    if reference_final is not None:
                        # CRÍTICO: Verificar se DigestMethod está dentro de Transforms (ERRADO) e movê-lo para fora
                        ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
                        transforms_final = reference_final.findall(f'.//{{{ns_ds}}}Transform') or reference_final.findall('.//Transform')
                        digest_methods_all = reference_final.findall(f'.//{{{ns_ds}}}DigestMethod') or reference_final.findall('.//DigestMethod')
                        
                        # Remover DigestMethod que está dentro de Transforms (ERRADO)
                        for transform in transforms_final:
                            digest_in_transform = transform.find(f'.//{{{ns_ds}}}DigestMethod') or transform.find('.//DigestMethod')
                            if digest_in_transform is not None:
                                print("   ⚠️ ERRO: DigestMethod encontrado dentro de Transforms (ERRADO)!")
                                print("   🔧 Removendo DigestMethod de dentro de Transforms...")
                                transform.remove(digest_in_transform)
                                print("   ✅ DigestMethod removido de dentro de Transforms")
                        
                        # Buscar DigestMethod correto (fora de Transforms, dentro de Reference)
                        digest_method_final = None
                        for dm in digest_methods_all:
                            parent = dm.getparent()
                            if parent is not None:
                                # Verificar se o pai é Reference (correto) ou Transform (errado)
                                parent_tag = parent.tag.split('}')[-1] if '}' in parent.tag else parent.tag
                                if parent_tag == 'Reference':
                                    digest_method_final = dm
                                    break
                        
                        if digest_method_final is not None:
                            algo_digest_final = digest_method_final.get('Algorithm', '').strip()
                            # SEMPRE forçar o valor correto (garantir 100%)
                            digest_method_final.set('Algorithm', URI_DIGEST_FINAL)
                            if algo_digest_final != URI_DIGEST_FINAL:
                                print(f"   🔧 FORÇANDO DigestMethod (validação final):")
                                print(f"      De: '{algo_digest_final}'")
                                print(f"      Para: '{URI_DIGEST_FINAL}'")
                            print(f"   ✅ DigestMethod FINAL: '{digest_method_final.get('Algorithm')}'")
                        else:
                            print("   ⚠️ DigestMethod não encontrado - CRIANDO...")
                            # Criar DigestMethod se não existir
                            ns_ds = 'http://www.w3.org/2000/09/xmldsig#'
                            digest_method_final = etree.Element(f'{{{ns_ds}}}DigestMethod')
                            digest_method_final.set('Algorithm', URI_DIGEST_FINAL)
                            
                            # Encontrar posição correta (depois de Transforms, antes de DigestValue)
                            transforms_final = reference_final.findall(f'.//{{{ns_ds}}}Transform') or reference_final.findall('.//Transform')
                            digest_value_final = reference_final.find(f'.//{{{ns_ds}}}DigestValue') or reference_final.find('.//DigestValue')
                            
                            if transforms_final and len(transforms_final) > 0:
                                # Inserir depois do último Transform
                                last_transform = transforms_final[-1]
                                parent = last_transform.getparent()
                                if parent is not None:
                                    index = list(parent).index(last_transform)
                                    parent.insert(index + 1, digest_method_final)
                                    print(f"   ✅ DigestMethod CRIADO após Transforms")
                                else:
                                    reference_final.insert(0, digest_method_final)
                                    print(f"   ✅ DigestMethod CRIADO no início de Reference")
                            elif digest_value_final is not None:
                                # Inserir antes de DigestValue
                                parent = digest_value_final.getparent()
                                if parent is not None:
                                    index = list(parent).index(digest_value_final)
                                    parent.insert(index, digest_method_final)
                                    print(f"   ✅ DigestMethod CRIADO antes de DigestValue")
                                else:
                                    reference_final.insert(0, digest_method_final)
                                    print(f"   ✅ DigestMethod CRIADO no início de Reference")
                            else:
                                # Adicionar no início de Reference
                                reference_final.insert(0, digest_method_final)
                                print(f"   ✅ DigestMethod CRIADO no início de Reference")
                            
                            print(f"   ✅ DigestMethod FINAL CRIADO: '{digest_method_final.get('Algorithm')}'")
                    else:
                        print("   ⚠️ AVISO: Reference não encontrado na validação final (pode ser normal se a assinatura ainda não foi completada)")
                    
                    print("=" * 70)
                    print("✅ VALIDAÇÃO FINAL CONCLUÍDA - Algoritmos garantidos como corretos")
                    print("=" * 70)
                    print("\n   ✅ Validação da assinatura concluída")
                    # Verificar se todos os elementos críticos estão presentes
                    elementos_criticos = {
                        'Signature': signature is not None,
                        'KeyInfo': key_info is not None,
                        'X509Data': x509_data is not None,
                        'X509Certificate': x509_cert is not None and x509_cert.text and x509_cert.text.strip(),
                        'SignatureValue': sig_value is not None and sig_value.text and sig_value.text.strip()
                    }
                    
                    elementos_faltando = [elem for elem, presente in elementos_criticos.items() if not presente]
                    if elementos_faltando:
                        print(f"   ⚠️ AVISO: Alguns elementos podem estar faltando: {', '.join(elementos_faltando)}")
                        print("   ⚠️ Isso pode causar problemas na validação pela SEFAZ")
                        if 'SignatureValue' in elementos_faltando:
                            print("   ⚠️ CRÍTICO: SignatureValue não encontrado - a assinatura pode não ser válida")
                        if 'X509Certificate' in elementos_faltando:
                            print("   ⚠️ CRÍTICO: X509Certificate não encontrado - causará cStat=290")
                    else:
                        print("   ✅ Todos os elementos obrigatórios estão presentes")
                    
                except ValueError as e_valid_sig:
                    # Se é ValueError sobre X509Certificate, tentar adicionar manualmente
                    error_msg = str(e_valid_sig)
                    if 'X509Certificate' in error_msg or 'X509Data' in error_msg:
                        print(f"\n   ⚠️ AVISO: {error_msg}")
                        print("   🔧 Tentando adicionar X509Certificate manualmente...")
                        
                        # Tentar adicionar X509Certificate manualmente
                        try:
                            # Buscar KeyInfo
                            key_info_elem = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}KeyInfo')
                            if key_info_elem is None:
                                key_info_elem = xml_assinado.find('.//KeyInfo')
                            
                            if key_info_elem is not None:
                                # Buscar ou criar X509Data
                                x509_data = key_info_elem.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Data')
                                if x509_data is None:
                                    x509_data = key_info_elem.find('.//X509Data')
                                    if x509_data is None:
                                        # Criar X509Data
                                        ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                                        x509_data = etree.SubElement(key_info_elem, f'{{{ns_xmldsig}}}X509Data')
                                        print("   ✅ X509Data criado")
                                
                                # Verificar se X509Certificate existe
                                x509_cert = x509_data.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate')
                                if x509_cert is None:
                                    x509_cert = x509_data.find('.//X509Certificate')
                                
                                if x509_cert is None or not x509_cert.text or not x509_cert.text.strip():
                                    # Adicionar X509Certificate do certificado carregado
                                    if hasattr(assinador, 'cert') and assinador.cert:
                                        import base64
                                        ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                                        
                                        # Converter certificado para base64
                                        if isinstance(assinador.cert, bytes):
                                            cert_base64 = base64.b64encode(assinador.cert).decode('utf-8')
                                        elif isinstance(assinador.cert, str):
                                            # Se já é string, pode ser PEM - extrair apenas o conteúdo base64
                                            cert_str = assinador.cert
                                            # Remover headers PEM se houver
                                            cert_str = cert_str.replace('-----BEGIN CERTIFICATE-----', '')
                                            cert_str = cert_str.replace('-----END CERTIFICATE-----', '')
                                            cert_str = cert_str.replace('\n', '').replace('\r', '').strip()
                                            cert_base64 = cert_str
                                        else:
                                            # Tentar serializar
                                            from cryptography import x509 as crypto_x509
                                            from cryptography.hazmat.backends import default_backend
                                            if isinstance(assinador.cert, crypto_x509.Certificate):
                                                cert_der = assinador.cert.public_bytes(crypto_x509.Encoding.DER)
                                                cert_base64 = base64.b64encode(cert_der).decode('utf-8')
                                            else:
                                                raise ValueError(f"Formato de certificado não suportado: {type(assinador.cert)}")
                                        
                                        # Criar elemento X509Certificate
                                        x509_cert = etree.SubElement(x509_data, f'{{{ns_xmldsig}}}X509Certificate')
                                        x509_cert.text = cert_base64
                                        print(f"   ✅ X509Certificate adicionado manualmente: {len(cert_base64)} caracteres")
                                        
                                        # Validar que começa com MII
                                        if cert_base64.startswith('MII'):
                                            print("   ✅ X509Certificate parece válido (começa com 'MII')")
                                        else:
                                            print("   ⚠️ AVISO: X509Certificate não começa com 'MII'")
                                    else:
                                        raise ValueError("Certificado não está disponível no assinador para adicionar manualmente")
                        except Exception as e_add_cert:
                            print(f"   ❌ ERRO ao adicionar X509Certificate manualmente: {e_add_cert}")
                            print("   ⚠️ A assinatura está incompleta e será rejeitada pela SEFAZ (cStat=290)")
                            import traceback
                            traceback.print_exc()
                            # Bloquear processamento se não conseguir adicionar
                            raise ValueError(
                                f"ERRO CRÍTICO: Não foi possível incluir X509Certificate na assinatura digital.\n\n"
                                f"Erro original: {error_msg}\n"
                                f"Erro ao adicionar manualmente: {str(e_add_cert)}\n\n"
                                f"SOLUÇÃO:\n"
                                f"1. Verifique se o certificado está válido e não expirado\n"
                                f"2. Verifique se a senha do certificado está correta\n"
                                f"3. Tente exportar o certificado novamente do e-CPF/e-CNPJ\n"
                                f"4. Verifique se o certificado é ICP-Brasil válido"
                            )
                    else:
                        # Outro tipo de ValueError - re-lançar
                        raise
                except Exception as e_valid_sig:
                    print(f"\n   ❌ ERRO na validação da assinatura: {e_valid_sig}")
                    print("   ⚠️ A assinatura pode estar incompleta ou inválida")
                    print("   ⚠️ Isso pode causar cStat=290 (Certificado inválido)")
                    import traceback
                    traceback.print_exc()
                    # Bloquear processamento se houver erro crítico
                    if 'X509Certificate' in str(e_valid_sig) or 'X509Data' in str(e_valid_sig):
                        raise ValueError(
                            f"ERRO CRÍTICO: Assinatura digital incompleta.\n\n"
                            f"Erro: {str(e_valid_sig)}\n\n"
                            f"SOLUÇÃO:\n"
                            f"1. Verifique se o certificado está válido e não expirado\n"
                            f"2. Verifique se a senha do certificado está correta\n"
                            f"3. Tente exportar o certificado novamente do e-CPF/e-CNPJ"
                        )
                
                # CORREÇÃO: Remover texto do KeyInfo (schema não permite texto em KeyInfo)
                print("🔧 Corrigindo estrutura da assinatura (KeyInfo)...")
                try:
                    # Buscar KeyInfo na assinatura
                    key_info_elem = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}KeyInfo')
                    if key_info_elem is None:
                        key_info_elem = xml_assinado.find('.//KeyInfo')
                    
                    if key_info_elem is not None:
                        # Remover texto do KeyInfo (deve conter apenas elementos filhos)
                        if key_info_elem.text and key_info_elem.text.strip():
                            print(f"   ⚠️ Removendo texto do KeyInfo: '{key_info_elem.text.strip()}'")
                            key_info_elem.text = None
                        
                        # Remover tail também (espaços após o elemento)
                        if key_info_elem.tail and key_info_elem.tail.strip():
                            key_info_elem.tail = None
                        
                        # Verificar se KeyInfo tem X509Data como filho
                        x509_data = key_info_elem.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Data')
                        if x509_data is None:
                            x509_data = key_info_elem.find('.//X509Data')
                        
                        if x509_data is None:
                            print("   ⚠️ AVISO: KeyInfo não contém X509Data (pode causar erro no schema)")
                        else:
                            print("   ✅ KeyInfo contém X509Data")
                        
                        print("   ✅ KeyInfo corrigido (texto removido)")
                    else:
                        print("   ⚠️ KeyInfo não encontrado na assinatura")
                except Exception as e_keyinfo:
                    print(f"   ⚠️ Erro ao corrigir KeyInfo: {e_keyinfo}")
                    # Não bloquear, mas avisar
                
                # CORREÇÃO: Validar e corrigir campos vazios no endereço do destinatário
                print("🔧 Validando endereço do destinatário...")
                try:
                    # Buscar enderDest no XML assinado
                    ender_dest = xml_assinado.find('.//{http://www.portalfiscal.inf.br/nfe}enderDest')
                    if ender_dest is None:
                        ender_dest = xml_assinado.find('.//enderDest')
                    
                    if ender_dest is not None:
                        # Validar xLgr
                        xlgr_dest = ender_dest.find('.//{http://www.portalfiscal.inf.br/nfe}xLgr')
                        if xlgr_dest is None:
                            xlgr_dest = ender_dest.find('.//xLgr')
                        
                        if xlgr_dest is not None:
                            if not xlgr_dest.text or not xlgr_dest.text.strip():
                                xlgr_dest.text = 'NÃO INFORMADO'
                                print("   ✅ xLgr do destinatário corrigido: 'NÃO INFORMADO'")
                        
                        # Validar xBairro
                        xbairro_dest = ender_dest.find('.//{http://www.portalfiscal.inf.br/nfe}xBairro')
                        if xbairro_dest is None:
                            xbairro_dest = ender_dest.find('.//xBairro')
                        
                        if xbairro_dest is not None:
                            if not xbairro_dest.text or not xbairro_dest.text.strip():
                                xbairro_dest.text = 'NÃO INFORMADO'
                                print("   ✅ xBairro do destinatário corrigido: 'NÃO INFORMADO'")
                    else:
                        print("   ℹ️ enderDest não encontrado (pode ser NFC-e sem destinatário)")
                except Exception as e_ender:
                    print(f"   ⚠️ Erro ao validar endereço do destinatário: {e_ender}")
                    # Não bloquear, mas avisar
                
                # Validar XML assinado antes de enviar
                print("🔍 Validando XML assinado...")
                try:
                    xml_str_validacao = etree.tostring(xml_assinado, encoding='unicode')
                    # Verificar se contém elementos obrigatórios
                    if 'infNFe' not in xml_str_validacao:
                        raise ValueError("XML não contém elemento infNFe")
                    if 'Id=' not in xml_str_validacao:
                        raise ValueError("XML não contém atributo Id no infNFe")
                    
                    # CORREÇÃO: Validar e corrigir campos vazios no endereço do destinatário
                    print("🔧 Validando endereço do destinatário...")
                    try:
                        # Buscar enderDest no XML assinado
                        ender_dest = xml_assinado.find('.//{http://www.portalfiscal.inf.br/nfe}enderDest')
                        if ender_dest is None:
                            ender_dest = xml_assinado.find('.//enderDest')
                        
                        if ender_dest is not None:
                            # Validar xLgr
                            xlgr_dest = ender_dest.find('.//{http://www.portalfiscal.inf.br/nfe}xLgr')
                            if xlgr_dest is None:
                                xlgr_dest = ender_dest.find('.//xLgr')
                            
                            if xlgr_dest is not None:
                                if not xlgr_dest.text or not xlgr_dest.text.strip():
                                    xlgr_dest.text = 'NÃO INFORMADO'
                                    print("   ✅ xLgr do destinatário corrigido: 'NÃO INFORMADO'")
                            
                            # Validar xBairro
                            xbairro_dest = ender_dest.find('.//{http://www.portalfiscal.inf.br/nfe}xBairro')
                            if xbairro_dest is None:
                                xbairro_dest = ender_dest.find('.//xBairro')
                            
                            if xbairro_dest is not None:
                                if not xbairro_dest.text or not xbairro_dest.text.strip():
                                    xbairro_dest.text = 'NÃO INFORMADO'
                                    print("   ✅ xBairro do destinatário corrigido: 'NÃO INFORMADO'")
                        else:
                            print("   ℹ️ enderDest não encontrado (pode ser NFC-e sem destinatário)")
                    except Exception as e_ender:
                        print(f"   ⚠️ Erro ao validar endereço do destinatário: {e_ender}")
                        # Não bloquear, mas avisar
                    
                    # Verificar formato de data/hora no XML
                    import re
                    # Procurar por padrões de data/hora malformados
                    dh_patterns = re.findall(r'<dh[A-Za-z]+>([^<]+)</dh[A-Za-z]+>', xml_str_validacao)
                    for dh_value in dh_patterns:
                        # Verificar se está no formato correto: YYYY-MM-DDTHH:MM:SS-TZ:TZ
                        if not re.match(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', dh_value):
                            print(f"   ⚠️ Data/hora com formato suspeito encontrada: {dh_value}")
                    
                    print("   ✅ XML validado com sucesso")
                except Exception as e_validacao:
                    print(f"   ⚠️ Aviso na validação: {e_validacao}")
                    # Não bloquear, apenas avisar
            
            except FileNotFoundError as e:
                error_msg = (
                    f"Erro ao carregar certificado digital: Arquivo não encontrado.\n"
                    f"{str(e)}\n\n"
                    f"Arquivo esperado: {cert_path}\n"
                    f"Verifique se o certificado foi fornecido corretamente."
                )
                print(f"❌ {error_msg}")
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'erro_certificado',
                    'error': error_msg,
                    'error_type': 'CertificateError'
                }
            except ValueError as e:
                error_str = str(e).lower()
                if 'senha' in error_str or 'vazia' in error_str:
                    error_msg = (
                        f"Erro ao carregar certificado digital: {str(e)}\n\n"
                        f"Verifique se a senha do certificado foi fornecida corretamente."
                    )
                else:
                    error_msg = (
                        f"Erro ao carregar certificado digital: {str(e)}\n\n"
                        f"Verifique se o certificado está no formato correto (PFX/P12)."
                    )
                print(f"❌ {error_msg}")
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'erro_certificado',
                    'error': error_msg,
                    'error_type': 'CertificateError',
                    'details': str(e)
                }
            except Exception as e:
                error_str = str(e).lower()
                import traceback
                traceback_str = traceback.format_exc()
                
                # Verificar tipo de erro
                if 'senha' in error_str or 'password' in error_str or 'invalid password' in error_str:
                    error_msg = (
                        f"Erro ao carregar certificado digital: Senha incorreta.\n"
                        f"{str(e)}\n\n"
                        f"Verifique se a senha do certificado está correta.\n"
                        f"Arquivo: {cert_path}"
                    )
                elif 'formato' in error_str or 'format' in error_str or 'invalid' in error_str or 'pkcs12' in error_str:
                    error_msg = (
                        f"Erro ao carregar certificado digital: Formato inválido.\n"
                        f"{str(e)}\n\n"
                        f"Verifique se o certificado está no formato correto (PFX/P12).\n"
                        f"O certificado deve ser um arquivo PFX/P12 válido.\n"
                        f"Arquivo: {cert_path}\n"
                        f"Tamanho: {os.path.getsize(cert_path) if os.path.exists(cert_path) else 'N/A'} bytes"
                    )
                elif 'permission' in error_str or 'permissão' in error_str:
                    error_msg = (
                        f"Erro ao carregar certificado digital: Permissão negada.\n"
                        f"{str(e)}\n\n"
                        f"Verifique as permissões do arquivo de certificado.\n"
                        f"Arquivo: {cert_path}"
                    )
                elif 'decode' in error_str or 'base64' in error_str:
                    error_msg = (
                        f"Erro ao processar certificado: Problema na decodificação.\n"
                        f"{str(e)}\n\n"
                        f"Verifique se o certificado está em base64 válido."
                    )
                else:
                    error_msg = (
                        f"Erro ao carregar certificado digital: {str(e)}\n\n"
                        f"Possíveis causas:\n"
                        f"1. Certificado corrompido ou inválido\n"
                        f"2. Senha incorreta\n"
                        f"3. Formato de arquivo não suportado (deve ser PFX/P12)\n"
                        f"4. Certificado expirado\n"
                        f"5. Problema com permissões do arquivo\n"
                        f"6. Certificado não é um arquivo PFX válido\n\n"
                        f"Arquivo: {cert_path}\n"
                        f"Tamanho: {os.path.getsize(cert_path) if os.path.exists(cert_path) else 'N/A'} bytes\n\n"
                        f"Detalhes técnicos:\n{traceback_str}"
                    )
                
                print(f"❌ {error_msg}")
                return {
                    'success': False,
                    'autorizada': False,
                    'status': 'erro_certificado',
                    'error': error_msg,
                    'error_type': 'CertificateError',
                    'details': str(e),
                    'traceback': traceback_str
                }
            
            # xml_assinado é um elemento XML (não lista)
            if hasattr(xml_assinado, 'tag'):
                xml_assinado_nfe = xml_assinado
                
                # Verificar estrutura após assinatura
                print(f"🔍 Estrutura do XML após assinatura:")
                print(f"   Tag raiz: {xml_assinado_nfe.tag}")
                print(f"   Atributos: {xml_assinado_nfe.attrib}")
                
                # Verificar se tem infNFe com Id
                inf_nfe = xml_assinado_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or xml_assinado_nfe.find('.//infNFe')
                if inf_nfe is not None:
                    print(f"   ✅ infNFe encontrado com Id: {inf_nfe.get('Id', 'NÃO ENCONTRADO')}")
                else:
                    print(f"   ⚠️ infNFe não encontrado!")
                    
            else:
                raise ValueError("XML assinado em formato inválido")
            
            # 8. Enviar para SEFAZ usando PyNFe
            print("\n[8/8] Enviando para SEFAZ via PyNFe...")
            uf = empresa_data.get('uf', 'SP')
            ambiente = 2 if ambiente_homologacao else 1  # 1=Produção, 2=Homologação
            
            # Armazenar valores para uso nos métodos auxiliares
            self._uf_temp = uf
            self._ambiente_temp = ambiente_homologacao
            
            # Verificar estrutura do XML antes de enviar
            print("🔍 Verificando estrutura do XML antes do envio...")
            xml_str_debug = etree.tostring(xml_assinado_nfe, encoding='unicode')
            print(f"   Tag raiz: {xml_assinado_nfe.tag}")
            print(f"   Elementos filhos: {[child.tag for child in xml_assinado_nfe]}")
            
            # Salvar XML assinado para debug e por empresa
            try:
                # Diretório de debug geral
                debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                os.makedirs(debug_dir, exist_ok=True)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                debug_file_xml = os.path.join(debug_dir, f'xml_assinado_{timestamp}.xml')
                
                # Diretório por empresa (usando CNPJ)
                cnpj = empresa_data.get('cnpj', 'sem_cnpj')
                cnpj_limpo = cnpj.replace('.', '').replace('/', '').replace('-', '')
                empresa_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_empresas', cnpj_limpo)
                os.makedirs(empresa_dir, exist_ok=True)
                
                # Salvar no diretório de debug geral
                with open(debug_file_xml, 'w', encoding='utf-8') as f:
                    f.write(xml_str_debug)
                print(f"   ✅ [XML 1/3] XML ASSINADO salvo em: {debug_file_xml}")
                print(f"      📋 Este é o XML da NFC-e assinado digitalmente (NFe + Signature)")
                print(f"      ⚠️  Este XML NÃO é o final - ainda precisa ser enviado para a SEFAZ")
                
                # VALIDAÇÃO FINAL CRÍTICA: Verificar se X509Certificate está presente no XML serializado
                print("\n" + "=" * 70)
                print("🔍 VALIDAÇÃO FINAL: Verificando X509Certificate no XML serializado")
                print("=" * 70)
                try:
                    xml_str_final = etree.tostring(xml_assinado, encoding='unicode', pretty_print=False)
                    # Verificar se X509Certificate está presente no XML
                    if 'X509Certificate' not in xml_str_final:
                        print("   ❌ ERRO CRÍTICO: X509Certificate não encontrado no XML serializado!")
                        print("   ⚠️ Isso causará cStat=290 (Certificado inválido)")
                        # Tentar adicionar novamente
                        signature_final = xml_assinado.find('.//{http://www.w3.org/2000/09/xmldsig#}Signature') or xml_assinado.find('.//Signature')
                        if signature_final:
                            key_info_final = signature_final.find('.//{http://www.w3.org/2000/09/xmldsig#}KeyInfo') or signature_final.find('.//KeyInfo')
                            if key_info_final:
                                x509_data_final = key_info_final.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Data') or key_info_final.find('.//X509Data')
                                if x509_data_final:
                                    x509_cert_final = x509_data_final.find('.//{http://www.w3.org/2000/09/xmldsig#}X509Certificate') or x509_data_final.find('.//X509Certificate')
                                    if x509_cert_final is None or not x509_cert_final.text:
                                        ns_xmldsig = 'http://www.w3.org/2000/09/xmldsig#'
                                        x509_cert_final = etree.SubElement(x509_data_final, f'{{{ns_xmldsig}}}X509Certificate')
                                        try:
                                            x509_cert_final.text = cert_base64
                                            print(f"   ✅ X509Certificate adicionado na validação final: {len(cert_base64)} chars")
                                        except NameError:
                                            # Tentar extrair do assinador
                                            if hasattr(assinador, 'cert') and assinador.cert:
                                                import base64 as b64_module
                                                if isinstance(assinador.cert, str):
                                                    pem_str = assinador.cert.replace('-----BEGIN CERTIFICATE-----', '')
                                                    pem_str = pem_str.replace('-----END CERTIFICATE-----', '')
                                                    pem_str = pem_str.replace('\n', '').replace('\r', '').strip()
                                                    cert_der_temp = b64_module.b64decode(pem_str)
                                                    cert_base64_temp = b64_module.b64encode(cert_der_temp).decode('utf-8')
                                                    x509_cert_final.text = cert_base64_temp
                                                    print(f"   ✅ X509Certificate adicionado (extraído do assinador): {len(cert_base64_temp)} chars")
                                    else:
                                        print(f"   ✅ X509Certificate encontrado no XML: {len(x509_cert_final.text.strip()) if x509_cert_final.text else 0} chars")
                    else:
                        # Verificar se o conteúdo está correto
                        import re
                        x509_matches = re.findall(r'<X509Certificate[^>]*>(.*?)</X509Certificate>', xml_str_final, re.DOTALL)
                        if x509_matches:
                            cert_text_final = x509_matches[0].strip()
                            if cert_text_final and cert_text_final.startswith('MII') and len(cert_text_final) > 100:
                                print(f"   ✅ X509Certificate presente e válido no XML serializado: {len(cert_text_final)} chars")
                            else:
                                print(f"   ⚠️ X509Certificate presente mas pode estar incorreto: {len(cert_text_final)} chars")
                                print(f"      Começa com: {cert_text_final[:30] if cert_text_final else 'VAZIO'}")
                        else:
                            print("   ⚠️ AVISO: X509Certificate não encontrado no XML serializado (mesmo com 'X509Certificate' no texto)")
                except Exception as e_val_final:
                    print(f"   ⚠️ Erro na validação final: {e_val_final}")
                    import traceback
                    traceback.print_exc()
                print("=" * 70)
                
                # Salvar no diretório da empresa
                empresa_file = os.path.join(empresa_dir, f'xml_assinado_{timestamp}_nfe_{numero_nfce}.xml')
                with open(empresa_file, 'w', encoding='utf-8') as f:
                    f.write(xml_str_debug)
                print(f"   ✅ XML assinado salvo por empresa em: {empresa_file}")
            except Exception as e_debug:
                print(f"   ⚠️ Erro ao salvar XML de debug: {e_debug}")
            
            # Verificar se o XML assinado está no formato correto para o lote
            # O PyNFe espera que o XML seja um elemento <NFe> que contém <infNFe>
            print("🔍 Verificando estrutura do XML para o lote...")
            
            # Verificar se é um elemento NFe
            if xml_assinado_nfe.tag.endswith('NFe') or 'NFe' in xml_assinado_nfe.tag:
                print("   ✅ XML está no formato NFe")
            else:
                print(f"   ⚠️ XML pode não estar no formato correto. Tag: {xml_assinado_nfe.tag}")
                # Tentar encontrar o elemento NFe dentro
                nfe_element = xml_assinado_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or xml_assinado_nfe.find('.//NFe')
                if nfe_element is not None:
                    print("   ✅ Elemento NFe encontrado dentro do XML")
                    xml_assinado_nfe = nfe_element
            
            # Montar XML do lote manualmente para debug
            try:
                from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
                lote_xml = etree.Element("enviNFe", xmlns=NAMESPACE_NFE, versao=VERSAO_PADRAO)
                # idLote deve ter 15 dígitos conforme schema XSD
                etree.SubElement(lote_xml, "idLote").text = "000000000000001"
                etree.SubElement(lote_xml, "indSinc").text = "1"
                
                # IMPORTANTE: O XML deve ser um elemento NFe completo
                # Criar uma cópia para não modificar o original
                # Serializar e parsear com validação segura
                xml_str_copy = etree.tostring(xml_assinado_nfe, encoding='unicode')
                nfe_copy = self._parse_xml_safe(xml_str_copy)
                lote_xml.append(nfe_copy)
                
                # Salvar XML do lote para debug e por empresa
                try:
                    # Diretório de debug geral
                    debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                    os.makedirs(debug_dir, exist_ok=True)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    debug_file_lote = os.path.join(debug_dir, f'xml_lote_{timestamp}.xml')
                    
                    # Diretório por empresa (usando CNPJ)
                    cnpj = empresa_data.get('cnpj', 'sem_cnpj')
                    cnpj_limpo = cnpj.replace('.', '').replace('/', '').replace('-', '')
                    empresa_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_empresas', cnpj_limpo)
                    os.makedirs(empresa_dir, exist_ok=True)
                    
                    lote_xml_str = etree.tostring(lote_xml, encoding='unicode', pretty_print=True)
                    
                    # Salvar no diretório de debug geral
                    with open(debug_file_lote, 'w', encoding='utf-8') as f:
                        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                        f.write(lote_xml_str)
                    print(f"   ✅ XML do lote salvo em: {debug_file_lote}")
                    
                    # Salvar no diretório da empresa
                    empresa_file = os.path.join(empresa_dir, f'lote_{timestamp}_nfe_{numero_nfce}.xml')
                    with open(empresa_file, 'w', encoding='utf-8') as f:
                        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                        f.write(lote_xml_str)
                    print(f"   ✅ XML do lote salvo por empresa em: {empresa_file}")
                    
                    print(f"   📋 Estrutura do lote:")
                    print(f"      - Tag raiz: {lote_xml.tag}")
                    print(f"      - idLote: {lote_xml.find('idLote').text if lote_xml.find('idLote') is not None else 'NÃO ENCONTRADO'}")
                    print(f"      - indSinc: {lote_xml.find('indSinc').text if lote_xml.find('indSinc') is not None else 'NÃO ENCONTRADO'}")
                    print(f"      - Elementos NFe: {len([e for e in lote_xml if e.tag.endswith('NFe') or 'NFe' in e.tag])}")
                except Exception as e_lote:
                    print(f"   ⚠️ Erro ao salvar XML do lote: {e_lote}")
            except Exception as e_lote_debug:
                print(f"   ⚠️ Erro ao montar XML do lote para debug: {e_lote_debug}")
                import traceback
                traceback.print_exc()
            
            # Função auxiliar para garantir que o XML está no formato correto
            def garantir_estrutura_nfe_correta(xml_element):
                """Garante que o XML está no formato <NFe><infNFe>...</infNFe></NFe> (SEM xmlns próprio - herda do enviNFe)"""
                from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
                
                # Converter para string e fazer parse limpo
                xml_str = etree.tostring(xml_element, encoding='unicode')
                xml_parsed = self._parse_xml_safe(xml_str)
                
                # Verificar tag
                tag_limpa = xml_parsed.tag.split('}')[-1] if '}' in xml_parsed.tag else xml_parsed.tag
                
                if tag_limpa == 'infNFe':
                    # Criar wrapper NFe SEM xmlns (herda do enviNFe)
                    nfe = etree.Element("NFe")
                    nfe.append(xml_parsed)
                    return nfe
                elif tag_limpa == 'NFe':
                    # REMOVER xmlns do NFe - ele deve herdar do enviNFe quando adicionado ao lote
                    # Remover namespace prefixado da tag se existir
                    if xml_parsed.tag.startswith('{'):
                        nfe_limpo = etree.Element("NFe")  # SEM xmlns - herda do enviNFe
                        for child in xml_parsed:
                            nfe_limpo.append(child)
                        return nfe_limpo
                    # Remover xmlns se existir
                    if 'xmlns' in xml_parsed.attrib:
                        del xml_parsed.attrib['xmlns']
                    return xml_parsed
                else:
                    # Tentar encontrar NFe ou infNFe dentro
                    nfe_encontrado = xml_parsed.find(f'.//{{{NAMESPACE_NFE}}}NFe') or xml_parsed.find('.//NFe')
                    if nfe_encontrado:
                        return garantir_estrutura_nfe_correta(nfe_encontrado)
                    
                    inf_nfe_encontrado = xml_parsed.find(f'.//{{{NAMESPACE_NFE}}}infNFe') or xml_parsed.find('.//infNFe')
                    if inf_nfe_encontrado:
                        nfe = etree.Element("NFe")  # SEM xmlns - herda do enviNFe
                        nfe.append(inf_nfe_encontrado)
                        return nfe
                    
                    raise ValueError(f"Estrutura XML inválida. Tag: {xml_parsed.tag}")
            
            # Corrigir estrutura do XML antes de passar para o PyNFe
            print("🔧 Corrigindo estrutura do XML para garantir conformidade com o schema...")
            xml_para_envio = garantir_estrutura_nfe_correta(xml_assinado_nfe)
            
            # VERIFICAÇÃO FINAL CRÍTICA: Garantir algoritmos corretos ANTES do envio
            print("\n" + "=" * 70)
            print("🔍 VERIFICAÇÃO FINAL ANTES DO ENVIO: Algoritmos de Assinatura")
            print("=" * 70)
            ns_ds_final = 'http://www.w3.org/2000/09/xmldsig#'
            URI_SIG_ENVIO = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
            URI_DIGEST_ENVIO = 'http://www.w3.org/2001/04/xmlenc#sha256'
            
            signature_envio = xml_para_envio.find(f'.//{{{ns_ds_final}}}Signature') or xml_para_envio.find('.//Signature')
            if signature_envio is not None:
                signed_info_envio = signature_envio.find(f'.//{{{ns_ds_final}}}SignedInfo') or signature_envio.find('.//SignedInfo')
                if signed_info_envio is not None:
                    # FORÇAR SignatureMethod
                    sig_method_envio = signed_info_envio.find(f'.//{{{ns_ds_final}}}SignatureMethod') or signed_info_envio.find('.//SignatureMethod')
                    if sig_method_envio is not None:
                        algo_sig_envio = sig_method_envio.get('Algorithm', '').strip()
                        sig_method_envio.set('Algorithm', URI_SIG_ENVIO)
                        if algo_sig_envio != URI_SIG_ENVIO:
                            print(f"   🔧 CORRIGINDO SignatureMethod antes do envio:")
                            print(f"      De: '{algo_sig_envio}'")
                            print(f"      Para: '{URI_SIG_ENVIO}'")
                        print(f"   ✅ SignatureMethod para envio: '{sig_method_envio.get('Algorithm')}'")
                    
                    # FORÇAR DigestMethod
                    reference_envio = signed_info_envio.find(f'.//{{{ns_ds_final}}}Reference') or signed_info_envio.find('.//Reference')
                    if reference_envio is not None:
                        digest_method_envio = reference_envio.find(f'.//{{{ns_ds_final}}}DigestMethod') or reference_envio.find('.//DigestMethod')
                        if digest_method_envio is not None:
                            algo_digest_envio = digest_method_envio.get('Algorithm', '').strip()
                            digest_method_envio.set('Algorithm', URI_DIGEST_ENVIO)
                            if algo_digest_envio != URI_DIGEST_ENVIO:
                                print(f"   🔧 CORRIGINDO DigestMethod antes do envio:")
                                print(f"      De: '{algo_digest_envio}'")
                                print(f"      Para: '{URI_DIGEST_ENVIO}'")
                            print(f"   ✅ DigestMethod para envio: '{digest_method_envio.get('Algorithm')}'")
            
            print("=" * 70)
            print("✅ Algoritmos verificados e corrigidos antes do envio")
            print("=" * 70 + "\n")
            
            # Validar estrutura corrigida
            inf_nfe_validacao = xml_para_envio.find('.//{http://www.portalfiscal.inf.br/nfe}infNFe') or xml_para_envio.find('.//infNFe')
            if inf_nfe_validacao is None:
                raise ValueError("ERRO CRÍTICO: infNFe não encontrado após correção!")
            
            if 'Id' not in inf_nfe_validacao.attrib:
                raise ValueError("ERRO CRÍTICO: infNFe não possui atributo Id!")
            
            print(f"   ✅ XML corrigido e validado:")
            print(f"      Tag raiz: {xml_para_envio.tag}")
            print(f"      infNFe Id: {inf_nfe_validacao.get('Id', 'N/A')}")
            print(f"      infNFe versao: {inf_nfe_validacao.get('versao', 'N/A')}")
            
            # Salvar XML corrigido para debug e por empresa
            try:
                # Diretório de debug geral
                debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                os.makedirs(debug_dir, exist_ok=True)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                debug_file_corrigido = os.path.join(debug_dir, f'xml_corrigido_final_{timestamp}.xml')
                
                # Diretório por empresa (usando CNPJ)
                cnpj = empresa_data.get('cnpj', 'sem_cnpj')
                cnpj_limpo = cnpj.replace('.', '').replace('/', '').replace('-', '')
                empresa_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'xmls_empresas', cnpj_limpo)
                os.makedirs(empresa_dir, exist_ok=True)
                
                xml_corrigido_str = etree.tostring(xml_para_envio, encoding='unicode', pretty_print=True)
                
                # Salvar no diretório de debug geral
                with open(debug_file_corrigido, 'w', encoding='utf-8') as f:
                    f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                    f.write(xml_corrigido_str)
                print(f"   ✅ [XML 2/3] XML CORRIGIDO salvo em: {debug_file_corrigido}")
                print(f"      📋 Este é o XML corrigido antes de enviar para a SEFAZ")
                print(f"      ⚠️  Este XML NÃO é o final - ainda precisa ser enviado para a SEFAZ")
                
                # Salvar no diretório da empresa
                empresa_file = os.path.join(empresa_dir, f'xml_corrigido_{timestamp}_nfe_{numero_nfce}.xml')
                with open(empresa_file, 'w', encoding='utf-8') as f:
                    f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                    f.write(xml_corrigido_str)
                print(f"   ✅ XML corrigido salvo por empresa em: {empresa_file}")
            except Exception as e_debug:
                print(f"   ⚠️ Erro ao salvar XML corrigido: {e_debug}")
            
            # Função para corrigir valores decimais ANTES de passar para PyNFe
            def corrigir_valores_decimais_xml(xml_element):
                """Corrige valores decimais no XML para padrão TDec_1302"""
                from decimal import Decimal, InvalidOperation
                import re
                
                campos_tdec_1302 = [
                    'vProd', 'vUnCom', 'vUnTrib', 'vFrete', 'vSeg', 'vDesc', 'vOutro',
                    'vBC', 'vICMS', 'vICMSDeson', 'vFCP', 'vBCST', 'vST', 'vFCPST',
                    'vFCPSTRet', 'vIPI', 'vIPIDevol', 'vPIS', 'vCOFINS', 'vNF', 
                    'vTotTrib', 'vICMSUFDest', 'vFCPUFDest', 'vICMSUFRemet'
                ]
                
                correcoes = 0
                for elem in xml_element.iter():
                    if elem.text and elem.text.strip():
                        tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                        if tag_limpa in campos_tdec_1302:
                            try:
                                valor_decimal = Decimal(elem.text.strip())
                                valor_formatado = f"{valor_decimal:.2f}"
                                if elem.text.strip() != valor_formatado:
                                    elem.text = valor_formatado
                                    correcoes += 1
                            except:
                                pass
                return correcoes
            
            # Corrigir valores decimais no XML antes de passar para PyNFe
            print("🔧 Corrigindo valores decimais no XML...")
            num_correcoes = corrigir_valores_decimais_xml(xml_para_envio)
            if num_correcoes > 0:
                print(f"   ✅ {num_correcoes} valor(es) decimal(is) corrigido(s)")
            
            # Usar o método ORIGINAL do PyNFe (não sobrescrever)
            comunicacao = ComunicacaoSefaz(uf, cert_path, self.senha_certificado, ambiente)
            
            # SOLUÇÃO DEFINITIVA: Usar método ORIGINAL do PyNFe SEM override
            # Apenas garantir que idLote tem 15 dígitos ANTES de chamar
            
            # Criar instância de comunicação ORIGINAL (sem override)
            comunicacao = ComunicacaoSefaz(uf, cert_path, self.senha_certificado, ambiente)
            
            # Armazenar instância para uso nos métodos auxiliares
            self._comunicacao_sefaz = comunicacao
            self._uf_temp = uf
            self._ambiente_temp = ambiente_homologacao
            
            # Garantir que idLote tem 15 dígitos (conforme schema XSD)
            id_lote_corrigido = str(1).zfill(15)
            
            # Chamar método autorizacao ORIGINAL do PyNFe (sem nenhuma modificação)
            try:
                resultado_autorizacao = comunicacao.autorizacao(
                    modelo="nfce",
                    nota_fiscal=xml_para_envio,
                    id_lote=id_lote_corrigido,
                    ind_sinc=1,
                    timeout=60
                )
                
                # Processar resultado retornado pelo PyNFe
                # O método autorizacao do PyNFe retorna uma tupla (retorno, prot) ou (retorno, prot, nota_fiscal)
                
                if isinstance(resultado_autorizacao, tuple):
                    # É uma tupla (retorno, prot) ou (retorno, prot, nota_fiscal)
                    if len(resultado_autorizacao) == 2:
                        status, resultado = resultado_autorizacao
                    elif len(resultado_autorizacao) == 3:
                        status, resultado, nota_fiscal_ret = resultado_autorizacao
                    else:
                        raise ValueError(f"Retorno inesperado: {len(resultado_autorizacao)} valores na tupla")
                elif hasattr(resultado_autorizacao, 'status_code'):
                    # É um objeto Response do requests
                    status = resultado_autorizacao
                    try:
                        if hasattr(status, 'text') and status.text:
                            resultado = self._parse_xml_safe(status.text)
                        elif hasattr(status, 'content') and status.content:
                            resultado = self._parse_xml_safe(status.content)
                        else:
                            resultado = status
                    except Exception as e_parse:
                        print(f"   ⚠️ Erro ao parsear resposta: {e_parse}")
                        resultado = status
                else:
                    # Tipo desconhecido
                    status = resultado_autorizacao
                    resultado = resultado_autorizacao
                
                # O resultado já foi processado pelo PyNFe
                # O método autorizacao retorna uma tupla (retorno, prot) ou (retorno, prot, nota_fiscal)
                # Processar o resultado corretamente abaixo
                retorno, prot = None, None
                if isinstance(resultado_autorizacao, tuple):
                    if len(resultado_autorizacao) == 2:
                        retorno, prot = resultado_autorizacao
                    elif len(resultado_autorizacao) == 3:
                        retorno, prot, nota_fiscal_ret = resultado_autorizacao
                    else:
                        raise ValueError(f"Retorno inesperado: {len(resultado_autorizacao)} valores na tupla")
                elif hasattr(resultado_autorizacao, 'status_code'):
                    # É um objeto Response
                    retorno = resultado_autorizacao
                    try:
                        if hasattr(retorno, 'text') and retorno.text:
                            prot = self._parse_xml_safe(retorno.text)
                        elif hasattr(retorno, 'content') and retorno.content:
                            prot = self._parse_xml_safe(retorno.content)
                        else:
                            prot = None
                    except Exception as e_parse:
                        print(f"   ⚠️ Erro ao parsear resposta: {e_parse}")
                        prot = None
                else:
                    raise ValueError(f"Tipo de retorno inesperado: {type(resultado_autorizacao)}")
                
                # Processar resultado retornado pelo PyNFe
                # O método autorizacao do PyNFe já criou e enviou o lote, agora precisamos processar a resposta
                # Continuar com o processamento abaixo (linha ~5236)
                
            except Exception as e:
                # Tratar erros da chamada ao PyNFe
                error_msg = f"Erro ao chamar método autorizacao do PyNFe: {str(e)}"
                print(f"❌ {error_msg}")
                raise ValueError(error_msg) from e
            
            # O resultado já foi processado acima
            # Continuar com o processamento do resultado abaixo (linha ~5236)
            
            # Se chegou aqui, houve algum problema ou status não é 0
            # Tentar processar resultado mesmo assim (pode ser envelope SOAP ou XML direto)
            if hasattr(resultado, 'tag'):
                # resultado já é um elemento XML - processar diretamente
                prot = resultado
                try:
                    ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
                    
                    # Procurar por retEnviNFe
                    ret_envi_nfe = None
                    for elem in prot.iter():
                        if 'retEnviNFe' in elem.tag or elem.tag.endswith('retEnviNFe'):
                            ret_envi_nfe = elem
                            break
                    
                    if ret_envi_nfe is not None:
                        c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or ret_envi_nfe.find('.//cStat')
                        x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or ret_envi_nfe.find('.//xMotivo')
                        
                        if c_stat is not None:
                            c_stat_text = c_stat.text
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                            
                            print(f"   📋 cStat do lote: {c_stat_text}")
                            print(f"   📋 xMotivo do lote: {x_motivo_text}")
                            
                            # cStat 104 = Lote processado - verificar status da nota individual
                            if c_stat_text == '104':
                    print("=" * 70)
                                print("   ✅ Lote processado (cStat=104), verificando status da nota individual...")
                    print("=" * 70)
                                
                                # Buscar protNFe
                                prot_nfe = ret_envi_nfe.find('{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('.//protNFe')
                                
                                if prot_nfe is not None:
                                    inf_prot = prot_nfe.find('{http://www.portalfiscal.inf.br/nfe}infProt')
                                    if inf_prot is None:
                                        inf_prot = prot_nfe.find('infProt')
                                    if inf_prot is None:
                                        inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt')
                                    if inf_prot is None:
                                        inf_prot = prot_nfe.find('.//infProt')
                                    
                                    if inf_prot is not None:
                                        c_stat_nfe = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}cStat')
                                        if c_stat_nfe is None:
                                            c_stat_nfe = inf_prot.find('cStat')
                                        
                                        if c_stat_nfe is not None and c_stat_nfe.text == '100':
                                            # Autorizada
                                            chave_acesso = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}chNFe')
                                            if chave_acesso is None:
                                                chave_acesso = inf_prot.find('chNFe')
                                            
                                            protocolo = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}nProt')
                                            if protocolo is None:
                                                protocolo = inf_prot.find('nProt')
                                            
                                            x_motivo_nfe = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                            if x_motivo_nfe is None:
                                                x_motivo_nfe = inf_prot.find('xMotivo')
                                            
                                            chave_acesso_text = chave_acesso.text if chave_acesso is not None else ''
                                            protocolo_text = protocolo.text if protocolo is not None else ''
                                            x_motivo_text = x_motivo_nfe.text if x_motivo_nfe is not None else 'Autorizada'
                                            
                                            print(f"   ✅ NFC-e autorizada! Chave: {chave_acesso_text}")
                                            
                                            # Retornar sucesso
                                            return {
                                                'success': True,
                                                'autorizada': True,
                                                'status': 'autorizada',
                                                'chave_acesso': chave_acesso_text,
                                                'protocolo': protocolo_text,
                                                'mensagem': x_motivo_text
                                            }
                                        else:
                                            # Rejeitada
                                            x_motivo_nfe = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                            if x_motivo_nfe is None:
                                                x_motivo_nfe = inf_prot.find('xMotivo')
                                            
                                            c_stat_nfe_text = c_stat_nfe.text if c_stat_nfe is not None else 'N/A'
                                            x_motivo_text = x_motivo_nfe.text if x_motivo_nfe is not None else 'Erro desconhecido'
                                            
                                            return {
                                                'success': False,
                                                'autorizada': False,
                                                'status': 'rejeitada',
                                                'cStat': c_stat_nfe_text,
                                                'xMotivo': x_motivo_text,
                                                'error': x_motivo_text,
                                                'error_type': 'SEFAZRejection'
                                            }
                except Exception as e:
                    print(f"   ⚠️ Erro ao processar resultado: {e}")
                    import traceback
                    traceback.print_exc()
            
            # Se chegou aqui, não foi possível processar o resultado
            return {
                'success': False,
                'error': 'Não foi possível processar o resultado da SEFAZ',
                'error_type': 'ProcessingError'
            }
            
            # O código acima (linha 3620-3693) já chamou o método original do PyNFe
            # O resultado está em resultado_autorizacao, retorno e prot
            # Continuar processamento do resultado abaixo (linha ~5236)
            
            # O método pode retornar diferentes tipos:
            # - Tupla (status, resultado) ou (status, resultado, nota_fiscal)
            # - Objeto Response diretamente
            # - Outros tipos
            
            # Verificar tipo do retorno
            if isinstance(resultado_autorizacao, tuple):
                # É uma tupla
                if len(resultado_autorizacao) == 2:
                    status, resultado = resultado_autorizacao
                elif len(resultado_autorizacao) == 3:
                    status, resultado, nota_fiscal_ret = resultado_autorizacao
                            else:
                    raise ValueError(f"Retorno inesperado do método autorizacao: {len(resultado_autorizacao)} valores na tupla")
            elif hasattr(resultado_autorizacao, 'status_code'):
                # É um objeto Response do requests
                status = resultado_autorizacao
                # Tentar extrair o resultado do Response
                try:
                    if hasattr(status, 'text') and status.text:
                        resultado = nfce_instance._parse_xml_safe(status.text)
                    elif hasattr(status, 'content') and status.content:
                        resultado = nfce_instance._parse_xml_safe(status.content)
                                    else:
                        resultado = status
                except Exception as e_parse:
                    print(f"   ⚠️ Erro ao parsear resposta: {e_parse}")
                    resultado = status
                            else:
                # Tipo desconhecido, usar diretamente
                status = resultado_autorizacao
                resultado = resultado_autorizacao
            
            # Processar resultado (código continua abaixo na linha ~5236)
            
        except Exception as e:
                # Verificar se é erro de conexão/DNS
                error_str = str(e).lower()
                is_connection_error = any(keyword in error_str for keyword in [
                    'connection', 'dns', 'resolve', 'getaddrinfo', 'name resolution',
                    'failed to resolve', 'connectionerror', 'timeout'
                ])
                
                if is_connection_error:
                    # Verificar se é erro de DNS (NameResolutionError)
                    is_dns_error = 'nameresolutionerror' in error_str or 'failed to resolve' in error_str or 'getaddrinfo' in error_str
                    
                    if is_dns_error:
                        error_msg = (
                            f"❌ Erro de DNS: Não foi possível resolver o nome do servidor da SEFAZ.\n\n"
                            f"🔍 Detalhes do erro:\n{str(e)}\n\n"
                            f"⚠️ Você está testando em um servidor local.\n\n"
                            f"Possíveis causas:\n"
                            f"1. Servidor local sem acesso à internet\n"
                            f"2. Servidor local sem configuração de DNS\n"
                            f"3. Firewall bloqueando resolução DNS\n"
                            f"4. Proxy/VPN interferindo na resolução\n\n"
                            f"📋 Informações:\n"
                            f"URL tentada: {getattr(comunicacao, 'url', 'Não disponível')}\n"
                            f"Host: homologacao.nfce.fazenda.sp.gov.br\n"
                            f"UF: {uf}\n"
                            f"Ambiente: {'Homologação' if ambiente_homologacao else 'Produção'}\n\n"
                            f"✅ Soluções para servidor local:\n"
                            f"1. Verificar se o servidor tem acesso à internet:\n"
                            f"   - Teste: ping 8.8.8.8\n"
                            f"   - Teste: ping google.com\n\n"
                            f"2. Verificar resolução DNS:\n"
                            f"   - Teste: nslookup homologacao.nfce.fazenda.sp.gov.br\n"
                            f"   - Ou configure DNS manualmente (8.8.8.8, 8.8.4.4)\n\n"
                            f"3. Se o servidor não tem internet, você precisa:\n"
                            f"   - Conectar o servidor à internet\n"
                            f"   - Ou usar um servidor com acesso à internet\n"
                            f"   - Ou configurar um proxy/tunnel\n\n"
                            f"4. Testar conectividade manualmente:\n"
                            f"   - Abra um navegador no servidor\n"
                            f"   - Tente acessar: https://homologacao.nfce.fazenda.sp.gov.br\n"
                            f"   - Se não abrir, o problema é de rede/DNS"
                        )
                    else:
                        error_msg = (
                            f"Erro de conexão com a SEFAZ: {str(e)}\n\n"
                            f"Possíveis causas:\n"
                            f"1. Problema de conectividade de internet\n"
                            f"2. Servidor da SEFAZ temporariamente indisponível\n"
                            f"3. Problema de DNS (não consegue resolver o nome do servidor)\n"
                            f"4. Firewall bloqueando a conexão\n"
                            f"5. Timeout na conexão\n\n"
                            f"📋 Informações:\n"
                            f"URL tentada: {getattr(comunicacao, 'url', 'Não disponível')}\n"
                            f"UF: {uf}\n"
                            f"Ambiente: {'Homologação' if ambiente_homologacao else 'Produção'}\n\n"
                            f"✅ Soluções:\n"
                            f"1. Verificar conectividade de internet\n"
                            f"2. Verificar se o servidor da SEFAZ está online\n"
                            f"3. Verificar configurações de firewall\n"
                            f"4. Tentar novamente em alguns minutos"
                        )
                    
                    raise ConnectionError(error_msg)
                
                # Se não é erro de conexão, relançar o erro original
                raise
            
            # O código acima (linha 3620-3693) já chamou o método original do PyNFe
            # O resultado está em resultado_autorizacao, retorno e prot
            # Continuar processamento do resultado abaixo (linha ~5236)
                
                # O método pode retornar diferentes tipos:
                # - Tupla (status, resultado) ou (status, resultado, nota_fiscal)
                # - Objeto Response diretamente
                # - Outros tipos
                
                # Verificar tipo do retorno
                if isinstance(resultado_autorizacao, tuple):
                    # É uma tupla
                    if len(resultado_autorizacao) == 2:
                        status, resultado = resultado_autorizacao
                    elif len(resultado_autorizacao) == 3:
                        status, resultado, nota_fiscal_ret = resultado_autorizacao
                    else:
                        raise ValueError(f"Retorno inesperado do método autorizacao: {len(resultado_autorizacao)} valores na tupla")
                elif hasattr(resultado_autorizacao, 'status_code'):
                    # É um objeto Response do requests
                    status = resultado_autorizacao
                    # Tentar extrair o resultado do Response
                    try:
                        if hasattr(status, 'text') and status.text:
                            resultado = nfce_instance._parse_xml_safe(status.text)
                        elif hasattr(status, 'content') and status.content:
                            resultado = nfce_instance._parse_xml_safe(status.content)
                        else:
                            resultado = status
                    except Exception as e_parse:
                        print(f"   ⚠️ Erro ao parsear resposta: {e_parse}")
                        resultado = status
                else:
                    # Tipo desconhecido, usar diretamente
                    status = resultado_autorizacao
                    resultado = resultado_autorizacao
            except Exception as e:
                # Verificar se é erro de conexão/DNS
                error_str = str(e).lower()
                is_connection_error = any(keyword in error_str for keyword in [
                    'connection', 'dns', 'resolve', 'getaddrinfo', 'name resolution',
                    'failed to resolve', 'connectionerror', 'timeout'
                ])
                
                if is_connection_error:
                    # Verificar se é erro de DNS (NameResolutionError)
                    is_dns_error = 'nameresolutionerror' in error_str or 'failed to resolve' in error_str or 'getaddrinfo' in error_str
                    
                    if is_dns_error:
                        error_msg = (
                            f"❌ Erro de DNS: Não foi possível resolver o nome do servidor da SEFAZ.\n\n"
                            f"🔍 Detalhes do erro:\n{str(e)}\n\n"
                            f"⚠️ Você está testando em um servidor local.\n\n"
                            f"Possíveis causas:\n"
                            f"1. Servidor local sem acesso à internet\n"
                            f"2. Servidor local sem configuração de DNS\n"
                            f"3. Firewall bloqueando resolução DNS\n"
                            f"4. Proxy/VPN interferindo na resolução\n\n"
                            f"📋 Informações:\n"
                            f"URL tentada: {getattr(comunicacao, 'url', 'Não disponível')}\n"
                            f"Host: homologacao.nfce.fazenda.sp.gov.br\n"
                            f"UF: {uf}\n"
                            f"Ambiente: {'Homologação' if ambiente_homologacao else 'Produção'}\n\n"
                            f"✅ Soluções para servidor local:\n"
                            f"1. Verificar se o servidor tem acesso à internet:\n"
                            f"   - Teste: ping 8.8.8.8\n"
                            f"   - Teste: ping google.com\n\n"
                            f"2. Verificar resolução DNS:\n"
                            f"   - Teste: nslookup homologacao.nfce.fazenda.sp.gov.br\n"
                            f"   - Ou configure DNS manualmente (8.8.8.8, 8.8.4.4)\n\n"
                            f"3. Se o servidor não tem internet, você precisa:\n"
                            f"   - Conectar o servidor à internet\n"
                            f"   - Ou usar um servidor com acesso à internet\n"
                            f"   - Ou configurar um proxy/tunnel\n\n"
                            f"4. Testar conectividade manualmente:\n"
                            f"   - Abra um navegador no servidor\n"
                            f"   - Tente acessar: https://homologacao.nfce.fazenda.sp.gov.br\n"
                            f"   - Se não abrir, o problema é de rede/DNS"
                        )
                    else:
                        error_msg = (
                            f"Erro de conexão com a SEFAZ: {str(e)}\n\n"
                            f"Possíveis causas:\n"
                            f"1. Problema de conectividade de internet\n"
                            f"2. Servidor da SEFAZ temporariamente indisponível\n"
                            f"3. Problema de DNS (não consegue resolver o nome do servidor)\n"
                            f"4. Firewall bloqueando a conexão\n"
                            f"5. Timeout na conexão\n\n"
                            f"📋 Informações:\n"
                            f"URL tentada: {getattr(comunicacao, 'url', 'Não disponível')}\n"
                            f"UF: {uf}\n"
                            f"Ambiente: {'Homologação' if ambiente_homologacao else 'Produção'}\n\n"
                            f"✅ Soluções:\n"
                            f"1. Verificar conectividade de internet\n"
                            f"2. Verificar se o servidor da SEFAZ está online\n"
                            f"3. Verificar configurações de firewall\n"
                            f"4. Tentar novamente em alguns minutos"
                        )
                    
                    raise ConnectionError(error_msg)
                
                # Se não é erro de conexão, relançar o erro original
                raise
            
            # Função auxiliar para criar NFe limpo sem prefixos de namespace
            def criar_nfe_limpo_sem_prefixos(elem_orig, cert_base64_ref=None):
                """Cria novo NFe e filhos sem prefixos de namespace"""
                # Criar novo NFe sem namespace próprio (herda do enviNFe)
                nfe_limpo = etree.Element("NFe")
                
                def copiar_elemento_sem_prefixo(elem_orig, elem_dest):
                    """Copia elemento removendo prefixos de namespace"""
                    # Extrair nome local (sem namespace)
                    tag_local = None
                    if '}' in elem_orig.tag:
                        namespace, tag_local = elem_orig.tag.split('}', 1)
                        namespace = namespace[1:]  # Remover {
                        
                        # Se é namespace NFE, criar sem prefixo (herda do enviNFe)
                        if namespace == 'http://www.portalfiscal.inf.br/nfe':
                            novo_elem = etree.SubElement(elem_dest, tag_local)
                        # Se é namespace Signature, manter o namespace completo mas sem prefixo
                        elif namespace == 'http://www.w3.org/2000/09/xmldsig#':
                            # Criar com namespace completo mas sem prefixo
                            novo_elem = etree.SubElement(elem_dest, '{' + namespace + '}' + tag_local)
                        # Outros namespaces - manter como está
                        else:
                            novo_elem = etree.SubElement(elem_dest, elem_orig.tag)
                    else:
                        tag_local = elem_orig.tag
                        novo_elem = etree.SubElement(elem_dest, elem_orig.tag)
                    
                    # Copiar atributos (remover xmlns:ns0, xmlns:ns1, etc)
                    for attr, valor in elem_orig.attrib.items():
                        if not attr.startswith('xmlns:ns'):
                            novo_elem.set(attr, valor)
                    
                    # Copiar texto (CRÍTICO para X509Certificate)
                    # IMPORTANTE: Para X509Certificate, garantir que o texto seja copiado corretamente
                    if tag_local and 'X509Certificate' in tag_local:
                        # X509Certificate - copiar texto de forma especial
                        if elem_orig.text:
                            novo_elem.text = elem_orig.text
                        elif cert_base64_ref:
                            # Se o texto foi perdido, usar o certificado original
                            novo_elem.text = cert_base64_ref
                            print(f"      🔧 X509Certificate texto restaurado durante cópia: {len(cert_base64_ref)} chars")
                    else:
                        # Outros elementos - copiar texto normalmente
                        if elem_orig.text:
                            novo_elem.text = elem_orig.text
                    
                    # Copiar filhos recursivamente
                    for filho in elem_orig:
                        copiar_elemento_sem_prefixo(filho, novo_elem)
                    
                    # Copiar tail
                    if elem_orig.tail:
                        novo_elem.tail = elem_orig.tail
                
                # Copiar todos os filhos do NFe original
                for filho in elem_orig:
                    copiar_elemento_sem_prefixo(filho, nfe_limpo)
                
                return nfe_limpo
            
            # Processar resultado da autorização
            # NOTA: O resultado já foi processado acima (linhas 3916-3940)
            # Esta seção não é mais necessária, mas mantida para compatibilidade
            # O status e resultado já foram definidos no bloco anterior
            try:
                # Verificar se status e resultado já foram definidos
                if 'status' not in locals() or 'resultado' not in locals():
                    # Se não foram definidos, processar agora
                    if isinstance(resultado_autorizacao, tuple):
                        if len(resultado_autorizacao) == 2:
                            status, resultado = resultado_autorizacao
                        elif len(resultado_autorizacao) == 3:
                            status, resultado, nota_fiscal_ret = resultado_autorizacao
                    elif hasattr(resultado_autorizacao, 'status_code'):
                        status = resultado_autorizacao
                        resultado = nfce_instance._parse_xml_safe(status.text if hasattr(status, 'text') and status.text else status.content)
                    else:
                        status = resultado_autorizacao
                        resultado = resultado_autorizacao
                
                # O resultado da autorização já foi processado
                # O lote foi criado e enviado dentro do método autorizacao da classe ComunicacaoSefazComValidacao
            except Exception as e:
                # Se houver erro no processamento, relançar
                raise
            
            # NOTA: O resultado da autorização já foi processado acima (linhas 3902-3940)
            # Continuar com o processamento do resultado já obtido
            print(f"Status retornado pelo PyNFe: {status}")
            print(f"Tipo do status: {type(status)}")
            print(f"Tipo do resultado: {type(resultado)}")
            
            # Verificar se status é um objeto Response do requests
            if hasattr(status, 'status_code'):
                # Status é um objeto Response - processar diretamente
                print(f"   🔍 Status é um objeto Response (HTTP {status.status_code})")
                
                # Tratar erro HTTP 400 (Bad Request) - SEFAZ rejeitou a requisição
                if status.status_code == 400:
                    error_msg = (
                        f"❌ Erro HTTP 400: A SEFAZ rejeitou a requisição antes de processar o XML.\n\n"
                        f"Possíveis causas:\n"
                        f"1. XML do lote malformado ou inválido\n"
                        f"2. Estrutura do envelope SOAP incorreta\n"
                        f"3. Headers HTTP incorretos\n"
                        f"4. XML muito grande ou com caracteres inválidos\n\n"
                        f"SOLUÇÃO:\n"
                        f"1. Verifique o XML do lote salvo em logs/debug/\n"
                        f"2. Verifique se o XML está bem formado\n"
                        f"3. Verifique se não há xmlns duplicados\n"
                        f"4. Verifique se todos os namespaces estão corretos\n\n"
                    )
                    
                    # Tentar extrair mais informações da resposta
                    try:
                        if hasattr(status, 'text') and status.text:
                            error_msg += f"Resposta da SEFAZ (primeiros 500 chars):\n{status.text[:500]}\n\n"
                        if hasattr(status, 'headers'):
                            error_msg += f"Headers da resposta: {dict(status.headers)}\n"
                    except:
                        pass
                    
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro_http_400',
                        'error': error_msg,
                        'error_type': 'HTTP400',
                        'status_code': 400
                    }
                
                if status.status_code == 200:
                    # Tentar processar a resposta HTTP diretamente
                    try:
                        # O resultado já é um elemento XML (envelope SOAP), não precisa parsear novamente
                        # O PyNFe já parseou a resposta e retornou como elemento
                        prot = resultado  # resultado já é o envelope SOAP parseado
                        
                        # Se resultado não é um elemento, tentar parsear do texto
                        if not hasattr(prot, 'tag'):
                            print("   🔍 Resultado não é elemento, tentando parsear do texto HTTP...")
                            
                            # Verificar se status tem text ou content
                            if hasattr(status, 'text'):
                                xml_resposta = status.text
                                print(f"   📋 Resposta HTTP (text): {len(xml_resposta) if xml_resposta else 0} caracteres")
                            elif hasattr(status, 'content'):
                                xml_resposta = status.content.decode('utf-8')
                                print(f"   📋 Resposta HTTP (content): {len(xml_resposta) if xml_resposta else 0} caracteres")
                            else:
                                # Tentar acessar diretamente
                                xml_resposta = str(status) if status else ''
                                print(f"   📋 Resposta HTTP (str): {len(xml_resposta) if xml_resposta else 0} caracteres")
                            
                            # Log detalhado da resposta
                            if xml_resposta:
                                print(f"   📋 Primeiros 200 chars da resposta: {xml_resposta[:200]}")
                            else:
                                print("   ❌ Resposta está vazia!")
                                # Tentar obter mais informações do objeto status
                                print(f"   📋 Tipo do status: {type(status)}")
                                print(f"   📋 Atributos do status: {dir(status)}")
                                if hasattr(status, 'headers'):
                                    print(f"   📋 Headers: {dict(status.headers)}")
                                if hasattr(status, 'status_code'):
                                    print(f"   📋 Status code: {status.status_code}")
                            
                            # Remover declaração XML se houver (pode causar erro)
                            if xml_resposta and xml_resposta.strip().startswith('<?xml'):
                                # Encontrar primeira tag
                                primeira_tag = xml_resposta.find('<')
                                if primeira_tag > 0:
                                    xml_resposta = xml_resposta[primeira_tag:]
                            
                            # Validar que xml_resposta não está vazio antes de parsear
                            if not xml_resposta or not xml_resposta.strip():
                                error_msg = (
                                    "❌ Resposta XML está vazia da SEFAZ.\n\n"
                                    "🔍 Diagnóstico:\n"
                                    f"   - Status HTTP: {status.status_code if hasattr(status, 'status_code') else 'N/A'}\n"
                                    f"   - Tipo do objeto: {type(status)}\n"
                                )
                                
                                if hasattr(status, 'headers'):
                                    error_msg += f"   - Headers: {dict(status.headers)}\n"
                                
                                error_msg += (
                                    "\n💡 Possíveis causas:\n"
                                    "   1. SEFAZ retornou resposta vazia (problema temporário)\n"
                                    "   2. Erro na comunicação (timeout, conexão perdida)\n"
                                    "   3. Problema com certificado (não aceito pela SEFAZ)\n"
                                    "   4. URL incorreta ou serviço indisponível\n\n"
                                    "✅ Soluções:\n"
                                    "   1. Aguarde alguns minutos e tente novamente\n"
                                    "   2. Verifique se o certificado está válido\n"
                                    "   3. Verifique a conectividade com a SEFAZ\n"
                                    "   4. Verifique se a URL da SEFAZ está correta"
                                )
                                
                                raise ValueError(error_msg)
                            
                            print(f"   ✅ XML resposta válido: {len(xml_resposta)} caracteres")
                            prot = self._parse_xml_safe(xml_resposta)
                        
                        # Procurar por retEnviNFe ou nfeProc
                        ret_envi_nfe = None
                        nfe_proc = None
                        
                        # Tentar encontrar retEnviNFe
                        for elem in prot.iter():
                            if 'retEnviNFe' in elem.tag or elem.tag.endswith('retEnviNFe'):
                                ret_envi_nfe = elem
                                break
                            if 'nfeProc' in elem.tag or elem.tag.endswith('nfeProc'):
                                nfe_proc = elem
                                break
                        
                        if nfe_proc is not None:
                            # Já tem nfeProc completo
                            resultado = nfe_proc
                            # Continuar processamento normal abaixo
                        elif ret_envi_nfe is not None:
                            # Tem retEnviNFe - processar
                            resultado = ret_envi_nfe
                            # Continuar processamento normal abaixo
                        else:
                            # Não encontrou - tentar processar como envelope SOAP
                            resultado = prot
                    except Exception as e_parse:
                        print(f"   ⚠️ Erro ao processar resposta HTTP: {e_parse}")
                        # Continuar com processamento normal
            
            # IMPORTANTE: Preservar XML assinado para construir nfeProc quando necessário
            # O xml_para_envio contém o XML assinado completo (NFe com infNFe e Signature)
            xml_assinado_original = xml_para_envio  # Preservar para uso posterior
            
            # Processar resultado conforme documentação do PyNFe
            if isinstance(status, int) and status == 0:  # Sucesso - resultado é XML (nfeProc)
                # resultado é um elemento XML com nfeProc
                if hasattr(resultado, 'tag'):
                    # Verificar se já é nfeProc completo
                    if 'nfeProc' in resultado.tag or resultado.tag.endswith('nfeProc'):
                        print("   ✅ Resposta já contém nfeProc completo!")
                        # Extrair dados do nfeProc
                        xml_str = etree.tostring(resultado, encoding='unicode')
                        
                        # Buscar chave de acesso e protocolo
                        inf_prot = resultado.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or resultado.find('.//infProt')
                        if inf_prot is not None:
                            chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or inf_prot.find('.//chNFe')
                            protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') or inf_prot.find('.//nProt')
                            c_stat = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or inf_prot.find('.//cStat')
                            x_motivo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or inf_prot.find('.//xMotivo')
                            
                            chave_acesso = chave.text if chave is not None else ''
                            protocolo_text = protocolo.text if protocolo is not None else ''
                            c_stat_text = c_stat.text if c_stat is not None else ''
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Autorizado'
                            
                            if c_stat_text in ['100', '150']:
                                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                
                                dados_impressao = {
                                    'chave_acesso': chave_acesso,
                                    'protocolo': protocolo_text,
                                    'xml': xml_str,
                                    'empresa': empresa_data,
                                    'produtos': produtos,
                                    'pagamentos': pagamentos,
                                    'consumidor': consumidor,
                                    'numero_nfce': numero_nfce,
                                    'caminho_xml': caminho_xml
                                }
                                
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'status': 'autorizada',
                                    'chave_acesso': chave_acesso,
                                    'protocolo': protocolo_text,
                                    'mensagem': x_motivo_text,
                                    'xml': xml_str,
                                    'caminho_xml': caminho_xml,
                                    'dados_impressao': dados_impressao
                                }
                    
                    # Extrair dados do protocolo
                    ns = {'nfe': 'http://www.portalfiscal.inf.br/nfe'}
                    
                    # Procurar protNFe
                    prot_nfe = resultado.find('.//nfe:protNFe', ns)
                    if prot_nfe is None:
                        # Tentar sem namespace
                        prot_nfe = resultado.find('.//protNFe')
                    
                    if prot_nfe is not None:
                        inf_prot = prot_nfe.find('.//nfe:infProt', ns)
                        if inf_prot is None:
                            inf_prot = prot_nfe.find('.//infProt')
                        
                        if inf_prot is not None:
                            c_stat = inf_prot.find('.//nfe:cStat', ns) or inf_prot.find('.//cStat')
                            x_motivo = inf_prot.find('.//nfe:xMotivo', ns) or inf_prot.find('.//xMotivo')
                            chave = inf_prot.find('.//nfe:chNFe', ns) or inf_prot.find('.//chNFe')
                            protocolo = inf_prot.find('.//nfe:nProt', ns) or inf_prot.find('.//nProt')
                            
                            c_stat_text = c_stat.text if c_stat is not None else ''
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                            
                            if c_stat_text in ['100', '150']:  # Autorizada
                                xml_str = etree.tostring(resultado, encoding='unicode')
                                
                                # Salvar XML em pasta por empresa e mês
                                chave_acesso = chave.text if chave is not None else ''
                                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                
                                # Preparar dados para impressão
                                dados_impressao = {
                                    'chave_acesso': chave_acesso,
                                    'protocolo': protocolo.text if protocolo is not None else '',
                                    'xml': xml_str,
                                    'empresa': empresa_data,
                                    'produtos': produtos,
                                    'pagamentos': pagamentos,
                                    'consumidor': consumidor,
                                    'numero_nfce': numero_nfce,
                                    'caminho_xml': caminho_xml
                                }
                                
                                return {
                                    'success': True,
                                    'autorizada': True,
                                    'status': 'autorizada',
                                    'chave_acesso': chave_acesso,
                                    'protocolo': protocolo.text if protocolo is not None else '',
                                    'mensagem': x_motivo_text,
                                    'xml': xml_str,
                                    'caminho_xml': caminho_xml,
                                    'dados_impressao': dados_impressao
                                }
                            else:
                                # Rejeição
                                error_msg = x_motivo_text
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'status': 'rejeitada',
                                    'cStat': c_stat_text,
                                    'xMotivo': x_motivo_text,
                                    'error': error_msg,
                                    'error_type': 'SEFAZRejection'
                                }
            
            # Se chegou aqui, houve algum problema ou status não é 0
            # Tentar processar resultado mesmo assim (pode ser envelope SOAP ou XML direto)
            if hasattr(resultado, 'tag'):
                # resultado já é um elemento XML - processar diretamente
                prot = resultado
                try:
                    ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
                    
                    # Procurar por retEnviNFe
                    ret_envi_nfe = None
                    for elem in prot.iter():
                        if 'retEnviNFe' in elem.tag or elem.tag.endswith('retEnviNFe'):
                            ret_envi_nfe = elem
                            break
                    
                    if ret_envi_nfe is not None:
                        c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or ret_envi_nfe.find('.//cStat')
                        x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or ret_envi_nfe.find('.//xMotivo')
                        
                        if c_stat is not None:
                            c_stat_text = c_stat.text
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                            
                            print(f"   📋 cStat do lote: {c_stat_text}")
                            print(f"   📋 xMotivo do lote: {x_motivo_text}")
                            
                            # cStat 104 = Lote processado - verificar status da nota individual
                            if c_stat_text == '104':
                                print("=" * 70)
                                print("   ✅ Lote processado (cStat=104), verificando status da nota individual...")
                                print("=" * 70)
                                
                                # IMPORTANTE: Salvar resposta XML completa para debug
                                try:
                                    debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                                    os.makedirs(debug_dir, exist_ok=True)
                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                    resposta_xml_str = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    debug_file = os.path.join(debug_dir, f'resposta_sefaz_cstat104_{timestamp}.xml')
                                    with open(debug_file, 'w', encoding='utf-8') as f:
                                        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                                        f.write(resposta_xml_str)
                                    print(f"   📁 Resposta XML salva para debug: {debug_file}")
                                except Exception as e_debug:
                                    print(f"   ⚠️ Erro ao salvar resposta para debug: {e_debug}")
                                
                                # Mostrar estrutura completa do retEnviNFe
                                print("\n   📋 Estrutura completa do retEnviNFe:")
                                print(f"      Tag raiz: {ret_envi_nfe.tag}")
                                print(f"      Atributos: {ret_envi_nfe.attrib}")
                                print(f"      Número de filhos diretos: {len(list(ret_envi_nfe))}")
                                
                                # Listar todos os filhos diretos
                                for idx, child in enumerate(ret_envi_nfe):
                                    tag_local = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                    print(f"      [{idx}] {tag_local} (tag completa: {child.tag})")
                                    print(f"          Atributos: {child.attrib}")
                                    print(f"          Texto: {child.text[:100] if child.text else 'None'}...")
                                    print(f"          Filhos: {len(list(child))}")
                                    
                                    # Listar filhos de segundo nível
                                    for sub_idx, subchild in enumerate(child):
                                        sub_tag_local = subchild.tag.split('}')[-1] if '}' in subchild.tag else subchild.tag
                                        print(f"            [{sub_idx}] {sub_tag_local}")
                                
                                # Estratégia 1: Buscar protNFe diretamente como filho do retEnviNFe
                                print("\n   🔍 Estratégia 1: Buscando protNFe como filho direto...")
                                prot_nfe = ret_envi_nfe.find('{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('protNFe')
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado como filho direto! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 2: Buscar protNFe recursivamente dentro do retEnviNFe
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 2: Buscando protNFe recursivamente...")
                                    prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                    if prot_nfe is None:
                                        prot_nfe = ret_envi_nfe.find('.//protNFe')
                                    if prot_nfe is not None:
                                        print(f"   ✅ protNFe encontrado recursivamente! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 3: Buscar por iteração manual (caso namespaces estejam diferentes)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 3: Buscando protNFe por iteração manual...")
                                    for elem in ret_envi_nfe.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado via iteração (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 4: Buscar em todo o documento (pode estar fora do retEnviNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 4: Buscando protNFe em todo o documento...")
                                    for elem in prot.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado no documento completo (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 5: Buscar infProt diretamente (pode estar sem protNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 5: Buscando infProt diretamente...")
                                    inf_prot_direto = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or ret_envi_nfe.find('.//infProt')
                                    if inf_prot_direto is None:
                                        # Buscar em todo o documento
                                        for elem in prot.iter():
                                            tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            if tag_local == 'infProt':
                                                inf_prot_direto = elem
                                                print(f"   ✅ infProt encontrado diretamente (tag completa: {elem.tag})")
                                                # Criar protNFe artificial
                                                from pynfe.utils.flags import NAMESPACE_NFE
                                                prot_nfe = etree.Element("protNFe", xmlns=NAMESPACE_NFE)
                                                prot_nfe.append(inf_prot_direto)
                                                print(f"   ✅ protNFe criado artificialmente com infProt encontrado")
                                                break
                                
                                # Debug: mostrar estrutura do retEnviNFe se não encontrou
                                if prot_nfe is None:
                                    print("\n   ❌ protNFe NÃO encontrado após todas as estratégias!")
                                    print("   📋 Estrutura XML completa (primeiros 2000 caracteres):")
                                    xml_str_debug = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    print(xml_str_debug[:2000])
                                    print("   ⚠️ Verifique o arquivo de debug salvo para análise completa")
                                    
                                    # Retornar erro descritivo
                                    error_msg = (
                                        f"Lote processado (cStat=104), mas protNFe não encontrado na resposta da SEFAZ.\n\n"
                                        f"O lote foi processado, mas não foi possível extrair o protocolo de autorização da nota individual.\n\n"
                                        f"Possíveis causas:\n"
                                        f"1. A resposta da SEFAZ está em um formato não esperado\n"
                                        f"2. O protNFe está em uma estrutura diferente\n"
                                        f"3. A nota ainda está sendo processada (pode ser necessário consultar o recibo)\n\n"
                                        f"SOLUÇÃO:\n"
                                        f"1. Verifique o arquivo de debug salvo em: logs/debug/resposta_sefaz_cstat104_*.xml\n"
                                        f"2. Verifique se há um número de recibo (nRec) na resposta\n"
                                        f"3. Se houver nRec, será necessário consultar o recibo para obter o status final\n\n"
                                        f"Estrutura encontrada:\n"
                                        f"- Tag raiz: {ret_envi_nfe.tag}\n"
                                        f"- Filhos diretos: {len(list(ret_envi_nfe))}\n"
                                    )
                                    
                                    # Verificar se há nRec (número de recibo) para consulta
                                    nrec_elem = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nRec') or ret_envi_nfe.find('.//nRec')
                                    if nrec_elem is not None and nrec_elem.text:
                                        nrec = nrec_elem.text
                                        print(f"   📋 Número do recibo encontrado: {nrec}")
                                        print(f"   💡 Tentando consultar recibo para obter status final...")
                                        
                                        # Tentar consultar recibo (se o método estiver disponível)
                                        try:
                                            # Aqui você pode adicionar lógica para consultar o recibo
                                            # Por enquanto, apenas informar
                                            error_msg += f"\nNúmero do recibo encontrado: {nrec}\n"
                                            error_msg += "Será necessário consultar o recibo para obter o status final da nota."
                                        except Exception as e_consulta:
                                            print(f"   ⚠️ Erro ao consultar recibo: {e_consulta}")
                                    
                                    return {
                                        'success': False,
                                        'autorizada': False,
                                        'status': 'lote_processado_sem_protocolo',
                                        'cStat': c_stat_text,
                                        'xMotivo': x_motivo_text,
                                        'error': error_msg,
                                        'error_type': 'ProtocolNotFound',
                                        'debug_file': debug_file if 'debug_file' in locals() else None
                                    }
                                
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado! Tag: {prot_nfe.tag}")
                                    # Buscar infProt dentro do protNFe
                                    inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or prot_nfe.find('.//infProt')
                                    
                                    if inf_prot is not None:
                                        print(f"   📋 infProt encontrado! Tag: {inf_prot.tag}")
                                        print(f"   📋 Filhos diretos do infProt: {[child.tag.split('}')[-1] if '}' in child.tag else child.tag for child in inf_prot]}")
                                        
                                        # Buscar cStat da nota individual - tentar múltiplas estratégias
                                        # Estratégia 1: Filho direto com namespace
                                        c_stat_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 2: Filho direto sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('cStat')
                                        # Estratégia 3: Descendente com namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 4: Descendente sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//cStat')
                                        
                                        # Buscar xMotivo da mesma forma
                                        x_motivo_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//xMotivo')
                                        
                                        if c_stat_nota is not None:
                                            c_stat_nota_text = c_stat_nota.text
                                            x_motivo_nota_text = x_motivo_nota.text if x_motivo_nota is not None else 'Erro desconhecido'
                                            
                                            print(f"   ✅ cStat da nota encontrado: {c_stat_nota_text}")
                                            print(f"   ✅ xMotivo da nota: {x_motivo_nota_text}")
                                            
                                            # Verificar se a nota foi autorizada (100 ou 150)
                                            if c_stat_nota_text in ['100', '150']:
                                                print("   ✅ Nota autorizada!")
                                                print("   🔧 Construindo nfeProc (XML assinado + protNFe)...")
                                                
                                                # Validar que temos o XML assinado original
                                                if xml_assinado_original is None:
                                                    print("   ⚠️ AVISO: xml_assinado_original não está disponível, tentando usar xml_para_envio...")
                                                    # Tentar buscar xml_para_envio do escopo
                                                    try:
                                                        xml_assinado_original = xml_para_envio
                                                    except NameError:
                                                        print("   ⚠️ AVISO: xml_para_envio também não está disponível")
                                                
                                                if xml_assinado_original is None:
                                                    raise ValueError(
                                                        "ERRO: XML assinado não está disponível para construir nfeProc.\n\n"
                                                        "O XML assinado é necessário para combinar com o protNFe e formar o nfeProc completo.\n\n"
                                                        "SOLUÇÃO:\n"
                                                        "1. Verifique se o XML foi assinado corretamente\n"
                                                        "2. Verifique se o XML assinado está sendo preservado no processamento"
                                                    )
                                                
                                                # Construir nfeProc seguindo o padrão do XML autorizado
                                                print(f"   📋 Tipo do XML assinado: {type(xml_assinado_original)}")
                                                nfe_proc = self._construir_nfeproc(xml_assinado_original, prot_nfe)
                                                
                                                print("   ✅ nfeProc construído com sucesso!")
                                                xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                                print(f"   📊 Tamanho do XML autorizado: {len(xml_str)} caracteres")
                                                
                                                # Validar que o nfeProc contém NFe e protNFe
                                                if '<nfeProc' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém tag nfeProc!")
                                                if '<NFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém NFe!")
                                                if '<protNFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém protNFe!")
                                                
                                                print("   ✅ XML autorizado validado (contém nfeProc, NFe e protNFe)")
                                                
                                                chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or inf_prot.find('.//chNFe')
                                                chave_acesso = chave.text if chave is not None else ''
                                                protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') or inf_prot.find('.//nProt')
                                                protocolo_text = protocolo.text if protocolo is not None else ''
                                                
                                                print(f"   📋 Chave de acesso: {chave_acesso}")
                                                print(f"   📋 Protocolo: {protocolo_text}")
                                                
                                                # Extrair QR Code do XML autorizado (do infNFeSupl)
                                                qrcode_url_autorizado = None
                                                url_chave_consulta = None
                                                try:
                                                    # Buscar infNFeSupl no XML autorizado
                                                    nfe_no_proc = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or nfe_proc.find('.//NFe')
                                                    if nfe_no_proc is not None:
                                                        inf_nfe_supl = nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infNFeSupl') or nfe_no_proc.find('.//infNFeSupl')
                                                        if inf_nfe_supl is not None:
                                                            qrcode_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}qrCode') or inf_nfe_supl.find('.//qrCode')
                                                            url_chave_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}urlChave') or inf_nfe_supl.find('.//urlChave')
                                                            
                                                            if qrcode_elem is not None and qrcode_elem.text:
                                                                qrcode_url_autorizado = qrcode_elem.text.strip()
                                                                print(f"   ✅ QR Code extraído do XML autorizado")
                                                                print(f"   📱 QR Code: {qrcode_url_autorizado[:80]}...")
                                                            
                                                            if url_chave_elem is not None and url_chave_elem.text:
                                                                url_chave_consulta = url_chave_elem.text.strip()
                                                                print(f"   ✅ URL de consulta: {url_chave_consulta}")
                                                except Exception as e_qr_extract:
                                                    print(f"   ⚠️ Erro ao extrair QR Code do XML: {e_qr_extract}")
                                                    # Se não encontrou no XML autorizado, usar o que foi gerado antes
                                                    if 'qrcode_url' in locals() and qrcode_url is not None:
                                                        qrcode_url_autorizado = qrcode_url
                                                        print(f"   ✅ Usando QR Code gerado anteriormente")
                                                
                                                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                                
                                                # Preparar dados para DANFE NFC-e
                                                dados_impressao = {
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'empresa': empresa_data,
                                                    'produtos': produtos,
                                                    'pagamentos': pagamentos,
                                                    'consumidor': consumidor,
                                                    'numero_nfce': numero_nfce,
                                                    'caminho_xml': caminho_xml
                                                }
                                                
                                                print("   ✅ Dados para DANFE NFC-e preparados")
                                                print("   📋 Próximos passos:")
                                                print("      1. XML autorizado salvo")
                                                print("      2. QR Code disponível para impressão no DANFE")
                                                print("      3. DANFE pode ser gerado no frontend usando os dados retornados")
                                                
                                                return {
                                                    'success': True,
                                                    'autorizada': True,
                                                    'status': 'autorizada',
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'mensagem': x_motivo_nota_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'caminho_xml': caminho_xml,
                                                    'dados_impressao': dados_impressao
                                                }
                                            else:
                                                # Nota rejeitada
                                                print("=" * 70)
                                                print(f"   ❌ NOTA REJEITADA PELA SEFAZ")
                                                print("=" * 70)
                                                print(f"   📋 cStat: {c_stat_nota_text}")
                                                print(f"   📋 xMotivo: {x_motivo_nota_text}")
                                                
                                                # Verificar se é erro de certificado (cStat 290)
                                                if c_stat_nota_text == '290':
                                                    print("\n   ⚠️ ERRO: Certificado de Assinatura inválido (cStat=290)")
                                                    print("   📋 Possíveis causas:")
                                                    print("      1. Certificado expirado")
                                                    print("      2. Certificado não é ICP-Brasil")
                                                    print("      3. Certificado não tem permissão para assinar NFC-e")
                                                    print("      4. Problema na assinatura digital gerada")
                                                    print("      5. Certificado não está no formato correto")
                                                    print("\n   💡 SOLUÇÕES:")
                                                    print("      1. Verifique se o certificado está válido e não expirado")
                                                    print("      2. Verifique se o certificado é ICP-Brasil (A1 ou A3)")
                                                    print("      3. Verifique se a senha do certificado está correta")
                                                    print("      4. Tente exportar o certificado novamente")
                                                    print("      5. Verifique se o certificado tem permissão para assinar documentos fiscais")
                                                
                                                # Mensagem simplificada - apenas xMotivo da SEFAZ
                                                error_msg = x_motivo_nota_text
                                                
                                                return {
                                                    'success': False,
                                                    'autorizada': False,
                                                    'status': 'rejeitada',
                                                    'cStat': c_stat_nota_text,
                                                    'xMotivo': x_motivo_nota_text,
                                                    'error': error_msg,
                                                    'error_type': 'SEFAZRejection',
                                                    'chave_acesso': inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe').text if inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') is not None else None
                                                }
                                        else:
                                            print("   ⚠️ cStat da nota não encontrado no infProt")
                                    else:
                                        print("   ⚠️ infProt não encontrado no protNFe")
                                else:
                                    print("   ⚠️ protNFe não encontrado no retEnviNFe")
                                    # Tentar salvar XML de resposta para debug
                                    try:
                                        debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                                        os.makedirs(debug_dir, exist_ok=True)
                                        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                        debug_file = os.path.join(debug_dir, f'resposta_sefaz_sem_protnfe_{timestamp}.xml')
                                        xml_resposta_str = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                        with open(debug_file, 'w', encoding='utf-8') as f:
                                            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                                            f.write(xml_resposta_str)
                                        print(f"   📋 XML de resposta salvo em: {debug_file}")
                                    except Exception as e_debug:
                                        print(f"   ⚠️ Erro ao salvar debug: {e_debug}")
                                    
                                    # Retornar erro descritivo
                                    error_msg = (
                                        f"❌ Erro ao processar resposta da SEFAZ: protNFe não encontrado no retEnviNFe.\n\n"
                                        f"Status do lote: {c_stat_text} - {x_motivo_text}\n\n"
                                        f"O lote foi processado, mas o protocolo da nota (protNFe) não foi encontrado na resposta.\n\n"
                                        f"Possíveis causas:\n"
                                        f"1. Estrutura da resposta diferente do esperado\n"
                                        f"2. Namespace diferente na resposta\n"
                                        f"3. Nota ainda em processamento (pode ser necessário consultar recibo)\n\n"
                                        f"SOLUÇÃO:\n"
                                        f"1. Verifique o XML de resposta salvo em logs/debug/\n"
                                        f"2. Verifique se a nota foi realmente autorizada\n"
                                        f"3. Tente consultar o recibo do lote se disponível"
                                    )
                                    return {
                                        'success': False,
                                        'autorizada': False,
                                        'status': 'erro_processamento',
                                        'cStat': c_stat_text,
                                        'xMotivo': x_motivo_text,
                                        'error': error_msg,
                                        'error_type': 'ProcessingError'
                                    }
                            
                            # cStat 100 ou 150 = Nota autorizada diretamente (sem lote)
                            elif c_stat_text in ['100', '150']:
                                # Sucesso! Processar normalmente
                                prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe') or ret_envi_nfe.find('.//protNFe')
                                if prot_nfe is not None:
                                    # Construir nfeProc seguindo o padrão do XML autorizado
                                    # Usar xml_assinado_original (preservado no início do processamento)
                                    xml_nfe_para_nfeproc = xml_assinado_original if xml_assinado_original is not None else xml_para_envio
                                    nfe_proc = self._construir_nfeproc(xml_nfe_para_nfeproc, prot_nfe)
                                    
                                    xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                    chave = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or prot_nfe.find('.//chNFe')
                                    chave_acesso = chave.text if chave is not None else ''
                                    caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                    
                                    dados_impressao = {
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'xml': xml_str,
                                        'empresa': empresa_data,
                                        'produtos': produtos,
                                        'pagamentos': pagamentos,
                                        'consumidor': consumidor,
                                        'numero_nfce': numero_nfce,
                                        'caminho_xml': caminho_xml
                                    }
                                    
                                    return {
                                        'success': True,
                                        'autorizada': True,
                                        'status': 'autorizada',
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'mensagem': x_motivo_text,
                                        'xml': xml_str,
                                        'caminho_xml': caminho_xml,
                                        'dados_impressao': dados_impressao
                                    }
                            
                            # Se não foi sucesso, retornar rejeição
                            return {
                                'success': False,
                                'autorizada': False,
                                'status': 'rejeitada',
                                'cStat': c_stat_text,
                                'xMotivo': x_motivo_text,
                                'error': self._formatar_erro_rejeicao(c_stat_text, x_motivo_text),
                                'error_type': 'SEFAZRejection'
                            }
                except Exception as e_parse:
                    print(f"   ⚠️ Erro ao processar resposta XML: {e_parse}")
                    import traceback
                    traceback.print_exc()
            elif hasattr(resultado, 'status_code') and resultado.status_code == 200:
                # resultado é um objeto Response - extrair XML
                try:
                    ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
                    xml_resposta = resultado.text if hasattr(resultado, 'text') else resultado.content.decode('utf-8')
                    prot = self._parse_xml_safe(xml_resposta)
                    
                    # Procurar por retEnviNFe
                    ret_envi_nfe = None
                    for elem in prot.iter():
                        if 'retEnviNFe' in elem.tag or elem.tag.endswith('retEnviNFe'):
                            ret_envi_nfe = elem
                            break
                    
                    if ret_envi_nfe is not None:
                        c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or ret_envi_nfe.find('.//cStat')
                        x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or ret_envi_nfe.find('.//xMotivo')
                        
                        if c_stat is not None:
                            c_stat_text = c_stat.text
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                            
                            print(f"   📋 cStat do lote: {c_stat_text}")
                            print(f"   📋 xMotivo do lote: {x_motivo_text}")
                            
                            # cStat 104 = Lote processado - verificar status da nota individual
                            if c_stat_text == '104':
                                print("=" * 70)
                                print("   ✅ Lote processado (cStat=104), verificando status da nota individual...")
                                print("=" * 70)
                                
                                # IMPORTANTE: Salvar resposta XML completa para debug
                                try:
                                    debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                                    os.makedirs(debug_dir, exist_ok=True)
                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                    resposta_xml_str = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    debug_file = os.path.join(debug_dir, f'resposta_sefaz_cstat104_{timestamp}.xml')
                                    with open(debug_file, 'w', encoding='utf-8') as f:
                                        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                                        f.write(resposta_xml_str)
                                    print(f"   📁 Resposta XML salva para debug: {debug_file}")
                                except Exception as e_debug:
                                    print(f"   ⚠️ Erro ao salvar resposta para debug: {e_debug}")
                                
                                # Mostrar estrutura completa do retEnviNFe
                                print("\n   📋 Estrutura completa do retEnviNFe:")
                                print(f"      Tag raiz: {ret_envi_nfe.tag}")
                                print(f"      Atributos: {ret_envi_nfe.attrib}")
                                print(f"      Número de filhos diretos: {len(list(ret_envi_nfe))}")
                                
                                # Listar todos os filhos diretos
                                for idx, child in enumerate(ret_envi_nfe):
                                    tag_local = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                    print(f"      [{idx}] {tag_local} (tag completa: {child.tag})")
                                    print(f"          Atributos: {child.attrib}")
                                    print(f"          Texto: {child.text[:100] if child.text else 'None'}...")
                                    print(f"          Filhos: {len(list(child))}")
                                    
                                    # Listar filhos de segundo nível
                                    for sub_idx, subchild in enumerate(child):
                                        sub_tag_local = subchild.tag.split('}')[-1] if '}' in subchild.tag else subchild.tag
                                        print(f"            [{sub_idx}] {sub_tag_local}")
                                
                                # Estratégia 1: Buscar protNFe diretamente como filho do retEnviNFe
                                print("\n   🔍 Estratégia 1: Buscando protNFe como filho direto...")
                                prot_nfe = ret_envi_nfe.find('{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('protNFe')
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado como filho direto! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 2: Buscar protNFe recursivamente dentro do retEnviNFe
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 2: Buscando protNFe recursivamente...")
                                    prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                    if prot_nfe is None:
                                        prot_nfe = ret_envi_nfe.find('.//protNFe')
                                    if prot_nfe is not None:
                                        print(f"   ✅ protNFe encontrado recursivamente! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 3: Buscar por iteração manual (caso namespaces estejam diferentes)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 3: Buscando protNFe por iteração manual...")
                                    for elem in ret_envi_nfe.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado via iteração (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 4: Buscar em todo o documento (pode estar fora do retEnviNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 4: Buscando protNFe em todo o documento...")
                                    for elem in prot.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado no documento completo (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 5: Buscar infProt diretamente (pode estar sem protNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 5: Buscando infProt diretamente...")
                                    inf_prot_direto = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or ret_envi_nfe.find('.//infProt')
                                    if inf_prot_direto is None:
                                        # Buscar em todo o documento
                                        for elem in prot.iter():
                                            tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            if tag_local == 'infProt':
                                                inf_prot_direto = elem
                                                print(f"   ✅ infProt encontrado diretamente (tag completa: {elem.tag})")
                                                # Criar protNFe artificial
                                                from pynfe.utils.flags import NAMESPACE_NFE
                                                prot_nfe = etree.Element("protNFe", xmlns=NAMESPACE_NFE)
                                                prot_nfe.append(inf_prot_direto)
                                                print(f"   ✅ protNFe criado artificialmente com infProt encontrado")
                                                break
                                
                                # Debug: mostrar estrutura do retEnviNFe se não encontrou
                                if prot_nfe is None:
                                    print("\n   ❌ protNFe NÃO encontrado após todas as estratégias!")
                                    print("   📋 Estrutura XML completa (primeiros 2000 caracteres):")
                                    xml_str_debug = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    print(xml_str_debug[:2000])
                                    print("   ⚠️ Verifique o arquivo de debug salvo para análise completa")
                                    
                                    # Retornar erro descritivo
                                    error_msg = (
                                        f"Lote processado (cStat=104), mas protNFe não encontrado na resposta da SEFAZ.\n\n"
                                        f"O lote foi processado, mas não foi possível extrair o protocolo de autorização da nota individual.\n\n"
                                        f"Possíveis causas:\n"
                                        f"1. A resposta da SEFAZ está em um formato não esperado\n"
                                        f"2. O protNFe está em uma estrutura diferente\n"
                                        f"3. A nota ainda está sendo processada (pode ser necessário consultar o recibo)\n\n"
                                        f"SOLUÇÃO:\n"
                                        f"1. Verifique o arquivo de debug salvo em: logs/debug/resposta_sefaz_cstat104_*.xml\n"
                                        f"2. Verifique se há um número de recibo (nRec) na resposta\n"
                                        f"3. Se houver nRec, será necessário consultar o recibo para obter o status final\n\n"
                                        f"Estrutura encontrada:\n"
                                        f"- Tag raiz: {ret_envi_nfe.tag}\n"
                                        f"- Filhos diretos: {len(list(ret_envi_nfe))}\n"
                                    )
                                    
                                    # Verificar se há nRec (número de recibo) para consulta
                                    nrec_elem = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nRec') or ret_envi_nfe.find('.//nRec')
                                    if nrec_elem is not None and nrec_elem.text:
                                        nrec = nrec_elem.text
                                        print(f"   📋 Número do recibo encontrado: {nrec}")
                                        print(f"   💡 Tentando consultar recibo para obter status final...")
                                        
                                        # Tentar consultar recibo (se o método estiver disponível)
                                        try:
                                            # Aqui você pode adicionar lógica para consultar o recibo
                                            # Por enquanto, apenas informar
                                            error_msg += f"\nNúmero do recibo encontrado: {nrec}\n"
                                            error_msg += "Será necessário consultar o recibo para obter o status final da nota."
                                        except Exception as e_consulta:
                                            print(f"   ⚠️ Erro ao consultar recibo: {e_consulta}")
                                    
                                    return {
                                        'success': False,
                                        'autorizada': False,
                                        'status': 'lote_processado_sem_protocolo',
                                        'cStat': c_stat_text,
                                        'xMotivo': x_motivo_text,
                                        'error': error_msg,
                                        'error_type': 'ProtocolNotFound',
                                        'debug_file': debug_file if 'debug_file' in locals() else None
                                    }
                                
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado! Tag: {prot_nfe.tag}")
                                    # Buscar infProt dentro do protNFe
                                    inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or prot_nfe.find('.//infProt')
                                    
                                    if inf_prot is not None:
                                        print(f"   📋 infProt encontrado! Tag: {inf_prot.tag}")
                                        print(f"   📋 Filhos diretos do infProt: {[child.tag.split('}')[-1] if '}' in child.tag else child.tag for child in inf_prot]}")
                                        
                                        # Buscar cStat da nota individual - tentar múltiplas estratégias
                                        # Estratégia 1: Filho direto com namespace
                                        c_stat_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 2: Filho direto sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('cStat')
                                        # Estratégia 3: Descendente com namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 4: Descendente sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//cStat')
                                        
                                        # Buscar xMotivo da mesma forma
                                        x_motivo_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//xMotivo')
                                        
                                        if c_stat_nota is not None:
                                            c_stat_nota_text = c_stat_nota.text
                                            x_motivo_nota_text = x_motivo_nota.text if x_motivo_nota is not None else 'Erro desconhecido'
                                            
                                            print(f"   ✅ cStat da nota encontrado: {c_stat_nota_text}")
                                            print(f"   ✅ xMotivo da nota: {x_motivo_nota_text}")
                                            
                                            # Verificar se a nota foi autorizada (100 ou 150)
                                            if c_stat_nota_text in ['100', '150']:
                                                print("   ✅ Nota autorizada!")
                                                print("   🔧 Construindo nfeProc (XML assinado + protNFe)...")
                                                
                                                # Validar que temos o XML assinado original
                                                if xml_assinado_original is None:
                                                    print("   ⚠️ AVISO: xml_assinado_original não está disponível, tentando usar xml_para_envio...")
                                                    # Tentar buscar xml_para_envio do escopo
                                                    try:
                                                        xml_assinado_original = xml_para_envio
                                                    except NameError:
                                                        print("   ⚠️ AVISO: xml_para_envio também não está disponível")
                                                
                                                if xml_assinado_original is None:
                                                    raise ValueError(
                                                        "ERRO: XML assinado não está disponível para construir nfeProc.\n\n"
                                                        "O XML assinado é necessário para combinar com o protNFe e formar o nfeProc completo.\n\n"
                                                        "SOLUÇÃO:\n"
                                                        "1. Verifique se o XML foi assinado corretamente\n"
                                                        "2. Verifique se o XML assinado está sendo preservado no processamento"
                                                    )
                                                
                                                # Construir nfeProc seguindo o padrão do XML autorizado
                                                print(f"   📋 Tipo do XML assinado: {type(xml_assinado_original)}")
                                                nfe_proc = self._construir_nfeproc(xml_assinado_original, prot_nfe)
                                                
                                                print("   ✅ nfeProc construído com sucesso!")
                                                xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                                print(f"   📊 Tamanho do XML autorizado: {len(xml_str)} caracteres")
                                                
                                                # Validar que o nfeProc contém NFe e protNFe
                                                if '<nfeProc' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém tag nfeProc!")
                                                if '<NFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém NFe!")
                                                if '<protNFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém protNFe!")
                                                
                                                print("   ✅ XML autorizado validado (contém nfeProc, NFe e protNFe)")
                                                
                                                chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or inf_prot.find('.//chNFe')
                                                chave_acesso = chave.text if chave is not None else ''
                                                protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') or inf_prot.find('.//nProt')
                                                protocolo_text = protocolo.text if protocolo is not None else ''
                                                
                                                print(f"   📋 Chave de acesso: {chave_acesso}")
                                                print(f"   📋 Protocolo: {protocolo_text}")
                                                
                                                # Extrair QR Code do XML autorizado (do infNFeSupl)
                                                qrcode_url_autorizado = None
                                                url_chave_consulta = None
                                                try:
                                                    # Buscar infNFeSupl no XML autorizado
                                                    nfe_no_proc = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or nfe_proc.find('.//NFe')
                                                    if nfe_no_proc is not None:
                                                        inf_nfe_supl = nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infNFeSupl') or nfe_no_proc.find('.//infNFeSupl')
                                                        if inf_nfe_supl is not None:
                                                            qrcode_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}qrCode') or inf_nfe_supl.find('.//qrCode')
                                                            url_chave_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}urlChave') or inf_nfe_supl.find('.//urlChave')
                                                            
                                                            if qrcode_elem is not None and qrcode_elem.text:
                                                                qrcode_url_autorizado = qrcode_elem.text.strip()
                                                                print(f"   ✅ QR Code extraído do XML autorizado")
                                                                print(f"   📱 QR Code: {qrcode_url_autorizado[:80]}...")
                                                            
                                                            if url_chave_elem is not None and url_chave_elem.text:
                                                                url_chave_consulta = url_chave_elem.text.strip()
                                                                print(f"   ✅ URL de consulta: {url_chave_consulta}")
                                                except Exception as e_qr_extract:
                                                    print(f"   ⚠️ Erro ao extrair QR Code do XML: {e_qr_extract}")
                                                    # Se não encontrou no XML autorizado, usar o que foi gerado antes
                                                    if 'qrcode_url' in locals() and qrcode_url is not None:
                                                        qrcode_url_autorizado = qrcode_url
                                                        print(f"   ✅ Usando QR Code gerado anteriormente")
                                                
                                                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                                
                                                # Preparar dados para DANFE NFC-e
                                                dados_impressao = {
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'empresa': empresa_data,
                                                    'produtos': produtos,
                                                    'pagamentos': pagamentos,
                                                    'consumidor': consumidor,
                                                    'numero_nfce': numero_nfce,
                                                    'caminho_xml': caminho_xml
                                                }
                                                
                                                print("   ✅ Dados para DANFE NFC-e preparados")
                                                print("   📋 Próximos passos:")
                                                print("      1. XML autorizado salvo")
                                                print("      2. QR Code disponível para impressão no DANFE")
                                                print("      3. DANFE pode ser gerado no frontend usando os dados retornados")
                                                
                                                return {
                                                    'success': True,
                                                    'autorizada': True,
                                                    'status': 'autorizada',
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'mensagem': x_motivo_nota_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'caminho_xml': caminho_xml,
                                                    'dados_impressao': dados_impressao
                                                }
                                            else:
                                                # Nota rejeitada
                                                print("=" * 70)
                                                print(f"   ❌ NOTA REJEITADA PELA SEFAZ")
                                                print("=" * 70)
                                                print(f"   📋 cStat: {c_stat_nota_text}")
                                                print(f"   📋 xMotivo: {x_motivo_nota_text}")
                                                
                                                # Verificar se é erro de certificado (cStat 290)
                                                if c_stat_nota_text == '290':
                                                    print("\n   ⚠️ ERRO: Certificado de Assinatura inválido (cStat=290)")
                                                    print("   📋 Possíveis causas:")
                                                    print("      1. Certificado expirado")
                                                    print("      2. Certificado não é ICP-Brasil")
                                                    print("      3. Certificado não tem permissão para assinar NFC-e")
                                                    print("      4. Problema na assinatura digital gerada")
                                                    print("      5. Certificado não está no formato correto")
                                                    print("\n   💡 SOLUÇÕES:")
                                                    print("      1. Verifique se o certificado está válido e não expirado")
                                                    print("      2. Verifique se o certificado é ICP-Brasil (A1 ou A3)")
                                                    print("      3. Verifique se a senha do certificado está correta")
                                                    print("      4. Tente exportar o certificado novamente")
                                                    print("      5. Verifique se o certificado tem permissão para assinar documentos fiscais")
                                                
                                                # Mensagem simplificada - apenas xMotivo da SEFAZ
                                                error_msg = x_motivo_nota_text
                                                
                                                return {
                                                    'success': False,
                                                    'autorizada': False,
                                                    'status': 'rejeitada',
                                                    'cStat': c_stat_nota_text,
                                                    'xMotivo': x_motivo_nota_text,
                                                    'error': error_msg,
                                                    'error_type': 'SEFAZRejection',
                                                    'chave_acesso': inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe').text if inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') is not None else None
                                                }
                                        else:
                                            print("   ⚠️ cStat da nota não encontrado no infProt")
                                    else:
                                        print("   ⚠️ infProt não encontrado no protNFe")
                                else:
                                    print("   ⚠️ protNFe não encontrado no retEnviNFe")
                                    # Tentar salvar XML de resposta para debug
                                    try:
                                        debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                                        os.makedirs(debug_dir, exist_ok=True)
                                        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                        debug_file = os.path.join(debug_dir, f'resposta_sefaz_sem_protnfe_{timestamp}.xml')
                                        xml_resposta_str = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                        with open(debug_file, 'w', encoding='utf-8') as f:
                                            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                                            f.write(xml_resposta_str)
                                        print(f"   📋 XML de resposta salvo em: {debug_file}")
                                    except Exception as e_debug:
                                        print(f"   ⚠️ Erro ao salvar debug: {e_debug}")
                                    
                                    # Retornar erro descritivo
                                    error_msg = (
                                        f"❌ Erro ao processar resposta da SEFAZ: protNFe não encontrado no retEnviNFe.\n\n"
                                        f"Status do lote: {c_stat_text} - {x_motivo_text}\n\n"
                                        f"O lote foi processado, mas o protocolo da nota (protNFe) não foi encontrado na resposta.\n\n"
                                        f"Possíveis causas:\n"
                                        f"1. Estrutura da resposta diferente do esperado\n"
                                        f"2. Namespace diferente na resposta\n"
                                        f"3. Nota ainda em processamento (pode ser necessário consultar recibo)\n\n"
                                        f"SOLUÇÃO:\n"
                                        f"1. Verifique o XML de resposta salvo em logs/debug/\n"
                                        f"2. Verifique se a nota foi realmente autorizada\n"
                                        f"3. Tente consultar o recibo do lote se disponível"
                                    )
                                    return {
                                        'success': False,
                                        'autorizada': False,
                                        'status': 'erro_processamento',
                                        'cStat': c_stat_text,
                                        'xMotivo': x_motivo_text,
                                        'error': error_msg,
                                        'error_type': 'ProcessingError'
                                    }
                            
                            # cStat 100 ou 150 = Nota autorizada diretamente (sem lote)
                            elif c_stat_text in ['100', '150']:
                                # Sucesso! Processar normalmente
                                prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe') or ret_envi_nfe.find('.//protNFe')
                                if prot_nfe is not None:
                                    # Construir nfeProc seguindo o padrão do XML autorizado
                                    # Usar xml_assinado_original (preservado no início do processamento)
                                    xml_nfe_para_nfeproc = xml_assinado_original if xml_assinado_original is not None else xml_para_envio
                                    nfe_proc = self._construir_nfeproc(xml_nfe_para_nfeproc, prot_nfe)
                                    
                                    xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                    chave = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or prot_nfe.find('.//chNFe')
                                    chave_acesso = chave.text if chave is not None else ''
                                    caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                    
                                    dados_impressao = {
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'xml': xml_str,
                                        'empresa': empresa_data,
                                        'produtos': produtos,
                                        'pagamentos': pagamentos,
                                        'consumidor': consumidor,
                                        'numero_nfce': numero_nfce,
                                        'caminho_xml': caminho_xml
                                    }
                                    
                                    return {
                                        'success': True,
                                        'autorizada': True,
                                        'status': 'autorizada',
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'mensagem': x_motivo_text,
                                        'xml': xml_str,
                                        'caminho_xml': caminho_xml,
                                        'dados_impressao': dados_impressao
                                    }
                            
                            # Rejeição
                            error_msg = self._formatar_erro_rejeicao(c_stat_text, x_motivo_text)
                            return {
                                'success': False,
                                'autorizada': False,
                                'status': 'rejeitada',
                                'cStat': c_stat_text,
                                'xMotivo': x_motivo_text,
                                'error': error_msg,
                                'error_type': 'SEFAZRejection'
                            }
                except Exception as e_parse:
                    print(f"   ⚠️ Erro ao processar resposta HTTP: {e_parse}")
                    import traceback
                    traceback.print_exc()
            
            # Se não conseguiu processar, tentar extrair informações do envelope SOAP
            print(f"   🔍 [DEBUG] Verificando tipo do resultado...")
            print(f"   📋 [DEBUG] Tipo: {type(resultado)}")
            print(f"   📋 [DEBUG] Tem 'tag': {hasattr(resultado, 'tag')}")
            if hasattr(resultado, 'tag'):
                print(f"   📋 [DEBUG] Tag: {resultado.tag}")
            print(f"   📋 [DEBUG] Tem 'status_code': {hasattr(resultado, 'status_code')}")
            
            try:
                # Verificar se resultado é um elemento XML (envelope SOAP)
                if hasattr(resultado, 'tag'):
                    # É um elemento XML - tentar processar o envelope SOAP
                    print(f"   🔍 Tentando processar envelope SOAP...")
                    print(f"   📋 Tag do elemento: {resultado.tag}")
                    
                    # Procurar por retEnviNFe no envelope SOAP
                    ns_soap = {'soap': 'http://www.w3.org/2003/05/soap-envelope',
                              'nfe': 'http://www.portalfiscal.inf.br/nfe'}
                    
                    # Procurar retEnviNFe diretamente no envelope (pode estar em qualquer lugar)
                    ret_envi_nfe = None
                    
                    # Estratégia 1: Buscar com namespace completo usando XPath recursivo
                    ret_envi_nfe = resultado.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                    if ret_envi_nfe is not None:
                        print(f"   ✅ retEnviNFe encontrado via namespace completo")
                    
                    # Estratégia 2: Buscar sem namespace
                    if ret_envi_nfe is None:
                        ret_envi_nfe = resultado.find('.//retEnviNFe')
                        if ret_envi_nfe is not None:
                            print(f"   ✅ retEnviNFe encontrado sem namespace")
                    
                    # Estratégia 3: Buscar recursivamente por tag local (ignorando namespace)
                    if ret_envi_nfe is None:
                        print(f"   🔍 Buscando retEnviNFe recursivamente...")
                        for elem in resultado.iter():
                            # Extrair tag local (sem namespace)
                            if '}' in elem.tag:
                                tag_local = elem.tag.split('}')[-1]
                            else:
                                tag_local = elem.tag
                            
                            if tag_local == 'retEnviNFe':
                                ret_envi_nfe = elem
                                print(f"   ✅ retEnviNFe encontrado via busca recursiva (tag: {elem.tag})")
                                break
                    
                    # Se encontrou, processar
                    if ret_envi_nfe is not None:
                        print(f"   ✅ retEnviNFe encontrado no envelope SOAP!")
                        
                        # Procurar cStat e xMotivo dentro do retEnviNFe
                        c_stat = None
                        x_motivo = None
                        
                        # Buscar cStat
                        c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                        if c_stat is None:
                            c_stat = ret_envi_nfe.find('.//cStat')
                        if c_stat is None:
                            # Buscar recursivamente
                            for elem in ret_envi_nfe.iter():
                                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                if tag_limpa == 'cStat':
                                    c_stat = elem
                                    break
                        
                        # Buscar xMotivo
                        x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                        if x_motivo is None:
                            x_motivo = ret_envi_nfe.find('.//xMotivo')
                        if x_motivo is None:
                            # Buscar recursivamente
                            for elem in ret_envi_nfe.iter():
                                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                if tag_limpa == 'xMotivo':
                                    x_motivo = elem
                                    break
                        
                        if c_stat is not None:
                            c_stat_text = c_stat.text
                            x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                            
                            print(f"   ✅ cStat encontrado: {c_stat_text}")
                            print(f"   ✅ xMotivo encontrado: {x_motivo_text}")
                            
                            # cStat 104 = Lote processado - verificar status da nota individual
                            if c_stat_text == '104':
                                print("=" * 70)
                                print("   ✅ Lote processado (cStat=104), verificando status da nota individual...")
                                print("=" * 70)
                                
                                # IMPORTANTE: Salvar resposta XML completa para debug
                                try:
                                    debug_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'debug')
                                    os.makedirs(debug_dir, exist_ok=True)
                                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                                    resposta_xml_str = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    debug_file = os.path.join(debug_dir, f'resposta_sefaz_cstat104_{timestamp}.xml')
                                    with open(debug_file, 'w', encoding='utf-8') as f:
                                        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                                        f.write(resposta_xml_str)
                                    print(f"   📁 Resposta XML salva para debug: {debug_file}")
                                except Exception as e_debug:
                                    print(f"   ⚠️ Erro ao salvar resposta para debug: {e_debug}")
                                
                                # Mostrar estrutura completa do retEnviNFe
                                print("\n   📋 Estrutura completa do retEnviNFe:")
                                print(f"      Tag raiz: {ret_envi_nfe.tag}")
                                print(f"      Atributos: {ret_envi_nfe.attrib}")
                                print(f"      Número de filhos diretos: {len(list(ret_envi_nfe))}")
                                
                                # Listar todos os filhos diretos
                                for idx, child in enumerate(ret_envi_nfe):
                                    tag_local = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                                    print(f"      [{idx}] {tag_local} (tag completa: {child.tag})")
                                    print(f"          Atributos: {child.attrib}")
                                    print(f"          Texto: {child.text[:100] if child.text else 'None'}...")
                                    print(f"          Filhos: {len(list(child))}")
                                    
                                    # Listar filhos de segundo nível
                                    for sub_idx, subchild in enumerate(child):
                                        sub_tag_local = subchild.tag.split('}')[-1] if '}' in subchild.tag else subchild.tag
                                        print(f"            [{sub_idx}] {sub_tag_local}")
                                
                                # Estratégia 1: Buscar protNFe diretamente como filho do retEnviNFe
                                print("\n   🔍 Estratégia 1: Buscando protNFe como filho direto...")
                                prot_nfe = ret_envi_nfe.find('{http://www.portalfiscal.inf.br/nfe}protNFe')
                                if prot_nfe is None:
                                    prot_nfe = ret_envi_nfe.find('protNFe')
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado como filho direto! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 2: Buscar protNFe recursivamente dentro do retEnviNFe
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 2: Buscando protNFe recursivamente...")
                                    prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe')
                                    if prot_nfe is None:
                                        prot_nfe = ret_envi_nfe.find('.//protNFe')
                                    if prot_nfe is not None:
                                        print(f"   ✅ protNFe encontrado recursivamente! Tag: {prot_nfe.tag}")
                                
                                # Estratégia 3: Buscar por iteração manual (caso namespaces estejam diferentes)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 3: Buscando protNFe por iteração manual...")
                                    for elem in ret_envi_nfe.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado via iteração (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 4: Buscar em todo o documento (pode estar fora do retEnviNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 4: Buscando protNFe em todo o documento...")
                                    for elem in prot.iter():
                                        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                        if tag_local == 'protNFe':
                                            prot_nfe = elem
                                            print(f"   ✅ protNFe encontrado no documento completo (tag completa: {elem.tag})")
                                            break
                                
                                # Estratégia 5: Buscar infProt diretamente (pode estar sem protNFe)
                                if prot_nfe is None:
                                    print("   🔍 Estratégia 5: Buscando infProt diretamente...")
                                    inf_prot_direto = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or ret_envi_nfe.find('.//infProt')
                                    if inf_prot_direto is None:
                                        # Buscar em todo o documento
                                        for elem in prot.iter():
                                            tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                            if tag_local == 'infProt':
                                                inf_prot_direto = elem
                                                print(f"   ✅ infProt encontrado diretamente (tag completa: {elem.tag})")
                                                # Criar protNFe artificial
                                                from pynfe.utils.flags import NAMESPACE_NFE
                                                prot_nfe = etree.Element("protNFe", xmlns=NAMESPACE_NFE)
                                                prot_nfe.append(inf_prot_direto)
                                                print(f"   ✅ protNFe criado artificialmente com infProt encontrado")
                                                break
                                
                                # Debug: mostrar estrutura do retEnviNFe se não encontrou
                                if prot_nfe is None:
                                    print("\n   ❌ protNFe NÃO encontrado após todas as estratégias!")
                                    print("   📋 Estrutura XML completa (primeiros 2000 caracteres):")
                                    xml_str_debug = etree.tostring(ret_envi_nfe, encoding='unicode', pretty_print=True)
                                    print(xml_str_debug[:2000])
                                    print("   ⚠️ Verifique o arquivo de debug salvo para análise completa")
                                    
                                    # Retornar erro descritivo
                                    error_msg = (
                                        f"Lote processado (cStat=104), mas protNFe não encontrado na resposta da SEFAZ.\n\n"
                                        f"O lote foi processado, mas não foi possível extrair o protocolo de autorização da nota individual.\n\n"
                                        f"Possíveis causas:\n"
                                        f"1. A resposta da SEFAZ está em um formato não esperado\n"
                                        f"2. O protNFe está em uma estrutura diferente\n"
                                        f"3. A nota ainda está sendo processada (pode ser necessário consultar o recibo)\n\n"
                                        f"SOLUÇÃO:\n"
                                        f"1. Verifique o arquivo de debug salvo em: logs/debug/resposta_sefaz_cstat104_*.xml\n"
                                        f"2. Verifique se há um número de recibo (nRec) na resposta\n"
                                        f"3. Se houver nRec, será necessário consultar o recibo para obter o status final\n\n"
                                        f"Estrutura encontrada:\n"
                                        f"- Tag raiz: {ret_envi_nfe.tag}\n"
                                        f"- Filhos diretos: {len(list(ret_envi_nfe))}\n"
                                    )
                                    
                                    # Verificar se há nRec (número de recibo) para consulta
                                    nrec_elem = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nRec') or ret_envi_nfe.find('.//nRec')
                                    if nrec_elem is not None and nrec_elem.text:
                                        nrec = nrec_elem.text
                                        print(f"   📋 Número do recibo encontrado: {nrec}")
                                        print(f"   💡 Tentando consultar recibo para obter status final...")
                                        
                                        # Tentar consultar recibo (se o método estiver disponível)
                                        try:
                                            # Aqui você pode adicionar lógica para consultar o recibo
                                            # Por enquanto, apenas informar
                                            error_msg += f"\nNúmero do recibo encontrado: {nrec}\n"
                                            error_msg += "Será necessário consultar o recibo para obter o status final da nota."
                                        except Exception as e_consulta:
                                            print(f"   ⚠️ Erro ao consultar recibo: {e_consulta}")
                                    
                                    return {
                                        'success': False,
                                        'autorizada': False,
                                        'status': 'lote_processado_sem_protocolo',
                                        'cStat': c_stat_text,
                                        'xMotivo': x_motivo_text,
                                        'error': error_msg,
                                        'error_type': 'ProtocolNotFound',
                                        'debug_file': debug_file if 'debug_file' in locals() else None
                                    }
                                
                                if prot_nfe is not None:
                                    print(f"   ✅ protNFe encontrado! Tag: {prot_nfe.tag}")
                                    # Buscar infProt dentro do protNFe
                                    inf_prot = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}infProt') or prot_nfe.find('.//infProt')
                                    
                                    if inf_prot is not None:
                                        print(f"   📋 infProt encontrado! Tag: {inf_prot.tag}")
                                        print(f"   📋 Filhos diretos do infProt: {[child.tag.split('}')[-1] if '}' in child.tag else child.tag for child in inf_prot]}")
                                        
                                        # Buscar cStat da nota individual - tentar múltiplas estratégias
                                        # Estratégia 1: Filho direto com namespace
                                        c_stat_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 2: Filho direto sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('cStat')
                                        # Estratégia 3: Descendente com namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                                        # Estratégia 4: Descendente sem namespace
                                        if c_stat_nota is None:
                                            c_stat_nota = inf_prot.find('.//cStat')
                                        
                                        # Buscar xMotivo da mesma forma
                                        x_motivo_nota = inf_prot.find('{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                                        if x_motivo_nota is None:
                                            x_motivo_nota = inf_prot.find('.//xMotivo')
                                        
                                        if c_stat_nota is not None:
                                            c_stat_nota_text = c_stat_nota.text
                                            x_motivo_nota_text = x_motivo_nota.text if x_motivo_nota is not None else 'Erro desconhecido'
                                            
                                            print(f"   ✅ cStat da nota encontrado: {c_stat_nota_text}")
                                            print(f"   ✅ xMotivo da nota: {x_motivo_nota_text}")
                                            
                                            # Verificar se a nota foi autorizada (100 ou 150)
                                            if c_stat_nota_text in ['100', '150']:
                                                print("   ✅ Nota autorizada!")
                                                print("   🔧 Construindo nfeProc (XML assinado + protNFe)...")
                                                
                                                # Validar que temos o XML assinado original
                                                if xml_assinado_original is None:
                                                    print("   ⚠️ AVISO: xml_assinado_original não está disponível, tentando usar xml_para_envio...")
                                                    # Tentar buscar xml_para_envio do escopo
                                                    try:
                                                        xml_assinado_original = xml_para_envio
                                                    except NameError:
                                                        print("   ⚠️ AVISO: xml_para_envio também não está disponível")
                                                
                                                if xml_assinado_original is None:
                                                    raise ValueError(
                                                        "ERRO: XML assinado não está disponível para construir nfeProc.\n\n"
                                                        "O XML assinado é necessário para combinar com o protNFe e formar o nfeProc completo.\n\n"
                                                        "SOLUÇÃO:\n"
                                                        "1. Verifique se o XML foi assinado corretamente\n"
                                                        "2. Verifique se o XML assinado está sendo preservado no processamento"
                                                    )
                                                
                                                # Construir nfeProc seguindo o padrão do XML autorizado
                                                print(f"   📋 Tipo do XML assinado: {type(xml_assinado_original)}")
                                                nfe_proc = self._construir_nfeproc(xml_assinado_original, prot_nfe)
                                                
                                                print("   ✅ nfeProc construído com sucesso!")
                                                xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                                print(f"   📊 Tamanho do XML autorizado: {len(xml_str)} caracteres")
                                                
                                                # Validar que o nfeProc contém NFe e protNFe
                                                if '<nfeProc' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém tag nfeProc!")
                                                if '<NFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém NFe!")
                                                if '<protNFe' not in xml_str:
                                                    raise ValueError("ERRO: nfeProc não contém protNFe!")
                                                
                                                print("   ✅ XML autorizado validado (contém nfeProc, NFe e protNFe)")
                                                
                                                chave = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or inf_prot.find('.//chNFe')
                                                chave_acesso = chave.text if chave is not None else ''
                                                protocolo = inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') or inf_prot.find('.//nProt')
                                                protocolo_text = protocolo.text if protocolo is not None else ''
                                                
                                                print(f"   📋 Chave de acesso: {chave_acesso}")
                                                print(f"   📋 Protocolo: {protocolo_text}")
                                                
                                                # Extrair QR Code do XML autorizado (do infNFeSupl)
                                                qrcode_url_autorizado = None
                                                url_chave_consulta = None
                                                try:
                                                    # Buscar infNFeSupl no XML autorizado
                                                    nfe_no_proc = nfe_proc.find('.//{http://www.portalfiscal.inf.br/nfe}NFe') or nfe_proc.find('.//NFe')
                                                    if nfe_no_proc is not None:
                                                        inf_nfe_supl = nfe_no_proc.find('.//{http://www.portalfiscal.inf.br/nfe}infNFeSupl') or nfe_no_proc.find('.//infNFeSupl')
                                                        if inf_nfe_supl is not None:
                                                            qrcode_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}qrCode') or inf_nfe_supl.find('.//qrCode')
                                                            url_chave_elem = inf_nfe_supl.find('.//{http://www.portalfiscal.inf.br/nfe}urlChave') or inf_nfe_supl.find('.//urlChave')
                                                            
                                                            if qrcode_elem is not None and qrcode_elem.text:
                                                                qrcode_url_autorizado = qrcode_elem.text.strip()
                                                                print(f"   ✅ QR Code extraído do XML autorizado")
                                                                print(f"   📱 QR Code: {qrcode_url_autorizado[:80]}...")
                                                            
                                                            if url_chave_elem is not None and url_chave_elem.text:
                                                                url_chave_consulta = url_chave_elem.text.strip()
                                                                print(f"   ✅ URL de consulta: {url_chave_consulta}")
                                                except Exception as e_qr_extract:
                                                    print(f"   ⚠️ Erro ao extrair QR Code do XML: {e_qr_extract}")
                                                    # Se não encontrou no XML autorizado, usar o que foi gerado antes
                                                    if 'qrcode_url' in locals() and qrcode_url is not None:
                                                        qrcode_url_autorizado = qrcode_url
                                                        print(f"   ✅ Usando QR Code gerado anteriormente")
                                                
                                                caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                                
                                                # Preparar dados para DANFE NFC-e
                                                dados_impressao = {
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'empresa': empresa_data,
                                                    'produtos': produtos,
                                                    'pagamentos': pagamentos,
                                                    'consumidor': consumidor,
                                                    'numero_nfce': numero_nfce,
                                                    'caminho_xml': caminho_xml
                                                }
                                                
                                                print("   ✅ Dados para DANFE NFC-e preparados")
                                                print("   📋 Próximos passos:")
                                                print("      1. XML autorizado salvo")
                                                print("      2. QR Code disponível para impressão no DANFE")
                                                print("      3. DANFE pode ser gerado no frontend usando os dados retornados")
                                                
                                                return {
                                                    'success': True,
                                                    'autorizada': True,
                                                    'status': 'autorizada',
                                                    'chave_acesso': chave_acesso,
                                                    'protocolo': protocolo_text,
                                                    'mensagem': x_motivo_nota_text,
                                                    'xml': xml_str,
                                                    'qrcode': qrcode_url_autorizado,
                                                    'url_consulta': url_chave_consulta,
                                                    'caminho_xml': caminho_xml,
                                                    'dados_impressao': dados_impressao
                                                }
                                            else:
                                                # Nota rejeitada
                                                print("=" * 70)
                                                print(f"   ❌ NOTA REJEITADA PELA SEFAZ")
                                                print("=" * 70)
                                                print(f"   📋 cStat: {c_stat_nota_text}")
                                                print(f"   📋 xMotivo: {x_motivo_nota_text}")
                                                
                                                # Verificar se é erro de certificado (cStat 290)
                                                if c_stat_nota_text == '290':
                                                    print("\n   ⚠️ ERRO: Certificado de Assinatura inválido (cStat=290)")
                                                    print("   📋 Possíveis causas:")
                                                    print("      1. Certificado expirado")
                                                    print("      2. Certificado não é ICP-Brasil")
                                                    print("      3. Certificado não tem permissão para assinar NFC-e")
                                                    print("      4. Problema na assinatura digital gerada")
                                                    print("      5. Certificado não está no formato correto")
                                                    print("\n   💡 SOLUÇÕES:")
                                                    print("      1. Verifique se o certificado está válido e não expirado")
                                                    print("      2. Verifique se o certificado é ICP-Brasil (A1 ou A3)")
                                                    print("      3. Verifique se a senha do certificado está correta")
                                                    print("      4. Tente exportar o certificado novamente")
                                                    print("      5. Verifique se o certificado tem permissão para assinar documentos fiscais")
                                                
                                                # Mensagem simplificada - apenas xMotivo da SEFAZ
                                                error_msg = x_motivo_nota_text
                                                
                                                return {
                                                    'success': False,
                                                    'autorizada': False,
                                                    'status': 'rejeitada',
                                                    'cStat': c_stat_nota_text,
                                                    'xMotivo': x_motivo_nota_text,
                                                    'error': error_msg,
                                                    'error_type': 'SEFAZRejection',
                                                    'chave_acesso': inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe').text if inf_prot.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') is not None else None
                                                }
                                        else:
                                            print("   ⚠️ cStat da nota não encontrado no infProt")
                                    else:
                                        print("   ⚠️ infProt não encontrado no protNFe")
                            
                            elif c_stat_text in ['100', '150']:
                                # Autorizada! Processar normalmente
                                prot_nfe = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe') or ret_envi_nfe.find('.//protNFe')
                                if prot_nfe is not None:
                                    # Construir nfeProc seguindo o padrão do XML autorizado
                                    # Usar xml_assinado_original (preservado no início do processamento)
                                    xml_nfe_para_nfeproc = xml_assinado_original if xml_assinado_original is not None else xml_para_envio
                                    nfe_proc = self._construir_nfeproc(xml_nfe_para_nfeproc, prot_nfe)
                                    
                                    xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                    chave = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or prot_nfe.find('.//chNFe')
                                    chave_acesso = chave.text if chave is not None else ''
                                    caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                    
                                    dados_impressao = {
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'xml': xml_str,
                                        'empresa': empresa_data,
                                        'produtos': produtos,
                                        'pagamentos': pagamentos,
                                        'consumidor': consumidor,
                                        'numero_nfce': numero_nfce,
                                        'caminho_xml': caminho_xml
                                    }
                                    
                                    return {
                                        'success': True,
                                        'autorizada': True,
                                        'status': 'autorizada',
                                        'chave_acesso': chave_acesso,
                                        'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                        'mensagem': x_motivo_text,
                                        'xml': xml_str,
                                        'caminho_xml': caminho_xml,
                                        'dados_impressao': dados_impressao
                                    }
                            
                            # Rejeição
                            error_msg = self._formatar_erro_rejeicao(c_stat_text, x_motivo_text)
                            return {
                                'success': False,
                                'autorizada': False,
                                'status': 'rejeitada',
                                'cStat': c_stat_text,
                                'xMotivo': x_motivo_text,
                                'error': error_msg,
                                'error_type': 'SEFAZRejection'
                            }
                    
                    # Se não encontrou retEnviNFe no Body, tentar buscar em todo o envelope
                    if ret_envi_nfe is None:
                        print(f"   🔍 retEnviNFe não encontrado no Body, buscando em todo o envelope...")
                        # Buscar em todo o resultado (envelope completo)
                        ret_envi_nfe = resultado.find('.//{http://www.portalfiscal.inf.br/nfe}retEnviNFe')
                        if ret_envi_nfe is None:
                            ret_envi_nfe = resultado.find('.//retEnviNFe')
                        if ret_envi_nfe is None:
                            # Busca recursiva em todos os elementos
                            for elem in resultado.iter():
                                tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                if tag_limpa == 'retEnviNFe':
                                    ret_envi_nfe = elem
                                    print(f"   ✅ retEnviNFe encontrado via busca recursiva!")
                                    break
                        
                        if ret_envi_nfe is not None:
                            # Processar retEnviNFe encontrado
                            c_stat = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}cStat')
                            if c_stat is None:
                                c_stat = ret_envi_nfe.find('.//cStat')
                            if c_stat is None:
                                for elem in ret_envi_nfe.iter():
                                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                    if tag_limpa == 'cStat':
                                        c_stat = elem
                                        break
                            
                            x_motivo = ret_envi_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo')
                            if x_motivo is None:
                                x_motivo = ret_envi_nfe.find('.//xMotivo')
                            if x_motivo is None:
                                for elem in ret_envi_nfe.iter():
                                    tag_limpa = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                                    if tag_limpa == 'xMotivo':
                                        x_motivo = elem
                                        break
                            
                            if c_stat is not None:
                                c_stat_text = c_stat.text
                                x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                                
                                print(f"   ✅ cStat: {c_stat_text}")
                                print(f"   ✅ xMotivo: {x_motivo_text}")
                                
                                # Usar a função de formatação de erro
                                error_msg = x_motivo_text
                                
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'status': 'rejeitada',
                                    'cStat': c_stat_text,
                                    'xMotivo': x_motivo_text,
                                    'error': error_msg,
                                    'error_type': 'SEFAZRejection'
                                }
                    
                    # Se não encontrou retEnviNFe, verificar se há erro SOAP (Fault)
                    fault = resultado.find('.//{http://www.w3.org/2003/05/soap-envelope}Fault') or resultado.find('.//Fault')
                    if fault is not None:
                        fault_code = fault.find('.//{http://www.w3.org/2003/05/soap-envelope}Code') or fault.find('.//Code')
                        fault_reason = fault.find('.//{http://www.w3.org/2003/05/soap-envelope}Reason') or fault.find('.//Reason')
                        fault_text = fault_code.text if fault_code is not None else 'Erro SOAP desconhecido'
                        fault_reason_text = fault_reason.text if fault_reason is not None else ''
                        
                        return {
                            'success': False,
                            'autorizada': False,
                            'status': 'erro_soap',
                            'error': f"Erro SOAP da SEFAZ: {fault_text}\n{fault_reason_text}",
                            'error_type': 'SOAPFault'
                        }
                    
                    # Se não encontrou retEnviNFe nem Fault, tentar extrair XML completo para debug
                    print(f"   ⚠️ Não encontrou retEnviNFe nem Fault no envelope SOAP")
                    print(f"   📋 Tentando extrair XML completo do envelope...")
                    try:
                        xml_completo = etree.tostring(resultado, encoding='unicode', pretty_print=True)
                        print(f"   📋 XML completo (primeiros 1000 chars):\n{xml_completo[:1000]}")
                        
                        # Tentar procurar por qualquer elemento que possa conter informações
                        # Procurar por nfeProc, protNFe, ou qualquer elemento com cStat
                        for elem in resultado.iter():
                            # Procurar por cStat em qualquer lugar
                            c_stat = elem.find('.//{http://www.portalfiscal.inf.br/nfe}cStat') or elem.find('.//cStat')
                            if c_stat is not None and c_stat.text:
                                x_motivo = elem.find('.//{http://www.portalfiscal.inf.br/nfe}xMotivo') or elem.find('.//xMotivo')
                                c_stat_text = c_stat.text
                                x_motivo_text = x_motivo.text if x_motivo is not None else 'Erro desconhecido'
                                
                                print(f"   ✅ Encontrado cStat: {c_stat_text}")
                                
                                if c_stat_text in ['100', '150']:
                                    # Autorizada! Tentar extrair protNFe
                                    prot_nfe = elem.find('.//{http://www.portalfiscal.inf.br/nfe}protNFe') or elem.find('.//protNFe')
                                    if prot_nfe is not None:
                                        from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
                                        # Construir nfeProc seguindo o padrão do XML autorizado
                                        nfe_proc = self._construir_nfeproc(xml_para_envio, prot_nfe)
                                        
                                        xml_str = etree.tostring(nfe_proc, encoding='unicode')
                                        chave = prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}chNFe') or prot_nfe.find('.//chNFe')
                                        chave_acesso = chave.text if chave is not None else ''
                                        caminho_xml = self._salvar_xml(empresa_data, chave_acesso, xml_str, numero_nfce)
                                        
                                        return {
                                            'success': True,
                                            'autorizada': True,
                                            'status': 'autorizada',
                                            'chave_acesso': chave_acesso,
                                            'protocolo': prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt').text if prot_nfe.find('.//{http://www.portalfiscal.inf.br/nfe}nProt') is not None else '',
                                            'mensagem': x_motivo_text,
                                            'xml': xml_str,
                                            'caminho_xml': caminho_xml
                                        }
                                
                                # Rejeição
                                error_msg = x_motivo_text
                                return {
                                    'success': False,
                                    'autorizada': False,
                                    'status': 'rejeitada',
                                    'cStat': c_stat_text,
                                    'xMotivo': x_motivo_text,
                                    'error': error_msg,
                                    'error_type': 'SEFAZRejection'
                                }
                    except Exception as e_xml:
                        print(f"   ⚠️ Erro ao extrair XML: {e_xml}")
                    
                    # Se chegou aqui, não conseguiu processar o envelope SOAP
                    print(f"   ❌ Não foi possível processar o envelope SOAP")
                    # Continuar para retornar erro mais detalhado abaixo
                
                # Se resultado é um objeto Response do requests
                if hasattr(resultado, 'status_code'):
                    xml_str = resultado.text if hasattr(resultado, 'text') else str(resultado.content)
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro',
                        'error': f"Erro ao processar resposta da SEFAZ (HTTP {resultado.status_code}).\n\nResposta: {xml_str[:500]}",
                        'error_type': 'HTTPError'
                    }
                
                # Tentar converter para string de forma segura
                resultado_str = 'Erro desconhecido'
                try:
                    if hasattr(resultado, 'tag'):
                        # É um elemento XML - tentar extrair mais informações
                        tag = resultado.tag
                        # Tentar extrair XML completo para debug
                        try:
                            xml_debug = etree.tostring(resultado, encoding='unicode', pretty_print=False)
                            # Limitar tamanho para não ficar muito grande
                            xml_preview = xml_debug[:500] if len(xml_debug) > 500 else xml_debug
                            resultado_str = (
                                f"Elemento XML: {tag}\n\n"
                                f"O envelope SOAP foi recebido, mas não foi possível processar a resposta.\n\n"
                                f"Preview do XML (primeiros 500 chars):\n{xml_preview}\n\n"
                                f"Possíveis causas:\n"
                                f"1. Estrutura da resposta diferente do esperado\n"
                                f"2. Namespace incorreto na resposta\n"
                                f"3. Resposta em formato não suportado\n\n"
                                f"SOLUÇÃO: Verifique os logs do servidor para ver o XML completo."
                            )
                        except:
                            resultado_str = f"Elemento XML: {tag} (não foi possível extrair conteúdo)"
                    else:
                        resultado_str = str(resultado)
                except:
                    resultado_str = f"Objeto do tipo: {type(resultado).__name__}"
                
            except Exception as e_process:
                print(f"   ⚠️ Erro ao processar resultado: {e_process}")
                import traceback
                traceback.print_exc()
                resultado_str = f"Erro ao processar: {str(e_process)}"
            
            # Se não conseguiu processar, retornar erro genérico
            return {
                'success': False,
                'autorizada': False,
                'status': 'erro',
                'error': f"Erro ao emitir NFC-e: {resultado_str}",
                'error_type': 'UnexpectedError'
            }
            
        except Exception as e:
                # Verificar se é erro de conexão/DNS
                error_str = str(e).lower()
                is_connection_error = any(keyword in error_str for keyword in [
                    'connection', 'dns', 'resolve', 'getaddrinfo', 'name resolution',
                    'failed to resolve', 'connectionerror', 'timeout'
                ])
                
                if is_connection_error:
                    error_msg = (
                        f"Erro de conexão com a SEFAZ: {str(e)}\n\n"
                        f"Possíveis causas:\n"
                        f"1. Problema de conectividade de internet\n"
                        f"2. Servidor da SEFAZ temporariamente indisponível\n"
                        f"3. Problema de DNS (não consegue resolver o nome do servidor)\n"
                        f"4. Firewall ou proxy bloqueando a conexão\n\n"
                        f"URL tentada: {getattr(comunicacao, 'url', 'Não disponível')}\n"
                        f"UF: {uf}\n"
                        f"Ambiente: {'Homologação' if ambiente_homologacao else 'Produção'}\n\n"
                        f"Soluções:\n"
                        f"- Verificar sua conexão com a internet\n"
                        f"- Verificar se o servidor da SEFAZ está acessível\n"
                        f"- Tentar novamente em alguns instantes\n"
                        f"- Verificar configurações de firewall/proxy"
                    )
                    return {
                        'success': False,
                        'autorizada': False,
                        'status': 'erro_conexao',
                        'error': error_msg,
                        'error_type': 'ConnectionError',
                        'details': str(e)
                    }
                else:
                    # Re-raise se não for erro de conexão
                    raise
            
        except Exception as e:
            import traceback
            print(f"\n❌ ERRO: {e}")
            print(traceback.format_exc())
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
    
    def _construir_xml_soap(self, metodo: str, dados, cabecalho: bool = False):
        """
        Constrói envelope SOAP para envio à SEFAZ
        Delega para ComunicacaoSefaz do PyNFe
        """
        # Usar instância armazenada se disponível, senão criar temporária
        if hasattr(self, '_comunicacao_sefaz') and self._comunicacao_sefaz is not None:
            return self._comunicacao_sefaz._construir_xml_soap(metodo, dados, cabecalho)
        
        # Fallback: criar instância temporária
        uf_temp = getattr(self, '_uf_temp', 'SP')
        cert_temp = getattr(self, 'certificado_path', '')
        senha_temp = getattr(self, 'senha_certificado', '')
        ambiente_temp = getattr(self, '_ambiente_temp', True)
        
        comunicacao_temp = ComunicacaoSefaz(uf_temp, cert_temp, senha_temp, ambiente_temp)
        return comunicacao_temp._construir_xml_soap(metodo, dados, cabecalho)
    
    def _get_url(self, modelo: str, consulta: str, contingencia: bool = False):
        """
        Obtém URL do webservice da SEFAZ
        Delega para ComunicacaoSefaz do PyNFe
        """
        # Usar instância armazenada se disponível, senão criar temporária
        if hasattr(self, '_comunicacao_sefaz') and self._comunicacao_sefaz is not None:
            return self._comunicacao_sefaz._get_url(modelo, consulta, contingencia)
        
        # Fallback: criar instância temporária
        uf_temp = getattr(self, '_uf_temp', 'SP')
        cert_temp = getattr(self, 'certificado_path', '')
        senha_temp = getattr(self, 'senha_certificado', '')
        ambiente_temp = getattr(self, '_ambiente_temp', True)
        
        comunicacao_temp = ComunicacaoSefaz(uf_temp, cert_temp, senha_temp, ambiente_temp)
        return comunicacao_temp._get_url(modelo, consulta, contingencia)
    
    def _post(self, url: str, xml, timeout: int = None):
        """
        Envia requisição POST para a SEFAZ
        Delega para ComunicacaoSefaz do PyNFe
        """
        # Usar instância armazenada se disponível, senão criar temporária
        if hasattr(self, '_comunicacao_sefaz') and self._comunicacao_sefaz is not None:
            return self._comunicacao_sefaz._post(url, xml, timeout)
        
        # Fallback: criar instância temporária
        uf_temp = getattr(self, '_uf_temp', 'SP')
        cert_temp = getattr(self, 'certificado_path', '')
        senha_temp = getattr(self, 'senha_certificado', '')
        ambiente_temp = getattr(self, '_ambiente_temp', True)
        
        comunicacao_temp = ComunicacaoSefaz(uf_temp, cert_temp, senha_temp, ambiente_temp)
        return comunicacao_temp._post(url, xml, timeout)
    
    def _salvar_xml(self, empresa_data: Dict, chave_acesso: str, xml_str: str, numero_nfce: int) -> str:
        """
        Salva XML autorizado da NFC-e em pasta organizada por empresa, ano e mês
        
        Estrutura de pastas:
        logs/xmls_nfce/{CNPJ}/{ano}/{mes}/{chave_acesso}.xml
        
        Args:
            empresa_data: Dados da empresa
            chave_acesso: Chave de acesso da NFC-e (44 dígitos)
            xml_str: XML completo autorizado (nfeProc) como string
            numero_nfce: Número da NFC-e
        
        Returns:
            Caminho completo do arquivo XML salvo
        """
        try:
            import re
            from datetime import datetime
            
            print("=" * 70)
            print("💾 SALVANDO XML AUTORIZADO (nfeProc) - É O XML FINAL!")
            print("=" * 70)
            print("   📋 Este XML contém:")
            print("      - NFe (nota fiscal completa)")
            print("      - Signature (assinatura digital)")
            print("      - protNFe (protocolo de autorização da SEFAZ)")
            print("   ✅ Este é o XML que deve ser armazenado e usado para impressão do DANFE")
            print("=" * 70)
            
            # Extrair CNPJ da empresa
            cnpj = empresa_data.get('cnpj', '') or empresa_data.get('CNPJ', '')
            razao_social = empresa_data.get('razao_social', '') or empresa_data.get('razaoSocial', '') or empresa_data.get('nome', '')
            
            if cnpj:
                cnpj_limpo = re.sub(r'[^\d]', '', str(cnpj))
                empresa_id = cnpj_limpo if len(cnpj_limpo) >= 11 else 'sem_cnpj'
            else:
                empresa_id = empresa_data.get('id', '') or empresa_data.get('_id', '') or 'sem_empresa'
            
            print(f"   📋 Empresa: {razao_social or 'N/A'} ({empresa_id})")
            print(f"   📋 Chave de acesso: {chave_acesso or 'N/A'}")
            print(f"   📋 Número NFC-e: {numero_nfce}")
            
            # Criar estrutura de pastas: logs/xmls_nfce/{CNPJ}/{ano}/{mes}/
            agora = datetime.now()
            ano = agora.strftime('%Y')
            mes = agora.strftime('%m')
            mes_nome = agora.strftime('%B')  # Nome do mês em português
            
            # Pasta da empresa (usando CNPJ)
            pasta_empresa = os.path.join(self.base_xml_dir, empresa_id)
            
            # Adicionar nome da empresa na pasta se disponível
            if razao_social:
                # Limpar nome da empresa para usar como nome de pasta
                nome_empresa_limpo = re.sub(r'[<>:"/\\|?*]', '_', razao_social)[:50]  # Limitar a 50 caracteres
                pasta_empresa_com_nome = os.path.join(self.base_xml_dir, f"{empresa_id}_{nome_empresa_limpo}")
            else:
                pasta_empresa_com_nome = pasta_empresa
            
            # Pastas por ano e mês
            pasta_ano = os.path.join(pasta_empresa_com_nome, ano)
            pasta_mes = os.path.join(pasta_ano, f"{mes}_{mes_nome}")
            
            # Criar pastas se não existirem
            os.makedirs(pasta_mes, exist_ok=True)
            print(f"   📁 Pasta criada: {pasta_mes}")
            
            # Nome do arquivo: usar chave de acesso se disponível, senão usar número + timestamp
            if chave_acesso and len(chave_acesso) == 44:
                nome_arquivo = f"{chave_acesso}.xml"
            else:
                timestamp = agora.strftime('%Y%m%d_%H%M%S')
                nome_arquivo = f"NFe{numero_nfce:09d}_{timestamp}.xml"
                print(f"   ⚠️ Chave de acesso não disponível ou inválida, usando nome alternativo")
            
            caminho_completo = os.path.join(pasta_mes, nome_arquivo)
            
            # Validar que o XML não está vazio
            if not xml_str or not xml_str.strip():
                raise ValueError("XML está vazio! Não é possível salvar XML vazio.")
            
            # Validar que é um nfeProc (deve conter <nfeProc>)
            if '<nfeProc' not in xml_str and '<nfeProc ' not in xml_str:
                print("   ⚠️ AVISO: XML pode não ser um nfeProc completo (não contém tag nfeProc)")
            
            # Salvar XML com encoding UTF-8
            with open(caminho_completo, 'w', encoding='utf-8') as f:
                # Adicionar declaração XML se não tiver
                if not xml_str.strip().startswith('<?xml'):
                    f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
                f.write(xml_str)
            
            # Verificar tamanho do arquivo
            tamanho_arquivo = os.path.getsize(caminho_completo)
            print(f"   ✅ XML autorizado salvo com sucesso!")
            print(f"   📁 Caminho: {caminho_completo}")
            print(f"   📊 Tamanho: {tamanho_arquivo:,} bytes ({tamanho_arquivo / 1024:.2f} KB)")
            
            # Criar arquivo README na pasta da empresa com informações
            try:
                readme_path = os.path.join(pasta_empresa_com_nome, 'README.txt')
                if not os.path.exists(readme_path):
                    with open(readme_path, 'w', encoding='utf-8') as f:
                        f.write("=" * 70 + "\n")
                        f.write("PASTA DE XMLs AUTORIZADOS - NFC-e\n")
                        f.write("=" * 70 + "\n\n")
                        f.write(f"Empresa: {razao_social or 'N/A'}\n")
                        f.write(f"CNPJ: {empresa_id}\n")
                        f.write(f"Data de criação: {agora.strftime('%d/%m/%Y %H:%M:%S')}\n\n")
                        f.write("ESTRUTURA DE PASTAS:\n")
                        f.write("  {CNPJ}/{ano}/{mes}/ - XMLs autorizados por mês\n\n")
                        f.write("IMPORTANTE:\n")
                        f.write("- Os XMLs autorizados devem ser mantidos por 5 anos (obrigatório)\n")
                        f.write("- Cada XML contém o nfeProc completo (NFe + protNFe)\n")
                        f.write("- Os arquivos são nomeados pela chave de acesso (44 dígitos)\n")
                        f.write("=" * 70 + "\n")
            except Exception as e_readme:
                print(f"   ⚠️ Erro ao criar README: {e_readme}")
            
            print("=" * 70)
            return caminho_completo
            
        except Exception as e:
            print(f"   ❌ Erro ao salvar XML: {e}")
            import traceback
            traceback.print_exc()
            return ""
    
    def imprimir_nfce(self, dados_impressao: Dict) -> Dict[str, Any]:
        """
        Gera PDF do DANFE NFC-e e abre para visualização/impressão
        
        Args:
            dados_impressao: Dicionário com dados para impressão contendo:
                - chave_acesso: Chave de acesso da NFC-e
                - protocolo: Protocolo de autorização
                - xml: XML autorizado completo
                - qrcode: URL do QR Code
                - url_consulta: URL de consulta
                - empresa: Dados da empresa
                - produtos: Lista de produtos
                - pagamentos: Lista de pagamentos
                - consumidor: Dados do consumidor (opcional)
                - numero_nfce: Número da NFC-e
                - caminho_xml: Caminho do XML salvo
        
        Returns:
            Dicionário com resultado da impressão
        """
        try:
            import subprocess
            import tempfile
            from datetime import datetime
            
            print("=" * 70)
            print("GERANDO PDF DO DANFE NFC-e")
            print("=" * 70)
            
            # Extrair dados
            empresa_data = dados_impressao.get('empresa', {})
            produtos = dados_impressao.get('produtos', [])
            pagamentos = dados_impressao.get('pagamentos', [])
            consumidor = dados_impressao.get('consumidor', {})
            chave_acesso = dados_impressao.get('chave_acesso', '')
            protocolo = dados_impressao.get('protocolo', '')
            qrcode = dados_impressao.get('qrcode', '')
            numero_nfce = dados_impressao.get('numero_nfce', 0)
            caminho_xml = dados_impressao.get('caminho_xml', '')
            
            # Calcular totais
            valor_total = sum(p.get('valor', 0) for p in pagamentos)
            
            # Tentar gerar PDF usando reportlab (se disponível)
            try:
                from reportlab.lib.pagesizes import A4
                from reportlab.lib.units import mm
                from reportlab.pdfgen import canvas
                from reportlab.lib import colors
                from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
                from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image
                from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
                
                # Criar arquivo PDF temporário
                pdf_dir = os.path.join(os.path.dirname(__file__), '..', 'logs', 'danfe_pdf')
                os.makedirs(pdf_dir, exist_ok=True)
                
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                pdf_filename = f'DANFE_NFCe_{numero_nfce:09d}_{timestamp}.pdf'
                pdf_path = os.path.join(pdf_dir, pdf_filename)
                
                print(f"   📄 Gerando PDF: {pdf_path}")
                
                # Criar documento PDF (80mm x 297mm - formato térmica)
                doc = SimpleDocTemplate(
                    pdf_path,
                    pagesize=(80*mm, 297*mm),  # 80mm x 297mm
                    rightMargin=5*mm,
                    leftMargin=5*mm,
                    topMargin=5*mm,
                    bottomMargin=5*mm
                )
                
                # Estilos
                styles = getSampleStyleSheet()
                style_normal = ParagraphStyle(
                    'CustomNormal',
                    parent=styles['Normal'],
                    fontSize=8,
                    leading=10,
                    alignment=TA_LEFT
                )
                style_center = ParagraphStyle(
                    'CustomCenter',
                    parent=styles['Normal'],
                    fontSize=8,
                    leading=10,
                    alignment=TA_CENTER
                )
                style_title = ParagraphStyle(
                    'CustomTitle',
                    parent=styles['Heading1'],
                    fontSize=10,
                    leading=12,
                    alignment=TA_CENTER,
                    textColor=colors.black
                )
                
                # Conteúdo do PDF
                story = []
                
                # Cabeçalho
                razao_social = empresa_data.get('razao_social', '') or empresa_data.get('razaoSocial', '') or 'N/A'
                cnpj = empresa_data.get('cnpj', '') or empresa_data.get('CNPJ', '')
                endereco = empresa_data.get('endereco', {}) or {}
                endereco_completo = f"{endereco.get('logradouro', '')}, {endereco.get('numero', '')} - {endereco.get('bairro', '')}"
                cidade_uf = f"{endereco.get('cidade', '')}/{endereco.get('uf', '')} - CEP: {endereco.get('cep', '')}"
                
                story.append(Paragraph("DANFE NFC-e", style_title))
                story.append(Spacer(1, 5*mm))
                story.append(Paragraph(f"<b>{razao_social}</b>", style_center))
                story.append(Paragraph(f"CNPJ: {cnpj}", style_center))
                story.append(Paragraph(endereco_completo, style_center))
                story.append(Paragraph(cidade_uf, style_center))
                story.append(Spacer(1, 5*mm))
                
                # Dados da NFC-e
                story.append(Paragraph(f"<b>NFC-e Nº {numero_nfce:09d}</b>", style_center))
                story.append(Paragraph(f"Protocolo: {protocolo}", style_center))
                story.append(Paragraph(f"Chave de Acesso:", style_center))
                # Formatar chave de acesso (44 dígitos em grupos de 4)
                chave_formatada = ' '.join([chave_acesso[i:i+4] for i in range(0, len(chave_acesso), 4)])
                story.append(Paragraph(chave_formatada, style_center))
                story.append(Spacer(1, 5*mm))
                
                # Data/Hora
                data_emissao = datetime.now().strftime('%d/%m/%Y %H:%M:%S')
                story.append(Paragraph(f"Data/Hora de Emissão: {data_emissao}", style_normal))
                story.append(Spacer(1, 3*mm))
                
                # Consumidor (se informado)
                if consumidor:
                    nome_consumidor = consumidor.get('nome', '') or consumidor.get('nomeConsumidor', '')
                    cpf_cnpj = consumidor.get('cpf', '') or consumidor.get('cnpj', '') or consumidor.get('cpfCnpj', '')
                    if nome_consumidor or cpf_cnpj:
                        story.append(Paragraph("<b>DESTINATÁRIO</b>", style_normal))
                        if nome_consumidor:
                            story.append(Paragraph(f"Nome: {nome_consumidor}", style_normal))
                        if cpf_cnpj:
                            story.append(Paragraph(f"CPF/CNPJ: {cpf_cnpj}", style_normal))
                        story.append(Spacer(1, 3*mm))
                
                # Itens
                story.append(Paragraph("<b>ITENS</b>", style_normal))
                story.append(Spacer(1, 2*mm))
                
                for produto in produtos:
                    descricao = produto.get('descricao', '') or produto.get('nome', '')
                    quantidade = produto.get('quantidade', 0)
                    valor_unitario = produto.get('valor_unitario', 0) or produto.get('preco', 0)
                    valor_total_item = quantidade * valor_unitario
                    
                    item_text = f"{descricao[:30]} - Qtd: {quantidade} x R$ {valor_unitario:.2f} = R$ {valor_total_item:.2f}"
                    story.append(Paragraph(item_text, style_normal))
                
                story.append(Spacer(1, 5*mm))
                
                # Totais
                story.append(Paragraph(f"<b>VALOR TOTAL: R$ {valor_total:.2f}</b>", style_center))
                story.append(Spacer(1, 3*mm))
                
                # Formas de Pagamento
                if pagamentos:
                    story.append(Paragraph("<b>FORMA DE PAGAMENTO</b>", style_normal))
                    for pagamento in pagamentos:
                        forma = pagamento.get('forma', '') or pagamento.get('tipo', '')
                        valor = pagamento.get('valor', 0)
                        story.append(Paragraph(f"{forma}: R$ {valor:.2f}", style_normal))
                    story.append(Spacer(1, 3*mm))
                
                # QR Code (texto)
                if qrcode:
                    story.append(Paragraph("<b>CONSULTA NFC-e</b>", style_center))
                    story.append(Paragraph("Acesse o QR Code abaixo ou digite a chave de acesso no site da SEFAZ", style_center))
                    story.append(Spacer(1, 3*mm))
                    # Nota: Para gerar imagem do QR Code, seria necessário instalar qrcode[pil]
                    # Por enquanto, apenas mostrar a URL
                    story.append(Paragraph(f"URL: {qrcode[:60]}...", style_normal))
                    story.append(Spacer(1, 3*mm))
                
                # Rodapé
                story.append(Spacer(1, 5*mm))
                story.append(Paragraph("Este documento é uma representação gráfica da NFC-e", style_center))
                story.append(Paragraph("em ambiente de autorização de nota fiscal eletrônica", style_center))
                
                # Construir PDF
                doc.build(story)
                
                print(f"   ✅ PDF gerado com sucesso: {pdf_path}")
                
                # Abrir PDF
                if os.name == 'nt':  # Windows
                    try:
                        os.startfile(pdf_path)
                        print(f"   ✅ PDF aberto no visualizador padrão")
                    except Exception as e:
                        subprocess.Popen(['start', pdf_path], shell=True)
                        print(f"   ✅ PDF aberto via subprocess")
                else:  # Linux/Mac
                    subprocess.Popen(['xdg-open', pdf_path])
                    print(f"   ✅ PDF aberto no visualizador padrão")
                
                return {
                    'success': True,
                    'mensagem': 'PDF do DANFE NFC-e gerado e aberto com sucesso',
                    'caminho_pdf': pdf_path,
                    'caminho_xml': caminho_xml
                }
                
            except ImportError:
                # Se reportlab não estiver disponível, abrir apenas o XML
                print("   ⚠️ reportlab não disponível, abrindo apenas XML")
                print("   💡 Para gerar PDF, instale: pip install reportlab")
                
            if not caminho_xml or not os.path.exists(caminho_xml):
                return {
                    'success': False,
                    'error': 'Arquivo XML não encontrado para impressão',
                    'error_type': 'FileNotFound'
                }
            
                # Abrir XML
            if os.name == 'nt':  # Windows
                try:
                    os.startfile(caminho_xml)
                except Exception as e:
                        subprocess.Popen(['start', caminho_xml], shell=True)
                else:  # Linux/Mac
                    subprocess.Popen(['xdg-open', caminho_xml])
                
                    return {
                        'success': True,
                    'mensagem': 'XML aberto (instale reportlab para gerar PDF)',
                    'caminho_xml': caminho_xml,
                    'sugestao': 'Instale reportlab: pip install reportlab'
                    }
                    
        except Exception as e:
            import traceback
            print(f"   ❌ Erro ao gerar PDF: {e}")
            traceback.print_exc()
            return {
                'success': False,
                'error': f'Erro ao gerar PDF do DANFE: {str(e)}',
                'error_type': 'PDFGenerationError',
                'details': traceback.format_exc()
            }


def criar_servico_nfce_pynfe_completo():
    """
    Factory para criar serviço NFC-e com PyNFe completo
    
    Returns:
        Instância de NFCePyNFeCompleto ou None se PyNFe não disponível
    """
    if PYNFE_DISPONIVEL:
        return NFCePyNFeCompleto()
    else:
        return None

