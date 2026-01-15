"""
API REST para emissão de NFC-e
Sistema completo - funciona em produção e homologação
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from nfce_completo import NFCeCompleto

app = Flask(__name__)
CORS(app)

nfce = NFCeCompleto()

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'message': 'Sistema de emissão NFC-e funcionando',
        'versao': '1.0.0'
    })

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
        return jsonify({
            'success': False,
            'error': f'Erro ao processar requisição: {str(e)}',
            'error_type': 'ServerError',
            'details': traceback.format_exc()
        }), 500

if __name__ == '__main__':
    print("=" * 60)
    print("SISTEMA DE EMISSÃO NFC-e")
    print("=" * 60)
    print("✅ Funciona em Produção e Homologação")
    print("✅ 100% Local - Sem APIs de terceiros")
    print("✅ Gera XML, assina e envia para SEFAZ")
    print()
    print("Servidor: http://localhost:5000")
    print("=" * 60)
    print()
    
    app.run(host='0.0.0.0', port=5000, debug=True)




















