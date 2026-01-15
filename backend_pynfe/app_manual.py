"""
Backend MANUAL para NFC-e
100% LOCAL - gera XML, assina e envia para SEFAZ sem APIs de terceiros
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

app = Flask(__name__)
CORS(app)  # Permitir requisições do Flutter

# Importar serviço manual
try:
    from services.nfce_service_manual import NFCeServiceManual
    MANUAL_DISPONIVEL = True
    print("[OK] NFCeServiceManual disponível")
except ImportError as e:
    MANUAL_DISPONIVEL = False
    print(f"[AVISO] NFCeServiceManual não disponível: {e}")

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    return jsonify({
        'status': 'ok',
        'message': 'Backend NFC-e MANUAL está funcionando',
        'servico': '100% Local - Sem APIs de Terceiros',
        'manual_disponivel': MANUAL_DISPONIVEL
    })

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """
    Emite NFC-e manualmente (100% local, sem APIs)
    
    Body JSON esperado:
    {
        "empresa": {
            "cnpj": "12345678000190",
            "razao_social": "Empresa Teste",
            "certificado_base64": "...",
            "senha_certificado": "...",
            "numero_nfce": 1,
            "serie_nfce": 1,
            ...
        },
        "produtos": [...],
        "pagamentos": [...],
        "consumidor": {...},
        "observacoes": "..."
    }
    """
    if not MANUAL_DISPONIVEL:
        return jsonify({
            'success': False,
            'error': 'Serviço manual não está disponível'
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
        nfce_service = NFCeServiceManual()
        
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
    print("BACKEND NFC-e MANUAL (100% LOCAL)")
    print("=" * 60)
    print()
    print("✅ 100% LOCAL - funciona no seu servidor")
    print("✅ Sem APIs de terceiros")
    print("✅ Tudo no seu código")
    print("✅ Gera XML, assina e envia para SEFAZ")
    print()
    
    if not MANUAL_DISPONIVEL:
        print("⚠️  AVISO: Serviço manual não está disponível")
        print("   Verifique se as dependências estão instaladas")
    else:
        print("✅ Serviço manual disponível")
    
    print()
    print("Servidor iniciando em: http://localhost:5000")
    print("=" * 60)
    print()
    
    app.run(host='0.0.0.0', port=5000, debug=True)




















