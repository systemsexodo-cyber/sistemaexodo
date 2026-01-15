"""
Backend Python SIMPLIFICADO para emissão de NFC-e
Versão que funciona mesmo com problemas de importação
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import sys

# Criar app Flask
app = Flask(__name__)
CORS(app)  # Permitir requisições do Flutter

# Variáveis globais
PYNFE_DISPONIVEL = False
nfce_service = None
certificado_service = None

# Tentar importar serviços com tratamento robusto de erros
print("=" * 50)
print("Iniciando Backend NFC-e...")
print("=" * 50)

# 1. Tentar importar dotenv (opcional)
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("✅ dotenv carregado")
except ImportError:
    print("⚠️ dotenv não instalado (opcional)")

# 2. Tentar importar serviços
print("\n📦 Carregando serviços...")

try:
    from services.certificado_service import CertificadoService
    certificado_service = CertificadoService()
    print("✅ CertificadoService carregado")
except Exception as e:
    print(f"⚠️ CertificadoService não disponível: {e}")
    certificado_service = None

try:
    from services.nfce_service import NFCeService
    nfce_service = NFCeService()
    PYNFE_DISPONIVEL = True
    print("✅ NFCeService carregado (PyNFe disponível)")
except Exception as e:
    print(f"⚠️ NFCeService não disponível: {e}")
    print("⚠️ PyNFe não está instalado ou há erro de importação")
    PYNFE_DISPONIVEL = False
    nfce_service = None

print("=" * 50)
print()

@app.route('/health', methods=['GET'])
def health():
    """Endpoint de health check"""
    status = {
        'status': 'ok',
        'message': 'Backend NFC-e está funcionando',
        'local': True,
        'pynfe_disponivel': PYNFE_DISPONIVEL,
    }
    
    if not PYNFE_DISPONIVEL:
        status['warning'] = 'PyNFe não está instalado. Execute: pip install git+https://github.com/TadaSoftware/PyNFe.git'
    
    return jsonify(status)

@app.route('/api/nfce/emitir', methods=['POST'])
def emitir_nfce():
    """Emite uma NFC-e"""
    if not PYNFE_DISPONIVEL or not nfce_service:
        return jsonify({
            'success': False,
            'error': 'PyNFe não está instalado. Execute: pip install git+https://github.com/TadaSoftware/PyNFe.git'
        }), 503
    
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'error': 'Dados não fornecidos'
            }), 400
        
        if 'empresa' not in data:
            return jsonify({
                'success': False,
                'error': 'Dados da empresa não fornecidos'
            }), 400
        
        resultado = nfce_service.emitir_nfce(data)
        return jsonify(resultado)
        
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"❌ ERRO ao emitir NFC-e: {e}")
        print(f"Detalhes: {error_details}")
        
        return jsonify({
            'success': False,
            'error': str(e),
            'details': error_details if os.getenv('DEBUG', 'False').lower() == 'true' else None
        }), 500

@app.route('/api/certificado/validar', methods=['POST'])
def validar_certificado():
    """Valida um certificado digital"""
    if not certificado_service:
        return jsonify({
            'success': False,
            'error': 'Serviço de certificado não disponível'
        }), 503
    
    try:
        data = request.get_json()
        
        if not data or 'certificado_base64' not in data:
            return jsonify({
                'success': False,
                'error': 'Certificado não fornecido'
            }), 400
        
        resultado = certificado_service.validar_certificado(
            data['certificado_base64'],
            data.get('senha', '')
        )
        
        return jsonify(resultado)
        
    except Exception as e:
        import traceback
        print(f"❌ ERRO ao validar certificado: {e}")
        print(traceback.format_exc())
        
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'True').lower() == 'true'
    
    print('=' * 50)
    print('🚀 Backend NFC-e - Modo LOCAL (Simplificado)')
    print('=' * 50)
    print(f'📝 Porta: {port}')
    print(f'🐛 Debug: {debug}')
    print(f'🌐 URL: http://localhost:{port}')
    print(f'📡 Health: http://localhost:{port}/health')
    print('=' * 50)
    print('')
    
    if not PYNFE_DISPONIVEL:
        print('⚠️  AVISO: PyNFe não está instalado!')
        print('⚠️  Execute: pip install git+https://github.com/TadaSoftware/PyNFe.git')
        print('')
    
    print('Pressione Ctrl+C para parar')
    print('')
    
    try:
        app.run(host='0.0.0.0', port=port, debug=debug, use_reloader=False)
    except Exception as e:
        print(f"❌ ERRO ao iniciar servidor: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


