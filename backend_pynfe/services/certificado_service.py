"""
Serviço para manipulação de certificados digitais
"""

import base64
import tempfile
import os
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend


class CertificadoService:
    """Serviço para manipulação de certificados digitais"""
    
    def _is_pem_format(self, data):
        """Verifica se os dados são formato PEM (texto)"""
        try:
            if isinstance(data, bytes):
                texto = data.decode('utf-8', errors='ignore')
            else:
                texto = str(data)
            return '-----BEGIN' in texto and '-----END' in texto
        except:
            return False
    
    def _carregar_pem(self, certificado_bytes, senha):
        """Carrega certificado em formato PEM"""
        try:
            # Decodificar como texto
            if isinstance(certificado_bytes, bytes):
                pem_content = certificado_bytes.decode('utf-8')
            else:
                pem_content = str(certificado_bytes)
            
            # Extrair certificado e chave privada do PEM
            certificate = None
            private_key = None
            
            # Tentar carregar certificado
            try:
                certificate = x509.load_pem_x509_certificate(
                    pem_content.encode('utf-8'),
                    default_backend()
                )
            except Exception as e:
                # Pode não ter certificado, apenas chave
                pass
            
            # Tentar carregar chave privada
            try:
                # Tentar sem senha primeiro
                try:
                    private_key = serialization.load_pem_private_key(
                        pem_content.encode('utf-8'),
                        password=None,
                        backend=default_backend()
                    )
                except:
                    # Tentar com senha
                    if senha:
                        private_key = serialization.load_pem_private_key(
                            pem_content.encode('utf-8'),
                            password=senha.encode() if isinstance(senha, str) else senha,
                            backend=default_backend()
                        )
            except Exception as e:
                # Pode não ter chave privada
                pass
            
            if certificate is None and private_key is None:
                raise ValueError('Não foi possível extrair certificado nem chave privada do arquivo PEM')
            
            # Se não tiver certificado mas tiver chave, criar um certificado vazio para validação
            if certificate is None:
                raise ValueError('Certificado não encontrado no arquivo PEM')
            
            # Extrair informações do certificado
            subject = certificate.subject
            cnpj = None
            for attr in subject:
                if attr.oid._name == 'serialNumber':
                    cnpj = attr.value
                    break
            
            validade = certificate.not_valid_after
            
            return {
                'senha': senha,  # Incluir senha no retorno
                'cnpj': cnpj,
                'validade': validade.isoformat(),
                'subject': str(subject),
                'issuer': str(certificate.issuer)
            }
            
        except Exception as e:
            raise Exception(f'Erro ao carregar certificado PEM: {str(e)}')
    
    def _carregar_pfx(self, certificado_bytes, senha):
        """Carrega certificado em formato PFX/PKCS12"""
        try:
            # Salvar temporariamente
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pfx')
            temp_file.write(certificado_bytes)
            temp_file.close()
            
            # Carregar certificado
            with open(temp_file.name, 'rb') as f:
                certificado_pfx = f.read()
            
            # Extrair certificado e chave privada
            private_key, certificate, additional_certificates = serialization.pkcs12.load_key_and_certificates(
                certificado_pfx,
                senha.encode() if isinstance(senha, str) else senha,
                backend=default_backend()
            )
            
            if certificate is None:
                raise ValueError('Certificado não encontrado no arquivo PFX')
            
            if private_key is None:
                raise ValueError('Chave privada não encontrada no arquivo PFX')
            
            # Extrair informações do certificado
            subject = certificate.subject
            cnpj = None
            for attr in subject:
                if attr.oid._name == 'serialNumber':
                    cnpj = attr.value
                    break
            
            validade = certificate.not_valid_after
            
            return {
                'arquivo': temp_file.name,
                'senha': senha,  # Incluir senha no retorno
                'cnpj': cnpj,
                'validade': validade.isoformat(),
                'subject': str(subject),
                'issuer': str(certificate.issuer)
            }
            
        except Exception as e:
            raise Exception(f'Erro ao carregar certificado PFX: {str(e)}')
    
    def carregar_certificado(self, certificado_base64, senha):
        """
        Carrega certificado digital a partir de base64
        Suporta tanto PFX/PKCS12 quanto PEM
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
            
        Returns:
            Dicionário com informações do certificado
        """
        try:
            # Decodificar base64
            certificado_bytes = base64.b64decode(certificado_base64)
            
            # Detectar formato (PEM ou PFX)
            if self._is_pem_format(certificado_bytes):
                # É formato PEM
                return self._carregar_pem(certificado_bytes, senha)
            else:
                # É formato PFX/PKCS12
                return self._carregar_pfx(certificado_bytes, senha)
            
        except Exception as e:
            raise Exception(f'Erro ao carregar certificado: {str(e)}')
    
    def validar_certificado(self, certificado_base64, senha):
        """
        Valida um certificado digital
        
        Args:
            certificado_base64: Certificado em base64
            senha: Senha do certificado
            
        Returns:
            Dicionário com resultado da validação
        """
        try:
            certificado_info = self.carregar_certificado(certificado_base64, senha)
            
            from datetime import datetime
            agora = datetime.now()
            validade = datetime.fromisoformat(certificado_info['validade'])
            
            is_valido = validade > agora
            dias_restantes = (validade - agora).days if is_valido else 0
            
            return {
                'success': True,
                'valido': is_valido,
                'cnpj': certificado_info['cnpj'],
                'validade': certificado_info['validade'],
                'dias_restantes': dias_restantes,
                'subject': certificado_info['subject']
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

