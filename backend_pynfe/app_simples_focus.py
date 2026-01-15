"""
Backend SIMPLIFICADO para NFC-e usando Focus NFe API
Esta é a forma MAIS FÁCIL de emitir NFC-e!
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

app = Flask(__name__)
CORS(app)  # Permitir requisições do Flutter

# Importar serviço Focus NFe
try:
    from services.nfce_service_focus import NFCeServiceFocus
    FOCUS_DISPONIVEL = True
    print("[OK] NFCeServiceFocus disponível")
except ImportError as e:
    FOCUS_DISPONIVEL = False
    print(f"[AVISO] NFCeServiceFocus não disponível: {e}")

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    return jsonify({
        'status': 'ok',
        'message': 'Backend NFC-e SIMPLIFICADO está funcionando',
        'servico': 'Focus NFe API',
        'focus_disponivel': FOCUS_DISPONIVEL
    })

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """
    Emite NFC-e usando Focus NFe API (ULTRA SIMPLES)
    
    Body JSON esperado:
    {
        "empresa": {
            "cnpj": "12345678000190",
            "razao_social": "Empresa Teste",
            ...
        },
        "produtos": [...],
        "pagamentos": [...],
        "consumidor": {...},
        "observacoes": "..."
    }
    """
    if not FOCUS_DISPONIVEL:
        return jsonify({
            'success': False,
            'error': 'Serviço Focus NFe não está disponível'
        }), 503
    
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos'
            }), 400
        
        # Verificar se tem token configurado
        api_token = os.getenv('FOCUSNFE_TOKEN', '')
        if not api_token:
            return jsonify({
                'success': False,
                'error': 'Token da API Focus NFe não configurado.\n\n'
                         'Configure a variável de ambiente FOCUSNFE_TOKEN\n'
                         'ou adicione no arquivo .env:\n'
                         'FOCUSNFE_TOKEN=seu_token_aqui',
                'error_type': 'TokenNotConfigured'
            }), 400
        
        # Obter ambiente
        ambiente_homologacao = data.get('empresa', {}).get('ambiente_homologacao', True)
        
        # Criar serviço
        nfce_service = NFCeServiceFocus(
            api_token=api_token,
            ambiente_homologacao=ambiente_homologacao
        )
        
        # Emitir NFC-e
        resultado = nfce_service.emitir_nfce(data)
        
        # Retornar resultado
        if resultado.get('success'):
            return jsonify(resultado), 200
        else:
            status_code = 500 if resultado.get('error_type') != 'APIError' else 400
            return jsonify(resultado), status_code
        
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        
        return jsonify({
            'success': False,
            'error': f'Erro ao processar requisição: {str(e)}',
            'error_type': 'ServerError',
            'details': error_details
        }), 500

if __name__ == '__main__':
    print("=" * 60)
    print("BACKEND NFC-e SIMPLIFICADO - Focus NFe API")
    print("=" * 60)
    print()
    
    if not FOCUS_DISPONIVEL:
        print("⚠️  AVISO: Serviço Focus NFe não está disponível")
        print("   Instale: pip install requests")
    else:
        print("✅ Serviço Focus NFe disponível")
    
    token = os.getenv('FOCUSNFE_TOKEN', '')
    if token:
        print(f"✅ Token configurado: {token[:10]}...")
    else:
        print("⚠️  Token não configurado!")
        print("   Configure: export FOCUSNFE_TOKEN=seu_token")
        print("   Ou adicione no .env: FOCUSNFE_TOKEN=seu_token")
    
    print()
    print("Servidor iniciando em: http://localhost:5000")
    print("=" * 60)
    print()
    
    app.run(host='0.0.0.0', port=5000, debug=True)




















