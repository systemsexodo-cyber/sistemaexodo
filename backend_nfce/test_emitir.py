#!/usr/bin/env python3
"""
Teste simples para diagnosticar o erro tempfile
"""
import sys
import traceback

# Adicionar o diretório atual ao path
sys.path.insert(0, 'C:\\Users\\charles\\.antigravity\\sistema_exodo_15-04-2026\\backend_nfce')

try:
    from nfce_handler import emitir_nfce_pynfe
    print("[OK] Importação bem-sucedida")
    
    # Criar um objeto de requisição simples para teste
    class MockEmpresa:
        def __init__(self):
            self.certificado_base64 = ""
            self.senha_certificado = ""
            self.ambiente = 2
            self.cnpj = "12345678000195"
            self.razao_social = "Teste"
            self.nome_fantasia = "Teste"
            self.inscricao_estadual = "123456"
            self.logradouro = "Rua Teste"
            self.numero = "123"
            self.bairro = "Centro"
            self.municipio = "SAO PAULO"
            self.codigo_municipio = "3550308"
            self.uf = "SP"
            self.cep = "01001000"
            self.crt = "1"
            self.csc = ""
            self.csc_id_token = ""
    
    class MockReq:
        def __init__(self):
            self.empresa = MockEmpresa()
            self.cpf_cliente = ""
            self.venda_numero = "1"
            self.serie = 1
            self.valor_total = 10.0
            self.itens = []
            self.pagamentos = []
    
    req = MockReq()
    
    print("[TESTE] Chamando emitir_nfce_pynfe...")
    resultado = emitir_nfce_pynfe(req)
    print(f"[RESULTADO] {resultado}")
    
except Exception as e:
    print(f"[ERRO] {type(e).__name__}: {e}")
    print("[TRACEBACK]")
    traceback.print_exc()
