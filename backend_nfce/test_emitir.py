#!/usr/bin/env python3
"""
Teste simples para diagnosticar o erro tempfile e validação de schema
"""
import sys
import os
import base64
import traceback

# Adicionar o diretório atual ao path
sys.path.insert(0, 'C:\\Users\\charles\\.antigravity\\sistema_exodo_15-04-2026\\backend_nfce')

try:
    from nfce_handler import emitir_nfce_pynfe
    print("[OK] Importação bem-sucedida")
    
    # Carregar certificado real do Firestore
    import firebase_admin
    from firebase_admin import credentials, firestore
    cred = credentials.Certificate('firebase-credentials.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    empresa = db.collection('empresas').document('22ae2c16-a730-43f3-a4f9-19f105eb0d13').get().to_dict()
    cert_b64 = empresa['configuracoes'].get('certificadoDigitalBytes')

    # Criar um objeto de requisição simples para teste
    class MockEmpresa:
        def __init__(self):
            self.certificado_base64 = cert_b64
            self.senha_certificado = "Rotwailler1"
            self.ambiente = 2
            self.cnpj = "04829400000165"
            self.razao_social = "BMJ COMERCIO E SERVICOS DE PETSHOP LTDA"
            self.nome_fantasia = "E O BICHO PETSHOP"
            self.inscricao_estadual = "645431707119"
            self.logradouro = "SAO JERONIMO"
            self.numero = "177"
            self.bairro = "JARDIM SAO JUDAS TADEU"
            self.municipio = "SAO JOSE DOS CAMPOS"
            self.codigo_municipio = "3549904"
            self.uf = "SP"
            self.cep = "12228350"
            self.crt = "1"
            self.csc = "584c0db0-0d0b-46c7-91ca-ebcfcfc43a50"
            self.csc_id = "1"
    
    class MockItem:
        def __init__(self):
            self.codigo = "COD-1"
            self.descricao = "PRODUTO TESTE"
            self.ncm = "22011000"
            self.cfop = "5102"
            self.quantidade = 1.0
            self.valor_unitario = 2.0
            self.valor_total = 2.0
            self.icms_csosn = "102"
            self.icms_cst = "00"
            self.icms_origem = 0
            self.icms_aliquota = 0.0

    class MockReq:
        def __init__(self):
            self.empresa = MockEmpresa()
            self.cpf_cliente = ""
            self.venda_numero = "173"
            self.serie = 1
            self.valor_total = 2.0
            self.itens = [MockItem()]
            self.pagamentos = []
    
    req = MockReq()
    
    print("[TESTE] Chamando emitir_nfce_pynfe...")
    resultado = emitir_nfce_pynfe(req)
    print(f"[RESULTADO] {resultado}")
    
except Exception as e:
    print(f"[ERRO] {type(e).__name__}: {e}")
    print("[TRACEBACK]")
    traceback.print_exc()

