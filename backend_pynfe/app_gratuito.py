"""
Backend GRATUITO para NFC-e usando PyTrustNFe
Funciona localmente, sem APIs pagas - tudo no seu código!
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

app = Flask(__name__)
CORS(app)  # Permitir requisições do Flutter

# Importar serviço PyTrustNFe
try:
    from services.nfce_service_pytrust import NFCeServicePyTrust
    PYTRUST_DISPONIVEL = True
    print("[OK] NFCeServicePyTrust disponível")
except ImportError as e:
    PYTRUST_DISPONIVEL = False
    print(f"[AVISO] NFCeServicePyTrust não disponível: {e}")
    print("[INFO] Instale com: pip install PyTrustNFe")

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    return jsonify({
        'status': 'ok',
        'message': 'Backend NFC-e GRATUITO está funcionando',
        'servico': 'PyTrustNFe (Gratuito e Local)',
        'pytrust_disponivel': PYTRUST_DISPONIVEL
    })

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """
    Emite NFC-e usando PyTrustNFe (GRATUITO e LOCAL)
    
    Body JSON esperado:
    {
        "empresa": {
            "cnpj": "12345678000190",
            "razao_social": "Empresa Teste",
            "certificado_base64": "...",
            "senha_certificado": "...",
            ...
        },
        "produtos": [...],
        "pagamentos": [...],
        "consumidor": {...},
        "observacoes": "..."
    }
    """
    if not PYTRUST_DISPONIVEL:
        return jsonify({
            'success': False,
            'error': 'PyTrustNFe não está instalado.\n\n'
                    'Execute: pip install PyTrustNFe\n\n'
                    'Depois REINICIE o servidor!',
            'error_type': 'LibraryNotAvailable'
        }), 503
    
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos'
            }), 400
        
        # Validar certificado
        empresa_data = data.get('empresa', {})
        if 'certificado_base64' not in empresa_data:
            return jsonify({
                'success': False,
                'error': 'Certificado digital não fornecido',
                'error_type': 'CertificateMissing'
            }), 400
        
        if not empresa_data.get('senha_certificado'):
            return jsonify({
                'success': False,
                'error': 'Senha do certificado não fornecida',
                'error_type': 'CertificatePasswordMissing'
            }), 400
        
        # Criar serviço
        nfce_service = NFCeServicePyTrust()
        
        # Emitir NFC-e
        resultado = nfce_service.emitir_nfce(data)
        
        # Retornar resultado
        if resultado.get('success'):
            return jsonify(resultado), 200
        else:
            status_code = 500 if resultado.get('error_type') not in ['SEFAZRejection', 'CertificateError'] else 400
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
    print("BACKEND NFC-e GRATUITO - PyTrustNFe")
    print("=" * 60)
    print()
    print("✅ 100% GRATUITO - funciona localmente")
    print("✅ Sem APIs pagas")
    print("✅ Tudo no seu código")
    print()
    
    if not PYTRUST_DISPONIVEL:
        print("⚠️  AVISO: PyTrustNFe não está instalado")
        print("   Instale com: pip install PyTrustNFe")
    else:
        print("✅ PyTrustNFe disponível")
    
    print()
    print("Servidor iniciando em: http://localhost:5000")
    print("=" * 60)
    print()
    
    app.run(host='0.0.0.0', port=5000, debug=True)




















