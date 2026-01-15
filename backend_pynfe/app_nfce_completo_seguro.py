"""
API REST para emissão de NFC-e
Versão SEGURA com tratamento de erros na inicialização
"""

import sys
import traceback

try:
    from flask import Flask, request, jsonify
    from flask_cors import CORS
    print("[OK] Flask importado")
except ImportError as e:
    print(f"[ERRO] Falha ao importar Flask: {e}")
    print("Instale com: pip install Flask Flask-CORS")
    input("Pressione Enter para sair...")
    sys.exit(1)

try:
    from nfce_completo import NFCeCompleto
    print("[OK] NFCeCompleto importado")
except ImportError as e:
    print(f"[ERRO] Falha ao importar NFCeCompleto: {e}")
    print("\nVerifique se o arquivo nfce_completo.py existe")
    print("E se todas as dependências estão instaladas:")
    print("  pip install lxml cryptography zeep")
    input("Pressione Enter para sair...")
    sys.exit(1)

app = Flask(__name__)
CORS(app)

# Criar instância com tratamento de erro
try:
    nfce = NFCeCompleto()
    print("[OK] NFCeCompleto instanciado")
except Exception as e:
    print(f"[ERRO] Falha ao criar instância NFCeCompleto: {e}")
    traceback.print_exc()
    input("Pressione Enter para sair...")
    sys.exit(1)

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    try:
        return jsonify({
            'status': 'ok',
            'message': 'Sistema de emissão NFC-e funcionando',
            'versao': '1.0.0'
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """
    Emite NFC-e
    
    Body JSON:
    {
        "empresa": {
            "cnpj": "...",
            "razaoSocial": "...",
            "nomeFantasia": "...",
            "inscricaoEstadual": "...",
            "codigoIBGE": "...",
            "uf": "SP",
            "endereco": "...",
            "numero": "...",
            "bairro": "...",
            "cidade": "...",
            "cep": "...",
            "telefone": "...",
            "crt": 3,
            "serie_nfce": 1,
            "ambienteHomologacao": true,
            "certificado_base64": "...",
            "senhaCertificado": "..."
        },
        "produtos": [...],
        "pagamentos": [...],
        "consumidor": {...},
        "observacoes": "...",
        "numero_nfce": 1
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos'
            }), 400
        
        empresa_data = data.get('empresa', {})
        produtos = data.get('produtos', [])
        pagamentos = data.get('pagamentos', [])
        consumidor = data.get('consumidor')
        observacoes = data.get('observacoes', '')
        numero_nfce = data.get('numero_nfce', 1)
        
        # Validar dados obrigatórios
        if not empresa_data.get('cnpj'):
            return jsonify({
                'success': False,
                'error': 'CNPJ da empresa não fornecido'
            }), 400
        
        if not produtos:
            return jsonify({
                'success': False,
                'error': 'Nenhum produto informado'
            }), 400
        
        if not pagamentos:
            return jsonify({
                'success': False,
                'error': 'Nenhuma forma de pagamento informada'
            }), 400
        
        # Emitir NFC-e
        resultado = nfce.emitir(
            empresa_data=empresa_data,
            produtos=produtos,
            pagamentos=pagamentos,
            consumidor=consumidor,
            observacoes=observacoes,
            numero_nfce=numero_nfce
        )
        
        if resultado.get('success'):
            return jsonify(resultado), 200
        else:
            status_code = 400 if resultado.get('error_type') in ['SEFAZRejection', 'CertificateError', 'CertificateMissing'] else 500
            return jsonify(resultado), status_code
        
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"\n[ERRO] Erro ao processar requisição: {e}")
        print(error_details)
        
        return jsonify({
            'success': False,
            'error': f'Erro ao processar requisição: {str(e)}',
            'error_type': 'ServerError',
            'details': error_details
        }), 500

if __name__ == '__main__':
    print("=" * 60)
    print("SISTEMA DE EMISSÃO NFC-e")
    print("=" * 60)
    print("✅ Funciona em Produção e Homologação")
    print("✅ 100% Local - Sem APIs de terceiros")
    print("✅ Gera XML, assina e envia para SEFAZ")
    print()
    
    try:
        print("Iniciando servidor...")
        print("Servidor: http://localhost:5000")
        print("=" * 60)
        print()
        print("Pressione Ctrl+C para parar o servidor")
        print()
        
        app.run(host='0.0.0.0', port=5000, debug=True)
        
    except KeyboardInterrupt:
        print("\n\nServidor interrompido pelo usuário")
    except Exception as e:
        print(f"\n[ERRO CRÍTICO] Falha ao iniciar servidor: {e}")
        traceback.print_exc()
        input("\nPressione Enter para sair...")
        sys.exit(1)




















