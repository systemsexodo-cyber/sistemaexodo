

class MockFonteDados:
    def __init__(self, nota):
        self.nota = nota
    def obter_lista(self, _classe=None, **kwargs):
        return [self.nota]
    def limpar_dados(self):
        pass

def validar_certificado_pynfe(req_dict):
    """Valida se um certificado Base64 e senha estao corretos e ativos."""
    try:
        from pynfe.entidades.certificado import CertificadoA1
        import base64
        import tempfile
        import os

        cert_b64 = req_dict.get('certificado_base64')
        senha = req_dict.get('senha_certificado')

        if not cert_b64 or not senha:
            return {'success': False, 'error': 'Certificado ou senha nao fornecidos.'}

        cert_data = base64.b64decode(cert_b64)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.pfx') as tmp_cert:
            tmp_cert.write(cert_data)
            caminho_cert = tmp_cert.name

        try:
            # Tentar instanciar o certificado (valida a senha)
            CertificadoA1(caminho_cert).separar_arquivo(senha)
            return {
                'success': True,
                'mensagem': 'Certificado validado com sucesso.',
                'valido': True
            }
        except Exception as e:
            return {'success': False, 'error': f'Sua senha ou o arquivo do certificado estao incorretos: {str(e)}'}
        finally:
            if os.path.exists(caminho_cert):
                try: os.remove(caminho_cert)
                except: pass
    except Exception as e:
        return {'success': False, 'error': str(e)}
